import Foundation
import CoreGraphics
import CoreVideo
import ImageIO
import Vision

/// One tracked patch, in the upright camera image (normalised, origin top-left).
struct PatchObservation: Sendable, Equatable {
    var id: Int
    var centreX: Double
    var centreY: Double
    var width: Double
    var height: Double
    /// Current size / size when seeded. Above 1 means the camera got closer.
    var scaleRatio: Double
    /// Vision's tracking confidence, 0...1.
    var confidence: Double
    /// How busy the patch looked when seeded, 0...1.
    var quality: Double
    // Distances are not kept here: FlyCore's PatchReferenceBook (fed by RouteBAdapter) owns them.
}

struct TrackerReport: Sendable, Equatable {
    var time: Double
    var imageWidth: Int
    var imageHeight: Int
    var patches: [PatchObservation]
    /// Patch ids seeded / lost on this frame.
    var seeded: [Int]
    var lost: [Int]
    var error: String?
}

/// Finds and follows landing spots in camera frames. Route B: `PatchTracker`.
/// `track` is called on the capture queue only; `reset` from any thread.
protocol SpotTracker: AnyObject, Sendable {
    var displayName: String { get }
    func track(_ pixelBuffer: CVPixelBuffer, time: Double) -> TrackerReport
    func reset()
}

/// Route B: picks a few high-contrast cells of the Y plane and follows them with Vision.
final class PatchTracker: SpotTracker, @unchecked Sendable {
    struct Settings: Sendable {
        var targetPatches = 4
        /// Seed every this many frames while short of patches.
        var seedInterval = 8
        /// The image's short side is cut into this many square cells.
        var gridDivisions = 7
        /// Minimum luma standard deviation (0...1) for a cell to count as busy.
        var minStdDev = 0.06
        /// Minimum centre spacing between patches, in cells.
        var minSpacingCells = 1.5
        var minConfidence = 0.3
        var maxLowConfidenceFrames = 3
        var minScaleRatio = 0.3
        var maxScaleRatio = 5.0
        var edgeMargin = 0.03
    }

    private final class Patch {
        let id: Int
        let request: VNTrackObjectRequest
        let initialSize: Double
        let quality: Double
        var lowFrames = 0
        var last: PatchObservation?

        init(id: Int, request: VNTrackObjectRequest, initialSize: Double, quality: Double) {
            self.id = id
            self.request = request
            self.initialSize = initialSize
            self.quality = quality
        }
    }

    let displayName = "Route B patch tracker (Vision VNTrackObjectRequest)"
    let settings: Settings

    // Capture queue only.
    private var handler = VNSequenceRequestHandler()
    private var patches: [Patch] = []
    private var retiring: [VNTrackObjectRequest] = []
    private var nextID = 1
    private var frameIndex = 0
    private var lastWidth = 0
    private var lastHeight = 0
    private var formatWarningGiven = false

    // Any thread, guarded.
    private let resetLock = NSLock()
    private var resetRequested = false

    init(settings: Settings = Settings()) {
        self.settings = settings
    }

    func reset() {
        resetLock.lock()
        resetRequested = true
        resetLock.unlock()
    }

    func track(_ pixelBuffer: CVPixelBuffer, time: Double) -> TrackerReport {
        frameIndex += 1
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var seeded: [Int] = []
        var lost: [Int] = []
        var errorText: String? = nil

        resetLock.lock()
        let wantsReset = resetRequested
        resetRequested = false
        resetLock.unlock()
        if wantsReset || width != lastWidth || height != lastHeight {
            // New size (rotation) or a reset: every old box is meaningless now.
            lost.append(contentsOf: patches.map { $0.id })
            patches.removeAll()
            retiring.removeAll()
            handler = VNSequenceRequestHandler()
            lastWidth = width
            lastHeight = height
        }

        // 1. Follow existing patches.
        if !patches.isEmpty || !retiring.isEmpty {
            for r in retiring {
                r.isLastFrame = true
            }
            var requests: [VNRequest] = []
            for p in patches {
                requests.append(p.request)
            }
            for r in retiring {
                requests.append(r)
            }
            var performed = true
            do {
                try handler.perform(requests, on: pixelBuffer, orientation: .up)
            } catch {
                performed = false
                errorText = "track failed: \(error.localizedDescription)"
                lost.append(contentsOf: patches.map { $0.id })
                patches.removeAll()
                handler = VNSequenceRequestHandler()
            }
            retiring.removeAll()
            if performed {
                updatePatches(width: width, height: height, lost: &lost)
            }
        }

        // 2. Seed more when short.
        let short = patches.count < settings.targetPatches
        let due = patches.isEmpty ? (frameIndex % 3 == 0) : (frameIndex % settings.seedInterval == 0)
        if short && due {
            let made = seed(pixelBuffer, width: width, height: height)
            if made == nil && !formatWarningGiven {
                formatWarningGiven = true
                errorText = "can't read the luma plane (pixel format \(CVPixelBufferGetPixelFormatType(pixelBuffer)))"
            }
            seeded = made ?? []
        }

        let observations = patches.compactMap { $0.last }
        return TrackerReport(time: time, imageWidth: width, imageHeight: height,
                             patches: observations, seeded: seeded, lost: lost, error: errorText)
    }

    // MARK: Private (capture queue)

    private func updatePatches(width: Int, height: Int, lost: inout [Int]) {
        let s = settings
        var keep: [Patch] = []
        for p in patches {
            guard let obs = p.request.results?.first as? VNDetectedObjectObservation else {
                p.lowFrames += 1
                if p.lowFrames > s.maxLowConfidenceFrames {
                    retire(p)
                    lost.append(p.id)
                } else {
                    keep.append(p)
                }
                continue
            }
            p.request.inputObservation = obs
            let box = obs.boundingBox
            let confidence = Double(obs.confidence)
            if confidence < s.minConfidence {
                p.lowFrames += 1
            } else {
                p.lowFrames = 0
            }
            let cx = Double(box.midX)
            let cy = 1 - Double(box.midY)
            let bw = Double(box.width)
            let bh = Double(box.height)
            let size = (max(bw, 0) * max(bh, 0)).squareRoot()
            let ratio = p.initialSize > 0 ? size / p.initialSize : 1
            let pixelAspect = bh > 0 ? (bw * Double(width)) / (bh * Double(height)) : 0
            let m = s.edgeMargin
            let bad = p.lowFrames > s.maxLowConfidenceFrames
                || !cx.isFinite || !cy.isFinite
                || cx < m || cx > 1 - m || cy < m || cy > 1 - m
                || !(ratio >= s.minScaleRatio && ratio <= s.maxScaleRatio)
                || pixelAspect > 3 || pixelAspect < 1.0 / 3.0
            if bad {
                retire(p)
                lost.append(p.id)
                continue
            }
            p.last = PatchObservation(id: p.id, centreX: cx, centreY: cy, width: bw, height: bh,
                                      scaleRatio: ratio,
                                      confidence: min(1, max(0, confidence)), quality: p.quality)
            keep.append(p)
        }
        // Two trackers that slid onto the same texture: drop the newer one.
        var deduped: [Patch] = []
        for p in keep {
            guard let a = p.last else { deduped.append(p); continue }
            let clash = deduped.contains { q in
                guard let b = q.last else { return false }
                let dx = (a.centreX - b.centreX) * Double(width)
                let dy = (a.centreY - b.centreY) * Double(height)
                let limit = 0.5 * min(a.width * Double(width), b.width * Double(width))
                return (dx * dx + dy * dy).squareRoot() < limit
            }
            if clash {
                retire(p)
                lost.append(p.id)
            } else {
                deduped.append(p)
            }
        }
        patches = deduped
    }

    private func retire(_ p: Patch) {
        // Performed once more with isLastFrame so Vision frees the tracker.
        retiring.append(p.request)
    }

    /// Grid variance on the Y plane; returns the new ids, or nil if the plane can't be read.
    private func seed(_ pixelBuffer: CVPixelBuffer, width: Int, height: Int) -> [Int]? {
        let s = settings
        struct Cell { var x0: Int; var y0: Int; var score: Double }
        let cellsOrNil: (cells: [Cell], cell: Int)? = LumaMath.withLumaPlane(pixelBuffer) { plane -> (cells: [Cell], cell: Int) in
            let cell = max(16, min(plane.width, plane.height) / max(3, s.gridDivisions))
            let cols = plane.width / cell
            let rows = plane.height / cell
            let step = max(2, cell / 24)
            var cells: [Cell] = []
            if cols >= 3 && rows >= 3 {
                for r in 1..<(rows - 1) {
                    for c in 1..<(cols - 1) {
                        let x0 = c * cell
                        let y0 = r * cell
                        let st = LumaMath.stats(plane, x0: x0, y0: y0, size: cell, step: step)
                        if st.stdDev >= s.minStdDev {
                            cells.append(Cell(x0: x0, y0: y0, score: st.stdDev))
                        }
                    }
                }
            }
            return (cells, cell)
        }
        guard let found = cellsOrNil else { return nil }
        let cell = found.cell
        let w = Double(width)
        let h = Double(height)
        guard w > 0, h > 0 else { return [] }

        var centres: [(Double, Double)] = patches.compactMap { p in
            guard let o = p.last else { return nil }
            return (o.centreX * w, o.centreY * h)
        }
        let minSpacing = s.minSpacingCells * Double(cell)
        var made: [Int] = []
        let sorted = found.cells.sorted { $0.score > $1.score }
        for candidate in sorted {
            if patches.count >= s.targetPatches { break }
            let cx = Double(candidate.x0) + Double(cell) / 2
            let cy = Double(candidate.y0) + Double(cell) / 2
            let tooClose = centres.contains { c in
                let dx = c.0 - cx
                let dy = c.1 - cy
                return (dx * dx + dy * dy).squareRoot() < minSpacing
            }
            if tooClose { continue }
            // Vision: normalised, origin bottom-left.
            let nx = Double(candidate.x0) / w
            let nw = Double(cell) / w
            let nh = Double(cell) / h
            let ny = 1 - (Double(candidate.y0) + Double(cell)) / h
            let rect = CGRect(x: nx, y: ny, width: nw, height: nh)
            let observation = VNDetectedObjectObservation(boundingBox: rect)
            let request = VNTrackObjectRequest(detectedObjectObservation: observation)
            request.trackingLevel = .accurate
            let quality = min(1, max(0.3, candidate.score / 0.25))
            let patch = Patch(id: nextID, request: request, initialSize: (nw * nh).squareRoot(),
                              quality: quality)
            nextID += 1
            patches.append(patch)
            centres.append((cx, cy))
            made.append(patch.id)
        }
        return made
    }
}
