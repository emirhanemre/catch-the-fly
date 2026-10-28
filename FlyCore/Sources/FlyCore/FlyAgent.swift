import Foundation

/// What the fly is doing.
public enum FlyState: String, Sendable, Equatable, CaseIterable {
    /// Flying to a landing spot (or looping lazily if there are none).
    case wandering
    /// Sitting on a landing spot. Follows the spot if the app moves it.
    case landed
    /// Startled: frozen for `alarmDuration`, then escapes.
    case alarmed
    /// Taken off because the player is close; loops near its spot. This is the catch window.
    case hovering
    /// Flying fast to a far spot (or straight away if there are none).
    case escaping
    /// Hit. Terminal.
    case smashed
}

/// A place the fly can land, supplied by the app every frame.
///
/// Route A (world tracking): fixed world points, for example on detected planes.
/// Route B (tracked patches): one spot per tracked image patch; the app recomputes `position`
/// each frame (camera position + direction to the patch * estimated distance) and keeps `id`
/// stable for as long as it tracks that patch. A landed fly follows its spot's position.
public struct LandingSpot: Sendable, Equatable {
    /// Stable identifier chosen by the app. Must be unique within one frame's list.
    public var id: Int
    /// World position (metres) in the same frame as `FlyCamera.position`.
    public var position: Vec3
    /// Unit normal pointing out of the surface, or `Vec3.zero` if unknown.
    public var normal: Vec3
    /// How good a spot it is, 0...1 (for example tracking confidence or texture score).
    public var quality: Double

    public init(id: Int, position: Vec3, normal: Vec3 = Vec3.zero, quality: Double = 1.0) {
        self.id = id
        self.position = position
        self.normal = normal
        self.quality = quality
    }
}

/// What the fly can sense about the player this tick.
public struct PlayerMotion: Sendable, Equatable {
    /// Estimated distance from the phone to the fly (m), nil if unknown.
    public var distance: Double?
    /// Confidence in `distance`, 0...1.
    public var distanceConfidence: Double
    /// How fast the distance is shrinking (m/s, positive = closing in).
    public var approachRate: Double
    /// Magnitude of the device rotation rate (rad/s).
    public var angularSpeed: Double

    public init(distance: Double? = nil, distanceConfidence: Double = 0, approachRate: Double = 0, angularSpeed: Double = 0) {
        self.distance = distance
        self.distanceConfidence = distanceConfidence
        self.approachRate = approachRate
        self.angularSpeed = angularSpeed
    }

    /// No distance information and no motion.
    public static let still = PlayerMotion()
}

/// Why the fly changed state.
public enum FlyTransitionReason: String, Sendable, Equatable, CaseIterable {
    /// Reached its target spot and landed.
    case arrived
    /// Landed timer ran out; off to another spot.
    case restless
    /// The player came within `takeOffDistance`.
    case playerClose
    /// The player moved too fast nearby.
    case alarmed
    /// `alarm()` was called from outside (for example after a missed smash).
    case startled
    /// The startle ended; the fly bolts.
    case startleEnded
    /// Hover timer ran out.
    case hoverEnded
    /// The spot the fly sat on disappeared from the app's list.
    case spotLost
    /// A spot-less escape ran its course.
    case escapeEnded
    /// `markSmashed()` was called.
    case smashed
}

/// One state change.
public struct FlyTransition: Sendable, Equatable {
    public var from: FlyState
    public var to: FlyState
    public var reason: FlyTransitionReason

    public init(from: FlyState, to: FlyState, reason: FlyTransitionReason) {
        self.from = from
        self.to = to
        self.reason = reason
    }
}

/// The fly: a deterministic state machine ticked by `dt`, player motion and the current landing spots.
///
/// Alarm rules: only a landed or hovering fly can be alarmed (a flying fly's own motion would
/// otherwise look like the player approaching). It is alarmed when the distance is known with at
/// least `minDistanceConfidence`, is within `alarmRadius`, and either the approach rate exceeds
/// `alarmApproachRate` or the device rotation exceeds `alarmAngularSpeed` (both multiplied by
/// `hoverAlarmMultiplier` while hovering).
public struct FlyAgent: Sendable, Equatable {
    public private(set) var state: FlyState
    /// World position (m).
    public private(set) var position: Vec3
    /// World velocity over the last tick (m/s).
    public private(set) var velocity: Vec3
    /// Landed/hovering: the spot it is on or near. Wandering/escaping: the target spot. Nil if none.
    public private(set) var spotID: Int?
    /// Seconds spent in the current state.
    public private(set) var stateTime: Double
    /// Countdown for the current state's timer (landed, hovering, alarmed, spot-less escape), in seconds.
    public private(set) var timeRemaining: Double

    private var rng: FlyRNG
    private var hoverAnchor: Vec3
    private var hoverNormal: Vec3
    private var hoverPhase: Double
    private var escapeDirection: Vec3
    private var looping: Bool
    private var loopCentre: Vec3
    private var loopPhase: Double

    /// A wandering fly at `position`.
    public init(position: Vec3, seed: UInt64) {
        self.state = .wandering
        self.position = position
        self.velocity = Vec3.zero
        self.spotID = nil
        self.stateTime = 0
        self.timeRemaining = 0
        self.rng = FlyRNG(seed: seed)
        self.hoverAnchor = position
        self.hoverNormal = Vec3.zero
        self.hoverPhase = 0
        self.escapeDirection = Vec3(x: 1, y: 0, z: 0)
        self.looping = false
        self.loopCentre = position
        self.loopPhase = 0
    }

    /// A fly already landed on `spot`, staying for `landedDuration` seconds unless disturbed.
    public init(landedOn spot: LandingSpot, seed: UInt64, landedDuration: Double) {
        self.init(position: spot.position, seed: seed)
        self.state = .landed
        self.spotID = spot.id
        self.timeRemaining = landedDuration
    }

    /// Current speed (m/s).
    public var speed: Double {
        return velocity.length
    }

    // MARK: Public mutations

    /// Advances the fly by `dt` seconds. Returns the state change, if one happened.
    /// At most one transition happens per tick. `dt <= 0` does nothing.
    @discardableResult
    public mutating func tick(dt: Double, motion: PlayerMotion, spots: [LandingSpot], tunables: FlyTunables) -> FlyTransition? {
        if !dt.isFinite || dt <= 0 { return nil }
        let start = position
        stateTime += dt
        var result: FlyTransition? = nil
        switch state {
        case .wandering:
            result = tickWandering(dt: dt, spots: spots, tunables: tunables)
        case .landed:
            result = tickLanded(dt: dt, motion: motion, spots: spots, tunables: tunables)
        case .alarmed:
            result = tickAlarmed(dt: dt, spots: spots, tunables: tunables)
        case .hovering:
            result = tickHovering(dt: dt, motion: motion, spots: spots, tunables: tunables)
        case .escaping:
            result = tickEscaping(dt: dt, spots: spots, tunables: tunables)
        case .smashed:
            result = nil
        }
        if state == .smashed {
            velocity = Vec3.zero
        } else {
            velocity = (position - start) / dt
        }
        return result
    }

    /// Startles the fly (for example after a missed smash). Works from wandering, landed and
    /// hovering; returns nil (and does nothing) if alarmed, escaping or smashed.
    @discardableResult
    public mutating func alarm(tunables: FlyTunables) -> FlyTransition? {
        switch state {
        case .wandering, .landed, .hovering:
            timeRemaining = tunables.alarmDuration
            return enter(.alarmed, reason: .startled)
        case .alarmed, .escaping, .smashed:
            return nil
        }
    }

    /// Marks the fly as hit. Returns nil if it already was.
    @discardableResult
    public mutating func markSmashed() -> FlyTransition? {
        if state == .smashed { return nil }
        velocity = Vec3.zero
        timeRemaining = 0
        return enter(.smashed, reason: .smashed)
    }

    // MARK: States

    private mutating func tickWandering(dt: Double, spots: [LandingSpot], tunables: FlyTunables) -> FlyTransition? {
        var target: LandingSpot? = nil
        if let id = spotID {
            target = FlyAgent.findSpot(id, in: spots)
        }
        if target == nil {
            target = chooseSpot(spots, excluding: nil, tunables: tunables)
            spotID = target?.id
        }
        if let spot = target {
            looping = false
            if moveTowards(spot.position, speed: tunables.wanderSpeed, dt: dt, arrivalRadius: tunables.arrivalRadius) {
                timeRemaining = randomLandedDuration(tunables)
                return enter(.landed, reason: .arrived)
            }
            return nil
        }
        // No spots at all: loop lazily in a horizontal circle.
        let r = max(tunables.noSpotLoopRadius, 0.01)
        if !looping {
            looping = true
            loopCentre = position - Vec3(x: r, y: 0, z: 0)
            loopPhase = 0
        }
        loopPhase += max(tunables.wanderSpeed, 0) / r * dt
        position = loopCentre + Vec3(x: r * cos(loopPhase), y: 0, z: r * sin(loopPhase))
        return nil
    }

    private mutating func tickLanded(dt: Double, motion: PlayerMotion, spots: [LandingSpot], tunables: FlyTunables) -> FlyTransition? {
        guard let id = spotID, let spot = FlyAgent.findSpot(id, in: spots) else {
            spotID = chooseSpot(spots, excluding: nil, tunables: tunables)?.id
            return enter(.wandering, reason: .spotLost)
        }
        position = spot.position
        if FlyAgent.isAlarming(motion, tunables: tunables, multiplier: 1.0) {
            timeRemaining = tunables.alarmDuration
            return enter(.alarmed, reason: .alarmed)
        }
        if FlyAgent.isClose(motion, tunables: tunables) {
            hoverAnchor = spot.position
            hoverNormal = spot.normal
            hoverPhase = 0
            timeRemaining = tunables.hoverDuration
            return enter(.hovering, reason: .playerClose)
        }
        timeRemaining -= dt
        if timeRemaining <= 0 {
            spotID = chooseSpot(spots, excluding: id, tunables: tunables)?.id
            return enter(.wandering, reason: .restless)
        }
        return nil
    }

    private mutating func tickAlarmed(dt: Double, spots: [LandingSpot], tunables: FlyTunables) -> FlyTransition? {
        timeRemaining -= dt
        if timeRemaining <= 0 {
            beginEscape(spots: spots, tunables: tunables)
            return enter(.escaping, reason: .startleEnded)
        }
        return nil
    }

    private mutating func tickHovering(dt: Double, motion: PlayerMotion, spots: [LandingSpot], tunables: FlyTunables) -> FlyTransition? {
        if let id = spotID, let spot = FlyAgent.findSpot(id, in: spots) {
            hoverAnchor = spot.position
            hoverNormal = spot.normal
        }
        if FlyAgent.isAlarming(motion, tunables: tunables, multiplier: tunables.hoverAlarmMultiplier) {
            timeRemaining = tunables.alarmDuration
            return enter(.alarmed, reason: .alarmed)
        }
        hoverPhase += tunables.hoverAngularSpeed * dt
        position = hoverPosition(tunables)
        timeRemaining -= dt
        if timeRemaining <= 0 {
            beginEscape(spots: spots, tunables: tunables)
            return enter(.escaping, reason: .hoverEnded)
        }
        return nil
    }

    private mutating func tickEscaping(dt: Double, spots: [LandingSpot], tunables: FlyTunables) -> FlyTransition? {
        if let id = spotID {
            if let target = FlyAgent.findSpot(id, in: spots) {
                if moveTowards(target.position, speed: tunables.escapeSpeed, dt: dt, arrivalRadius: tunables.arrivalRadius) {
                    timeRemaining = randomLandedDuration(tunables)
                    return enter(.landed, reason: .arrived)
                }
                return nil
            }
            // Target vanished mid-escape: pick another, or fly straight off.
            beginEscape(spots: spots, tunables: tunables)
            return nil
        }
        position = position + escapeDirection * (tunables.escapeSpeed * dt)
        timeRemaining -= dt
        if timeRemaining <= 0 {
            spotID = chooseSpot(spots, excluding: nil, tunables: tunables)?.id
            return enter(.wandering, reason: .escapeEnded)
        }
        return nil
    }

    // MARK: Helpers

    private mutating func enter(_ newState: FlyState, reason: FlyTransitionReason) -> FlyTransition {
        let t = FlyTransition(from: state, to: newState, reason: reason)
        state = newState
        stateTime = 0
        return t
    }

    /// Moves towards `target`; returns true (and snaps onto it) on arrival.
    private mutating func moveTowards(_ target: Vec3, speed: Double, dt: Double, arrivalRadius: Double) -> Bool {
        let delta = target - position
        let d = delta.length
        let step = max(speed, 0) * dt
        if d <= max(arrivalRadius, step) {
            position = target
            return true
        }
        position = position + delta * (step / d)
        return false
    }

    private func hoverPosition(_ tunables: FlyTunables) -> Vec3 {
        var lift = 1.0
        if tunables.hoverLiftTime > 0 {
            lift = FlyMath.clamp(stateTime / tunables.hoverLiftTime, 0, 1)
        }
        let n = hoverNormal.normalised()
        let basis = FlyAgent.tangentBasis(n)
        let r = tunables.hoverRadius
        // Split up so the type checker stays fast inside an app module full of operator overloads.
        let sideAmount: Double = r * sin(hoverPhase)
        let upAmount: Double = 0.5 * r * sin(2.0 * hoverPhase)
        let loop: Vec3 = basis.0 * sideAmount + basis.1 * upAmount
        let lifted: Vec3 = hoverAnchor + n * (tunables.hoverStandoff * lift)
        return lifted + loop
    }

    private mutating func beginEscape(spots: [LandingSpot], tunables: FlyTunables) {
        let pick = chooseEscapeSpot(spots, tunables: tunables)
        spotID = pick?.id
        if pick == nil {
            escapeDirection = randomDirection()
            timeRemaining = tunables.escapeNoSpotDuration
        }
    }

    private mutating func randomLandedDuration(_ tunables: FlyTunables) -> Double {
        let lo = max(0, tunables.landedMinDuration)
        let hi = max(lo, tunables.landedMaxDuration)
        return rng.nextDouble(from: lo, to: hi)
    }

    private mutating func randomDirection() -> Vec3 {
        let v = Vec3(
            x: rng.nextDouble(from: -1, to: 1),
            y: rng.nextDouble(from: -0.5, to: 0.5),
            z: rng.nextDouble(from: -1, to: 1)
        ).normalised()
        if v == Vec3.zero { return Vec3(x: 1, y: 0, z: 0) }
        return v
    }

    /// Random spot, preferring good quality and avoiding `excluding`; falls back to any spot.
    private mutating func chooseSpot(_ spots: [LandingSpot], excluding: Int?, tunables: FlyTunables) -> LandingSpot? {
        if spots.isEmpty { return nil }
        var candidates: [LandingSpot] = []
        for s in spots where s.quality >= tunables.minSpotQuality && s.id != excluding {
            candidates.append(s)
        }
        if candidates.isEmpty {
            for s in spots where s.id != excluding {
                candidates.append(s)
            }
        }
        if candidates.isEmpty {
            candidates = spots
        }
        return candidates[rng.nextInt(below: candidates.count)]
    }

    /// Escape target: never the current spot; a random spot at least `escapeMinDistance` away,
    /// else the farthest one. Nil if there is no other spot.
    private mutating func chooseEscapeSpot(_ spots: [LandingSpot], tunables: FlyTunables) -> LandingSpot? {
        let current = spotID
        var eligible: [LandingSpot] = []
        for s in spots where s.quality >= tunables.minSpotQuality && s.id != current {
            eligible.append(s)
        }
        if eligible.isEmpty {
            for s in spots where s.id != current {
                eligible.append(s)
            }
        }
        if eligible.isEmpty { return nil }
        var far: [LandingSpot] = []
        for s in eligible where s.position.distance(to: position) >= tunables.escapeMinDistance {
            far.append(s)
        }
        if !far.isEmpty {
            return far[rng.nextInt(below: far.count)]
        }
        var best = eligible[0]
        var bestDistance = best.position.distance(to: position)
        for s in eligible {
            let d = s.position.distance(to: position)
            if d > bestDistance {
                best = s
                bestDistance = d
            }
        }
        return best
    }

    private static func findSpot(_ id: Int, in spots: [LandingSpot]) -> LandingSpot? {
        for s in spots where s.id == id {
            return s
        }
        return nil
    }

    private static func isAlarming(_ motion: PlayerMotion, tunables: FlyTunables, multiplier: Double) -> Bool {
        guard let d = motion.distance, motion.distanceConfidence >= tunables.minDistanceConfidence else { return false }
        if d > tunables.alarmRadius { return false }
        if motion.approachRate > tunables.alarmApproachRate * multiplier { return true }
        if motion.angularSpeed > tunables.alarmAngularSpeed * multiplier { return true }
        return false
    }

    private static func isClose(_ motion: PlayerMotion, tunables: FlyTunables) -> Bool {
        guard let d = motion.distance, motion.distanceConfidence >= tunables.minDistanceConfidence else { return false }
        return d <= tunables.takeOffDistance
    }

    /// Two unit vectors perpendicular to `n` (and to each other). For a zero normal: +X and +Y.
    private static func tangentBasis(_ n: Vec3) -> (Vec3, Vec3) {
        if n == Vec3.zero {
            return (Vec3(x: 1, y: 0, z: 0), Vec3(x: 0, y: 1, z: 0))
        }
        var t1 = n.cross(Vec3(x: 0, y: 1, z: 0))
        if t1.length < 1e-6 {
            t1 = n.cross(Vec3(x: 1, y: 0, z: 0))
        }
        t1 = t1.normalised()
        let t2 = n.cross(t1).normalised()
        return (t1, t2)
    }
}
