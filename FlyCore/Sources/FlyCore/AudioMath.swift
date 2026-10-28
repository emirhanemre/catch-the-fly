import Foundation

/// Left and right channel gains for an equal-power pan.
public struct StereoGains: Sendable, Equatable {
    public var left: Double
    public var right: Double

    public init(left: Double, right: Double) {
        self.left = left
        self.right = right
    }
}

/// Buzz positioning: bearing to pan, distance to gain.
public enum AudioMath {
    /// Stereo pan for a bearing in radians (0 ahead, positive right): -1 full left ... 1 full right.
    /// `sin(bearing)` up to 90 degrees either side; anything further round stays fully to that side.
    public static func pan(bearing: Double) -> Double {
        let b = FlyMath.clamp(FlyMath.wrapAngle(bearing), -Double.pi / 2, Double.pi / 2)
        return FlyMath.clamp(sin(b), -1, 1)
    }

    /// 1 at or inside `referenceDistance`, falling as `referenceDistance / distance`, never below `minimumGain`.
    public static func distanceGain(distance: Double, referenceDistance: Double, minimumGain: Double) -> Double {
        let minGain = FlyMath.clamp(minimumGain, 0, 1)
        if !distance.isFinite || !(referenceDistance > 0) { return minGain }
        let g = referenceDistance / max(distance, referenceDistance)
        return FlyMath.clamp(g, minGain, 1)
    }

    /// 1 straight ahead, `1 - rearAttenuation` directly behind, smooth (cosine) in between.
    public static func rearFactor(bearing: Double, rearAttenuation: Double) -> Double {
        let a = FlyMath.clamp(rearAttenuation, 0, 1)
        let c = cos(bearing)
        return 1.0 - a * (1.0 - c) * 0.5
    }

    /// Overall buzz gain: `distanceGain * rearFactor`, using the audio tunables.
    public static func gain(distance: Double, bearing: Double, tunables: FlyTunables) -> Double {
        let d = distanceGain(distance: distance, referenceDistance: tunables.audioReferenceDistance, minimumGain: tunables.audioMinimumGain)
        return d * rearFactor(bearing: bearing, rearAttenuation: tunables.audioRearAttenuation)
    }

    /// Equal-power channel gains for a pan of -1...1 (centre gives about 0.707 each).
    public static func stereoGains(pan: Double) -> StereoGains {
        let p = FlyMath.clamp(pan, -1, 1)
        let a = (p + 1.0) * Double.pi / 4.0
        return StereoGains(left: cos(a), right: sin(a))
    }
}
