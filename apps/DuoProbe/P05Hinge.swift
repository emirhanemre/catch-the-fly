import SwiftUI

@MainActor
final class P5Model: ObservableObject {
    let hinge: HingeProbe
    let motion = MotionRecorder()
    @Published private(set) var recording = false
    @Published private(set) var readout = ""
    @Published private(set) var summary = ""
    private var motionSamples: [MotionSample] = []
    private var startT: TimeInterval = 0
    private var csv: CSVWriter?
    private let poller = Poller()
    private let log: ProbeLog

    init(log: ProbeLog) {
        self.log = log
        hinge = HingeProbe(testID: "P5", log: log)
        hinge.logEachSample = true
    }

    func appeared() {
        poller.start { [weak self] in
            self?.tick()
        }
    }

    func start() {
        guard !recording else { return }
        log.add("P5", "---- P5 hinge: 1 slow + 5 normal closes ----")
        log.add("P5", "hinge availability: \(hinge.availability)")
        startT = uptimeNow()
        motionSamples = []
        hinge.resetSamples()
        if !motion.start() {
            log.add("P5", "device motion not available: closes will be timed from the hinge alone")
        }
        csv = Sidecar.start(log: log, testID: "P5", prefix: "P5-hinge-motion", motion: motion,
                            frameBox: nil, hingeBox: hinge.latestBox)
        recording = true
        summary = ""
    }

    func stop() {
        guard recording else { return }
        recording = false
        motionSamples += motion.samples.drain()
        motion.stop()
        Sidecar.finish(csv, motion: motion, log: log, testID: "P5")
        csv = nil
        analyse()
    }

    func leave() {
        stop()
        poller.stop()
    }

    private func tick() {
        if recording {
            motionSamples += motion.samples.drain()
        }
        var text = hinge.readout
        if recording {
            text += "\nRecording for \(fmt(uptimeNow() - startT, 0)) s"
        }
        readout = text
    }

    private func analyse() {
        let hs = hinge.samples.filter { $0.t >= startT }
        log.result("P5", .value, "hinge samples recorded: \(hs.count); motion samples: \(motionSamples.count)")
        guard hinge.isAvailable else {
            log.result("P5", .notAvailable, "hinge API not available: \(hinge.availability)")
            summary = "Hinge not available on this device. That's expected on the iPad."
            return
        }
        guard !hs.isEmpty else {
            log.result("P5", .fail, "the hinge interaction was attached but sent no updates")
            summary = "No hinge updates arrived."
            return
        }
        let angles = hs.compactMap { $0.angle }
        if let lo = angles.min(), let hi = angles.max() {
            log.result("P5", .value, "angle range \(fmt(lo, 3))...\(fmt(hi, 3)) rad (\(degText(lo))...\(degText(hi)))")
        }
        var statusCounts: [Int: Int] = [:]
        for s in hs {
            if let raw = s.statusRaw { statusCounts[raw, default: 0] += 1 }
        }
        let statusText = statusCounts.keys.sorted().map { "\($0)×\(statusCounts[$0] ?? 0)" }.joined(separator: ", ")
        log.result("P5", .value, "raw status values seen: \(statusText.isEmpty ? "none" : statusText)")
        let nilHinge = hs.filter { !$0.hasHinge }.count
        if nilHinge > 0 {
            log.result("P5", .value, "\(nilHinge) updates had update.hinge = nil")
        }

        let closes = CloseMath.hingeCloses(hs)
        var lines: [String] = []
        var normalCounts: [Double] = []
        var normalTimes: [Double] = []
        for (k, idx) in closes.enumerated() {
            let endT = hs[idx].t
            let gyroStart = CloseMath.motionStart(before: endT, motion: motionSamples)
            let hingeStart = CloseMath.hingeMotionStart(hs, closeIndex: idx)
            let start = gyroStart ?? hingeStart ?? (endT - 1.0)
            let source = gyroStart != nil ? "gyro" : (hingeStart != nil ? "hinge" : "guess 1 s")
            let count = hs.filter { $0.t >= start && $0.t <= endT }.count
            let before = hs.last(where: { $0.t < start })?.statusRaw
            let change = hs.first(where: { $0.t >= start && $0.t <= endT + 2.0 && $0.statusRaw != before })
            let beforeText = before.map { "\($0)" } ?? "nil"
            var changeText = "no status change"
            if let c = change {
                let raw = c.statusRaw.map { "\($0)" } ?? "nil"
                changeText = "status \(beforeText)→\(raw) after \(ms(c.t - start)) ms"
            }
            let label = k == 0 ? "slow close" : "normal close \(k)"
            let line = "\(label): \(count) samples from motion start (\(source)) to angle < 9°, taking \(ms(endT - start)) ms; \(changeText)"
            lines.append(line)
            log.result("P5", .value, line)
            if k > 0 {
                normalCounts.append(Double(count))
                normalTimes.append(endT - start)
            }
        }
        if closes.isEmpty {
            log.result("P5", .value, "no close detected (angle never went from > 29° to < 9°). Check the angle range above")
        }
        if let medianCount = CloseMath.median(normalCounts), let medianTime = CloseMath.median(normalTimes) {
            let verdict = medianCount >= 4 ? ResultKind.pass : ResultKind.value
            log.result("P5", verdict, "\(normalCounts.count) normal closes: median \(fmt(medianCount, 0)) samples per close, median \(ms(medianTime)) ms from motion start to angle < 9° (plan needs at least 4 samples)")
        }
        summary = lines.isEmpty ? "No closes detected. See the log." : lines.joined(separator: "\n")
    }
}

struct P5View: View {
    let log: ProbeLog
    @StateObject private var model: P5Model

    init(log: ProbeLog) {
        self.log = log
        _model = StateObject(wrappedValue: P5Model(log: log))
    }

    var body: some View {
        TestPage(id: "P5", title: "Hinge", steps: [
            "Hold the phone in Posture A (half-open like an L, small outer screen facing you). Tap Start.",
            "Close the phone SLOWLY once, taking about 3 seconds. Keep it shut for 2 seconds, then open it back to Posture A and wait 2 seconds.",
            "Now close it 5 times at normal speed, the way you'd shut a book. Never slam it. Each time: keep it shut for 2 seconds, open back to Posture A, wait 2 seconds.",
            "Open the phone and tap Stop and analyse."
        ], log: log) {
            ReadoutBox(text: model.readout)
            HStack {
                BigButton("Start", enabled: !model.recording) { model.start() }
                BigButton("Stop and analyse", enabled: model.recording) { model.stop() }
            }
            if !model.summary.isEmpty {
                ReadoutBox(text: model.summary)
            }
        }
        .background(HingeHost(probe: model.hinge))
        .onAppear { model.appeared() }
        .onDisappear { model.leave() }
    }
}
