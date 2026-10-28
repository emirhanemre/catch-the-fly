import XCTest
@testable import FlyCore

final class HitRegionTests: XCTestCase {

    func p(_ x: Double, _ y: Double) -> FlyScreenPoint {
        return FlyScreenPoint(x: x, y: y)
    }

    func testRightEdge() {
        let r = HitRegion(hingeEdge: .right, width: 0.5, blockedMargin: 0.06)
        XCTAssertTrue(r.contains(p(0.7, 0.5)))
        XCTAssertTrue(r.contains(p(0.5, 0.0)))
        XCTAssertFalse(r.contains(p(0.97, 0.5)), "blocked strip at the hinge edge")
        XCTAssertFalse(r.contains(p(0.4, 0.5)))
        XCTAssertFalse(r.contains(p(0.7, 1.2)), "off screen")
    }

    func testLeftEdge() {
        let r = HitRegion(hingeEdge: .left, width: 0.5, blockedMargin: 0.06)
        XCTAssertTrue(r.contains(p(0.3, 0.5)))
        XCTAssertFalse(r.contains(p(0.03, 0.5)))
        XCTAssertFalse(r.contains(p(0.6, 0.5)))
    }

    func testTopAndBottomEdges() {
        let top = HitRegion(hingeEdge: .top, width: 0.4, blockedMargin: 0.05)
        XCTAssertTrue(top.contains(p(0.5, 0.3)))
        XCTAssertFalse(top.contains(p(0.5, 0.02)))
        XCTAssertFalse(top.contains(p(0.5, 0.5)))
        let bottom = HitRegion(hingeEdge: .bottom, width: 0.4, blockedMargin: 0.05)
        XCTAssertTrue(bottom.contains(p(0.5, 0.7)))
        XCTAssertFalse(bottom.contains(p(0.5, 0.98)))
        XCTAssertFalse(bottom.contains(p(0.5, 0.5)))
    }

    func testCentreForIPad() {
        let r = HitRegion(hingeEdge: .centre, width: 0.5, blockedMargin: 0.3)
        XCTAssertTrue(r.contains(p(0.5, 0.5)))
        XCTAssertTrue(r.contains(p(0.26, 0.74)), "margin is ignored for the centre region")
        XCTAssertFalse(r.contains(p(0.1, 0.5)))
        XCTAssertFalse(r.contains(p(0.5, 0.8)))
    }

    func testFromTunables() {
        var t = FlyTunables()
        t.hitRegionWidth = 0.3
        t.hitBlockedMargin = 0.1
        let r = HitRegion(hingeEdge: .left, tunables: t)
        XCTAssertEqual(r, HitRegion(hingeEdge: .left, width: 0.3, blockedMargin: 0.1))
    }
}

final class HitJudgeTests: XCTestCase {

    let t = FlyTunables()
    let region = HitRegion(hingeEdge: .right, width: 0.5, blockedMargin: 0.06)

    func snap(_ time: Double, _ state: FlyState = .hovering, speed: Double = 0.05, distance: Double? = 0.08,
              confidence: Double = 1, screen: FlyScreenPoint? = FlyScreenPoint(x: 0.7, y: 0.5)) -> FlySnapshot {
        return FlySnapshot(time: time, flyState: state, flySpeed: speed, distance: distance, distanceConfidence: confidence, screenPosition: screen)
    }

    func judgeOne(_ s: FlySnapshot) -> HitVerdict {
        var j = HitJudge()
        j.record(s)
        return j.judge(SmashEvent(time: s.time + 0.3, motionStartTime: s.time + 0.1, source: .hinge), region: region, tunables: t)
    }

    func testUsesSnapshotFromBeforeTheFold() {
        var j = HitJudge(bufferDuration: 1.0)
        var k = 0
        while k <= 90 {
            let time = Double(k) / 60.0
            if time <= 1.0 {
                j.record(snap(time))
            } else {
                // Mid-fold: camera covered, fly startled away.
                j.record(snap(time, .escaping, speed: 2.0, distance: 0.5, confidence: 0.2, screen: nil))
            }
            k += 1
        }
        let hit = j.judge(SmashEvent(time: 1.3, motionStartTime: 1.0, source: .hinge), region: region, tunables: t)
        XCTAssertTrue(hit.isHit)
        XCTAssertEqual(hit.reason, .hit)
        XCTAssertEqual(hit.judgedTime, 1.0 - t.judgeLeadTime, accuracy: 1e-12)
        XCTAssertTrue((hit.snapshot?.time ?? 99) <= 1.0 - t.judgeLeadTime)
        let late = j.judge(SmashEvent(time: 1.8, motionStartTime: 1.5, source: .hinge), region: region, tunables: t)
        XCTAssertFalse(late.isHit)
        XCTAssertEqual(late.reason, .flyEscaping)
    }

    func testEmptyBufferIsNoSnapshot() {
        let j = HitJudge()
        let v = j.judge(SmashEvent(time: 1, motionStartTime: 1, source: .manual), region: region, tunables: t)
        XCTAssertEqual(v.reason, .noSnapshot)
        XCTAssertNil(v.snapshot)
        XCTAssertFalse(v.isHit)
    }

    func testReasons() {
        XCTAssertEqual(judgeOne(snap(1)).reason, .hit)
        XCTAssertEqual(judgeOne(snap(1, .smashed)).reason, .alreadySmashed)
        XCTAssertEqual(judgeOne(snap(1, .escaping)).reason, .flyEscaping)
        XCTAssertEqual(judgeOne(snap(1, .wandering, speed: 0.5)).reason, .flyTooFast)
        XCTAssertEqual(judgeOne(snap(1, .wandering, speed: 0.2)).reason, .hit, "a slow fly can be hit")
        XCTAssertEqual(judgeOne(snap(1, .landed, speed: 0)).reason, .hit)
        XCTAssertEqual(judgeOne(snap(1, .hovering, speed: 1.0)).reason, .hit, "hovering is never too fast")
        XCTAssertEqual(judgeOne(snap(1, distance: nil)).reason, .distanceUnknown)
        XCTAssertEqual(judgeOne(snap(1, confidence: 0.1)).reason, .distanceUnknown)
        XCTAssertEqual(judgeOne(snap(1, distance: 0.2)).reason, .tooFar)
        XCTAssertEqual(judgeOne(snap(1, screen: nil)).reason, .offScreen)
        XCTAssertEqual(judgeOne(snap(1, screen: FlyScreenPoint(x: 1.3, y: 0.5))).reason, .offScreen)
        XCTAssertEqual(judgeOne(snap(1, screen: FlyScreenPoint(x: 0.2, y: 0.5))).reason, .outsideHitRegion)
        XCTAssertEqual(judgeOne(snap(1, screen: FlyScreenPoint(x: 0.98, y: 0.5))).reason, .outsideHitRegion)
    }

    func testStaticReason() {
        XCTAssertEqual(HitJudge.reason(for: snap(0), region: region, tunables: t), .hit)
        XCTAssertEqual(HitJudge.reason(for: snap(0, distance: 0.13), region: region, tunables: t), .tooFar)
    }

    func testRingBufferPrunesAndFallsBackToOldest() {
        var j = HitJudge(bufferDuration: 1.0)
        var k = 0
        while k <= 180 {
            j.record(snap(Double(k) / 60.0))
            k += 1
        }
        let oldest = j.snapshots.first?.time ?? 0
        XCTAssertTrue(oldest >= 2.0 - 1e-9)
        XCTAssertEqual(j.snapshots.last?.time ?? 0, 3.0, accuracy: 1e-12)
        XCTAssertEqual(j.snapshot(at: 0.5)?.time ?? -1, oldest, accuracy: 1e-12)
        XCTAssertEqual(j.snapshot(at: 2.51)?.time ?? -1, 150.0 / 60.0, accuracy: 1e-9)
        XCTAssertEqual(j.snapshot(at: 10)?.time ?? -1, 3.0, accuracy: 1e-12)
    }

    func testOutOfOrderSnapshotIgnoredAndClear() {
        var j = HitJudge()
        j.record(snap(2.0))
        j.record(snap(1.0))
        XCTAssertEqual(j.snapshots.count, 1)
        j.clear()
        XCTAssertTrue(j.snapshots.isEmpty)
    }
}
