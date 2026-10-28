import SwiftUI

@MainActor
final class P3Model: ObservableObject {
    let camera: CameraController
    @Published private(set) var choiceNote = ""
    private let log: ProbeLog

    init(log: ProbeLog) {
        self.log = log
        camera = CameraController(testID: "P3", log: log)
    }

    func start() {
        log.add("P3", "---- P3 inner camera preview ----")
        Task { @MainActor in
            if let choice = await InnerCamera.start(camera, testID: "P3", log: log) {
                choiceNote = "\(choice.label): \(choice.note)"
            } else {
                choiceNote = "No camera could be started (see the log)."
            }
        }
    }

    func stop() {
        if camera.isRunning {
            log.result("P3", .value, "inner camera ran: \(camera.frameCount) frames, last \(fmt(camera.fps, 0)) fps, \(Int(camera.frameSize.width))x\(Int(camera.frameSize.height))")
        }
        camera.stop()
    }
}

struct P3View: View {
    let log: ProbeLog
    @StateObject private var model: P3Model

    init(log: ProbeLog) {
        self.log = log
        _model = StateObject(wrappedValue: P3Model(log: log))
    }

    var body: some View {
        TestPage(id: "P3", title: "Inner camera", steps: [
            "Hold the phone in Posture A, small outer screen facing you, and point it at a textured wall or a bookshelf about 1 to 2 m away.",
            "Tap Start camera. The picture may be sideways or mirrored: that's on purpose.",
            "Answer the three questions below while you look at the picture.",
            "Tap Stop camera when you're done."
        ], log: log) {
            CameraPanel(camera: model.camera, onStart: { model.start() }, onStop: { model.stop() })
            if !model.choiceNote.isEmpty {
                Text(model.choiceNote).font(.caption)
            }
            AnswerButtons(testID: "P3", question: "How sharp is the picture?",
                          options: ["Sharp", "OK", "Blurry"], log: log)
            AnswerButtons(testID: "P3",
                          question: "Which edge of the picture is nearest the hinge (the fold of the phone)? Use the yellow labels.",
                          options: ["TOP", "BOTTOM", "LEFT", "RIGHT", "Can't tell"], log: log)
            AnswerButtons(testID: "P3",
                          question: "How much of the picture is blocked by the other half of the phone?",
                          options: ["None", "A thin strip", "A lot"], log: log)
        }
        .onDisappear { model.stop() }
    }
}
