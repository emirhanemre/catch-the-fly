import Foundation

/// Every gameplay number in one place. Units: metres, seconds, radians, radians per second,
/// metres per second; luma is a mean brightness in 0...1.
///
/// All properties have defaults, so `FlyTunables()` is a playable starting point.
/// Change a value with `var t = FlyTunables(); t.smashDistance = 0.15`.
public struct FlyTunables: Sendable, Equatable {

    // MARK: Fly flight

    /// Cruising speed while wandering between landing spots (m/s).
    public var wanderSpeed: Double = 0.5
    /// Speed while escaping after an alarm or a miss (m/s).
    public var escapeSpeed: Double = 2.0
    /// Within this distance of a spot the fly snaps onto it and lands (m).
    public var arrivalRadius: Double = 0.03
    /// Shortest time the fly sits on a spot before getting restless (s).
    public var landedMinDuration: Double = 3.0
    /// Longest time the fly sits on a spot before getting restless (s).
    public var landedMaxDuration: Double = 8.0
    /// Spots with a quality below this are avoided when better ones exist (0...1).
    public var minSpotQuality: Double = 0.3
    /// Radius of the lazy circle the fly flies when the app supplies no spots (m).
    public var noSpotLoopRadius: Double = 0.4
    /// A new fly appears this far in front of the camera (m).
    public var spawnDistance: Double = 1.5
    /// Delay between a hit and the next fly of the round appearing (s).
    public var respawnDelay: Double = 1.5

    // MARK: Alarm and escape

    /// The fly only notices the player within this distance (m).
    public var alarmRadius: Double = 1.5
    /// Device rotation rate above which a nearby fly is alarmed ("alarm speed", rad/s).
    public var alarmAngularSpeed: Double = 2.0
    /// Closing speed above which a nearby fly is alarmed ("alarm approach rate", m/s).
    public var alarmApproachRate: Double = 0.6
    /// While hovering, both alarm thresholds are multiplied by this (the catch window is forgiving).
    public var hoverAlarmMultiplier: Double = 2.0
    /// How long the fly freezes, startled, before bolting (s).
    public var alarmDuration: Double = 0.25
    /// When escaping, prefer spots at least this far from where the fly was (m).
    public var escapeMinDistance: Double = 0.5
    /// With no spot to escape to, the fly flies off in a straight line for this long (s).
    public var escapeNoSpotDuration: Double = 1.5

    // MARK: Hover (the catch window)

    /// A landed fly takes off and hovers when the player is this close (m).
    public var takeOffDistance: Double = 0.30
    /// How long the fly hovers before getting bored and escaping (s).
    public var hoverDuration: Double = 4.0
    /// Hover centre sits this far off the spot, along the spot's normal (m).
    public var hoverStandoff: Double = 0.06
    /// Time to rise from the spot to the hover centre (s).
    public var hoverLiftTime: Double = 0.3
    /// Size of the lazy figure-of-eight loop while hovering (m).
    public var hoverRadius: Double = 0.04
    /// Phase speed of the hover loop (rad/s).
    public var hoverAngularSpeed: Double = 2.5

    // MARK: Distance estimate

    /// Distance readings with a confidence below this are ignored by the fly (0...1).
    public var minDistanceConfidence: Double = 0.3
    /// Smoothing time constant for the distance (s).
    public var distanceSmoothingTime: Double = 0.12
    /// Smoothing time constant for the approach rate (s).
    public var approachRateSmoothingTime: Double = 0.25
    /// Confidence fades to zero this long after the last measurement (s).
    public var distanceStaleTime: Double = 0.5
    /// A raw change faster than this is treated as a glitch or a patch switch, not motion (m/s).
    public var distanceJumpRate: Double = 4.0
    /// Measurements are clamped to at least this (m).
    public var minimumDistance: Double = 0.02
    /// Measurements are clamped to at most this (m).
    public var maximumDistance: Double = 20.0

    // MARK: Route B patch reference distance (PatchReferencePolicy)

    /// Distance assumed for a patch seeded with no tracked peers to borrow from (m). The player is asked
    /// to start about 1 m from the scene.
    public var patchDefaultReferenceDistance: Double = 1.0
    /// A new patch borrows the median distance of its peers only when at least this many qualify.
    public var patchReferenceMinimumPeers: Int = 1
    /// Peers with a tracking confidence below this are not borrowed from (0...1).
    public var patchReferenceMinimumPeerConfidence: Double = 0.3
    /// The distance a new patch is seeded at is clamped to at least this (m).
    public var patchReferenceMinimumDistance: Double = 0.2
    /// The distance a new patch is seeded at is clamped to at most this (m).
    public var patchReferenceMaximumDistance: Double = 5.0

    // MARK: Smash detection: hinge

    /// The hinge counts as open (and arms the detector) at or above this angle (rad, about 40 degrees).
    public var hingeArmAngle: Double = 0.7
    /// The hinge counts as shut at or below this angle, or when status is `.closed` (rad, about 7 degrees).
    public var hingeClosedAngle: Double = 0.12
    /// A close must fold through at least this much angle (rad).
    public var hingeMinCloseDrop: Double = 0.5
    /// Slowest average closing speed that still counts as a smash ("smash angle velocity", rad/s).
    /// Deliberately low: a slow, careful close counts. Nothing rewards slamming.
    public var smashMinAngularSpeed: Double = 0.6
    /// Typical closing speed, used to estimate when motion began between sparse hinge samples (rad/s).
    public var smashNominalAngularSpeed: Double = 2.5
    /// Hinge segments slower than this, and smaller than `hingeSegmentMinDrop`, are drift, not the close (rad/s).
    public var hingeStillSpeed: Double = 0.2
    /// A hinge segment dropping at least this much is part of the close however slow it looks (rad).
    public var hingeSegmentMinDrop: Double = 0.1
    /// Longest close that counts, from motion start to shut (s).
    public var closeMaxDuration: Double = 2.5
    /// With the hinge available, darkness is confirmed when the hinge has fallen at least this much (rad).
    public var hingeCorroborationDrop: Double = 0.15
    /// How long a dark camera waits for the hinge to confirm before it is rejected as a hand (s).
    public var hingeCorroborationWindow: Double = 0.25
    /// Maps raw `UIHinge.status` integers (`HingeSample.statusRaw`) to `HingeStatus`. A guess until spike P5.
    public var hingeStatusMapping: HingeStatusMapping = HingeStatusMapping.declarationOrderGuess

    // MARK: Smash detection: camera darkening

    /// Mean luma at or below this counts as dark ("darkening threshold", 0...1).
    public var darkeningThreshold: Double = 0.06
    /// Mean luma at or above this counts as lit, and re-arms the luma path (0...1).
    public var litThreshold: Double = 0.15
    /// How far back to look for the lit baseline before a collapse (s).
    public var lumaLookback: Double = 1.0
    /// The collapse starts at the last sample at or above this fraction of the baseline.
    public var lumaStartFraction: Double = 0.85
    /// Without a hinge, the collapse from lit to dark must take no longer than this (s).
    public var lumaCollapseMaxDuration: Double = 0.5
    /// The half starts moving this long before the luma starts falling; subtracted from the luma start (s).
    public var lumaMotionLead: Double = 0.1
    /// A luma stream silent for this long counts as stopped (s).
    public var lumaStallTimeout: Double = 0.15
    /// A stopped stream counts as a collapse if its last value had fallen to this fraction of the baseline.
    public var lumaStallDropRatio: Double = 0.6
    /// Without a hinge, may a stream that stopped while dropping fire a smash on its own?
    public var lumaStallCountsAlone: Bool = true

    // MARK: Smash detection: both

    /// Minimum time between two smash events (s).
    public var smashDebounce: Double = 0.8

    // MARK: Hit judging

    /// Length of the game-state ring buffer (s).
    public var snapshotBufferDuration: Double = 1.0
    /// The judged snapshot is taken this long before the smash's motion start (s).
    public var judgeLeadTime: Double = 0.03
    /// The fly must be nearer than this to be hit (m).
    public var smashDistance: Double = 0.12
    /// A fly that is not hovering must be slower than this to be hit (m/s).
    public var hitMaxFlySpeed: Double = 0.4
    /// Width of the hinge-side hit region, as a fraction of the frame measured from the hinge edge.
    /// For `HingeEdge.centre` it is the side of a centred square.
    public var hitRegionWidth: Double = 0.5
    /// Strip at the very hinge edge excluded from the hit region (occluded by the forward half).
    public var hitBlockedMargin: Double = 0.06

    // MARK: Audio

    /// At or nearer than this the buzz plays at full gain (m).
    public var audioReferenceDistance: Double = 0.3
    /// The buzz never drops below this gain from distance alone (0...1).
    public var audioMinimumGain: Double = 0.05
    /// Directly behind, the gain is reduced by this fraction (0...1).
    public var audioRearAttenuation: Double = 0.4

    // MARK: Simulation

    /// Longest simulation step; bigger `dt` values (after a pause) are clamped to this (s).
    public var maxStepDt: Double = 0.1

    public init() {}
}
