import SwiftUI

/// Timestamps everything the app can observe while the phone closes and reopens:
/// scene phase and lifecycle notifications (logged as SYS by the app), window, screen and
/// size-class changes, gyro spikes, luma, frame gaps and hinge samples.
@MainActor
final class P10Model: ObservableObject {
    let camera: CameraController
    let hinge: HingeProbe
    let motion = MotionRecorder()
    @Published private(set) var recording = false
    @Published private(set) var counts = "Nothing recorded yet"
    private var csv: CSVWriter?
    private var inSpike = false
    private var spikePeak = 0.0
    private var lumaBaseline: Double?
    private var isDark = false
    private var lastFrameT: Double?
    private var tally: [String: Int] = [:]
    private let poller = Poller()
    private let log: ProbeLog

    init(log: ProbeLog) {
        self.log = log
        camera = CameraController(testID: "P10", log: log)
        hinge = HingeProbe(testID: "P10", log: log)
        camera.onFrames = { [weak self] batch in
            self?.frames(batch)
        }
        hinge.onSample = { [weak self] _ in
            self?.count("hinge sample")
        }
    }

    func start() {
        guard !recording else { return }
        log.add("P10", "---- P10 close signals: 3 normal closes ----")
        for line in DisplayInfo.describeScenes() {
            log.add("P10", "scenes at start: " + line)
        }
        tally = [:]
        inSpike = false
        lumaBaseline = nil
        isDark = false
        lastFrameT = nil
        recording = true
        hinge.logEachSample = true
        Task { @MainActor in
            if !camera.isRunning {
                await InnerCamera.start(camera, testID: "P10", log: log)
            }
            // Stopped or left while the camera was starting: don't start sensors after stop().
            guard recording else {
                camera.stop()
                return
            }
            motion.start()
            csv = Sidecar.start(log: log, testID: "P10", prefix: "P10-signals", motion: motion,
                                frameBox: camera.latestFrame, hingeBox: hinge.latestBox)
            poller.start(intervalMs: 50) { [weak self = self] in
                self?.tick()
            }
        }
    }

    func stop() {
        guard recording else { return }
        recording = false
        hinge.logEachSample = false
        poller.stop()
        tick()
        motion.stop()
        Sidecar.finish(csv, motion: motion, log: log, testID: "P10")
        csv = nil
        camera.stop()
        for line in DisplayInfo.describeScenes() {
            log.add("P10", "scenes at end: " + line)
        }
        let summary = tally.keys.sorted().map { "\($0) ×\(tally[$0] ?? 0)" }.joined(separator: ", ")
        log.result("P10", .value, "signals seen: \(summary.isEmpty ? "none" : summary)")
    }

    func geometryChanged(_ text: String) {
        log.add("P10", "geometry: " + text)
        if recording { count("geometry change") }
    }

    private func count(_ key: String) {
        guard recording else { return }
        tally[key, default: 0] += 1
        counts = tally.keys.sorted().map { "\($0): \(tally[$0] ?? 0)" }.joined(separator: "\n")
    }

    private func tick() {
        for m in motion.samples.drain() {
            let r = m.rotationMagnitude
            if !inSpike && r > 1.5 {
                inSpike = true
                spikePeak = r
                log.add("P10", "gyro spike START |ω| \(fmt(r, 2)) rad/s", at: m.t)
                count("gyro spike")
            } else if inSpike {
                spikePeak = max(spikePeak, r)
                if r < 0.5 {
                    inSpike = false
                    log.add("P10", "gyro spike END (peak \(fmt(spikePeak, 2)) rad/s)", at: m.t)
                }
            }
        }
        if let last = lastFrameT, recording, camera.isRunning, uptimeNow() - last > 0.5 {
            // Frames stopped arriving: log once per gap (the next frame logs "arriving").
            log.add("P10", "camera frames stopped (none for \(ms(uptimeNow() - last)) ms)")
            count("frame gap")
            lastFrameT = nil
        }
    }

    private func frames(_ batch: [FrameSample]) {
        guard recording else { return }
        for f in batch where f.luma >= 0 {
            if lastFrameT == nil {
                log.add("P10", "camera frames arriving (luma \(fmt(f.luma, 0)))", at: f.t)
            }
            lastFrameT = f.t
            guard let b = lumaBaseline else {
                lumaBaseline = f.luma
                continue
            }
            if !isDark {
                if b > 12 && f.luma < 0.25 * b {
                    isDark = true
                    log.add("P10", "luma DARK (\(fmt(f.luma, 0)), open was \(fmt(b, 0)))", at: f.t)
                    count("luma dark")
                } else if f.luma >= 0.5 * b {
                    lumaBaseline = 0.95 * b + 0.05 * f.luma
                }
            } else if f.luma > 0.6 * b {
                isDark = false
                lumaBaseline = f.luma
                log.add("P10", "luma BRIGHT again (\(fmt(f.luma, 0)))", at: f.t)
                count("luma bright")
            }
        }
    }

    func leave() {
        stop()
        camera.stop()
    }
}

struct P10View: View {
    let log: ProbeLog
    @StateObject private var model: P10Model

    init(log: ProbeLog) {
        self.log = log
        _model = StateObject(wrappedValue: P10Model(log: log))
    }

    var body: some View {
        TestPage(id: "P10", title: "What the app notices when you close", steps: [
            "Hold the phone in Posture A, pointing at the room. Tap Start and wait for the camera numbers to move.",
            "Close the phone at normal speed. Never slam it.",
            "While it's shut, look at the small outer screen for 3 seconds and remember what it shows.",
            "Open it back to Posture A and wait 3 seconds.",
            "Do steps 2 to 4 three times in total, then tap Stop and answer the questions."
        ], log: log) {
            CameraPanel(camera: model.camera)
            ReadoutBox(text: model.counts)
            HStack {
                BigButton("Start", enabled: !model.recording) { model.start() }
                BigButton("Stop", enabled: model.recording) { model.stop() }
            }
            AnswerButtons(testID: "P10", question: "When the phone was shut, what did the small outer screen show?",
                          options: ["Nothing / black", "This app (DuoProbe)", "The lock screen",
                                    "The home screen", "Something else"], log: log)
            AnswerButtons(testID: "P10", question: "When you opened it again, what was on the screen?",
                          options: ["This test, still running", "This app, but it had restarted",
                                    "The lock screen", "The home screen", "Something else"], log: log)
        }
        .background(HingeHost(probe: model.hinge))
        .background(WindowWatcher { text in model.geometryChanged(text) })
        .onDisappear { model.leave() }
    }
}
