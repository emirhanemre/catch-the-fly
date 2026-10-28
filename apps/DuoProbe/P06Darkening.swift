import SwiftUI

@MainActor
final class P6Model: ObservableObject {
    let camera: CameraController
    let hinge: HingeProbe
    let motion = MotionRecorder()
    @Published private(set) var recording = false
    @Published private(set) var darkCount = 0
    @Published private(set) var summary = ""
    private var frames: [FrameSample] = []
    private var motionSamples: [MotionSample] = []
    private var startT: TimeInterval = 0
    private var csv: CSVWriter?
    private let poller = Poller()
    private let log: ProbeLog

    init(log: ProbeLog) {
        self.log = log
        camera = CameraController(testID: "P6", log: log)
        hinge = HingeProbe(testID: "P6", log: log)
        camera.onFrames = { [weak self] batch in
            self?.received(batch)
        }
    }

    func start() {
        guard !recording else { return }
        log.add("P6", "---- P6 darkening: 5 normal closes ----")
        frames = []
        motionSamples = []
        darkCount = 0
        summary = ""
        startT = uptimeNow()
        recording = true
        Task { @MainActor in
            if !camera.isRunning {
                await InnerCamera.start(camera, testID: "P6", log: log)
            }
            // Stopped or left while the camera was starting: don't start sensors after stop().
            guard recording else {
                camera.stop()
                return
            }
            motion.start()
            csv = Sidecar.start(log: log, testID: "P6", prefix: "P6-luma-motion", motion: motion,
                                frameBox: camera.latestFrame, hingeBox: hinge.latestBox)
            poller.start { [weak self = self] in
                self?.tick()
            }
        }
    }

    private func received(_ batch: [FrameSample]) {
        guard recording else { return }
        frames.append(contentsOf: batch)
    }

    private func tick() {
        motionSamples += motion.samples.drain()
        darkCount = CloseMath.darkEvents(frames.suffix(1800).map { $0 }).count
    }

    func stop() {
        guard recording else { return }
        recording = false
        poller.stop()
        motionSamples += motion.samples.drain()
        motion.stop()
        Sidecar.finish(csv, motion: motion, log: log, testID: "P6")
        csv = nil
        writeFrameCSV()
        analyse()
        camera.stop()
    }

    private func writeFrameCSV() {
        let url = log.newFileURL(prefix: "P6-frames", ext: "csv")
        guard let w = CSVWriter(url: url, header: "t,luma,width,height") else { return }
        for f in frames {
            w.write("\(fmt(f.t, 4)),\(fmt(f.luma, 1)),\(f.width),\(f.height)")
        }
        w.close()
        log.attach(url)
    }

    private func analyse() {
        log.result("P6", .value, "frames recorded: \(frames.count) over \(fmt(uptimeNow() - startT, 1)) s")
        let events = CloseMath.darkEvents(frames)
        var toDark: [Double] = []
        var lines: [String] = []
        for (k, e) in events.enumerated() {
            let gyroStart = CloseMath.motionStart(before: e.darkT, motion: motionSamples)
            let start = gyroStart ?? e.halfT
            let window = frames.filter { $0.t >= start - 0.2 && $0.t <= e.darkT + 0.5 }.map { $0.t }
            let gap = CloseMath.maxGap(window)
            let hingeClosed = hinge.samples.first { s in
                guard let a = s.angle else { return false }
                return a < 0.16 && s.t >= e.darkT - 1.5 && s.t <= e.darkT + 1.5
            }
            let hingeText = hingeClosed.map { "hinge < 9° at \(ms($0.t - e.darkT)) ms relative to dark" } ?? "no hinge reading"
            let capEvents = camera.events.filter { ev in
                ev.t >= e.darkT - 2 && ev.t <= e.darkT + 3
                    && (ev.text.contains("INTERRUPTED") || ev.text.contains("didStopRunning") || ev.text.contains("ERROR"))
            }
            let capText = capEvents.isEmpty ? "no capture interruptions" : capEvents.map { $0.text }.joined(separator: " / ")
            var line = "close \(k + 1): open luma \(fmt(e.baseline, 0)); "
            if let g = gyroStart {
                line += "motion start→half dark \(ms(e.halfT - g)) ms, →dark \(ms(e.darkT - g)) ms; "
                toDark.append(e.darkT - g)
            } else {
                line += "no gyro burst found, half dark→dark \(ms(e.darkT - e.halfT)) ms; "
            }
            line += "\(window.count) frames in the close, longest gap \(ms(gap)) ms; \(hingeText); \(capText)"
            lines.append(line)
            log.result("P6", .value, line)
        }
        let interruptions = camera.events.filter { $0.t >= startT && $0.text.contains("INTERRUPTED") }
        log.result("P6", .value, "capture interruptions during the test: \(interruptions.count)")
        if let m = CloseMath.median(toDark) {
            log.result("P6", .pass, "\(events.count) darkening events; median motion start→dark \(ms(m)) ms")
        } else if events.isEmpty {
            log.result("P6", .fail, "no darkening detected (luma never fell below 25% of the open brightness)")
        } else {
            log.result("P6", .value, "\(events.count) darkening events, but no gyro burst to time them from")
        }
        summary = lines.isEmpty ? "No darkening detected. See the log." : lines.joined(separator: "\n")
    }

    func leave() {
        stop()
        camera.stop()
    }
}

struct P6View: View {
    let log: ProbeLog
    @StateObject private var model: P6Model

    init(log: ProbeLog) {
        self.log = log
        _model = StateObject(wrappedValue: P6Model(log: log))
    }

    var body: some View {
        TestPage(id: "P6", title: "Darkness during a close", steps: [
            "Stand somewhere with normal room light. Hold the phone in Posture A, pointing at the room.",
            "Tap Start and wait until the camera numbers below are moving.",
            "Close the phone at normal speed 5 times. Never slam it. Each time: keep it shut for 2 seconds, open back to Posture A, wait 3 seconds.",
            "Open the phone and tap Stop and analyse.",
            "On an iPad: cover the front camera with your hand 5 times instead."
        ], log: log) {
            CameraPanel(camera: model.camera)
            ReadoutBox(text: "Darkening events so far: \(model.darkCount)")
            HStack {
                BigButton("Start", enabled: !model.recording) { model.start() }
                BigButton("Stop and analyse", enabled: model.recording) { model.stop() }
            }
            if !model.summary.isEmpty {
                ReadoutBox(text: model.summary)
            }
        }
        .background(HingeHost(probe: model.hinge))
        .onDisappear { model.leave() }
    }
}
