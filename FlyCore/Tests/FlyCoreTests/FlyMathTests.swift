import XCTest
@testable import FlyCore

final class FlyMathTests: XCTestCase {

    func testVec3Arithmetic() {
        let a = Vec3(1, 2, 3)
        let b = Vec3(x: 4, y: 5, z: 6)
        XCTAssertEqual(a + b, Vec3(5, 7, 9))
        XCTAssertEqual(b - a, Vec3(3, 3, 3))
        XCTAssertEqual(a * 2, Vec3(2, 4, 6))
        XCTAssertEqual(2 * a, Vec3(2, 4, 6))
        XCTAssertEqual(b / 2, Vec3(2, 2.5, 3))
        XCTAssertEqual(a / 0, Vec3.zero)
        XCTAssertEqual(-a, Vec3(-1, -2, -3))
        XCTAssertEqual(a.dot(b), 32, accuracy: 1e-12)
        XCTAssertEqual(Vec3(1, 0, 0).cross(Vec3(0, 1, 0)), Vec3(0, 0, 1))
    }

    func testVec3LengthAndNormalise() {
        let v = Vec3(3, 4, 0)
        XCTAssertEqual(v.length, 5, accuracy: 1e-12)
        XCTAssertEqual(v.lengthSquared, 25, accuracy: 1e-12)
        let n = v.normalised()
        XCTAssertEqual(n.length, 1, accuracy: 1e-12)
        XCTAssertEqual(n.x, 0.6, accuracy: 1e-12)
        XCTAssertEqual(Vec3.zero.normalised(), Vec3.zero)
        XCTAssertEqual(Vec3(1, 1, 1).distance(to: Vec3(1, 1, 3)), 2, accuracy: 1e-12)
    }

    func testClampLerp() {
        XCTAssertEqual(FlyMath.clamp(5, 0, 1), 1)
        XCTAssertEqual(FlyMath.clamp(-5, 0, 1), 0)
        XCTAssertEqual(FlyMath.clamp(0.5, 0, 1), 0.5)
        XCTAssertEqual(FlyMath.clamp(Double.nan, 0, 1), 0)
        XCTAssertEqual(FlyMath.lerp(2, 4, 0.25), 2.5, accuracy: 1e-12)
    }

    func testWrapAngle() {
        XCTAssertEqual(FlyMath.wrapAngle(0), 0, accuracy: 1e-12)
        XCTAssertEqual(FlyMath.wrapAngle(2.5 * Double.pi), Double.pi / 2, accuracy: 1e-9)
        XCTAssertEqual(FlyMath.wrapAngle(-Double.pi), Double.pi, accuracy: 1e-9)
        XCTAssertEqual(FlyMath.wrapAngle(Double.pi / 2 + 2 * Double.pi), Double.pi / 2, accuracy: 1e-9)
        XCTAssertEqual(FlyMath.wrapAngle(-Double.pi / 2), -Double.pi / 2, accuracy: 1e-12)
        XCTAssertEqual(FlyMath.wrapAngle(Double.infinity), 0)
    }

    func testSmoothingAlpha() {
        XCTAssertEqual(FlyMath.smoothingAlpha(dt: 0.1, timeConstant: 0), 1)
        XCTAssertEqual(FlyMath.smoothingAlpha(dt: 0, timeConstant: 0.1), 0)
        XCTAssertEqual(FlyMath.smoothingAlpha(dt: 0.1, timeConstant: 0.1), 1 - exp(-1.0), accuracy: 1e-12)
    }

    func testRNGMatchesSplitMix64Reference() {
        var rng = FlyRNG(seed: 0)
        XCTAssertEqual(rng.next(), 0xE220_A839_7B1D_CDAF)
        XCTAssertEqual(rng.next(), 0x6E78_9E6A_A1B9_65F4)
        XCTAssertEqual(rng.next(), 0x06C4_5D18_8009_454F)
        var r42 = FlyRNG(seed: 42)
        XCTAssertEqual(r42.next(), 0xBDD7_3226_2FEB_6E95)
    }

    func testRNGDeterministicAndSeedDependent() {
        var a = FlyRNG(seed: 7)
        var b = FlyRNG(seed: 7)
        var c = FlyRNG(seed: 8)
        var same = true
        var differs = false
        for _ in 0..<100 {
            let x = a.next()
            if x != b.next() { same = false }
            if x != c.next() { differs = true }
        }
        XCTAssertTrue(same)
        XCTAssertTrue(differs)
        XCTAssertEqual(a, b)
    }

    func testRNGRanges() {
        var rng = FlyRNG(seed: 123)
        for _ in 0..<1000 {
            let u = rng.nextUnit()
            XCTAssertTrue(u >= 0 && u < 1)
            let d = rng.nextDouble(from: -2, to: 3)
            XCTAssertTrue(d >= -2 && d < 3)
            let i = rng.nextInt(below: 5)
            XCTAssertTrue(i >= 0 && i < 5)
        }
        XCTAssertEqual(rng.nextInt(below: 0), 0)
        XCTAssertEqual(rng.nextInt(below: -3), 0)
    }
}

final class FlyCameraTests: XCTestCase {

    let camera = FlyCamera(position: Vec3.zero, horizontalFOV: Double.pi / 2, verticalFOV: Double.pi / 2)

    func testProjectCentreAndEdges() throws {
        let centre = try XCTUnwrap(camera.project(Vec3(0, 0, -1)))
        XCTAssertEqual(centre.x, 0.5, accuracy: 1e-12)
        XCTAssertEqual(centre.y, 0.5, accuracy: 1e-12)
        // 90 degree FOV: a point at 45 degrees right lands on the right edge.
        let right = try XCTUnwrap(camera.project(Vec3(1, 0, -1)))
        XCTAssertEqual(right.x, 1.0, accuracy: 1e-12)
        let up = try XCTUnwrap(camera.project(Vec3(0, 0.5, -1)))
        XCTAssertEqual(up.y, 0.25, accuracy: 1e-12)
        XCTAssertTrue(up.isOnScreen)
        let off = try XCTUnwrap(camera.project(Vec3(3, 0, -1)))
        XCTAssertFalse(off.isOnScreen)
    }

    func testProjectBehindIsNil() {
        XCTAssertNil(camera.project(Vec3(0, 0, 1)))
        XCTAssertNil(camera.project(Vec3(0, 0, -0.001)))
    }

    func testCustomBasis() throws {
        // Camera at (1, 0, 0) looking along +X, with +Z as screen right.
        let cam = FlyCamera(position: Vec3(1, 0, 0), forward: Vec3(1, 0, 0), right: Vec3(0, 0, 1), up: Vec3(0, 1, 0),
                            horizontalFOV: Double.pi / 2, verticalFOV: Double.pi / 2)
        let p = try XCTUnwrap(cam.project(Vec3(2, 0, 0.5)))
        XCTAssertEqual(p.x, 0.75, accuracy: 1e-12)
        XCTAssertEqual(cam.distance(to: Vec3(2, 0, 0)), 1, accuracy: 1e-12)
    }

    func testBearing() {
        XCTAssertEqual(camera.bearing(to: Vec3(0, 0, -1)), 0, accuracy: 1e-12)
        XCTAssertEqual(camera.bearing(to: Vec3(1, 0, 0)), Double.pi / 2, accuracy: 1e-12)
        XCTAssertEqual(camera.bearing(to: Vec3(-1, 0, 0)), -Double.pi / 2, accuracy: 1e-12)
        XCTAssertEqual(abs(camera.bearing(to: Vec3(0, 0, 1))), Double.pi, accuracy: 1e-12)
        XCTAssertEqual(camera.bearing(to: Vec3.zero), 0)
    }
}

final class FlyTunablesTests: XCTestCase {

    func testDefaultsFromPlan() {
        let t = FlyTunables()
        XCTAssertEqual(t.takeOffDistance, 0.30, accuracy: 1e-12)
        XCTAssertEqual(t.smashDistance, 0.12, accuracy: 1e-12)
        XCTAssertEqual(t.snapshotBufferDuration, 1.0, accuracy: 1e-12)
        XCTAssertTrue(t.smashDistance < t.takeOffDistance)
        XCTAssertTrue(t.darkeningThreshold < t.litThreshold)
        XCTAssertTrue(t.hingeClosedAngle < t.hingeArmAngle)
        XCTAssertTrue(t.landedMinDuration <= t.landedMaxDuration)
        XCTAssertTrue(t.hitBlockedMargin < t.hitRegionWidth)
    }

    func testEquatableAndMutable() {
        var t = FlyTunables()
        XCTAssertEqual(t, FlyTunables())
        t.smashDistance = 0.15
        XCTAssertNotEqual(t, FlyTunables())
    }
}
