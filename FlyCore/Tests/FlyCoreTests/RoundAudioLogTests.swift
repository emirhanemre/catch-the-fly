import XCTest
@testable import FlyCore

/// In-memory store for tests. A class so the non-mutating protocol methods can record.
final class MemoryBestTimeStore: BestTimeStore {
    var stored: Double?
    var saveCount = 0

    init(stored: Double?) {
        self.stored = stored
    }

    func loadBestTime() -> Double? {
        return stored
    }

    func saveBestTime(_ seconds: Double) {
        stored = seconds
        saveCount += 1
    }
}

final class FlyRoundTests: XCTestCase {

    func testThreeFliesFinishRound() {
        var r = FlyRound()
        XCTAssertEqual(r.phase, .idle)
        r.start()
        XCTAssertEqual(r.phase, .playing)
        r.tick(dt: 5)
        let p1 = r.recordCatch()
        XCTAssertEqual(p1, FlyRoundProgress(fliesCaught: 1, flyTime: 5, roundFinished: false, roundTime: nil, isNewBest: false, counted: true))
        r.tick(dt: 3)
        r.recordCatch()
        XCTAssertEqual(r.fliesRemaining, 1)
        r.tick(dt: 2)
        let p3 = r.recordCatch()
        XCTAssertTrue(p3.roundFinished)
        XCTAssertEqual(p3.roundTime ?? 0, 10, accuracy: 1e-12)
        XCTAssertTrue(p3.isNewBest)
        XCTAssertEqual(r.phase, .finished)
        XCTAssertEqual(r.bestTime ?? 0, 10, accuracy: 1e-12)
        XCTAssertEqual(r.lastRoundTime ?? 0, 10, accuracy: 1e-12)
        XCTAssertEqual(r.flyTimes, [5, 3, 2])
    }

    func testClockOnlyRunsWhilePlaying() {
        var r = FlyRound()
        r.tick(dt: 4)
        XCTAssertEqual(r.elapsed, 0)
        r.start()
        r.tick(dt: 1)
        r.tick(dt: -1)
        r.tick(dt: Double.nan)
        XCTAssertEqual(r.elapsed, 1)
        r.cancel()
        r.tick(dt: 1)
        XCTAssertEqual(r.elapsed, 1)
        XCTAssertEqual(r.phase, .idle)
    }

    func testCatchIgnoredUnlessPlaying() {
        var r = FlyRound()
        let p = r.recordCatch()
        XCTAssertFalse(p.counted)
        XCTAssertEqual(r.fliesCaught, 0)
    }

    func testSlowerRoundIsNotNewBest() {
        var r = FlyRound(fliesPerRound: 1, bestTime: 8)
        r.start()
        r.tick(dt: 9)
        let p = r.recordCatch()
        XCTAssertTrue(p.roundFinished)
        XCTAssertFalse(p.isNewBest)
        XCTAssertEqual(r.bestTime ?? 0, 8)
        r.start()
        r.tick(dt: 7)
        XCTAssertTrue(r.recordCatch().isNewBest)
        XCTAssertEqual(r.bestTime ?? 0, 7)
    }

    func testRestartResets() {
        var r = FlyRound(fliesPerRound: 2)
        r.start()
        r.tick(dt: 1)
        r.recordCatch()
        r.start()
        XCTAssertEqual(r.fliesCaught, 0)
        XCTAssertEqual(r.elapsed, 0)
        XCTAssertTrue(r.flyTimes.isEmpty)
    }

    func testInvalidInitValues() {
        let r = FlyRound(fliesPerRound: 0, bestTime: -3)
        XCTAssertEqual(r.fliesPerRound, 1)
        XCTAssertNil(r.bestTime)
    }

    func testBestTimeStoreLoadAndSave() {
        let store = MemoryBestTimeStore(stored: 12)
        var r = FlyRound(fliesPerRound: 1, store: store)
        XCTAssertEqual(r.bestTime ?? 0, 12)
        r.start()
        r.tick(dt: 15)
        r.recordCatch(savingTo: store)
        XCTAssertEqual(store.saveCount, 0)
        r.start()
        r.tick(dt: 6)
        r.recordCatch(savingTo: store)
        XCTAssertEqual(store.saveCount, 1)
        XCTAssertEqual(store.stored ?? 0, 6)
    }
}

final class AudioMathTests: XCTestCase {

    func testPan() {
        XCTAssertEqual(AudioMath.pan(bearing: 0), 0, accuracy: 1e-12)
        XCTAssertEqual(AudioMath.pan(bearing: Double.pi / 2), 1, accuracy: 1e-12)
        XCTAssertEqual(AudioMath.pan(bearing: -Double.pi / 2), -1, accuracy: 1e-12)
        XCTAssertEqual(AudioMath.pan(bearing: Double.pi / 6), 0.5, accuracy: 1e-12)
        XCTAssertEqual(AudioMath.pan(bearing: 2.5), 1, accuracy: 1e-12, "behind-right stays right")
        XCTAssertEqual(AudioMath.pan(bearing: -2.5), -1, accuracy: 1e-12)
        XCTAssertEqual(AudioMath.pan(bearing: 2 * Double.pi + 0.1), sin(0.1), accuracy: 1e-9)
    }

    func testDistanceGain() {
        XCTAssertEqual(AudioMath.distanceGain(distance: 0.1, referenceDistance: 0.3, minimumGain: 0.05), 1)
        XCTAssertEqual(AudioMath.distanceGain(distance: 0.6, referenceDistance: 0.3, minimumGain: 0.05), 0.5, accuracy: 1e-12)
        XCTAssertEqual(AudioMath.distanceGain(distance: 100, referenceDistance: 0.3, minimumGain: 0.05), 0.05)
        XCTAssertEqual(AudioMath.distanceGain(distance: Double.nan, referenceDistance: 0.3, minimumGain: 0.05), 0.05)
    }

    func testRearFactorAndGain() {
        XCTAssertEqual(AudioMath.rearFactor(bearing: 0, rearAttenuation: 0.4), 1, accuracy: 1e-12)
        XCTAssertEqual(AudioMath.rearFactor(bearing: Double.pi, rearAttenuation: 0.4), 0.6, accuracy: 1e-12)
        XCTAssertEqual(AudioMath.rearFactor(bearing: Double.pi / 2, rearAttenuation: 0.4), 0.8, accuracy: 1e-12)
        let t = FlyTunables()
        XCTAssertEqual(AudioMath.gain(distance: 0.6, bearing: Double.pi, tunables: t), 0.5 * 0.6, accuracy: 1e-12)
    }

    func testStereoGains() {
        let c = AudioMath.stereoGains(pan: 0)
        XCTAssertEqual(c.left, c.right, accuracy: 1e-12)
        XCTAssertEqual(c.left * c.left + c.right * c.right, 1, accuracy: 1e-12)
        let r = AudioMath.stereoGains(pan: 1)
        XCTAssertEqual(r.left, 0, accuracy: 1e-12)
        XCTAssertEqual(r.right, 1, accuracy: 1e-12)
        XCTAssertEqual(AudioMath.stereoGains(pan: 5), r)
    }
}

final class FlyLogTests: XCTestCase {

    func testFixed() {
        XCTAssertEqual(FlyLog.fixed(1.5, decimals: 2), "1.50")
        XCTAssertEqual(FlyLog.fixed(12.3456), "12.346")
        XCTAssertEqual(FlyLog.fixed(-0.25, decimals: 1), "-0.3")
        XCTAssertEqual(FlyLog.fixed(-0.0004), "0.000")
        XCTAssertEqual(FlyLog.fixed(0.05, decimals: 3), "0.050")
        XCTAssertEqual(FlyLog.fixed(7, decimals: 0), "7")
        XCTAssertEqual(FlyLog.fixed(1.0049, decimals: 2), "1.00")
        XCTAssertEqual(FlyLog.fixed(Double.nan), "nan")
        XCTAssertEqual(FlyLog.fixed(Double.infinity), "inf")
        XCTAssertEqual(FlyLog.fixed(-Double.infinity), "-inf")
        XCTAssertEqual(FlyLog.optionalFixed(nil), "none")
    }

    func testLine() {
        XCTAssertEqual(FlyLog.line(time: 3.25, tag: "SMASH", message: "hello"), "[3.250] SMASH hello")
    }

    func testDescriptions() {
        XCTAssertEqual(FlyLog.describe(FlyTransition(from: .wandering, to: .landed, reason: .arrived)), "wandering->landed arrived")
        XCTAssertEqual(FlyLog.describe(SmashEvent(time: 1.2833, motionStartTime: 1.0, source: .hinge)),
                       "source=hinge start=1.000 at=1.283 stalled=no")
        XCTAssertEqual(FlyLog.describe(SmashRejection(time: 1, reason: .handOverLens)), "handOverLens")
        XCTAssertEqual(FlyLog.describe(DistanceEstimate(metres: 0.25, confidence: 1, approachRate: 0, time: 0)),
                       "dist=0.250 conf=1.00 rate=0.000")
        XCTAssertEqual(FlyLog.describe(Vec3(1, -2, 0.5)), "(1.000,-2.000,0.500)")
        let p: FlyScreenPoint? = nil
        XCTAssertEqual(FlyLog.describe(p), "none")
        let snap = FlySnapshot(time: 1, flyState: .hovering, flySpeed: 0, distance: 0.067, distanceConfidence: 1,
                               screenPosition: FlyScreenPoint(x: 0.71, y: 0.5))
        let event = SmashEvent(time: 1.3, motionStartTime: 1.0, source: .hinge)
        let v = HitVerdict(isHit: true, reason: .hit, event: event, snapshot: snap, judgedTime: 0.97)
        XCTAssertEqual(FlyLog.describe(v), "hit reason=hit judged=0.970 state=hovering dist=0.067 conf=1.00 screen=(0.710,0.500)")
        let none = HitVerdict(isHit: false, reason: .noSnapshot, event: event, snapshot: nil, judgedTime: 0.97)
        XCTAssertEqual(FlyLog.describe(none), "miss reason=noSnapshot judged=0.970")
    }

    func testOverlayLines() {
        let out = FlyGameOutput(time: 2, round: FlyRound())
        let lines = FlyLog.overlayLines(out)
        XCTAssertEqual(lines, [
            "t=2.00",
            "fly none",
            "dist=none conf=0.00 rate=0.000",
            "pan=0.00 gain=0.00",
            "round idle 0/3 time=0.00 best=none"
        ])
    }
}
