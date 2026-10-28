import Foundation

/// Everything the app gathers for one frame.
public struct FlyGameInput: Sendable, Equatable {
    /// Game clock (s). Must be the same clock as the hinge and luma sample times,
    /// for example `ProcessInfo.processInfo.systemUptime` or the camera frame timestamp.
    public var time: Double
    /// The camera this frame, used to project the fly and to bear the buzz.
    public var camera: FlyCamera
    /// Current landing spots (tracked patches, or fixed world points).
    public var spots: [LandingSpot]
    /// A distance reading for the fly this frame, if the route has one. When nil, FlyGame uses the
    /// straight-line distance from `camera.position` to the fly's world position.
    public var distanceMeasurement: DistanceMeasurement?
    /// Confidence (0...1) of `distanceMeasurement`. Ignored when the measurement is nil.
    public var distanceConfidence: Double
    /// When `distanceMeasurement` was made (s, same clock as `time`), for example the camera frame's
    /// timestamp. Nil means "at `time`". With a timestamp, the app can pass the latest frame's reading on
    /// every tick: a reading not newer than the last one counted is treated as no reading (the distance
    /// is held), so a 30 Hz tracker in a 60 Hz loop is not re-counted.
    public var distanceMeasuredAt: Double?
    /// Magnitude of the device rotation rate (rad/s), from CoreMotion or ARKit.
    public var angularSpeed: Double
    /// Hinge samples that arrived since the last frame, oldest first.
    public var hingeSamples: [HingeSample]
    /// Luma samples that arrived since the last frame, oldest first.
    public var lumaSamples: [LumaSample]
    /// The debug smash button was pressed this frame.
    public var manualSmash: Bool

    public init(time: Double,
                camera: FlyCamera,
                spots: [LandingSpot] = [],
                distanceMeasurement: DistanceMeasurement? = nil,
                distanceConfidence: Double = 1.0,
                distanceMeasuredAt: Double? = nil,
                angularSpeed: Double = 0,
                hingeSamples: [HingeSample] = [],
                lumaSamples: [LumaSample] = [],
                manualSmash: Bool = false) {
        self.time = time
        self.camera = camera
        self.spots = spots
        self.distanceMeasurement = distanceMeasurement
        self.distanceConfidence = distanceConfidence
        self.distanceMeasuredAt = distanceMeasuredAt
        self.angularSpeed = angularSpeed
        self.hingeSamples = hingeSamples
        self.lumaSamples = lumaSamples
        self.manualSmash = manualSmash
    }
}

/// One-off things the app should play or show this frame.
///
/// Suggested mapping: `hit` = heavy haptic + splat sound; `miss` = light haptic + smug buzz;
/// `flyAlarmed` = alarm buzz; `flyTookOff` = hover hum; `roundFinished` / `newBestTime` = fanfare.
public enum FlyGameCue: String, Sendable, Equatable, CaseIterable {
    case roundStarted
    case newFly
    case flyAlarmed
    case flyTookOff
    case hit
    case miss
    case roundFinished
    case newBestTime
}

/// Draw a splat here.
public struct SplatEvent: Sendable, Equatable {
    public var time: Double
    /// Where the fly was on screen just before the fold (from the judged snapshot), nil if unknown.
    public var screenPosition: FlyScreenPoint?
    /// The fly's world position when smashed.
    public var worldPosition: Vec3

    public init(time: Double, screenPosition: FlyScreenPoint?, worldPosition: Vec3) {
        self.time = time
        self.screenPosition = screenPosition
        self.worldPosition = worldPosition
    }
}

/// How to draw the fly this frame.
public struct FlyRenderState: Sendable, Equatable {
    public var state: FlyState
    public var position: Vec3
    public var spotID: Int?
    /// Projected position (may be outside 0...1 when off-screen), nil when behind the camera.
    public var screenPosition: FlyScreenPoint?
    /// Bearing from the camera (rad, 0 ahead, positive right).
    public var bearing: Double
    /// Straight-line distance from the camera (m).
    public var cameraDistance: Double
    public var speed: Double

    public init(state: FlyState, position: Vec3, spotID: Int?, screenPosition: FlyScreenPoint?, bearing: Double, cameraDistance: Double, speed: Double) {
        self.state = state
        self.position = position
        self.spotID = spotID
        self.screenPosition = screenPosition
        self.bearing = bearing
        self.cameraDistance = cameraDistance
        self.speed = speed
    }
}

/// Everything the app needs to draw, play and log for one frame.
public struct FlyGameOutput: Sendable, Equatable {
    public var time: Double
    /// Nil when there is no fly (before a round, or between flies).
    public var fly: FlyRenderState?
    public var distance: DistanceEstimate
    /// True while the buzz should play.
    public var buzzing: Bool
    /// -1 (left) ... 1 (right).
    public var audioPan: Double
    /// 0...1. 0 when not buzzing.
    public var audioGain: Double
    public var cues: [FlyGameCue]
    public var splats: [SplatEvent]
    public var smashEvents: [SmashEvent]
    public var verdicts: [HitVerdict]
    public var rejections: [SmashRejection]
    public var transitions: [FlyTransition]
    public var round: FlyRound
    /// Set on the frame a round finishes with a new best: save it with your `BestTimeStore`.
    public var newBestTime: Double?
    /// Session log lines produced this frame (see FlyLog).
    public var logLines: [String]

    public init(time: Double = 0, round: FlyRound = FlyRound()) {
        self.time = time
        self.fly = nil
        self.distance = DistanceEstimate.unknown
        self.buzzing = false
        self.audioPan = 0
        self.audioGain = 0
        self.cues = []
        self.splats = []
        self.smashEvents = []
        self.verdicts = []
        self.rejections = []
        self.transitions = []
        self.round = round
        self.newBestTime = nil
        self.logLines = []
    }
}

/// The façade the app calls once per frame. Owns the round, the fly, the distance estimator,
/// the smash detector and the hit judge.
public struct FlyGame: Sendable, Equatable {
    /// Live-tunable. Changes take effect on the next `step`.
    public var tunables: FlyTunables
    /// Which displayed frame edge is nearest the hinge (from spike P3); `.centre` on the iPad.
    public var hingeEdge: HingeEdge

    public private(set) var round: FlyRound
    public private(set) var fly: FlyAgent?
    public private(set) var estimator: DistanceEstimator
    public private(set) var detector: SmashDetector
    public private(set) var judge: HitJudge
    /// Time of the last `step` (s), nil before the first.
    public private(set) var lastStepTime: Double?

    private var rng: FlyRNG
    private var spawnPending: Bool
    private var announceRoundStart: Bool
    private var respawnAt: Double?

    public init(tunables: FlyTunables = FlyTunables(),
                seed: UInt64,
                hingeEdge: HingeEdge,
                hingeAvailable: Bool,
                fliesPerRound: Int = 3,
                bestTime: Double? = nil) {
        self.tunables = tunables
        self.hingeEdge = hingeEdge
        self.round = FlyRound(fliesPerRound: fliesPerRound, bestTime: bestTime)
        self.fly = nil
        self.estimator = DistanceEstimator(tunables: tunables)
        self.detector = SmashDetector(tunables: tunables, hingeAvailable: hingeAvailable)
        self.judge = HitJudge(bufferDuration: tunables.snapshotBufferDuration)
        self.lastStepTime = nil
        self.rng = FlyRNG(seed: seed)
        self.spawnPending = false
        self.announceRoundStart = false
        self.respawnAt = nil
    }

    /// As above, loading the best time from `store`.
    public init<S: BestTimeStore>(tunables: FlyTunables = FlyTunables(),
                                  seed: UInt64,
                                  hingeEdge: HingeEdge,
                                  hingeAvailable: Bool,
                                  fliesPerRound: Int = 3,
                                  store: S) {
        self.init(tunables: tunables, seed: seed, hingeEdge: hingeEdge, hingeAvailable: hingeAvailable,
                  fliesPerRound: fliesPerRound, bestTime: store.loadBestTime())
    }

    /// Whether the device has a usable hinge API (decides how camera darkening is treated).
    public var hingeAvailable: Bool {
        get { return detector.hingeAvailable }
        set { detector.hingeAvailable = newValue }
    }

    /// Starts a new round. The first fly appears on the next `step`.
    public mutating func startRound() {
        round.start()
        fly = nil
        respawnAt = nil
        spawnPending = true
        announceRoundStart = true
        judge.clear()
        estimator.reset()
    }

    /// Ends the round without a result and removes the fly.
    public mutating func cancelRound() {
        round.cancel()
        fly = nil
        respawnAt = nil
        spawnPending = false
        announceRoundStart = false
    }

    /// Advances the game by `dt` seconds (normally `input.time` minus the previous frame's time;
    /// clamped to `0...tunables.maxStepDt`) and returns what to draw and play.
    public mutating func step(input: FlyGameInput, dt: Double) -> FlyGameOutput {
        let stepDt = dt.isFinite ? FlyMath.clamp(dt, 0, tunables.maxStepDt) : 0
        let now = input.time
        let camera = input.camera
        lastStepTime = now

        estimator.apply(tunables)
        detector.tunables = tunables
        judge.bufferDuration = tunables.snapshotBufferDuration

        var out = FlyGameOutput(time: now, round: round)

        // 1. Spawning.
        if let due = respawnAt, now >= due, round.phase == .playing {
            respawnAt = nil
            spawnPending = true
        }
        if spawnPending && round.phase == .playing {
            spawnFly(camera: camera)
            if announceRoundStart {
                announceRoundStart = false
                out.cues.append(.roundStarted)
                out.logLines.append(FlyLog.line(time: now, tag: "ROUND", message: "started"))
            }
            out.cues.append(.newFly)
            if let f = fly {
                out.logLines.append(FlyLog.line(time: now, tag: "FLY", message: "spawned at " + FlyLog.describe(f.position)))
            }
        }

        // 2. Distance.
        let estimate: DistanceEstimate
        if let f = fly, f.state != .smashed {
            if let m = input.distanceMeasurement, let measuredAt = input.distanceMeasuredAt {
                estimate = estimator.update(m, measuredAt: measuredAt, sourceConfidence: input.distanceConfidence, time: now)
            } else if let m = input.distanceMeasurement {
                estimate = estimator.update(m, sourceConfidence: input.distanceConfidence, time: now)
            } else {
                let geometric = camera.distance(to: f.position)
                estimate = estimator.update(DistanceMeasurement.world(metres: geometric), sourceConfidence: 1.0, time: now)
            }
        } else {
            estimate = estimator.update(nil, sourceConfidence: 0, time: now)
        }
        let motion = PlayerMotion(distance: estimate.metres,
                                  distanceConfidence: estimate.confidence,
                                  approachRate: estimate.approachRate,
                                  angularSpeed: input.angularSpeed)

        // 3. The fly.
        if var f = fly {
            if let tr = f.tick(dt: stepDt, motion: motion, spots: input.spots, tunables: tunables) {
                handleTransition(tr, time: now, output: &out)
            }
            fly = f
        }
        round.tick(dt: stepDt)

        // 4. Snapshot for the hit judge.
        if let f = fly {
            let snap = FlySnapshot(time: now,
                                   flyState: f.state,
                                   flySpeed: f.speed,
                                   distance: estimate.metres,
                                   distanceConfidence: estimate.confidence,
                                   screenPosition: camera.project(f.position))
            judge.record(snap)
        }

        // 5. Smash detection, feeding hinge and luma samples in time order.
        var events: [SmashEvent] = []
        let hs = input.hingeSamples
        let ls = input.lumaSamples
        var hi = 0
        var li = 0
        while hi < hs.count || li < ls.count {
            var takeHinge = false
            if hi < hs.count && li < ls.count {
                takeHinge = hs[hi].time <= ls[li].time
            } else {
                takeHinge = hi < hs.count
            }
            if takeHinge {
                if let e = detector.addHinge(hs[hi]) { events.append(e) }
                hi += 1
            } else {
                if let e = detector.addLuma(ls[li]) { events.append(e) }
                li += 1
            }
        }
        if let e = detector.advance(to: now) { events.append(e) }
        if input.manualSmash {
            if let e = detector.manualSmash(at: now) { events.append(e) }
        }
        let rejected = detector.drainRejections()
        out.rejections = rejected
        for r in rejected {
            out.logLines.append(FlyLog.line(time: r.time, tag: "REJECT", message: FlyLog.describe(r)))
        }

        // 6. Judging.
        for e in events {
            out.smashEvents.append(e)
            out.logLines.append(FlyLog.line(time: e.time, tag: "SMASH", message: FlyLog.describe(e)))
            judgeSmash(e, now: now, output: &out)
        }

        // 7. Render and audio.
        out.distance = estimate
        if let f = fly {
            let distance = camera.distance(to: f.position)
            let bearing = camera.bearing(to: f.position)
            out.fly = FlyRenderState(state: f.state,
                                     position: f.position,
                                     spotID: f.spotID,
                                     screenPosition: camera.project(f.position),
                                     bearing: bearing,
                                     cameraDistance: distance,
                                     speed: f.speed)
            if f.state != .smashed && round.phase == .playing {
                out.buzzing = true
                out.audioPan = AudioMath.pan(bearing: bearing)
                out.audioGain = AudioMath.gain(distance: distance, bearing: bearing, tunables: tunables)
            }
        }
        out.round = round
        return out
    }

    // MARK: Private

    private mutating func spawnFly(camera: FlyCamera) {
        let base = camera.position + camera.forward * tunables.spawnDistance
        let jitter = Vec3(x: rng.nextDouble(from: -0.3, to: 0.3),
                          y: rng.nextDouble(from: -0.15, to: 0.15),
                          z: rng.nextDouble(from: -0.3, to: 0.3))
        fly = FlyAgent(position: base + jitter, seed: rng.next())
        estimator.reset()
        spawnPending = false
    }

    private mutating func handleTransition(_ tr: FlyTransition, time: Double, output: inout FlyGameOutput) {
        output.transitions.append(tr)
        output.logLines.append(FlyLog.line(time: time, tag: "FLY", message: FlyLog.describe(tr)))
        if tr.to == .alarmed {
            output.cues.append(.flyAlarmed)
        }
        if tr.to == .hovering {
            output.cues.append(.flyTookOff)
        }
        if tr.to == .landed {
            // The fly stopped moving: its own flight must not read as the player approaching.
            estimator.rebase()
        }
    }

    private mutating func judgeSmash(_ e: SmashEvent, now: Double, output: inout FlyGameOutput) {
        guard round.phase == .playing, var f = fly, f.state != .smashed else { return }
        let region = HitRegion(hingeEdge: hingeEdge, tunables: tunables)
        let verdict = judge.judge(e, region: region, tunables: tunables)
        output.verdicts.append(verdict)
        output.logLines.append(FlyLog.line(time: now, tag: "JUDGE", message: FlyLog.describe(verdict)))
        if verdict.isHit {
            if let tr = f.markSmashed() {
                output.transitions.append(tr)
                output.logLines.append(FlyLog.line(time: now, tag: "FLY", message: FlyLog.describe(tr)))
            }
            fly = f
            output.splats.append(SplatEvent(time: now, screenPosition: verdict.snapshot?.screenPosition, worldPosition: f.position))
            output.cues.append(.hit)
            let progress = round.recordCatch()
            let caughtText = String(progress.fliesCaught) + "/" + String(round.fliesPerRound)
            let flyTimeText = FlyLog.fixed(progress.flyTime, decimals: 2)
            output.logLines.append(FlyLog.line(time: now, tag: "ROUND", message: "caught \(caughtText) in \(flyTimeText)s"))
            if progress.roundFinished {
                output.cues.append(.roundFinished)
                let roundText = FlyLog.optionalFixed(progress.roundTime, decimals: 2)
                output.logLines.append(FlyLog.line(time: now, tag: "ROUND", message: "finished in \(roundText)s"))
                if progress.isNewBest {
                    output.cues.append(.newBestTime)
                    output.newBestTime = progress.roundTime
                }
            } else {
                respawnAt = now + tunables.respawnDelay
            }
        } else {
            output.cues.append(.miss)
            if let tr = f.alarm(tunables: tunables) {
                handleTransition(tr, time: now, output: &output)
            }
            fly = f
        }
    }
}
