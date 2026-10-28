import XCTest
@testable import FlyCore

final class FlyAgentTests: XCTestCase {

    let t = FlyTunables()
    let spotA = LandingSpot(id: 1, position: Vec3(0, 0, 0), normal: Vec3(0, 0, 1), quality: 1)
    let spotB = LandingSpot(id: 2, position: Vec3(2, 0, 0), normal: Vec3(0, 0, 1), quality: 1)

    func near(_ d: Double, rate: Double = 0, angular: Double = 0, confidence: Double = 1) -> PlayerMotion {
        return PlayerMotion(distance: d, distanceConfidence: confidence, approachRate: rate, angularSpeed: angular)
    }

    /// Ticks until a transition happens (or `maxTicks` pass). Returns the transition.
    func tickUntilTransition(_ fly: inout FlyAgent, dt: Double, motion: PlayerMotion, spots: [LandingSpot], maxTicks: Int) -> FlyTransition? {
        var n = 0
        while n < maxTicks {
            if let tr = fly.tick(dt: dt, motion: motion, spots: spots, tunables: t) {
                return tr
            }
            n += 1
        }
        return nil
    }

    // MARK: Wandering and landing

    func testWanderingFlyLandsOnSpot() throws {
        var fly = FlyAgent(position: Vec3(-0.5, 0, 0), seed: 1)
        XCTAssertEqual(fly.state, .wandering)
        let tr = try XCTUnwrap(tickUntilTransition(&fly, dt: 1.0 / 60.0, motion: .still, spots: [spotA], maxTicks: 200))
        XCTAssertEqual(tr, FlyTransition(from: .wandering, to: .landed, reason: .arrived))
        XCTAssertEqual(fly.state, .landed)
        XCTAssertEqual(fly.spotID, 1)
        XCTAssertEqual(fly.position, spotA.position)
        XCTAssertTrue(fly.timeRemaining >= t.landedMinDuration && fly.timeRemaining <= t.landedMaxDuration)
    }

    func testWanderingSpeed() {
        var fly = FlyAgent(position: Vec3(-1, 0, 0), seed: 1)
        fly.tick(dt: 0.1, motion: .still, spots: [spotA], tunables: t)
        XCTAssertEqual(fly.speed, t.wanderSpeed, accuracy: 1e-9)
        XCTAssertEqual(fly.spotID, 1)
    }

    func testNoSpotsLoopsWithoutLeaving() {
        let start = Vec3(0, 1, -1)
        var fly = FlyAgent(position: start, seed: 3)
        var n = 0
        while n < 120 {
            let tr = fly.tick(dt: 1.0 / 60.0, motion: .still, spots: [], tunables: t)
            XCTAssertNil(tr)
            n += 1
        }
        XCTAssertEqual(fly.state, .wandering)
        XCTAssertNil(fly.spotID)
        XCTAssertTrue(fly.position.distance(to: start) <= 2 * t.noSpotLoopRadius + 1e-9)
        XCTAssertTrue(fly.speed > 0)
    }

    func testLandedFollowsMovingSpot() {
        var fly = FlyAgent(landedOn: spotA, seed: 1, landedDuration: 10)
        let moved = LandingSpot(id: 1, position: Vec3(0.1, 0, 0), normal: Vec3(0, 0, 1))
        fly.tick(dt: 0.1, motion: .still, spots: [moved], tunables: t)
        XCTAssertEqual(fly.state, .landed)
        XCTAssertEqual(fly.position, moved.position)
    }

    func testRestlessFlyMovesToAnotherSpot() throws {
        var fly = FlyAgent(landedOn: spotA, seed: 1, landedDuration: 0.5)
        let tr = try XCTUnwrap(tickUntilTransition(&fly, dt: 0.1, motion: .still, spots: [spotA, spotB], maxTicks: 10))
        XCTAssertEqual(tr, FlyTransition(from: .landed, to: .wandering, reason: .restless))
        XCTAssertEqual(fly.spotID, 2)
    }

    func testSpotLostSendsFlyWandering() {
        var fly = FlyAgent(landedOn: spotA, seed: 1, landedDuration: 10)
        let tr = fly.tick(dt: 0.1, motion: .still, spots: [], tunables: t)
        XCTAssertEqual(tr, FlyTransition(from: .landed, to: .wandering, reason: .spotLost))
        XCTAssertNil(fly.spotID)
    }

    // MARK: Take-off and hover

    func testCloseApproachMakesFlyHover() {
        var fly = FlyAgent(landedOn: spotA, seed: 1, landedDuration: 10)
        let tr = fly.tick(dt: 1.0 / 60.0, motion: near(0.25), spots: [spotA], tunables: t)
        XCTAssertEqual(tr, FlyTransition(from: .landed, to: .hovering, reason: .playerClose))
        XCTAssertEqual(fly.timeRemaining, t.hoverDuration, accuracy: 1e-12)
    }

    func testNotCloseEnoughStaysLanded() {
        var fly = FlyAgent(landedOn: spotA, seed: 1, landedDuration: 10)
        XCTAssertNil(fly.tick(dt: 1.0 / 60.0, motion: near(0.35), spots: [spotA], tunables: t))
        XCTAssertEqual(fly.state, .landed)
    }

    func testHoverStaysNearSpot() {
        var fly = FlyAgent(landedOn: spotA, seed: 1, landedDuration: 10)
        fly.tick(dt: 1.0 / 60.0, motion: near(0.25), spots: [spotA], tunables: t)
        var n = 0
        while n < 60 {
            XCTAssertNil(fly.tick(dt: 1.0 / 60.0, motion: near(0.25), spots: [spotA], tunables: t))
            n += 1
        }
        XCTAssertEqual(fly.state, .hovering)
        let limit = t.hoverStandoff + t.hoverRadius * 1.2 + 1e-9
        XCTAssertTrue(fly.position.distance(to: spotA.position) <= limit)
        XCTAssertTrue(fly.position.z > 0, "hover centre sits off the surface along the normal")
    }

    func testHoverEndsInEscape() throws {
        var fly = FlyAgent(landedOn: spotA, seed: 1, landedDuration: 10)
        fly.tick(dt: 0.1, motion: near(0.25), spots: [spotA, spotB], tunables: t)
        XCTAssertEqual(fly.state, .hovering)
        let tr = try XCTUnwrap(tickUntilTransition(&fly, dt: 0.1, motion: near(0.25), spots: [spotA, spotB], maxTicks: 60))
        XCTAssertEqual(tr, FlyTransition(from: .hovering, to: .escaping, reason: .hoverEnded))
        XCTAssertEqual(fly.spotID, 2)
    }

    func testHoverAlarmUsesMultiplier() {
        var fly = FlyAgent(landedOn: spotA, seed: 1, landedDuration: 10)
        fly.tick(dt: 0.1, motion: near(0.25), spots: [spotA], tunables: t)
        // 1.0 m/s would alarm a landed fly (> 0.6) but not a hovering one (< 1.2).
        XCTAssertNil(fly.tick(dt: 0.1, motion: near(0.25, rate: 1.0), spots: [spotA], tunables: t))
        XCTAssertEqual(fly.state, .hovering)
        let tr = fly.tick(dt: 0.1, motion: near(0.25, rate: 1.5), spots: [spotA], tunables: t)
        XCTAssertEqual(tr, FlyTransition(from: .hovering, to: .alarmed, reason: .alarmed))
    }

    // MARK: Alarm and escape

    func testFastApproachAlarmsThenEscapesToFarSpot() throws {
        var fly = FlyAgent(landedOn: spotA, seed: 1, landedDuration: 10)
        let tr = fly.tick(dt: 0.1, motion: near(1.0, rate: 1.0), spots: [spotA, spotB], tunables: t)
        XCTAssertEqual(tr, FlyTransition(from: .landed, to: .alarmed, reason: .alarmed))
        let tr2 = try XCTUnwrap(tickUntilTransition(&fly, dt: 0.1, motion: .still, spots: [spotA, spotB], maxTicks: 5))
        XCTAssertEqual(tr2, FlyTransition(from: .alarmed, to: .escaping, reason: .startleEnded))
        XCTAssertEqual(fly.spotID, 2)
        let tr3 = try XCTUnwrap(tickUntilTransition(&fly, dt: 0.1, motion: .still, spots: [spotA, spotB], maxTicks: 30))
        XCTAssertEqual(tr3, FlyTransition(from: .escaping, to: .landed, reason: .arrived))
        XCTAssertEqual(fly.position, spotB.position)
    }

    func testEscapeSpeed() {
        var fly = FlyAgent(landedOn: spotA, seed: 1, landedDuration: 10)
        fly.tick(dt: 0.1, motion: near(1.0, rate: 1.0), spots: [spotA, spotB], tunables: t)
        _ = tickUntilTransition(&fly, dt: 0.1, motion: .still, spots: [spotA, spotB], maxTicks: 5)
        fly.tick(dt: 0.1, motion: .still, spots: [spotA, spotB], tunables: t)
        XCTAssertEqual(fly.state, .escaping)
        XCTAssertEqual(fly.speed, t.escapeSpeed, accuracy: 1e-9)
    }

    func testRotatingPhoneAlarms() {
        var fly = FlyAgent(landedOn: spotA, seed: 1, landedDuration: 10)
        let tr = fly.tick(dt: 0.1, motion: near(1.0, angular: 3.0), spots: [spotA], tunables: t)
        XCTAssertEqual(tr?.to, .alarmed)
    }

    func testFarPlayerDoesNotAlarm() {
        var fly = FlyAgent(landedOn: spotA, seed: 1, landedDuration: 10)
        XCTAssertNil(fly.tick(dt: 0.1, motion: near(3.0, rate: 2.0, angular: 5.0), spots: [spotA], tunables: t))
        XCTAssertEqual(fly.state, .landed)
    }

    func testLowConfidenceDistanceIsIgnored() {
        var fly = FlyAgent(landedOn: spotA, seed: 1, landedDuration: 10)
        XCTAssertNil(fly.tick(dt: 0.1, motion: near(0.2, rate: 2.0, confidence: 0.1), spots: [spotA], tunables: t))
        XCTAssertEqual(fly.state, .landed)
        XCTAssertNil(fly.tick(dt: 0.1, motion: PlayerMotion(distance: nil, distanceConfidence: 1, approachRate: 2, angularSpeed: 5), spots: [spotA], tunables: t))
        XCTAssertEqual(fly.state, .landed)
    }

    func testWanderingFlyIgnoresPlayerMotion() {
        var fly = FlyAgent(position: Vec3(-1, 0, 0), seed: 1)
        XCTAssertNil(fly.tick(dt: 0.1, motion: near(0.2, rate: 3.0, angular: 5.0), spots: [spotA], tunables: t))
        XCTAssertEqual(fly.state, .wandering)
    }

    func testEscapeWithNoOtherSpotFliesOffThenWanders() throws {
        var fly = FlyAgent(landedOn: spotA, seed: 5, landedDuration: 10)
        fly.tick(dt: 0.1, motion: near(1.0, rate: 1.0), spots: [spotA], tunables: t)
        let tr = try XCTUnwrap(tickUntilTransition(&fly, dt: 0.1, motion: .still, spots: [spotA], maxTicks: 5))
        XCTAssertEqual(tr.to, .escaping)
        XCTAssertNil(fly.spotID)
        let tr2 = try XCTUnwrap(tickUntilTransition(&fly, dt: 0.1, motion: .still, spots: [spotA], maxTicks: 30))
        XCTAssertEqual(tr2, FlyTransition(from: .escaping, to: .wandering, reason: .escapeEnded))
        XCTAssertTrue(fly.position.distance(to: spotA.position) > 1.0)
        XCTAssertEqual(fly.spotID, 1)
    }

    // MARK: External events

    func testAlarmMethod() {
        var fly = FlyAgent(landedOn: spotA, seed: 1, landedDuration: 10)
        fly.tick(dt: 0.1, motion: near(0.25), spots: [spotA], tunables: t)
        XCTAssertEqual(fly.alarm(tunables: t), FlyTransition(from: .hovering, to: .alarmed, reason: .startled))
        XCTAssertNil(fly.alarm(tunables: t))
    }

    func testMarkSmashedIsTerminal() {
        var fly = FlyAgent(landedOn: spotA, seed: 1, landedDuration: 10)
        XCTAssertEqual(fly.markSmashed(), FlyTransition(from: .landed, to: .smashed, reason: .smashed))
        XCTAssertNil(fly.markSmashed())
        XCTAssertNil(fly.alarm(tunables: t))
        XCTAssertNil(fly.tick(dt: 0.1, motion: near(0.1, rate: 5), spots: [spotA, spotB], tunables: t))
        XCTAssertEqual(fly.state, .smashed)
        XCTAssertEqual(fly.velocity, Vec3.zero)
    }

    func testStateTimeResetsOnTransition() {
        var fly = FlyAgent(landedOn: spotA, seed: 1, landedDuration: 10)
        fly.tick(dt: 0.1, motion: .still, spots: [spotA], tunables: t)
        XCTAssertEqual(fly.stateTime, 0.1, accuracy: 1e-12)
        fly.tick(dt: 0.1, motion: near(0.2), spots: [spotA], tunables: t)
        XCTAssertEqual(fly.stateTime, 0, accuracy: 1e-12)
    }

    func testZeroDtDoesNothing() {
        var fly = FlyAgent(landedOn: spotA, seed: 1, landedDuration: 10)
        let before = fly
        XCTAssertNil(fly.tick(dt: 0, motion: near(0.1), spots: [spotA], tunables: t))
        XCTAssertEqual(fly, before)
    }

    func testDeterministicForSameSeed() {
        let spots = [spotA, spotB, LandingSpot(id: 3, position: Vec3(1, 1, 0)), LandingSpot(id: 4, position: Vec3(0, 2, 1), quality: 0.1)]
        var a = FlyAgent(position: Vec3.zero, seed: 99)
        var b = FlyAgent(position: Vec3.zero, seed: 99)
        var trA: [FlyTransition] = []
        var trB: [FlyTransition] = []
        var n = 0
        while n < 1200 {
            if let x = a.tick(dt: 1.0 / 30.0, motion: .still, spots: spots, tunables: t) { trA.append(x) }
            if let y = b.tick(dt: 1.0 / 30.0, motion: .still, spots: spots, tunables: t) { trB.append(y) }
            n += 1
        }
        XCTAssertEqual(a, b)
        XCTAssertEqual(trA, trB)
        XCTAssertTrue(trA.count >= 4, "the fly should land and get restless several times in 40 s")
    }
}
