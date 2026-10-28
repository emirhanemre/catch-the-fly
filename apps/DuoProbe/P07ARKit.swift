import SwiftUI

@MainActor
final class P7Model: ObservableObject {
    let ar: ARController
    let camera: CameraController
    @Published private(set) var phase = "Not started"
    @Published private(set) var running = false
    private var task: Task<Void, Never>?
    private let log: ProbeLog

    init(log: ProbeLog) {
        self.log = log
        ar = ARController(testID: "P7", log: log)
        camera = CameraController(testID: "P7", log: log)
    }

    func run() {
        guard !running else { return }
        running = true
        task = Task { @MainActor [weak self] in
            await self?.sequence()
        }
    }

    private func sequence() async {
        log.add("P7", "---- P7 ARKit world tracking + inner camera ----")
        guard ar.start() else {
            phase = "AR world tracking isn't supported here."
            running = false
            return
        }
        phase = "Phase 1 of 2: AR on its own (10 s)"
        let t0 = uptimeNow()
        try? await Task.sleep(nanoseconds: 10_000_000_000)
        if Task.isCancelled { return }
        let arFrames1 = ar.frames
        let t1 = uptimeNow()
        log.result("P7", .value, "AR alone: \(arFrames1) frames in \(fmt(t1 - t0, 1)) s (\(fmt(Double(arFrames1) / max(t1 - t0, 0.001), 1)) fps), tracking \(ar.state)")

        phase = "Phase 2 of 2: AR + inner camera together (10 s)"
        await InnerCamera.start(camera, testID: "P7", log: log)
        if Task.isCancelled {
            camera.stop()
            return
        }
        let camStartFrames = camera.frameCount
        let arStartFrames = ar.frames
        let t2 = uptimeNow()
        try? await Task.sleep(nanoseconds: 10_000_000_000)
        if Task.isCancelled { return }
        let t3 = uptimeNow()
        let arFrames2 = ar.frames - arStartFrames
        let camFrames = camera.frameCount - camStartFrames
        let arFps = Double(arFrames2) / max(t3 - t2, 0.001)
        let camFps = Double(camFrames) / max(t3 - t2, 0.001)
        log.result("P7", .value, "together: AR \(arFrames2) frames (\(fmt(arFps, 1)) fps), tracking \(ar.state); inner camera \(camFrames) frames (\(fmt(camFps, 1)) fps)")
        let arTrouble = ar.events.filter { $0.t >= t2 && ($0.text.contains("INTERRUPTED") || $0.text.contains("FAILED")) }
        let camTrouble = camera.events.filter { $0.text.contains("INTERRUPTED") || $0.text.contains("FAIL") || $0.text.contains("ERROR") }
        log.result("P7", .value, "AR problems after the camera started: \(arTrouble.isEmpty ? "none" : arTrouble.map { $0.text }.joined(separator: " / "))")
        log.result("P7", .value, "camera problems: \(camTrouble.isEmpty ? "none" : camTrouble.map { $0.text }.joined(separator: " / "))")
        if arFps > 5 && camFps > 5 {
            log.result("P7", .pass, "AR world tracking and the inner camera ran together (route A2 looks possible)")
        } else {
            log.result("P7", .fail, "they didn't run together (AR \(fmt(arFps, 1)) fps, camera \(fmt(camFps, 1)) fps): route A2 is out")
        }
        finish()
        phase = "Done. Results are in the log."
    }

    private func finish() {
        camera.stop()
        ar.stop()
        running = false
    }

    func leave() {
        task?.cancel()
        task = nil
        if running {
            log.add("P7", "test left before it finished")
        }
        finish()
    }
}

struct P7View: View {
    let log: ProbeLog
    @StateObject private var model: P7Model

    init(log: ProbeLog) {
        self.log = log
        _model = StateObject(wrappedValue: P7Model(log: log))
    }

    var body: some View {
        TestPage(id: "P7", title: "AR tracking with the inner camera", steps: [
            "Hold the phone in Posture A, pointing at a textured wall about 2 m away.",
            "Tap Start. The test runs by itself for 20 seconds.",
            "During those 20 seconds, walk slowly towards the wall and back, twice. Watch where you're going.",
            "Wait until it says Done."
        ], log: log) {
            ReadoutBox(text: model.phase)
            ARReadout(ar: model.ar)
            CameraPanel(camera: model.camera)
            BigButton("Start", enabled: !model.running) { model.run() }
        }
        .onDisappear { model.leave() }
    }
}

struct ARReadout: View {
    @ObservedObject var ar: ARController

    var body: some View {
        ReadoutBox(text: ar.readout)
    }
}
