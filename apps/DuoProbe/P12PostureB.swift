import SwiftUI

@MainActor
final class P12Model: ObservableObject {
    let ar: ARController
    @Published private(set) var status = "Not started"
    @Published private(set) var running = false
    private var task: Task<Void, Never>?
    private let log: ProbeLog

    init(log: ProbeLog) {
        self.log = log
        ar = ARController(testID: "P12", log: log)
    }

    func run() {
        guard !running else { return }
        log.add("P12", "---- P12 Posture B: rear world tracking, inner display facing the tester ----")
        for line in DisplayInfo.describeScenes() {
            log.add("P12", "scenes: " + line)
        }
        guard ar.start() else {
            status = "AR world tracking isn't supported here."
            return
        }
        running = true
        status = "Running for 10 seconds…"
        task = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard let self, !Task.isCancelled else { return }
            let frames = self.ar.frames
            let state = self.ar.state
            let normal = self.ar.events.contains { $0.text.hasSuffix("-> normal") }
            self.ar.stop()
            self.running = false
            self.log.result("P12", normal ? .pass : .fail,
                            "Posture B world tracking: \(frames) frames in 10 s, reached normal tracking: \(normal), last state \(state)")
            self.status = "Done: \(frames) frames, tracking \(normal ? "reached normal" : "never reached normal")."
        }
    }

    func geometryChanged(_ text: String) {
        log.add("P12", "geometry: " + text)
    }

    func leave() {
        task?.cancel()
        ar.stop()
        running = false
    }
}

struct P12View: View {
    let log: ProbeLog
    @StateObject private var model: P12Model

    init(log: ProbeLog) {
        self.log = log
        _model = StateObject(wrappedValue: P12Model(log: log))
    }

    var body: some View {
        TestPage(id: "P12", title: "Posture B", steps: [
            "Open the phone wide, a bit more than halfway flat (about 130°), with the big inner screen facing you, like reading a book.",
            "Point the back of the phone at the room. Tap Start.",
            "For 10 seconds, slowly turn left and right a little.",
            "When it says Done, answer the question about the big inner screen."
        ], log: log) {
            ReadoutBox(text: model.status)
            ARReadout(ar: model.ar)
            BigButton("Start", enabled: !model.running) { model.run() }
            AnswerButtons(testID: "P12", question: "How does this app look on the big inner screen?",
                          options: ["Fills the whole screen", "Black bars at the sides", "Black bars at the top and bottom",
                                    "A small window in the middle", "Not sure"], log: log)
        }
        .background(WindowWatcher { text in model.geometryChanged(text) })
        .onDisappear { model.leave() }
    }
}
