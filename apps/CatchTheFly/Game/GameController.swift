import Foundation
import Combine
import CoreGraphics
import QuartzCore
import SwiftUI
import UIKit

// MARK: - What the views draw

struct SplatMark: Identifiable, Equatable, Sendable {
    let id: Int
    var time: Double
    var x: Double
    var y: Double
}

struct PatchMark: Identifiable, Equatable, Sendable {
    let id: Int
    /// FlyCore screen space (0...1, top-left origin).
    var rect: CGRect
    var ratio: Double
    var distance: Double
    var confidence: Double
    var isFlySpot: Bool
}

/// Everything the views need for one frame. Published once per display frame.
struct GameViewState: Sendable {
    var time: Double = 0
    var phase: FlyRoundPhase = .idle
    var roundNumber = 0
    var fliesCaught = 0
    var fliesPerRound = 3
    var elapsed: Double = 0
    var bestTime: Double?
    var lastRoundTime: Double?
    var lastRoundWasBest = false

    var fly: FlyRenderState?
    /// Normalised focal length across the view's width (1 / (2 tan(hFOV/2))), for sprite size.
    var focalWidth: Double = 1
    var splats: [SplatMark] = []
    var smugUntil: Double = 0
    var smugPoint: FlyScreenPoint?

    var patches: [PatchMark] = []
    var hitRect: CGRect = .zero
    var cameraStatus = "Starting camera…"
    var debugLines: [String] = []
    var smashLines: [String] = []
    /// The latest "Splat!" / "Missed!" / "Too fast" message (GameToast.isVisible decides if it shows).
    var toast: GameToast?
}

// MARK: - Controller

/// Owns FlyGame, gathers the platform inputs each display frame, steps the game with the real
/// frame time, and turns the output into sound, haptics and a GameViewState.
@MainActor
final class GameController: ObservableObject {
    @Published private(set) var state = GameViewState()
    @Published var showDebug = false {
        didSet { AppSettings.shared.debugOverlay = showDebug }
    }

    let logFileURL: URL
    let platformName: String

    private let frameSource: any FrameSource
    private let poseSource: any PoseSource
    private let tracker: any SpotTracker
    private let smashSources: [any SmashInputSource]
    private let debugButton: DebugButtonSmashSource?
    private let inbox: SessionInbox
    private let pipeline: FramePipeline
    private let store: DefaultsBestTimeStore
    private var game: FlyGame
    /// Route B reference distances per tracked patch (FlyCore's PatchReferencePolicy).
    private var references = PatchReferenceBook()
    private let audio = GameAudio()
    private let haptics = Haptics()
    private let log: SessionLog

    private var displayLink: CADisplayLink?
    private var linkProxy: DisplayLinkProxy?
    private var started = false
    private var running = false
    private var lastTick: Double?
    private var latestReport: FrameReport?
    private var viewSize: CGSize = .zero
    private var lastOrientationRefresh: Double = 0

    private var roundNumber = 0
    private var splats: [SplatMark] = []
    private var nextSplatID = 0
    private var smugUntil: Double = 0
    private var smugPoint: FlyScreenPoint?
    private var smashLines: [String] = []
    private var lastRoundWasBest = false
    private var cameraStatus = "Starting camera…"
    /// The posture's preset before the player's sensitivity settings (AppSettings) are applied.
    private var basePreset: FlyPreset
    private var toast: GameToast?
    private var nextToastID = 0

    // Frame statistics, logged every few seconds.
    private var statsStart: Double = 0
    private var statsFrames = 0
    private var statsDrops = 0
    private var statsProcessing: Double = 0
    private var fps: Double = 0
    private var meanProcessingMs: Double = 0

    init() {
        let inbox = SessionInbox()
        let tracker = Platform.makeSpotTracker()
        let store = DefaultsBestTimeStore()
        let sources = Platform.makeSmashSources()
        let seed = UInt64.random(in: 1...UInt64.max)
        let log = SessionLog()

        self.inbox = inbox
        self.tracker = tracker
        self.store = store
        self.smashSources = sources
        self.debugButton = sources.compactMap { $0 as? DebugButtonSmashSource }.first
        self.frameSource = Platform.makeFrameSource()
        self.poseSource = Platform.makePoseSource()
        self.pipeline = FramePipeline(tracker: tracker, inbox: inbox)
        self.platformName = Platform.name
        self.log = log
        self.logFileURL = log.fileURL
        let settings = AppSettings.shared
        let platformPreset = FlyPreset(name: "platform", tunables: Platform.makeTunables(), hingeEdge: Platform.hingeEdge)
        self.basePreset = platformPreset
        self.game = FlyGame(tunables: settings.adjusted(platformPreset.tunables), seed: seed, hingeEdge: platformPreset.hingeEdge,
                            hingeAvailable: false, store: store)
        self.showDebug = settings.debugOverlay

        let device = UIDevice.current
        log.append("Catch the Fly session log")
        log.append("started \(ISO8601DateFormatter().string(from: Date())) on \(device.model) iOS \(device.systemVersion)")
        log.append("platform: \(Platform.name)")
        log.append("frames: \(frameSource.displayName); pose: \(poseSource.displayName); tracker: \(tracker.displayName)")
        log.append("smash inputs: \(sources.map { $0.name }.joined(separator: ", "))")
        log.append("seed \(seed) hingeEdge \(Platform.hingeEdge.rawValue) smashDistance \(FlyLog.fixed(game.tunables.smashDistance)) takeOffDistance \(FlyLog.fixed(game.tunables.takeOffDistance))")
        log.append("clock: CACurrentMediaTime (host time) for game, frames, hinge")
        log.append("settings: \(settings.sensitivitySummary), sound \(settings.soundOn), haptics \(settings.hapticsOn)")
    }

    // MARK: Lifecycle

    func start() {
        if started {
            resume()
            return
        }
        started = true
        log.append(appLine("APP", audio.start()))
        resume()
    }

    private func resume() {
        guard !running else { return }
        running = true
        let inbox = self.inbox
        poseSource.start(notes: { message in inbox.note(message) })
        frameSource.start(consumer: pipeline)
        startDisplayLink()
        log.append(appLine("APP", "running"))
    }

    private func pause() {
        guard running else { return }
        running = false
        displayLink?.invalidate()
        displayLink = nil
        linkProxy = nil
        lastTick = nil
        frameSource.stop()
        poseSource.stop()
        log.append(appLine("APP", "paused"))
        log.flush()
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            if started { resume() }
        case .background:
            pause()
        case .inactive:
            log.flush()
        @unknown default:
            break
        }
    }

    /// Called once by the camera preview view when it is created.
    func attach(previewView: PreviewView) {
        frameSource.attachPreview(previewView.previewLayer)
        for s in smashSources {
            s.attach(to: previewView)
        }
        haptics.attach(to: previewView)
        previewView.onLayout = { [weak self] size in
            self?.viewSize = size
        }
        viewSize = previewView.bounds.size
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let proxy = DisplayLinkProxy()
        proxy.controller = self
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.fire(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: RunLoop.main, forMode: RunLoop.Mode.common)
        displayLink = link
        linkProxy = proxy
    }

    // MARK: Player actions

    func startRound() {
        game.startRound()
        roundNumber += 1
        splats.removeAll()
        smugUntil = 0
        smugPoint = nil
        lastRoundWasBest = false
        toast = nil
        log.append(appLine("APP", "round \(roundNumber) requested"))
    }

    func endRound() {
        game.cancelRound()
        log.append(appLine("APP", "round \(roundNumber) abandoned"))
    }

    func pressDebugSmash() {
        debugButton?.press()
        log.append(appLine("APP", "debug smash button"))
    }

    func resetTracking() {
        tracker.reset()
        log.append(appLine("APP", "tracking reset by the player"))
    }

    /// Phase 5 hook: the Duo build switches posture at run time, and with it the tunables and
    /// the hit region (FlyCore's FlyPreset). Takes effect on the next step.
    /// The player's sensitivity settings (AppSettings) are applied on top of the preset.
    func applyPreset(_ preset: FlyPreset) {
        basePreset = preset
        game.tunables = AppSettings.shared.adjusted(preset.tunables)
        game.hingeEdge = preset.hingeEdge
        log.append(appLine("APP", "preset \(preset.name): hingeEdge \(preset.hingeEdge.rawValue) smashDistance \(FlyLog.fixed(preset.tunables.smashDistance)) (\(AppSettings.shared.sensitivitySummary))"))
    }

    /// Settings sheet: re-applies the current preset with the new sensitivity.
    func refreshSensitivity() {
        game.tunables = AppSettings.shared.adjusted(basePreset.tunables)
        let t = game.tunables
        log.append(appLine("APP", "sensitivity \(AppSettings.shared.sensitivitySummary): alarmAngularSpeed \(FlyLog.fixed(t.alarmAngularSpeed)) alarmApproachRate \(FlyLog.fixed(t.alarmApproachRate)) darkeningThreshold \(FlyLog.fixed(t.darkeningThreshold)) hingeMinCloseDrop \(FlyLog.fixed(t.hingeMinCloseDrop))"))
    }

    /// Settings sheet: forgets the best time. The round holds its own copy, so outside a round
    /// FlyGame is rebuilt from the (now empty) store with the same tunables and hit region.
    func resetBestTime() {
        store.clearBestTime()
        lastRoundWasBest = false
        if game.round.phase != .playing {
            game = FlyGame(tunables: game.tunables, seed: UInt64.random(in: 1...UInt64.max), hingeEdge: game.hingeEdge,
                           hingeAvailable: game.hingeAvailable, store: store)
        }
        log.append(appLine("APP", "best time reset by the player"))
    }

    private func showToast(_ kind: GameToast.Kind, now: Double) {
        let t = GameToast(id: nextToastID, kind: kind, time: now)
        nextToastID += 1
        toast = t
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: t.text)
        }
    }

    // MARK: The frame

    fileprivate func tick() {
        let now = CACurrentMediaTime()
        let dt = lastTick.map { now - $0 } ?? 0
        lastTick = now

        // 1. Collect what the queues produced since the last frame.
        let batch = inbox.drain()
        for n in batch.notes {
            log.append(FlyLog.line(time: n.time, tag: "APP", message: n.text))
            if n.text.hasPrefix("CAM") {
                cameraStatus = n.text
            }
        }
        if let r = batch.latest {
            latestReport = r
            references.policy = PatchReferencePolicy(tunables: game.tunables)
            references.update(RouteBAdapter.readings(from: r.tracking))
        }
        if !batch.seededPatches.isEmpty {
            log.append(appLine("TRACK", "seeded \(batch.seededPatches.map { String($0) }.joined(separator: ","))"))
        }
        if !batch.lostPatches.isEmpty {
            log.append(appLine("TRACK", "lost \(batch.lostPatches.map { String($0) }.joined(separator: ","))"))
        }
        for e in batch.trackerErrors {
            log.append(appLine("TRACK", e))
        }
        updateStats(batch: batch, now: now)

        if now - lastOrientationRefresh > 0.5 {
            lastOrientationRefresh = now
            frameSource.refreshOrientation()
        }

        // 2. Smash inputs.
        var inputs = SmashInputs()
        for s in smashSources {
            s.receiveLuma(batch.luma)
            s.drain(into: &inputs)
        }
        for n in inputs.notes {
            log.append(appLine("APP", n))
        }
        inputs.hinge.sort { $0.time < $1.time }
        inputs.luma.sort { $0.time < $1.time }
        let hingeLive = smashSources.contains { $0.providesHinge }
        if hingeLive != game.hingeAvailable {
            game.hingeAvailable = hingeLive
            log.append(appLine("APP", "hingeAvailable=\(hingeLive)"))
        }

        // 3. Camera, landing spots and distance (route B).
        let report = latestReport
        let fresh = report.map { now - $0.info.time < 0.5 } ?? false
        let crop: DisplayCrop
        if let r = report {
            crop = DisplayCrop.aspectFill(imageWidth: r.tracking.imageWidth, imageHeight: r.tracking.imageHeight, viewSize: viewSize)
        } else {
            crop = .full
        }
        let pose = poseSource.latest()
        let camera = RouteBAdapter.camera(geometry: report?.info.geometry, crop: crop, pose: pose)
        var spots: [LandingSpot] = []
        var measurement: (measurement: DistanceMeasurement, confidence: Double, measuredAt: Double)? = nil
        if fresh, let r = report {
            spots = RouteBAdapter.spots(from: r.tracking, crop: crop, camera: camera, references: references)
            // Every tick, stamped with the frame time: FlyCore holds the distance on ticks without a new frame.
            measurement = RouteBAdapter.measurement(forSpot: game.fly?.spotID, report: r.tracking, references: references)
        }

        // 4. Step FlyCore.
        let input = FlyGameInput(time: now,
                                 camera: camera,
                                 spots: spots,
                                 distanceMeasurement: measurement?.measurement,
                                 distanceConfidence: measurement?.confidence ?? 0,
                                 distanceMeasuredAt: measurement?.measuredAt,
                                 angularSpeed: pose?.rotationRate ?? 0,
                                 hingeSamples: inputs.hinge,
                                 lumaSamples: inputs.luma,
                                 manualSmash: inputs.manual)
        let out = game.step(input: input, dt: dt)

        // 5. Play, persist, log, draw.
        handle(out, now: now)
        audio.update(gain: AppSettings.shared.soundOn ? out.audioGain : 0, pan: out.audioPan)
        publish(out, now: now, camera: camera, crop: crop, report: fresh ? report : nil, poseKnown: pose != nil)
        log.flushIfDue(now: now)
    }

    private func handle(_ out: FlyGameOutput, now: Double) {
        log.append(contentsOf: out.logLines)
        let settings = AppSettings.shared
        var fanfarePlayed = false
        for cue in out.cues {
            switch cue {
            case .hit:
                if settings.hapticsOn { haptics.hit() }
                if settings.soundOn { audio.play(.hit) }
                showToast(.splat, now: now)
                SplatGallery.shared.add(catchTime: out.round.flyTimes.last ?? 0,
                                        flyNumber: out.round.fliesCaught, roundNumber: roundNumber)
            case .miss:
                if settings.hapticsOn { haptics.miss() }
                if settings.soundOn { audio.play(.miss) }
                smugUntil = now + 1.6
                smugPoint = out.fly?.screenPosition
                showToast(.missed, now: now)
            case .flyAlarmed:
                // A miss also alarms the fly: keep the smug sound and the "Missed!" toast.
                if !out.cues.contains(.miss) {
                    if settings.soundOn { audio.play(.alarm) }
                    showToast(.spooked, now: now)
                }
            case .roundFinished, .newBestTime:
                if !fanfarePlayed {
                    fanfarePlayed = true
                    if settings.soundOn { audio.play(.fanfare) }
                }
                if cue == .newBestTime {
                    lastRoundWasBest = true
                }
            case .roundStarted, .newFly, .flyTookOff:
                break
            }
        }
        for s in out.splats {
            let p = s.screenPosition ?? out.fly?.screenPosition ?? FlyScreenPoint(x: 0.5, y: 0.5)
            splats.append(SplatMark(id: nextSplatID, time: now, x: p.x, y: p.y))
            nextSplatID += 1
        }
        splats.removeAll { now - $0.time > 4.0 }
        if let best = out.newBestTime {
            store.saveBestTime(best)
            log.append(appLine("APP", "best time saved: \(FlyLog.fixed(best, decimals: 2)) s"))
        }
        for e in out.smashEvents {
            addSmashLine("SMASH \(e.source.rawValue) start=\(FlyLog.fixed(e.motionStartTime, decimals: 2))")
        }
        for v in out.verdicts {
            let dist = FlyLog.optionalFixed(v.snapshot?.distance, decimals: 2)
            let state = v.snapshot?.flyState.rawValue ?? "none"
            addSmashLine("\(v.isHit ? "HIT" : "MISS") reason=\(v.reason.rawValue) fly=\(state) dist=\(dist)")
        }
        for r in out.rejections {
            addSmashLine("REJECTED \(r.reason.rawValue)")
        }
    }

    private func addSmashLine(_ line: String) {
        smashLines.append(line)
        if smashLines.count > 8 {
            smashLines.removeFirst(smashLines.count - 8)
        }
    }

    private func publish(_ out: FlyGameOutput, now: Double, camera: FlyCamera, crop: DisplayCrop, report: FrameReport?, poseKnown: Bool) {
        var s = GameViewState()
        s.time = now
        s.phase = out.round.phase
        s.roundNumber = roundNumber
        s.fliesCaught = out.round.fliesCaught
        s.fliesPerRound = out.round.fliesPerRound
        s.elapsed = out.round.elapsed
        s.bestTime = out.round.bestTime
        s.lastRoundTime = out.round.lastRoundTime
        s.lastRoundWasBest = lastRoundWasBest
        s.fly = out.fly
        let halfTan = tan(camera.horizontalFOV / 2)
        s.focalWidth = halfTan > 0 ? 1 / (2 * halfTan) : 1
        s.splats = splats
        s.smugUntil = smugUntil
        s.smugPoint = smugPoint
        s.cameraStatus = cameraStatus
        s.smashLines = smashLines
        s.toast = toast

        if showDebug {
            let flySpot = out.fly?.spotID
            if let r = report {
                s.patches = r.tracking.patches.map { p in
                    let c = crop.toScreen(x: p.centreX, y: p.centreY)
                    let w = p.width / crop.width
                    let h = p.height / crop.height
                    return PatchMark(id: p.id, rect: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h),
                                     ratio: p.scaleRatio,
                                     distance: references.distance(for: RouteBAdapter.reading(p)) ?? Double.nan,
                                     confidence: p.confidence, isFlySpot: p.id == flySpot)
                }
            }
            s.hitRect = RouteBAdapter.hitRect(edge: game.hingeEdge, tunables: game.tunables)
            var lines: [String] = []
            lines.append(platformName)
            let tracking = report == nil ? "no fresh frames" : "\(report?.tracking.patches.count ?? 0) patches"
            lines.append("tracking: \(tracking), fps \(FlyLog.fixed(fps, decimals: 0)), tracker \(FlyLog.fixed(meanProcessingMs, decimals: 1)) ms, pose \(poseKnown ? "ok" : "none")")
            lines.append(contentsOf: FlyLog.overlayLines(out))
            let d = game.detector
            lines.append("detector luma armed=\(d.isLumaArmed) hinge armed=\(d.isHingeArmed) awaiting hinge=\(d.isAwaitingHinge) hingeAvailable=\(game.hingeAvailable)")
            lines.append(smashSources.map { $0.statusText }.joined(separator: " | "))
            s.debugLines = lines
        }
        state = s
    }

    private func updateStats(batch: SessionInbox.Batch, now: Double) {
        if statsStart == 0 { statsStart = now }
        statsFrames += batch.frames
        statsDrops += batch.dropped
        statsProcessing += batch.processingTotal
        let span = now - statsStart
        guard span >= 2.0 else { return }
        fps = Double(statsFrames) / span
        meanProcessingMs = statsFrames > 0 ? 1000 * statsProcessing / Double(statsFrames) : 0
        let luma = FlyLog.optionalFixed(latestReport?.info.luma, decimals: 3)
        let patches = latestReport?.tracking.patches.count ?? 0
        let offset = FlyLog.optionalFixed(latestReport?.info.clockOffset, decimals: 3)
        log.append(appLine("FRAME", "fps=\(FlyLog.fixed(fps, decimals: 1)) drops=\(statsDrops) tracker=\(FlyLog.fixed(meanProcessingMs, decimals: 1))ms luma=\(luma) patches=\(patches) clockOffset=\(offset)s view=\(Int(viewSize.width))x\(Int(viewSize.height))"))
        statsStart = now
        statsFrames = 0
        statsDrops = 0
        statsProcessing = 0
    }

    private func appLine(_ tag: String, _ message: String) -> String {
        return FlyLog.line(time: CACurrentMediaTime(), tag: tag, message: message)
    }
}

/// CADisplayLink retains its target; this breaks the cycle with a weak reference.
@MainActor
final class DisplayLinkProxy: NSObject {
    weak var controller: GameController?

    @objc func fire(_ link: CADisplayLink) {
        controller?.tick()
    }
}
