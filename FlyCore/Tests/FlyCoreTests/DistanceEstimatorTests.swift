import XCTest
@testable import FlyCore

final class DistanceEstimatorTests: XCTestCase {

    func testMeasurementMetres() {
        XCTAssertEqual(DistanceMeasurement.world(metres: 0.8).metres, 0.8)
        XCTAssertNil(DistanceMeasurement.world(metres: -1).metres)
        XCTAssertNil(DistanceMeasurement.world(metres: Double.nan).metres)
        XCTAssertEqual(DistanceMeasurement.patchScale(ratio: 2, referenceDistance: 0.6).metres ?? 0, 0.3, accuracy: 1e-12)
        XCTAssertNil(DistanceMeasurement.patchScale(ratio: 0, referenceDistance: 0.6).metres)
        XCTAssertNil(DistanceMeasurement.patchScale(ratio: 1, referenceDistance: 0).metres)
    }

    func testFirstMeasurementIsTakenDirectly() {
        var e = DistanceEstimator()
        XCTAssertNil(e.estimate.metres)
        let r = e.update(.patchScale(ratio: 2, referenceDistance: 0.6), sourceConfidence: 0.8, time: 1.0)
        XCTAssertEqual(r.metres ?? 0, 0.3, accuracy: 1e-12)
        XCTAssertEqual(r.confidence, 0.8, accuracy: 1e-12)
        XCTAssertEqual(r.approachRate, 0)
        XCTAssertEqual(r.time, 1.0)
        XCTAssertEqual(e.estimate, r)
    }

    func testConstantReadingIsSteady() {
        var e = DistanceEstimator()
        var k = 0
        while k <= 30 {
            e.update(.world(metres: 1.0), time: Double(k) / 30.0)
            k += 1
        }
        XCTAssertEqual(e.estimate.metres ?? 0, 1.0, accuracy: 1e-12)
        XCTAssertEqual(e.estimate.approachRate, 0, accuracy: 1e-12)
        XCTAssertEqual(e.estimate.confidence, 1.0, accuracy: 1e-12)
    }

    func testSmoothingLagsAStep() {
        var e = DistanceEstimator()
        e.update(.world(metres: 1.0), time: 0)
        let r = e.update(.world(metres: 0.98), time: 1.0 / 30.0)
        let m = r.metres ?? 0
        XCTAssertTrue(m < 1.0 && m > 0.98)
    }

    func testApproachRateTracksSteadyApproach() {
        var e = DistanceEstimator()
        var k = 0
        while k <= 90 {
            let time = Double(k) / 60.0
            e.update(.world(metres: 1.0 - 0.5 * time), time: time)
            k += 1
        }
        XCTAssertEqual(e.estimate.approachRate, 0.5, accuracy: 0.03)
        XCTAssertEqual(e.estimate.metres ?? 0, 0.25, accuracy: 0.08)
    }

    func testRecedingGivesNegativeRate() {
        var e = DistanceEstimator()
        var k = 0
        while k <= 60 {
            let time = Double(k) / 60.0
            e.update(.patchScale(ratio: 1.0 / (0.5 + 0.3 * time), referenceDistance: 1.0), time: time)
            k += 1
        }
        XCTAssertEqual(e.estimate.approachRate, -0.3, accuracy: 0.05)
    }

    func testConfidenceFadesWithoutMeasurements() {
        var e = DistanceEstimator(staleTime: 0.5)
        e.update(.world(metres: 0.5), sourceConfidence: 1.0, time: 0)
        let half = e.update(nil, time: 0.25)
        XCTAssertEqual(half.confidence, 0.5, accuracy: 1e-9)
        XCTAssertEqual(half.metres ?? 0, 0.5, accuracy: 1e-12)
        let gone = e.update(nil, time: 0.6)
        XCTAssertEqual(gone.confidence, 0, accuracy: 1e-12)
        XCTAssertEqual(gone.metres ?? 0, 0.5, accuracy: 1e-12, "distance is held, only confidence fades")
    }

    func testInvalidMeasurementCountsAsNone() {
        var e = DistanceEstimator(staleTime: 0.5)
        e.update(.world(metres: 0.5), time: 0)
        let r = e.update(.patchScale(ratio: 0, referenceDistance: 1), time: 0.25)
        XCTAssertEqual(r.metres ?? 0, 0.5, accuracy: 1e-12)
        XCTAssertEqual(r.confidence, 0.5, accuracy: 1e-9)
    }

    func testJumpReseedsWithoutRate() {
        var e = DistanceEstimator()
        e.update(.world(metres: 1.0), time: 0)
        let r = e.update(.world(metres: 0.3), time: 1.0 / 60.0)
        XCTAssertEqual(r.metres ?? 0, 0.3, accuracy: 1e-12)
        XCTAssertEqual(r.approachRate, 0)
    }

    func testKindSwitchReseeds() {
        var e = DistanceEstimator()
        e.update(.world(metres: 1.0), time: 0)
        let r = e.update(.patchScale(ratio: 1, referenceDistance: 0.98), time: 1.0 / 60.0)
        XCTAssertEqual(r.metres ?? 0, 0.98, accuracy: 1e-12)
        XCTAssertEqual(r.approachRate, 0)
    }

    func testLongGapReseeds() {
        var e = DistanceEstimator(staleTime: 0.5)
        e.update(.world(metres: 1.0), time: 0)
        let r = e.update(.world(metres: 0.9), time: 2.0)
        XCTAssertEqual(r.metres ?? 0, 0.9, accuracy: 1e-12)
        XCTAssertEqual(r.approachRate, 0)
    }

    func testClampAndConfidenceClamp() {
        var e = DistanceEstimator(minimumDistance: 0.02, maximumDistance: 5)
        let r = e.update(.world(metres: 0.001), sourceConfidence: 1.7, time: 0)
        XCTAssertEqual(r.metres ?? 0, 0.02, accuracy: 1e-12)
        XCTAssertEqual(r.confidence, 1.0)
        var f = DistanceEstimator(minimumDistance: 0.02, maximumDistance: 5)
        XCTAssertEqual(f.update(.world(metres: 50), sourceConfidence: -1, time: 0).metres ?? 0, 5, accuracy: 1e-12)
        XCTAssertEqual(f.estimate.confidence, 0)
    }

    func testOutOfOrderUpdateIgnored() {
        var e = DistanceEstimator()
        e.update(.world(metres: 1.0), time: 1.0)
        let r = e.update(.world(metres: 0.5), time: 0.5)
        XCTAssertEqual(r.metres ?? 0, 1.0, accuracy: 1e-12)
        XCTAssertEqual(r.time, 1.0)
    }

    func testRebaseSnapsAndZeroesRate() {
        var e = DistanceEstimator()
        var k = 0
        while k <= 30 {
            let time = Double(k) / 60.0
            e.update(.world(metres: 1.0 - 0.5 * time), time: time)
            k += 1
        }
        XCTAssertTrue(e.estimate.approachRate > 0.2)
        e.rebase()
        XCTAssertEqual(e.estimate.approachRate, 0)
        XCTAssertEqual(e.estimate.metres ?? 0, 0.75, accuracy: 1e-9)
    }

    func testResetForgets() {
        var e = DistanceEstimator()
        e.update(.world(metres: 1.0), time: 1.0)
        e.reset()
        XCTAssertEqual(e.estimate, DistanceEstimate.unknown)
        let r = e.update(.world(metres: 0.4), time: 0.5)
        XCTAssertEqual(r.metres ?? 0, 0.4, accuracy: 1e-12)
    }

    func testTunablesInitAndApply() {
        var t = FlyTunables()
        t.distanceStaleTime = 2.0
        t.distanceJumpRate = 9.0
        var e = DistanceEstimator(tunables: t)
        XCTAssertEqual(e.staleTime, 2.0)
        XCTAssertEqual(e.jumpRate, 9.0)
        t.distanceSmoothingTime = 0.5
        e.apply(t)
        XCTAssertEqual(e.smoothingTime, 0.5)
    }

    // MARK: Timestamped readings (measuredAt)

    func testStaleReadingIsNotRecounted() {
        var e = DistanceEstimator(staleTime: 0.5)
        e.update(.world(metres: 1.0), measuredAt: 0, time: 0)
        // The same frame's reading again on the next tick (even with a different value): held, not counted.
        let r = e.update(.world(metres: 0.9), measuredAt: 0, time: 1.0 / 60.0)
        XCTAssertEqual(r.metres ?? 0, 1.0, accuracy: 1e-12)
        XCTAssertEqual(r.confidence, 1.0 - (1.0 / 60.0) / 0.5, accuracy: 1e-9)
        XCTAssertEqual(r.time, 1.0 / 60.0)
        // An older reading is stale too.
        let older = e.update(.world(metres: 0.5), measuredAt: -1, time: 2.0 / 60.0)
        XCTAssertEqual(older.metres ?? 0, 1.0, accuracy: 1e-12)
    }

    func testFrameRateReadingsInATickLoopMatchFeedingFramesOnly() {
        // Readings at 30 Hz (a steady 0.5 m/s approach), ticks at 60 Hz passing the latest reading every tick.
        var ticked = DistanceEstimator()
        var framesOnly = DistanceEstimator()
        var heldTicks = 0
        var k = 0
        while k <= 90 {
            let time = Double(k) / 60.0
            let frameK = k - k % 2
            let frameTime = Double(frameK) / 60.0
            let reading = DistanceMeasurement.world(metres: 1.0 - 0.5 * frameTime)
            let before = ticked.estimate
            let r = ticked.update(reading, measuredAt: frameTime, time: time)
            if k % 2 == 0 {
                framesOnly.update(reading, time: frameTime)
                XCTAssertEqual(r.metres, framesOnly.estimate.metres)
                XCTAssertEqual(r.approachRate, framesOnly.estimate.approachRate)
                XCTAssertEqual(r.confidence, 1.0)
            } else {
                heldTicks += 1
                XCTAssertEqual(r.metres, before.metres, "between frames the distance is held")
            }
            k += 1
        }
        XCTAssertEqual(heldTicks, 45)
        XCTAssertEqual(ticked.estimate.approachRate, 0.5, accuracy: 0.03)
    }

    func testRateResumesAfterHeldTicks() {
        // The rate shown between readings fades, but the next reading continues from the measured rate.
        var a = DistanceEstimator()
        var b = DistanceEstimator()
        var k = 0
        while k <= 30 {
            let time = Double(k) / 30.0
            let reading = DistanceMeasurement.world(metres: 1.0 - 0.5 * time)
            a.update(reading, time: time)
            b.update(reading, time: time)
            if k < 30 {
                b.update(nil, time: time + 1.0 / 60.0)
            }
            k += 1
        }
        XCTAssertEqual(a.estimate.approachRate, b.estimate.approachRate, accuracy: 1e-12)
        XCTAssertEqual(a.estimate.metres ?? 0, b.estimate.metres ?? 1, accuracy: 1e-12)
    }

    func testReadingAgeFadesConfidence() {
        var e = DistanceEstimator(staleTime: 0.5)
        let r = e.update(.world(metres: 1.0), measuredAt: 0.0, sourceConfidence: 0.8, time: 0.25)
        XCTAssertEqual(r.metres ?? 0, 1.0, accuracy: 1e-12)
        XCTAssertEqual(r.confidence, 0.4, accuracy: 1e-9)
        XCTAssertEqual(r.time, 0.25)
        let held = e.update(.world(metres: 1.0), measuredAt: 0.0, sourceConfidence: 0.8, time: 0.6)
        XCTAssertEqual(held.confidence, 0, accuracy: 1e-12)
    }

    func testFutureMeasuredAtIsTreatedAsNow() {
        var e = DistanceEstimator()
        let r = e.update(.world(metres: 1.0), measuredAt: 5.0, time: 1.0)
        XCTAssertEqual(r.confidence, 1.0)
        // The reading was counted at 1.0, so another reading stamped 1.0 is stale.
        let stale = e.update(.world(metres: 0.9), measuredAt: 1.0, time: 1.02)
        XCTAssertEqual(stale.metres ?? 0, 1.0, accuracy: 1e-12)
        let fresh = e.update(.world(metres: 0.99), measuredAt: 1.03, time: 1.03)
        let m = fresh.metres ?? 0
        XCTAssertTrue(m < 1.0 && m > 0.99)
    }

    func testNonFiniteMeasuredAtCountsAsNone() {
        var e = DistanceEstimator()
        let r = e.update(.world(metres: 1.0), measuredAt: Double.nan, time: 1.0)
        XCTAssertNil(r.metres)
        XCTAssertEqual(r.confidence, 0)
        XCTAssertEqual(r.time, 1.0)
    }

    func testGapBetweenReadingTimesReseeds() {
        var e = DistanceEstimator(staleTime: 0.5)
        e.update(.world(metres: 1.0), measuredAt: 0, time: 0)
        let r = e.update(.world(metres: 0.9), measuredAt: 0.6, time: 0.6)
        XCTAssertEqual(r.metres ?? 0, 0.9, accuracy: 1e-12)
        XCTAssertEqual(r.approachRate, 0)
    }
}
