import XCTest
@testable import FlyCore

final class SmashDetectorTests: XCTestCase {

    // MARK: Synthetic streams

    /// Hinge held at `from` until `stillUntil`, then closing linearly to 0 over `duration`, sampled at `rate` Hz until `end`.
    func hingeClose(stillUntil: Double, duration: Double, rate: Double, end: Double, from: Double = 1.57) -> [HingeSample] {
        var out: [HingeSample] = []
        var k = 0
        while true {
            let t = Double(k) / rate
            if t > end { break }
            var a = from
            if t > stillUntil {
                a = max(0, from * (1.0 - (t - stillUntil) / duration))
            }
            out.append(HingeSample(angle: a, time: t))
            k += 1
        }
        return out
    }

    /// Hinge held still at `angle`, sampled at `rate` Hz until `end`.
    func hingeStill(angle: Double, rate: Double, end: Double) -> [HingeSample] {
        var out: [HingeSample] = []
        var k = 0
        while true {
            let t = Double(k) / rate
            if t > end { break }
            out.append(HingeSample(angle: angle, time: t))
            k += 1
        }
        return out
    }

    /// Luma at `from` until `startAt`, then falling linearly to `to` over `duration`, sampled at `rate` Hz until `end`.
    func lumaRamp(startAt: Double, duration: Double, rate: Double, end: Double, from: Double = 0.5, to: Double = 0.02) -> [LumaSample] {
        var out: [LumaSample] = []
        var k = 0
        while true {
            let t = Double(k) / rate
            if t > end { break }
            var m = from
            if t > startAt {
                m = max(to, from - (from - to) * (t - startAt) / duration)
            }
            out.append(LumaSample(mean: m, time: t))
            k += 1
        }
        return out
    }

    /// Feeds both streams in time order like a frame loop (advancing after every sample),
    /// then keeps advancing at 60 Hz until `until`. Returns every event.
    func run(_ det: inout SmashDetector, hinge: [HingeSample], luma: [LumaSample], until: Double) -> [SmashEvent] {
        var events: [SmashEvent] = []
        var hi = 0
        var li = 0
        var lastTime = 0.0
        while hi < hinge.count || li < luma.count {
            var takeHinge = false
            if hi < hinge.count && li < luma.count {
                takeHinge = hinge[hi].time <= luma[li].time
            } else {
                takeHinge = hi < hinge.count
            }
            if takeHinge {
                lastTime = hinge[hi].time
                if let e = det.addHinge(hinge[hi]) { events.append(e) }
                hi += 1
            } else {
                lastTime = luma[li].time
                if let e = det.addLuma(luma[li]) { events.append(e) }
                li += 1
            }
            if let e = det.advance(to: lastTime) { events.append(e) }
        }
        var t = lastTime
        while t < until {
            t += 1.0 / 60.0
            if let e = det.advance(to: t) { events.append(e) }
        }
        return events
    }

    func reasons(_ det: inout SmashDetector) -> [SmashRejectReason] {
        var r: [SmashRejectReason] = []
        for x in det.drainRejections() {
            r.append(x.reason)
        }
        return r
    }

    // MARK: Hinge only

    func testHingeNormalClose() throws {
        var det = SmashDetector(hingeAvailable: true)
        let events = run(&det, hinge: hingeClose(stillUntil: 1.0, duration: 0.3, rate: 60, end: 1.6), luma: [], until: 1.8)
        XCTAssertEqual(events.count, 1)
        let e = try XCTUnwrap(events.first)
        XCTAssertEqual(e.source, .hinge)
        XCTAssertEqual(e.motionStartTime, 1.0, accuracy: 0.02)
        XCTAssertEqual(e.time, 77.0 / 60.0, accuracy: 1e-9)
        XCTAssertFalse(e.lumaStalled)
        XCTAssertEqual(det.lastEvent, e)
    }

    func testHingeSlowCloseCounts() throws {
        var det = SmashDetector(hingeAvailable: true)
        let events = run(&det, hinge: hingeClose(stillUntil: 1.0, duration: 1.5, rate: 60, end: 3.0), luma: [], until: 3.2)
        XCTAssertEqual(events.count, 1)
        let e = try XCTUnwrap(events.first)
        XCTAssertEqual(e.source, .hinge)
        XCTAssertEqual(e.motionStartTime, 1.0, accuracy: 0.02)
    }

    func testHingeVerySlowCloseRejected() {
        var det = SmashDetector(hingeAvailable: true)
        let events = run(&det, hinge: hingeClose(stillUntil: 1.0, duration: 4.0, rate: 60, end: 5.5), luma: [], until: 5.6)
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(reasons(&det), [.closeTooSlow])
    }

    func testSparseHingeFourSamples() throws {
        var det = SmashDetector(hingeAvailable: true)
        let samples = [
            HingeSample(angle: 1.57, time: 0.0),
            HingeSample(angle: 1.1, time: 1.10),
            HingeSample(angle: 0.5, time: 1.22),
            HingeSample(angle: 0.05, time: 1.34)
        ]
        let events = run(&det, hinge: samples, luma: [], until: 1.5)
        XCTAssertEqual(events.count, 1)
        let e = try XCTUnwrap(events.first)
        XCTAssertEqual(e.source, .hinge)
        // max(0, 1.10 - 0.47 / 2.5) = 0.912
        XCTAssertEqual(e.motionStartTime, 0.912, accuracy: 1e-9)
        XCTAssertEqual(e.time, 1.34, accuracy: 1e-12)
    }

    func testSparseHingeThreeSamplesWithStatus() throws {
        var det = SmashDetector(hingeAvailable: true)
        let samples = [
            HingeSample(angle: 1.57, time: 0.0, status: .partiallyOpen),
            HingeSample(angle: 0.8, time: 1.2, status: .partiallyOpen),
            HingeSample(angle: 0.3, time: 1.35, status: .closed)
        ]
        let events = run(&det, hinge: samples, luma: [], until: 1.5)
        XCTAssertEqual(events.count, 1)
        let e = try XCTUnwrap(events.first)
        XCTAssertEqual(e.motionStartTime, 1.2 - 0.77 / 2.5, accuracy: 1e-9)
    }

    func testTwoSamplesLongGapEstimatesStart() throws {
        var det = SmashDetector(hingeAvailable: true)
        let events = run(&det, hinge: [HingeSample(angle: 1.57, time: 0), HingeSample(angle: 0, time: 10)], luma: [], until: 10.1)
        XCTAssertEqual(events.count, 1)
        let e = try XCTUnwrap(events.first)
        XCTAssertEqual(e.motionStartTime, 10 - 1.57 / 2.5, accuracy: 1e-9)
    }

    func testClosedStatusAtSameAngleStillCounts() throws {
        var det = SmashDetector(hingeAvailable: true)
        let samples = [
            HingeSample(angle: 1.57, time: 0.0),
            HingeSample(angle: 0.9, time: 0.1),
            HingeSample(angle: 0.2, time: 0.2, status: .partiallyOpen),
            HingeSample(angle: 0.2, time: 0.3, status: .closed)
        ]
        let events = run(&det, hinge: samples, luma: [], until: 0.4)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.time ?? 0, 0.3, accuracy: 1e-12)
    }

    func testCloseFromNearlyShutIsTooSmall() {
        var det = SmashDetector(hingeAvailable: true)
        var samples = hingeStill(angle: 1.57, rate: 10, end: 0.5)
        samples.append(HingeSample(angle: 0.45, time: 1.0))
        samples.append(HingeSample(angle: 0.45, time: 2.0))
        samples.append(HingeSample(angle: 0.25, time: 2.1))
        samples.append(HingeSample(angle: 0.05, time: 2.2))
        let events = run(&det, hinge: samples, luma: [], until: 2.3)
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(reasons(&det), [.closeTooSmall])
    }

    func testNotArmedWithoutOpenAngle() {
        var det = SmashDetector(hingeAvailable: true)
        let events = run(&det, hinge: hingeClose(stillUntil: 1.0, duration: 0.3, rate: 60, end: 1.6, from: 0.6), luma: [], until: 1.7)
        XCTAssertTrue(events.isEmpty)
        XCTAssertFalse(det.isHingeArmed)
    }

    func testRearmNeededForSecondSmash() {
        var det = SmashDetector(hingeAvailable: true)
        var samples = hingeClose(stillUntil: 1.0, duration: 0.3, rate: 60, end: 2.0)
        // Wobble while shut: no new event.
        samples.append(HingeSample(angle: 0.1, time: 2.1))
        samples.append(HingeSample(angle: 0.0, time: 2.2))
        // Reopen, then close again.
        samples.append(HingeSample(angle: 1.5, time: 3.0))
        samples.append(HingeSample(angle: 1.5, time: 3.5))
        samples.append(HingeSample(angle: 0.8, time: 3.6))
        samples.append(HingeSample(angle: 0.0, time: 3.7))
        let events = run(&det, hinge: samples, luma: [], until: 3.8)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.last?.motionStartTime ?? 0, 3.5, accuracy: 1e-9)
    }

    // MARK: Luma only (no hinge API)

    func testLumaOnlyFastCollapse() throws {
        var det = SmashDetector(hingeAvailable: false)
        let events = run(&det, hinge: [], luma: lumaRamp(startAt: 1.0, duration: 0.2, rate: 30, end: 1.6), until: 1.7)
        XCTAssertEqual(events.count, 1)
        let e = try XCTUnwrap(events.first)
        XCTAssertEqual(e.source, .luma)
        XCTAssertEqual(e.time, 1.2, accuracy: 1e-9)
        // Collapse starts at the last bright sample (1.0), minus lumaMotionLead (0.1).
        XCTAssertEqual(e.motionStartTime, 0.9, accuracy: 1e-9)
        XCTAssertFalse(e.lumaStalled)
    }

    func testLumaOnlyHandOverLensFastCountsAsStandIn() {
        // Without a hinge a fast cover is indistinguishable from a close; this is the iPad stand-in.
        var det = SmashDetector(hingeAvailable: false)
        let events = run(&det, hinge: [], luma: lumaRamp(startAt: 0.5, duration: 0.1, rate: 60, end: 1.0), until: 1.1)
        XCTAssertEqual(events.count, 1)
    }

    func testLumaOnlySlowCollapseRejected() {
        var det = SmashDetector(hingeAvailable: false)
        let events = run(&det, hinge: [], luma: lumaRamp(startAt: 1.0, duration: 1.5, rate: 30, end: 3.0), until: 3.1)
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(reasons(&det), [.collapseTooSlow])
    }

    func testLumaStaysDarkOnlyOneEvent() {
        var det = SmashDetector(hingeAvailable: false)
        let events = run(&det, hinge: [], luma: lumaRamp(startAt: 1.0, duration: 0.2, rate: 30, end: 4.0), until: 4.1)
        XCTAssertEqual(events.count, 1)
        XCTAssertFalse(det.isLumaArmed)
    }

    func testLumaNeverLitDoesNotFire() {
        var det = SmashDetector(hingeAvailable: false)
        let events = run(&det, hinge: [], luma: lumaRamp(startAt: 0.5, duration: 0.2, rate: 30, end: 1.5, from: 0.1, to: 0.01), until: 1.6)
        XCTAssertTrue(events.isEmpty)
    }

    func testLumaOnlyStreamStopsWhileDropping() throws {
        var det = SmashDetector(hingeAvailable: false)
        let luma = [
            LumaSample(mean: 0.5, time: 0.9),
            LumaSample(mean: 0.5, time: 1.0),
            LumaSample(mean: 0.38, time: 1.0 + 1.0 / 30.0),
            LumaSample(mean: 0.27, time: 1.0 + 2.0 / 30.0),
            LumaSample(mean: 0.18, time: 1.1)
        ]
        let events = run(&det, hinge: [], luma: luma, until: 1.6)
        XCTAssertEqual(events.count, 1)
        let e = try XCTUnwrap(events.first)
        XCTAssertEqual(e.source, .luma)
        XCTAssertTrue(e.lumaStalled)
        XCTAssertEqual(e.motionStartTime, 0.9, accuracy: 1e-9)
        XCTAssertTrue(e.time >= 1.25 && e.time < 1.3)
    }

    func testStallWhileSteadyIsNotASmash() {
        var det = SmashDetector(hingeAvailable: false)
        let luma = [LumaSample(mean: 0.5, time: 0.9), LumaSample(mean: 0.5, time: 1.0)]
        let events = run(&det, hinge: [], luma: luma, until: 2.0)
        XCTAssertTrue(events.isEmpty)
    }

    func testStallAloneCanBeDisabled() {
        var t = FlyTunables()
        t.lumaStallCountsAlone = false
        var det = SmashDetector(tunables: t, hingeAvailable: false)
        let luma = [
            LumaSample(mean: 0.5, time: 1.0),
            LumaSample(mean: 0.3, time: 1.05),
            LumaSample(mean: 0.2, time: 1.1)
        ]
        let events = run(&det, hinge: [], luma: luma, until: 1.6)
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(reasons(&det), [.stallOnly])
    }

    // MARK: Luma with hinge available

    func testHandOverLensRejectedWhenHingeStill() {
        var det = SmashDetector(hingeAvailable: true)
        let events = run(&det,
                         hinge: hingeStill(angle: 1.57, rate: 10, end: 2.0),
                         luma: lumaRamp(startAt: 1.0, duration: 0.2, rate: 30, end: 2.0),
                         until: 2.1)
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(reasons(&det), [.handOverLens])
    }

    func testHandOverLensRejectedWhenHingeSilent() {
        var det = SmashDetector(hingeAvailable: true)
        let events = run(&det,
                         hinge: [HingeSample(angle: 1.57, time: 0)],
                         luma: lumaRamp(startAt: 1.0, duration: 0.2, rate: 30, end: 2.0),
                         until: 2.1)
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(reasons(&det), [.handOverLens])
    }

    func testDarkeningConfirmedByHinge() throws {
        var det = SmashDetector(hingeAvailable: true)
        let events = run(&det,
                         hinge: hingeClose(stillUntil: 1.0, duration: 0.3, rate: 60, end: 1.6),
                         luma: lumaRamp(startAt: 1.15, duration: 0.12, rate: 30, end: 1.6),
                         until: 1.7)
        XCTAssertEqual(events.count, 1)
        let e = try XCTUnwrap(events.first)
        XCTAssertEqual(e.source, .hingeAndLuma)
        XCTAssertEqual(e.motionStartTime, 1.0, accuracy: 0.02)
        XCTAssertTrue(e.time < 77.0 / 60.0, "darkness confirmed by a moving hinge beats the hinge reaching shut")
    }

    func testDarknessBeforeSparseHingeWaitsForIt() throws {
        var det = SmashDetector(hingeAvailable: true)
        let hinge = [
            HingeSample(angle: 1.57, time: 0.5),
            HingeSample(angle: 1.57, time: 1.0),
            HingeSample(angle: 0.6, time: 1.25)
        ]
        let events = run(&det, hinge: hinge, luma: lumaRamp(startAt: 1.0, duration: 0.2, rate: 30, end: 1.6), until: 1.7)
        XCTAssertEqual(events.count, 1)
        let e = try XCTUnwrap(events.first)
        XCTAssertEqual(e.source, .hingeAndLuma)
        XCTAssertEqual(e.time, 1.25, accuracy: 1e-12)
        XCTAssertEqual(e.motionStartTime, 0.9, accuracy: 1e-9)
    }

    func testCaptureInterruptedMidCloseWithHinge() throws {
        var det = SmashDetector(hingeAvailable: true)
        let hinge = [
            HingeSample(angle: 1.57, time: 0.5),
            HingeSample(angle: 1.57, time: 1.0),
            HingeSample(angle: 1.2, time: 1.1)
        ]
        let luma = [
            LumaSample(mean: 0.5, time: 0.9),
            LumaSample(mean: 0.5, time: 1.0),
            LumaSample(mean: 0.38, time: 1.0 + 1.0 / 30.0),
            LumaSample(mean: 0.27, time: 1.0 + 2.0 / 30.0),
            LumaSample(mean: 0.18, time: 1.1)
        ]
        let events = run(&det, hinge: hinge, luma: luma, until: 1.6)
        XCTAssertEqual(events.count, 1)
        let e = try XCTUnwrap(events.first)
        XCTAssertEqual(e.source, .hingeAndLuma)
        XCTAssertTrue(e.lumaStalled)
        XCTAssertEqual(e.motionStartTime, 0.9, accuracy: 1e-9)
    }

    func testCaptureInterruptedButHingeStillIsRejected() {
        var det = SmashDetector(hingeAvailable: true)
        let luma = [
            LumaSample(mean: 0.5, time: 1.0),
            LumaSample(mean: 0.3, time: 1.05),
            LumaSample(mean: 0.2, time: 1.1)
        ]
        let events = run(&det, hinge: hingeStill(angle: 1.57, rate: 10, end: 1.0), luma: luma, until: 1.8)
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(reasons(&det), [.handOverLens])
    }

    // MARK: Debounce, manual, robustness

    func testManualAndDebounce() {
        var det = SmashDetector(hingeAvailable: false)
        let first = det.manualSmash(at: 1.0)
        XCTAssertEqual(first, SmashEvent(time: 1.0, motionStartTime: 1.0, source: .manual))
        XCTAssertNil(det.manualSmash(at: 1.5))
        XCTAssertEqual(reasons(&det), [.debounced])
        XCTAssertNotNil(det.manualSmash(at: 2.0))
    }

    func testHingeSmashWithinDebounceOfManualIsRejected() {
        var det = SmashDetector(hingeAvailable: true)
        XCTAssertNotNil(det.manualSmash(at: 1.1))
        let events = run(&det, hinge: hingeClose(stillUntil: 1.0, duration: 0.3, rate: 60, end: 1.6), luma: [], until: 1.7)
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(reasons(&det), [.debounced])
    }

    func testOutOfOrderAndNonFiniteSamplesIgnored() {
        var det = SmashDetector(hingeAvailable: true)
        XCTAssertNil(det.addHinge(HingeSample(angle: 1.57, time: 2.0)))
        XCTAssertNil(det.addHinge(HingeSample(angle: 0.0, time: 1.0)))
        XCTAssertNil(det.addHinge(HingeSample(angle: Double.nan, time: 3.0)))
        XCTAssertNil(det.addLuma(LumaSample(mean: 0.5, time: 2.0)))
        XCTAssertNil(det.addLuma(LumaSample(mean: 0.0, time: 1.0)))
        XCTAssertNil(det.addLuma(LumaSample(mean: Double.infinity, time: 3.0)))
        XCTAssertNil(det.advance(to: Double.nan))
        XCTAssertTrue(det.isHingeArmed)
    }

    func testAwaitingHingeFlag() {
        var det = SmashDetector(hingeAvailable: true)
        det.addHinge(HingeSample(angle: 1.57, time: 0))
        for s in lumaRamp(startAt: 1.0, duration: 0.2, rate: 30, end: 1.2) {
            det.addLuma(s)
        }
        XCTAssertTrue(det.isAwaitingHinge)
        det.advance(to: 1.6)
        XCTAssertFalse(det.isAwaitingHinge)
    }

    func testReset() {
        var det = SmashDetector(hingeAvailable: true)
        _ = run(&det, hinge: hingeClose(stillUntil: 1.0, duration: 0.3, rate: 60, end: 1.6), luma: [], until: 1.7)
        XCTAssertNotNil(det.lastEvent)
        det.reset()
        XCTAssertNil(det.lastEvent)
        XCTAssertFalse(det.isHingeArmed)
        XCTAssertFalse(det.isLumaArmed)
        XCTAssertTrue(det.rejections.isEmpty)
    }

    // MARK: Hinge status mapping (raw UIHinge.status integers)

    func testDeclarationOrderGuessMapping() {
        let g = HingeStatusMapping.declarationOrderGuess
        XCTAssertEqual(g, HingeStatusMapping(closed: 0, partiallyOpen: 1, fullyOpen: 2, unknown: 3))
        XCTAssertEqual(g.status(forRaw: 0), .closed)
        XCTAssertEqual(g.status(forRaw: 1), .partiallyOpen)
        XCTAssertEqual(g.status(forRaw: 2), .fullyOpen)
        XCTAssertNil(g.status(forRaw: 3), "unknown maps to nil")
        XCTAssertNil(g.status(forRaw: 7))
        XCTAssertNil(g.status(forRaw: nil))
        XCTAssertEqual(g.rawValue(for: .closed), 0)
        XCTAssertEqual(g.rawValue(for: .partiallyOpen), 1)
        XCTAssertEqual(g.rawValue(for: .fullyOpen), 2)
        XCTAssertEqual(FlyTunables().hingeStatusMapping, g)
    }

    func testIgnoreStatusAndCustomMapping() {
        XCTAssertNil(HingeStatusMapping.ignoreStatus.status(forRaw: 0))
        XCTAssertNil(HingeStatusMapping.ignoreStatus.rawValue(for: .closed))
        // For example, if P5 finds unknown = 0: the mapping changes in one place.
        let p5 = HingeStatusMapping(closed: 1, partiallyOpen: 2, fullyOpen: 3, unknown: 0)
        XCTAssertNil(p5.status(forRaw: 0))
        XCTAssertEqual(p5.status(forRaw: 1), .closed)
        XCTAssertEqual(p5.status(forRaw: 3), .fullyOpen)
        // Unknown wins over a clash; otherwise closed, partiallyOpen, fullyOpen in that order.
        XCTAssertNil(HingeStatusMapping(closed: 5, partiallyOpen: nil, fullyOpen: nil, unknown: 5).status(forRaw: 5))
        XCTAssertEqual(HingeStatusMapping(closed: nil, partiallyOpen: 4, fullyOpen: 4, unknown: nil).status(forRaw: 4), .partiallyOpen)
    }

    func testResolvedStatusPrefersExplicitStatus() {
        let g = HingeStatusMapping.declarationOrderGuess
        XCTAssertEqual(HingeSample(angle: 1, time: 0, status: .fullyOpen, statusRaw: 0).resolvedStatus(g), .fullyOpen)
        XCTAssertEqual(HingeSample(angle: 1, time: 0, statusRaw: 0).resolvedStatus(g), .closed)
        XCTAssertNil(HingeSample(angle: 1, time: 0).resolvedStatus(g))
        XCTAssertNil(HingeSample(angle: 1, time: 0).statusRaw)
    }

    func testRawClosedStatusClosesTheHinge() throws {
        let samples = [
            HingeSample(angle: 1.57, time: 0.0, statusRaw: 1),
            HingeSample(angle: 0.8, time: 1.2, statusRaw: 1),
            HingeSample(angle: 0.3, time: 1.35, statusRaw: 0)
        ]
        var det = SmashDetector(hingeAvailable: true)
        let events = run(&det, hinge: samples, luma: [], until: 1.5)
        XCTAssertEqual(events.count, 1)
        let e = try XCTUnwrap(events.first)
        XCTAssertEqual(e.time, 1.35, accuracy: 1e-12)
        XCTAssertEqual(e.motionStartTime, 1.2 - 0.77 / 2.5, accuracy: 1e-9)

        // Same stream with the status ignored: 0.3 rad is not shut by angle, so nothing yet.
        var t = FlyTunables()
        t.hingeStatusMapping = .ignoreStatus
        var angleOnly = SmashDetector(tunables: t, hingeAvailable: true)
        XCTAssertTrue(run(&angleOnly, hinge: samples, luma: [], until: 1.5).isEmpty)
        XCTAssertTrue(reasons(&angleOnly).isEmpty)
    }

    func testWrongMappingCannotShutAnOpenHinge() throws {
        // Suppose the guess is wrong and raw 1 (reported while open) is mapped as closed.
        var t = FlyTunables()
        t.hingeStatusMapping = HingeStatusMapping(closed: 1, partiallyOpen: nil, fullyOpen: nil, unknown: nil)
        var det = SmashDetector(tunables: t, hingeAvailable: true)
        var samples: [HingeSample] = []
        for h in hingeClose(stillUntil: 1.0, duration: 0.3, rate: 60, end: 1.6) {
            samples.append(HingeSample(angle: h.angle, time: h.time, statusRaw: 1))
        }
        let events = run(&det, hinge: [samples[0]], luma: [], until: 0)
        XCTAssertTrue(events.isEmpty)
        XCTAssertTrue(det.isHingeArmed, "an open angle arms the hinge whatever the raw status says")
        XCTAssertTrue(reasons(&det).isEmpty)
        var det2 = SmashDetector(tunables: t, hingeAvailable: true)
        let all = run(&det2, hinge: samples, luma: [], until: 1.8)
        XCTAssertEqual(all.count, 1)
        let e = try XCTUnwrap(all.first)
        XCTAssertEqual(e.motionStartTime, 1.0, accuracy: 0.02)
        XCTAssertTrue(e.time < 77.0 / 60.0 + 1e-9, "the mapped status may close it early, below the arming angle")
    }

    func testPostureBPresetAcceptsSlowWideClose() {
        // From about 2.4 rad (posture B) closing at about 0.65 rad/s: too long for the default 2.5 s.
        let stream = hingeClose(stillUntil: 1.0, duration: 3.7, rate: 60, end: 5.0, from: 2.4)
        var a = SmashDetector(tunables: FlyTunables(), hingeAvailable: true)
        XCTAssertTrue(run(&a, hinge: stream, luma: [], until: 5.1).isEmpty)
        XCTAssertEqual(reasons(&a), [.closeTooSlow])
        var b = SmashDetector(tunables: FlyTunables.duoPostureB, hingeAvailable: true)
        let events = run(&b, hinge: stream, luma: [], until: 5.1)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.source, .hinge)
    }
}
