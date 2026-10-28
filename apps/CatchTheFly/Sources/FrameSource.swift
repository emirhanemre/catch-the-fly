import Foundation
import AVFoundation
import CoreVideo
import QuartzCore

// Camera frames: the protocol every camera implementation conforms to, the plain values
// that leave the capture queue, and the thread-safe inbox the main actor drains each tick.
//
// Threading rule: CVPixelBuffer and AVCaptureSession never leave the capture/session queues.
// Only the Sendable structs below cross to the main actor, through SessionInbox.

/// Geometry of the camera picture as the preview shows it (upright, before the aspect-fill crop).
struct CameraGeometry: Sendable, Equatable {
    var imageWidth: Int
    var imageHeight: Int
    /// Full angles in radians across the upright image.
    var horizontalFOV: Double
    var verticalFOV: Double
    /// Picture right, up and viewing direction in the CoreMotion device frame
    /// (x right, y towards the top edge, z out of the screen, all in portrait).
    var rightInDevice: Vec3
    var upInDevice: Vec3
    var forwardInDevice: Vec3
}

/// What a frame source knows about one frame, besides the pixels.
struct FrameInfo: Sendable, Equatable {
    /// Seconds on the shared game clock (CACurrentMediaTime / host time).
    var time: Double
    /// Mean luma 0...1, nil if the pixel format couldn't be read.
    var luma: Double?
    var geometry: CameraGeometry
    /// CACurrentMediaTime() at arrival minus the frame's presentation time (for the log).
    var clockOffset: Double
}

/// Receives frames on the capture queue. The pipeline (tracker + inbox) implements it.
protocol FrameConsumer: AnyObject, Sendable {
    /// Called on the frame source's serial capture queue. Don't keep the pixel buffer.
    func consume(_ pixelBuffer: CVPixelBuffer, info: FrameInfo)
    /// A status line for the session log. Any thread.
    func note(_ message: String)
    /// A frame was dropped by the capture output. Any thread.
    func frameDropped()
}

/// A camera. iPad: `RearCameraFrameSource`. Duo (runtime lookup): `InnerCameraFrameSource`.
/// A native iOS 27.1 version can be added in its own file under `#if IOS_27_1_SDK` and chosen
/// in Platform.swift.
protocol FrameSource: AnyObject, Sendable {
    var displayName: String { get }
    /// For the preview layer only (main actor). Configured and run on the source's own queue.
    var captureSession: AVCaptureSession { get }
    /// Asks for camera permission if needed, configures and starts capture. Safe to call again
    /// after `stop()`.
    func start(consumer: any FrameConsumer)
    func stop()
    /// Hands over the preview layer (main actor).
    @MainActor func attachPreview(_ layer: AVCaptureVideoPreviewLayer)
    /// Re-reads the interface orientation and rotates preview and frames to match. Called by the
    /// game a couple of times a second (main actor).
    @MainActor func refreshOrientation()
}

/// One processed frame, as the main actor sees it.
struct FrameReport: Sendable, Equatable {
    var info: FrameInfo
    var tracking: TrackerReport
    /// Seconds the tracker took on the capture queue.
    var processingTime: Double
}

struct InboxNote: Sendable, Equatable {
    var time: Double
    var text: String
}

/// Lock-protected mailbox between the capture/motion queues and the main actor.
/// Writers append from any thread; GameController drains it once per display frame.
final class SessionInbox: @unchecked Sendable {
    struct Batch: Sendable {
        var luma: [LumaSample] = []
        var latest: FrameReport?
        var notes: [InboxNote] = []
        var seededPatches: [Int] = []
        var lostPatches: [Int] = []
        var trackerErrors: [String] = []
        var frames: Int = 0
        var dropped: Int = 0
        var processingTotal: Double = 0
    }

    private let lock = NSLock()
    private var batch = Batch()
    private static let maxLuma = 240
    private static let maxNotes = 200

    func postLuma(_ sample: LumaSample) {
        lock.lock()
        defer { lock.unlock() }
        batch.luma.append(sample)
        if batch.luma.count > SessionInbox.maxLuma {
            batch.luma.removeFirst(batch.luma.count - SessionInbox.maxLuma)
        }
    }

    func post(_ report: FrameReport) {
        lock.lock()
        defer { lock.unlock() }
        batch.latest = report
        batch.frames += 1
        batch.processingTotal += report.processingTime
        batch.seededPatches.append(contentsOf: report.tracking.seeded)
        batch.lostPatches.append(contentsOf: report.tracking.lost)
        if let e = report.tracking.error {
            batch.trackerErrors.append(e)
        }
    }

    func note(_ text: String) {
        let t = CACurrentMediaTime()
        lock.lock()
        defer { lock.unlock() }
        if batch.notes.count < SessionInbox.maxNotes {
            batch.notes.append(InboxNote(time: t, text: text))
        }
    }

    func countDrop() {
        lock.lock()
        defer { lock.unlock() }
        batch.dropped += 1
    }

    func drain() -> Batch {
        lock.lock()
        defer { lock.unlock() }
        let out = batch
        batch = Batch()
        return out
    }
}

/// Runs the spot tracker on each frame (on the capture queue) and posts the results.
final class FramePipeline: FrameConsumer, @unchecked Sendable {
    private let tracker: any SpotTracker
    private let inbox: SessionInbox

    init(tracker: any SpotTracker, inbox: SessionInbox) {
        self.tracker = tracker
        self.inbox = inbox
    }

    func consume(_ pixelBuffer: CVPixelBuffer, info: FrameInfo) {
        // Luma first, so the smash path never waits for the tracker.
        if let l = info.luma {
            inbox.postLuma(LumaSample(mean: l, time: info.time))
        }
        let t0 = CACurrentMediaTime()
        let tracking = tracker.track(pixelBuffer, time: info.time)
        let spent = CACurrentMediaTime() - t0
        inbox.post(FrameReport(info: info, tracking: tracking, processingTime: spent))
    }

    func note(_ message: String) {
        inbox.note(message)
    }

    func frameDropped() {
        inbox.countDrop()
    }
}
