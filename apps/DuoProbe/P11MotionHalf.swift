import SwiftUI

/// Which half holds the motion sensors: swing one half while the other is held still,
/// then the reverse, and compare the gyro readings.
@MainActor
final class P11Model: ObservableObject {
    struct PhaseResult {
        let mean: Double
        let peak: Double
        let samples: Int
    }

    let motion = MotionRecorder()
    @Published private(set) var status = "Not started"
    @Published private(set) var busy = false
    @Published private(set) var phase1: PhaseResult?
    @Published private(set) var phase2: PhaseResult?
    private let log: ProbeLog

    init(log: ProbeLog) {
        self.log = log
    }

    func run(phase: Int) {
        guard !busy else { return }
        guard motion.isAvailable else {
            log.result("P11", .notAvailable, "device motion isn't available")
            status = "Motion sensors aren't available."
            return
        }
        busy = true
        Task { @MainActor in
            if phase == 1 {
                log.add("P11", "---- P11 which half has the motion sensors ----")
            }
            for n in [3, 2, 1] {
                status = "Phase \(phase): get ready… \(n)"
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            status = "Phase \(phase): swing now (5 seconds)"
            motion.start()
            let t0 = uptimeNow()
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            let samples = motion.samples.drain().filter { $0.t >= t0 }
            motion.stop()
            let mags = samples.map { $0.rotationMagnitude }
            let mean = mags.isEmpty ? 0 : mags.reduce(0, +) / Double(mags.count)
            let peak = mags.max() ?? 0
            let result = PhaseResult(mean: mean, peak: peak, samples: mags.count)
            let what = phase == 1 ? "half facing you held still, far half swinging" : "far half held still, half facing you swinging"
            log.result("P11", .value, "phase \(phase) (\(what)): mean |ω| \(fmt(mean, 3)) rad/s, peak \(fmt(peak, 3)) rad/s, \(mags.count) samples")
            if phase == 1 { phase1 = result } else { phase2 = result }
            status = "Phase \(phase) done."
            busy = false
            conclude()
        }
    }

    private func conclude() {
        guard let p1 = phase1, let p2 = phase2 else { return }
        let verdict: String
        if p1.mean > 2 * p2.mean {
            verdict = "the motion sensors are in the FAR (folding) half, not the half with the outer screen"
        } else if p2.mean > 2 * p1.mean {
            verdict = "the motion sensors are in the half facing you (the outer-screen half, which also holds the inner camera)"
        } else {
            verdict = "unclear (the two phases are within a factor of 2): repeat P11"
        }
        log.result("P11", .value, "conclusion: \(verdict)")
        status = "Done: \(verdict)."
    }
}

struct P11View: View {
    let log: ProbeLog
    @StateObject private var model: P11Model

    init(log: ProbeLog) {
        self.log = log
        _model = StateObject(wrappedValue: P11Model(log: log))
    }

    var body: some View {
        TestPage(id: "P11", title: "Which half has the motion sensors", steps: [
            "Sit at a table. Hold the phone in Posture A, small outer screen facing you.",
            "Phase 1: rest the half facing you on the table or hold it firmly so it doesn't move. Tap Start phase 1. After the countdown, gently swing the far half a little way open and closed (don't shut it) for 5 seconds.",
            "Phase 2: now hold the far half still and gently swing the half facing you instead. Tap Start phase 2 and do the same for 5 seconds.",
            "Keep the movements gentle and at normal speed."
        ], log: log) {
            ReadoutBox(text: model.status)
            BigButton("Start phase 1", enabled: !model.busy) { model.run(phase: 1) }
            BigButton("Start phase 2", enabled: !model.busy) { model.run(phase: 2) }
        }
    }
}
