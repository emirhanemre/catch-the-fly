import Foundation

/// Which edge of the camera frame (as displayed) is nearest the hinge.
public enum HingeEdge: String, Sendable, Equatable, CaseIterable {
    case left
    case right
    case top
    case bottom
    /// No hinge (the iPad stand-in): the hit region is a centred square. (Not called `none`, to avoid confusion with `Optional.none`.)
    case centre
}

/// The part of the screen where a fly can be smashed, in normalised screen coordinates
/// (x 0 left to 1 right, y 0 top to 1 bottom).
///
/// For an edge: a strip running from `blockedMargin` to `width`, measured inwards from that edge.
/// The first `blockedMargin` is excluded because the forward half of the phone occludes the
/// hinge-side edge of the inner camera's frame. For `.centre`: a centred square with side `width`
/// (`blockedMargin` is ignored).
public struct HitRegion: Sendable, Equatable {
    public var hingeEdge: HingeEdge
    public var width: Double
    public var blockedMargin: Double

    public init(hingeEdge: HingeEdge, width: Double, blockedMargin: Double) {
        self.hingeEdge = hingeEdge
        self.width = width
        self.blockedMargin = blockedMargin
    }

    /// Uses `hitRegionWidth` and `hitBlockedMargin` from the tunables.
    public init(hingeEdge: HingeEdge, tunables: FlyTunables) {
        self.init(hingeEdge: hingeEdge, width: tunables.hitRegionWidth, blockedMargin: tunables.hitBlockedMargin)
    }

    public func contains(_ p: FlyScreenPoint) -> Bool {
        if !p.isOnScreen { return false }
        let w = FlyMath.clamp(width, 0, 1)
        let m = FlyMath.clamp(blockedMargin, 0, 1)
        switch hingeEdge {
        case .left:
            return p.x >= m && p.x <= w
        case .right:
            return p.x >= 1.0 - w && p.x <= 1.0 - m
        case .top:
            return p.y >= m && p.y <= w
        case .bottom:
            return p.y >= 1.0 - w && p.y <= 1.0 - m
        case .centre:
            let half = w * 0.5
            return abs(p.x - 0.5) <= half && abs(p.y - 0.5) <= half
        }
    }
}

/// The game state at one moment, as the hit judge needs it.
public struct FlySnapshot: Sendable, Equatable {
    public var time: Double
    public var flyState: FlyState
    /// Fly speed (m/s).
    public var flySpeed: Double
    /// Estimated distance to the fly (m), nil if unknown.
    public var distance: Double?
    public var distanceConfidence: Double
    /// Where the fly was drawn, nil if behind the camera.
    public var screenPosition: FlyScreenPoint?

    public init(time: Double, flyState: FlyState, flySpeed: Double, distance: Double?, distanceConfidence: Double, screenPosition: FlyScreenPoint?) {
        self.time = time
        self.flyState = flyState
        self.flySpeed = flySpeed
        self.distance = distance
        self.distanceConfidence = distanceConfidence
        self.screenPosition = screenPosition
    }
}

/// Outcome of judging a smash. Checked in this order; the first failure is the reason.
public enum HitReason: String, Sendable, Equatable, CaseIterable {
    case hit
    /// No game state recorded yet.
    case noSnapshot
    /// The fly was already smashed.
    case alreadySmashed
    /// The fly was escaping.
    case flyEscaping
    /// Not hovering and faster than `hitMaxFlySpeed`.
    case flyTooFast
    /// Distance unknown or below `minDistanceConfidence`.
    case distanceUnknown
    /// Farther than `smashDistance`.
    case tooFar
    /// Not on screen (behind the camera or outside the frame).
    case offScreen
    /// On screen but outside the hit region.
    case outsideHitRegion
}

public struct HitVerdict: Sendable, Equatable {
    public var isHit: Bool
    public var reason: HitReason
    public var event: SmashEvent
    /// The snapshot judged, nil if there was none.
    public var snapshot: FlySnapshot?
    /// The time the snapshot was looked up for (`motionStartTime - judgeLeadTime`).
    public var judgedTime: Double

    public init(isHit: Bool, reason: HitReason, event: SmashEvent, snapshot: FlySnapshot?, judgedTime: Double) {
        self.isHit = isHit
        self.reason = reason
        self.event = event
        self.snapshot = snapshot
        self.judgedTime = judgedTime
    }
}

/// Keeps a short ring buffer of snapshots and judges smashes against the state from just before the fold.
public struct HitJudge: Sendable, Equatable {
    /// Snapshots older than this, relative to the newest, are dropped (s).
    public var bufferDuration: Double
    /// Oldest first.
    public private(set) var snapshots: [FlySnapshot]

    /// Hard cap on the buffer, whatever the frame rate.
    public static let maxSnapshots = 480

    public init(bufferDuration: Double = 1.0) {
        self.bufferDuration = bufferDuration
        self.snapshots = []
    }

    /// Adds a snapshot. Snapshots older than the newest one are ignored.
    public mutating func record(_ snapshot: FlySnapshot) {
        if !snapshot.time.isFinite { return }
        if let last = snapshots.last, snapshot.time < last.time { return }
        snapshots.append(snapshot)
        let cutoff = snapshot.time - bufferDuration
        var drop = 0
        while drop < snapshots.count - 1 && snapshots[drop].time < cutoff {
            drop += 1
        }
        if snapshots.count - drop > HitJudge.maxSnapshots {
            drop = snapshots.count - HitJudge.maxSnapshots
        }
        if drop > 0 {
            snapshots.removeFirst(drop)
        }
    }

    public mutating func clear() {
        snapshots = []
    }

    /// The newest snapshot at or before `time`. If `time` is older than the whole buffer, the oldest
    /// snapshot. Nil only when the buffer is empty.
    public func snapshot(at time: Double) -> FlySnapshot? {
        if snapshots.isEmpty { return nil }
        var i = snapshots.count - 1
        while i >= 0 {
            if snapshots[i].time <= time { return snapshots[i] }
            i -= 1
        }
        return snapshots[0]
    }

    /// Judges `event` against the snapshot at `event.motionStartTime - tunables.judgeLeadTime`.
    public func judge(_ event: SmashEvent, region: HitRegion, tunables: FlyTunables) -> HitVerdict {
        let t = event.motionStartTime - tunables.judgeLeadTime
        guard let s = snapshot(at: t) else {
            return HitVerdict(isHit: false, reason: .noSnapshot, event: event, snapshot: nil, judgedTime: t)
        }
        let reason = HitJudge.reason(for: s, region: region, tunables: tunables)
        return HitVerdict(isHit: reason == .hit, reason: reason, event: event, snapshot: s, judgedTime: t)
    }

    /// The verdict for a single snapshot, without the buffer lookup.
    public static func reason(for s: FlySnapshot, region: HitRegion, tunables: FlyTunables) -> HitReason {
        switch s.flyState {
        case .smashed:
            return .alreadySmashed
        case .escaping:
            return .flyEscaping
        case .hovering:
            break
        case .wandering, .landed, .alarmed:
            if s.flySpeed > tunables.hitMaxFlySpeed { return .flyTooFast }
        }
        guard let d = s.distance, s.distanceConfidence >= tunables.minDistanceConfidence else {
            return .distanceUnknown
        }
        if d > tunables.smashDistance { return .tooFar }
        guard let p = s.screenPosition, p.isOnScreen else { return .offScreen }
        if !region.contains(p) { return .outsideHitRegion }
        return .hit
    }
}
