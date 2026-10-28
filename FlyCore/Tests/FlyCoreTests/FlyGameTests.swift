import XCTest
@testable import FlyCore

final class FlyGameTests: XCTestCase {

    let dt = 1.0 / 60.0
    // About 92 degrees, roughly the ultrawide inner camera.
    let camera = FlyCamera(position: Vec3.zero, horizontalFOV: 1.6, verticalFOV: 1.6)
    // A spot 12 cm in front, slightly right, facing the camera. Hovering puts the fly at
    // (0.03, 0, -0.06): 6.7 cm away, at screen x of about 0.74 (inside a right-hinge region).
    let spot = LandingSpot(id: 7, position: Vec3(0.03, 0, -0.12), normal: Vec3(0, 0, 1))

    func tunables() -> FlyTunables {
        var t = FlyTunables()
        t.hoverRadius = 0
        return t
    }

    func makeGame(edge: HingeEdge = .right, hingeAvailable: Bool = true, seed: UInt64 = 2026, bestTime: Double? = nil) -> FlyGame {
        return FlyGame(tunables: tunables(), seed: seed, hingeEdge: edge, hingeAvailable: hingeAvailable, bestTime: bestTime)
    }

    func step(_ game: inout FlyGame, _ time: inout Double, manual: Bool = false, luma: [LumaSample] = []) -> FlyGameOutput {
        time += dt
        let input = FlyGameInput(time: time, camera: camera, spots: [spot], lumaSamples: luma, manualSmash: manual)
        return game.step(input: input, dt: dt)
    }

    /// Steps until the (current) fly has hovered for `hoverTime`. Collects every output on the way.
    func runUntilHovering(_ game: inout FlyGame, _ time: inout Double, hoverTime: Double = 0.5,
                          outputs: inout [FlyGameOutput], maxSteps: Int = 1200) -> Bool {
        var n = 0
        while n < maxSteps {
            let out = step(&game, &time)
            outputs.append(out)
            if let f = game.fly, f.state == .hovering, f.stateTime >= hoverTime {
                return true
            }
            n += 1
        }
        return false
    }

    // MARK: Tests

    func testNothingBeforeRoundStarts() {
        var game = makeGame()
        var time = 0.0
        let out = step(&game, &time)
        XCTAssertNil(out.fly)
        XCTAssertFalse(out.buzzing)
        XCTAssertEqual(out.audioGain, 0)
        XCTAssertTrue(out.cues.isEmpty)
        XCTAssertEqual(out.round.phase, .idle)
        XCTAssertEqual(game.lastStepTime ?? 0, dt, accuracy: 1e-12)
    }

    func testStartRoundSpawnsBuzzingFly() throws {
        var game = makeGame()
        var time = 0.0
        game.startRound()
        let out = step(&game, &time)
        XCTAssertEqual(out.cues, [.roundStarted, .newFly])
        let fly = try XCTUnwrap(out.fly)
        XCTAssertEqual(fly.state, .wandering)
        XCTAssertTrue(fly.cameraDistance > 1.0 && fly.cameraDistance < 2.0)
        XCTAssertTrue(out.buzzing)
        XCTAssertTrue(out.audioGain > 0 && out.audioGain <= 1)
        XCTAssertTrue(out.audioPan >= -1 && out.audioPan <= 1)
        XCTAssertEqual(out.round.phase, .playing)
        XCTAssertTrue(out.logLines.contains(FlyLog.line(time: dt, tag: "ROUND", message: "started")))
        let second = step(&game, &time)
        XCTAssertTrue(second.cues.isEmpty)
    }

    func testFlyLandsThenHoversWhenClose() {
        var game = makeGame()
        var time = 0.0
        game.startRound()
        var outputs: [FlyGameOutput] = []
        XCTAssertTrue(runUntilHovering(&game, &time, outputs: &outputs))
        var transitions: [FlyTransition] = []
        var cues: [FlyGameCue] = []
        for o in outputs {
            transitions += o.transitions
            cues += o.cues
        }
        XCTAssertTrue(transitions.contains(FlyTransition(from: .wandering, to: .landed, reason: .arrived)))
        XCTAssertTrue(transitions.contains(FlyTransition(from: .landed, to: .hovering, reason: .playerClose)))
        XCTAssertFalse(cues.contains(.flyAlarmed), "the fly's own approach must not alarm it")
        XCTAssertTrue(cues.contains(.flyTookOff))
        let last = outputs[outputs.count - 1]
        XCTAssertEqual(last.fly?.spotID, 7)
        XCTAssertTrue((last.distance.metres ?? 1) < 0.12)
    }

    func testManualSmashOnHoveringFlyIsHit() throws {
        var game = makeGame()
        var time = 0.0
        game.startRound()
        var outputs: [FlyGameOutput] = []
        XCTAssertTrue(runUntilHovering(&game, &time, outputs: &outputs))
        let out = step(&game, &time, manual: true)
        XCTAssertEqual(out.smashEvents.count, 1)
        XCTAssertEqual(out.smashEvents.first?.source, .manual)
        let verdict = try XCTUnwrap(out.verdicts.first)
        XCTAssertTrue(verdict.isHit, FlyLog.describe(verdict))
        XCTAssertEqual(out.splats.count, 1)
        let splat = try XCTUnwrap(out.splats.first?.screenPosition)
        XCTAssertTrue(splat.x > 0.5 && splat.x < 0.94)
        XCTAssertTrue(out.cues.contains(.hit))
        XCTAssertEqual(out.round.fliesCaught, 1)
        XCTAssertEqual(out.fly?.state, .smashed)
        XCTAssertFalse(out.buzzing)
        XCTAssertNil(out.newBestTime)
    }

    func testSmashOutsideRegionIsMissAndFlyBolts() throws {
        var game = makeGame(edge: .left)
        var time = 0.0
        game.startRound()
        var outputs: [FlyGameOutput] = []
        XCTAssertTrue(runUntilHovering(&game, &time, outputs: &outputs))
        let out = step(&game, &time, manual: true)
        let verdict = try XCTUnwrap(out.verdicts.first)
        XCTAssertFalse(verdict.isHit)
        XCTAssertEqual(verdict.reason, .outsideHitRegion)
        XCTAssertTrue(out.cues.contains(.miss))
        XCTAssertTrue(out.cues.contains(.flyAlarmed))
        XCTAssertEqual(out.fly?.state, .alarmed)
        XCTAssertEqual(out.round.fliesCaught, 0)
        XCTAssertTrue(out.splats.isEmpty)
    }

    func testLiveTunablesChangeTheVerdict() throws {
        var game = makeGame()
        var time = 0.0
        game.startRound()
        var outputs: [FlyGameOutput] = []
        XCTAssertTrue(runUntilHovering(&game, &time, outputs: &outputs))
        game.tunables.smashDistance = 0.01
        let out = step(&game, &time, manual: true)
        XCTAssertEqual(out.verdicts.first?.reason, .tooFar)
    }

    func testLumaSmashJudgedFromBeforeTheFold() throws {
        var game = makeGame(hingeAvailable: false)
        var time = 0.0
        game.startRound()
        var dropStart: Double? = nil
        var verdicts: [HitVerdict] = []
        var n = 0
        while n < 1500 && verdicts.isEmpty {
            let next = time + dt
            if dropStart == nil, let f = game.fly, f.state == .hovering, f.stateTime >= 0.8 {
                dropStart = next
            }
            var mean = 0.5
            if let s = dropStart {
                mean = max(0.02, 0.5 - 0.48 * (next - s) / 0.2)
            }
            let out = step(&game, &time, luma: [LumaSample(mean: mean, time: next)])
            verdicts += out.verdicts
            if let e = out.smashEvents.first {
                XCTAssertEqual(e.source, .luma)
                XCTAssertTrue(e.motionStartTime < (dropStart ?? 0))
            }
            n += 1
        }
        let v = try XCTUnwrap(verdicts.first)
        XCTAssertTrue(v.isHit, FlyLog.describe(v))
        XCTAssertEqual(v.snapshot?.flyState, .hovering)
    }

    func testFullRoundRecordsNewBestTime() {
        let store = MemoryBestTimeStore(stored: nil)
        var game = FlyGame(tunables: tunables(), seed: 5, hingeEdge: .right, hingeAvailable: true, store: store)
        var time = 0.0
        game.startRound()
        var finalOutput: FlyGameOutput? = nil
        var catches = 0
        while catches < 3 {
            var outputs: [FlyGameOutput] = []
            XCTAssertTrue(runUntilHovering(&game, &time, outputs: &outputs))
            let out = step(&game, &time, manual: true)
            XCTAssertEqual(out.verdicts.first?.isHit, true)
            catches += 1
            if catches < 3 {
                XCTAssertFalse(out.cues.contains(.roundFinished))
            } else {
                finalOutput = out
            }
        }
        guard let out = finalOutput else {
            XCTFail("no final output")
            return
        }
        XCTAssertTrue(out.cues.contains(.roundFinished))
        XCTAssertTrue(out.cues.contains(.newBestTime))
        XCTAssertEqual(out.round.phase, .finished)
        XCTAssertEqual(out.round.fliesCaught, 3)
        let best = out.newBestTime ?? -1
        XCTAssertEqual(best, out.round.lastRoundTime ?? -2)
        XCTAssertTrue(best > 0)
        if let b = out.newBestTime {
            store.saveBestTime(b)
        }
        let reloaded = FlyGame(seed: 1, hingeEdge: .right, hingeAvailable: true, store: store)
        XCTAssertEqual(reloaded.round.bestTime ?? -1, best)
        // After the round no new fly appears.
        var after = out
        var k = 0
        while k < 300 {
            after = step(&game, &time)
            k += 1
        }
        XCTAssertFalse(after.cues.contains(.newFly))
        XCTAssertFalse(after.buzzing)
    }

    func testSlowerRoundIsNotNewBest() {
        var game = makeGame(bestTime: 0.5)
        var time = 0.0
        game.startRound()
        var catches = 0
        var last: FlyGameOutput? = nil
        while catches < 3 {
            var outputs: [FlyGameOutput] = []
            XCTAssertTrue(runUntilHovering(&game, &time, outputs: &outputs))
            last = step(&game, &time, manual: true)
            catches += 1
        }
        XCTAssertEqual(last?.round.phase, .finished)
        XCTAssertNil(last?.newBestTime)
        XCTAssertFalse(last?.cues.contains(.newBestTime) ?? true)
        XCTAssertEqual(last?.round.bestTime ?? 0, 0.5)
    }

    func testDeterministicReplay() {
        var a = makeGame(seed: 77)
        var b = makeGame(seed: 77)
        a.startRound()
        b.startRound()
        var ta = 0.0
        var tb = 0.0
        var n = 0
        while n < 600 {
            let manual = n == 400
            let oa = step(&a, &ta, manual: manual)
            let ob = step(&b, &tb, manual: manual)
            XCTAssertEqual(oa, ob)
            n += 1
        }
        XCTAssertEqual(a, b)
    }

    func testCancelRoundAndHingeFlag() {
        var game = makeGame(hingeAvailable: false)
        XCTAssertFalse(game.hingeAvailable)
        game.hingeAvailable = true
        XCTAssertTrue(game.hingeAvailable)
        var time = 0.0
        game.startRound()
        _ = step(&game, &time)
        XCTAssertNotNil(game.fly)
        game.cancelRound()
        XCTAssertNil(game.fly)
        let out = step(&game, &time)
        XCTAssertNil(out.fly)
        XCTAssertEqual(out.round.phase, .idle)
    }

    func testLargeDtIsClamped() {
        var game = makeGame()
        game.startRound()
        let input = FlyGameInput(time: 10, camera: camera, spots: [spot])
        let out = game.step(input: input, dt: 5.0)
        XCTAssertEqual(out.round.elapsed, tunables().maxStepDt, accuracy: 1e-12)
        let out2 = game.step(input: FlyGameInput(time: 10.1, camera: camera, spots: [spot]), dt: Double.nan)
        XCTAssertEqual(out2.round.elapsed, tunables().maxStepDt, accuracy: 1e-12)
    }

    func testTimestampedDistanceReadingIsNotRecounted() {
        var game = makeGame()
        game.startRound()
        let m1 = DistanceMeasurement.patchScale(ratio: 1.0, referenceDistance: 1.0)
        let first = game.step(input: FlyGameInput(time: dt, camera: camera, spots: [spot],
                                                  distanceMeasurement: m1, distanceConfidence: 1.0,
                                                  distanceMeasuredAt: dt), dt: dt)
        XCTAssertEqual(first.distance.metres ?? 0, 1.0, accuracy: 1e-12)
        // Next tick, no new camera frame: the app passes the same frame's timestamp. Not counted.
        let m2 = DistanceMeasurement.patchScale(ratio: 2.0, referenceDistance: 1.0)
        let second = game.step(input: FlyGameInput(time: 2 * dt, camera: camera, spots: [spot],
                                                   distanceMeasurement: m2, distanceConfidence: 1.0,
                                                   distanceMeasuredAt: dt), dt: dt)
        XCTAssertEqual(second.distance.metres ?? 0, 1.0, accuracy: 1e-12)
        XCTAssertEqual(second.distance.confidence, 1.0 - dt / tunables().distanceStaleTime, accuracy: 1e-9)
        // A new frame: counted (smoothed towards 0.98).
        let m3 = DistanceMeasurement.patchScale(ratio: 1.0 / 0.98, referenceDistance: 1.0)
        let third = game.step(input: FlyGameInput(time: 3 * dt, camera: camera, spots: [spot],
                                                  distanceMeasurement: m3, distanceConfidence: 1.0,
                                                  distanceMeasuredAt: 3 * dt), dt: dt)
        let m = third.distance.metres ?? 0
        XCTAssertTrue(m < 1.0 && m > 0.98)
        XCTAssertEqual(third.distance.confidence, 1.0, accuracy: 1e-12)
        XCTAssertNil(FlyGameInput(time: 0, camera: camera).distanceMeasuredAt)
    }
}
