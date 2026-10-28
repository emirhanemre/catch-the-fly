import Foundation

// MARK: - Vec3

/// A small 3D vector of Doubles. FlyCore's stand-in for `simd_double3`.
/// Units are whatever the caller uses; FlyCore assumes metres.
public struct Vec3: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vec3(x: 0, y: 0, z: 0)

    public static func + (lhs: Vec3, rhs: Vec3) -> Vec3 {
        return Vec3(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    public static func - (lhs: Vec3, rhs: Vec3) -> Vec3 {
        return Vec3(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }

    public static func * (lhs: Vec3, rhs: Double) -> Vec3 {
        return Vec3(x: lhs.x * rhs, y: lhs.y * rhs, z: lhs.z * rhs)
    }

    public static func * (lhs: Double, rhs: Vec3) -> Vec3 {
        return Vec3(x: rhs.x * lhs, y: rhs.y * lhs, z: rhs.z * lhs)
    }

    /// Division by zero gives `Vec3.zero` rather than infinities.
    public static func / (lhs: Vec3, rhs: Double) -> Vec3 {
        if rhs == 0 { return Vec3.zero }
        return Vec3(x: lhs.x / rhs, y: lhs.y / rhs, z: lhs.z / rhs)
    }

    public static prefix func - (v: Vec3) -> Vec3 {
        return Vec3(x: -v.x, y: -v.y, z: -v.z)
    }

    public func dot(_ other: Vec3) -> Double {
        return x * other.x + y * other.y + z * other.z
    }

    public func cross(_ other: Vec3) -> Vec3 {
        return Vec3(
            x: y * other.z - z * other.y,
            y: z * other.x - x * other.z,
            z: x * other.y - y * other.x
        )
    }

    public var lengthSquared: Double {
        return x * x + y * y + z * z
    }

    public var length: Double {
        return lengthSquared.squareRoot()
    }

    /// Unit vector in the same direction, or `Vec3.zero` if the length is (nearly) zero.
    public func normalised() -> Vec3 {
        let l = length
        if l < 1e-12 { return Vec3.zero }
        return Vec3(x: x / l, y: y / l, z: z / l)
    }

    public func distance(to other: Vec3) -> Double {
        return (self - other).length
    }
}

// MARK: - FlyMath

/// Scalar helpers. A caseless enum used as a namespace.
public enum FlyMath {
    /// Clamps `value` into `lo...hi`. A NaN value returns `lo`.
    public static func clamp(_ value: Double, _ lo: Double, _ hi: Double) -> Double {
        if value.isNaN { return lo }
        if value < lo { return lo }
        if value > hi { return hi }
        return value
    }

    /// Linear interpolation: `a` at `t == 0`, `b` at `t == 1`. `t` is not clamped.
    public static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        return a + (b - a) * t
    }

    /// Wraps an angle in radians into `(-pi, pi]`. Non-finite input returns 0.
    public static func wrapAngle(_ angle: Double) -> Double {
        if !angle.isFinite { return 0 }
        let twoPi = 2.0 * Double.pi
        var r = angle.truncatingRemainder(dividingBy: twoPi)
        if r > Double.pi {
            r -= twoPi
        } else if r <= -Double.pi {
            r += twoPi
        }
        return r
    }

    /// Exponential smoothing factor for a step of `dt` seconds with time constant `timeConstant`.
    /// Returns 1 (no smoothing) when `timeConstant <= 0`, and 0 when `dt <= 0`.
    public static func smoothingAlpha(dt: Double, timeConstant: Double) -> Double {
        if timeConstant <= 0 { return 1 }
        if dt <= 0 || !dt.isFinite { return 0 }
        return 1.0 - exp(-dt / timeConstant)
    }
}

// MARK: - FlyRNG

/// Seeded SplitMix64 generator. Deterministic on every platform.
/// FlyCore never uses `SystemRandomNumberGenerator`.
public struct FlyRNG: Sendable, Equatable {
    public private(set) var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    /// Next raw 64-bit value (SplitMix64).
    public mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z: UInt64 = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform Double in `[0, 1)`, using the top 53 bits.
    public mutating func nextUnit() -> Double {
        let bits: UInt64 = next() >> 11
        return Double(bits) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// Uniform Double in `[lo, hi)`. If `hi < lo` the bounds are used as given (result between them).
    public mutating func nextDouble(from lo: Double, to hi: Double) -> Double {
        return lo + (hi - lo) * nextUnit()
    }

    /// Uniform Int in `0..<upperBound`. Returns 0 when `upperBound <= 0`.
    public mutating func nextInt(below upperBound: Int) -> Int {
        if upperBound <= 0 { return 0 }
        let n = UInt64(upperBound)
        return Int(next() % n)
    }
}
