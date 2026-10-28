import SwiftUI
import AVFoundation

@MainActor
final class P2Model: ObservableObject {
    static let roomAnswer = "Shows the room in front of me"

    @Published private(set) var cameras: [CameraInfo] = []
    @Published private(set) var selected: CameraInfo?
    let camera: CameraController
    private let log: ProbeLog
    private var previewTask: Task<Void, Never>?

    init(log: ProbeLog) {
        self.log = log
        camera = CameraController(testID: "P2", log: log)
    }

    func scan() {
        let found = CameraFinder.discover()
        log.add("P2", "---- P2 camera inventory ----")
        for line in found.report {
            log.add("P2", line)
        }
        cameras = found.devices.map { CameraFinder.info($0) }
        for c in cameras {
            log.result("P2", .value, "camera: \(c.summary)")
        }
        if cameras.isEmpty {
            log.result("P2", .fail, "no cameras found")
        }
    }

    func preview(_ info: CameraInfo) {
        selected = info
        previewTask?.cancel()
        camera.stop()
        log.add("P2", "tester opened preview of \(info.name) [\(info.typeRaw)]")
        previewTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.camera.start(deviceID: info.id, label: info.name)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self.camera.logActiveConstituent()
        }
    }

    func mark(_ answer: String, for info: CameraInfo) {
        guard answer == P2Model.roomAnswer else { return }
        log.testerPickedCameraID = info.id
        log.testerPickedCameraName = info.name
        log.result("P2", .value, "tester says the camera that shows the room in Posture A is \(info.name), type \(info.typeRaw), id \(info.id)")
    }

    func stopAll() {
        previewTask?.cancel()
        camera.stop()
    }
}

struct P2View: View {
    let log: ProbeLog
    @StateObject private var model: P2Model

    init(log: ProbeLog) {
        self.log = log
        _model = StateObject(wrappedValue: P2Model(log: log))
    }

    var body: some View {
        TestPage(id: "P2", title: "Cameras", steps: [
            "Hold the phone in Posture A: half-open like an L, the small outer screen facing you.",
            "Tap Find cameras.",
            "Tap each camera in the list, one at a time. Its picture appears below. It may look sideways: that's fine.",
            "For each one, tap the answer that fits. The important one: which camera shows the room in front of you?"
        ], log: log) {
            BigButton(model.cameras.isEmpty ? "Find cameras" : "Find cameras again") {
                model.scan()
            }
            ForEach(model.cameras) { info in
                Button {
                    model.preview(info)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.name).font(.headline)
                        Text("\(info.position) · \(info.typeRaw)\(info.isVirtual ? " · virtual" : "")")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .tint(model.selected?.id == info.id ? Color.green : Color.blue)
            }
            if let info = model.selected {
                Text("Showing: \(info.name)").font(.headline)
                CameraPanel(camera: model.camera)
                AnswerButtons(testID: "P2",
                              question: "In Posture A, what does \(info.name) show?",
                              options: [P2Model.roomAnswer, "Shows me (my face)", "Black / nothing", "Something else"],
                              log: log,
                              onAnswer: { answer in model.mark(answer, for: info) })
                    .id(info.id)
            }
        }
        .onDisappear {
            model.stopAll()
        }
    }
}
