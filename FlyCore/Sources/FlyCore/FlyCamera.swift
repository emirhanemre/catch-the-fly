import Foundation

/// A point in normalised screen coordinates: `x` 0 (left) to 1 (right), `y` 0 (top) to 1 (bottom).
/// Values outside 0...1 are off-screen.
public struct FlyScreenPoint: Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// True when both coordinates lie in `0...1`.
    public var isOnScreen: Bool {
        return x >= 0 && x <= 1 && y >= 0 && y <= 1
    }
}

/// A pinhole camera described by a position, an orthonormal basis and fields of view.
///
/// - `forward`: the direction the camera looks.
/// - `right`: screen +x.
/// - `up`: screen up (screen -y).
///
/// From an ARKit `camera.transform` (columns c0...c3): `right = c0.xyz`, `up = c1.xyz`,
/// `forward = -c2.xyz`, `position = c3.xyz`.
/// The fields of view must describe the picture as displayed (after any crop), not the raw sensor.
public struct FlyCamera: Sendable, Equatable {
    public var position: Vec3
    public var forward: Vec3
    public var right: Vec3
    public var up: Vec3
    /// Full horizontal field of view in radians.
    public var horizontalFOV: Double
    /// Full vertical field of view in radians.
    public var verticalFOV: Double

    public init(position: Vec3, forward: Vec3, right: Vec3, up: Vec3, horizontalFOV: Double, verticalFOV: Double) {
        self.position = position
        self.forward = forward
        self.right = right
        self.up = up
        self.horizontalFOV = horizontalFOV
        self.verticalFOV = verticalFOV
    }

    /// A camera at `position` looking along -Z with +X right and +Y up (ARKit's convention at identity).
    public init(position: Vec3 = Vec3.zero, horizontalFOV: Double, verticalFOV: Double) {
        self.position = position
        self.forward = Vec3(x: 0, y: 0, z: -1)
        self.right = Vec3(x: 1, y: 0, z: 0)
        self.up = Vec3(x: 0, y: 1, z: 0)
        self.horizontalFOV = horizontalFOV
        self.verticalFOV = verticalFOV
    }

    /// Points closer than this along `forward` (metres) do not project.
    public static let nearPlane: Double = 0.01

    /// Projects a world point to normalised screen coordinates.
    /// Returns nil if the point is behind the camera or nearer than `nearPlane`.
    /// The result can lie outside 0...1 (off-screen but in front).
    public func project(_ point: Vec3) -> FlyScreenPoint? {
        let d = point - position
        let depth = d.dot(forward)
        if !(depth > FlyCamera.nearPlane) { return nil }
        let halfW = tan(horizontalFOV * 0.5)
        let halfH = tan(verticalFOV * 0.5)
        if !(halfW > 0) || !(halfH > 0) { return nil }
        let xc = d.dot(right) / depth
        let yc = d.dot(up) / depth
        let sx = 0.5 + xc / (2.0 * halfW)
        let sy = 0.5 - yc / (2.0 * halfH)
        return FlyScreenPoint(x: sx, y: sy)
    }

    /// Bearing of a world point in radians: 0 straight ahead, positive to the right,
    /// plus or minus pi directly behind. Ignores elevation.
    public func bearing(to point: Vec3) -> Double {
        let d = point - position
        let ahead = d.dot(forward)
        let side = d.dot(right)
        if ahead == 0 && side == 0 { return 0 }
        return atan2(side, ahead)
    }

    /// Straight-line distance from the camera to a world point, in metres.
    public func distance(to point: Vec3) -> Double {
        return position.distance(to: point)
    }
}
