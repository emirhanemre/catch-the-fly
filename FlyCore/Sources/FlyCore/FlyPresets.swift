import Foundation

/// Named starting points for `FlyTunables`. Every value that differs from `FlyTunables()` is a
/// documented guess until the spike and playtests measure it; tune by copying and changing one field.
extension FlyTunables {
    /// The iPad stand-in (phase 4: rear camera, route B, smash = hand over the lens or the debug button).
    /// Use with `HingeEdge.centre`.
    /// - `smashDistance` 0.25 m: the iPad can't focus or track a patch from 12 cm, so the whole hover
    ///   window (hover starts at `takeOffDistance`, 30 cm) is accepted.
    public static let iPadPrototype: FlyTunables = {
        var t = FlyTunables()
        t.smashDistance = 0.25
        return t
    }()

    /// iPhone Duo, Posture A (the design: half-open L, inner camera, fold the forward half shut).
    /// The design values, `FlyTunables()` unchanged: 12 cm smash distance, 30 cm take-off, a hinge-side
    /// region half the frame wide with a 6 % occluded strip. The hinge edge comes from spike P3.
    public static let duoPostureA: FlyTunables = FlyTunables()

    /// iPhone Duo, Posture B (fallback: opened wide, about 120 to 150 degrees, rear cameras, close the book).
    /// Guesses, to be checked on the device:
    /// - `closeMaxDuration` 4.0 s: the fold starts from about 2.4 rad instead of about 1.6, so a slow,
    ///   careful close (at `smashMinAngularSpeed`, 0.6 rad/s) needs up to 4 s. Nothing rewards slamming.
    /// - `smashDistance` 0.15 m: the wide-open book sweeps a bigger wedge than the L.
    /// - `hitRegionWidth` 0.6: the fly is drawn across the fold, so the region is a centred square
    ///   (use with `HingeEdge.centre`), a little larger than the default.
    public static let duoPostureB: FlyTunables = {
        var t = FlyTunables()
        t.closeMaxDuration = 4.0
        t.smashDistance = 0.15
        t.hitRegionWidth = 0.6
        return t
    }()
}

/// Tunables plus the hit-region edge they are meant for, so the app picks a platform in one line.
public struct FlyPreset: Sendable, Equatable {
    public var name: String
    public var tunables: FlyTunables
    /// The edge to pass to `FlyGame(hingeEdge:)`.
    public var hingeEdge: HingeEdge

    public init(name: String, tunables: FlyTunables, hingeEdge: HingeEdge) {
        self.name = name
        self.tunables = tunables
        self.hingeEdge = hingeEdge
    }

    /// `FlyTunables.iPadPrototype` with `.centre`.
    public static let iPadPrototype = FlyPreset(name: "iPadPrototype", tunables: FlyTunables.iPadPrototype, hingeEdge: .centre)
    /// `FlyTunables.duoPostureA` with `.right`: a guess until spike P3 reports the edge nearest the hinge.
    public static let duoPostureA = FlyPreset(name: "duoPostureA", tunables: FlyTunables.duoPostureA, hingeEdge: .right)
    /// `FlyTunables.duoPostureB` with `.centre` (the fly is drawn across the fold).
    public static let duoPostureB = FlyPreset(name: "duoPostureB", tunables: FlyTunables.duoPostureB, hingeEdge: .centre)

    /// Every preset above, in that order.
    public static let all: [FlyPreset] = [iPadPrototype, duoPostureA, duoPostureB]
}
