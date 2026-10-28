import SwiftUI

struct ClipSpec: Identifiable {
    let id: String
    let title: String
    let how: String
}

@MainActor
final class P9Model: ObservableObject {
    static let clips: [ClipSpec] = [
        ClipSpec(id: "walk", title: "Clip 1: walk up to the wall",
                 how: "Start about 2 m from a textured wall in Posture A. Walk slowly towards it until you're about 30 cm away, then stop."),
        ClipSpec(id: "slowclose", title: "Clip 2: slow close",
                 how: "Stand still in Posture A facing the wall, about 1 m away. Close the phone slowly (about 3 seconds), keep it shut for 2 seconds, open it again."),
        ClipSpec(id: "normalclose", title: "Clip 3: normal close",
                 how: "Same as clip 2, but close at normal speed, like shutting a book. Never slam it.")
    ]

    let camera: CameraController
    let hinge: HingeProbe
    let motion = MotionRecorder()
    @Published private(set) var recordingID: String?
    @Published private(set) var saved: Set<String> = []
    private var csv: CSVWriter?
    private var pendingClip: [URL: String] = [:]
    private let log: ProbeLog

    init(log: ProbeLog) {
        self.log = log
        camera = CameraController(testID: "P9", log: log)
        hinge = HingeProbe(testID: "P9", log: log)
        camera.onClipFinished = { [weak self] clip in
            self?.clipFinished(clip)
        }
    }

    func startCamera() {
        log.add("P9", "---- P9 clips ----")
        Task { @MainActor in
            await InnerCamera.start(camera, testID: "P9", log: log, wantMovie: true)
        }
    }

    func record(_ spec: ClipSpec) {
        guard recordingID == nil, camera.isRunning else { return }
        let url = log.newFileURL(prefix: "P9-\(spec.id)", ext: "mov")
        pendingClip[url] = spec.id
        motion.start()
        csv = Sidecar.start(log: log, testID: "P9", prefix: "P9-\(spec.id)-sensors", motion: motion,
                            frameBox: camera.latestFrame, hingeBox: hinge.latestBox)
        camera.startRecording(to: url)
        recordingID = spec.id
        log.add("P9", "tester started \(spec.title)")
    }

    func stopRecording() {
        guard let id = recordingID else { return }
        camera.stopRecording()
        Sidecar.finish(csv, motion: motion, log: log, testID: "P9")
        csv = nil
        motion.stop()
        recordingID = nil
        log.add("P9", "tester stopped clip \(id)")
    }

    private func clipFinished(_ clip: ClipResult) {
        let id = pendingClip[clip.url] ?? "unknown"
        guard clip.ok else {
            log.result("P9", .fail, "clip \(id) wasn't saved: \(clip.message)")
            return
        }
        let size = try? clip.url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        log.attach(clip.url)
        saved.insert(id)
        log.result("P9", .value, "clip \(id) saved: \(clip.url.lastPathComponent), \(size.map { "\($0 / 1024) KB" } ?? "size unknown")")
        if saved.count == P9Model.clips.count {
            log.result("P9", .pass, "all \(saved.count) clips saved")
        }
    }

    func leave() {
        stopRecording()
        // Give the movie file a moment to finish before the session stops.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            self?.camera.stop()
        }
    }
}

struct P9View: View {
    let log: ProbeLog
    @StateObject private var model: P9Model

    init(log: ProbeLog) {
        self.log = log
        _model = StateObject(wrappedValue: P9Model(log: log))
    }

    var body: some View {
        TestPage(id: "P9", title: "Clips", steps: [
            "Tap Start camera and wait for the picture.",
            "Record the three clips below, one at a time. Tap Record, do what it says, then tap Stop.",
            "Each clip should be about 5 to 15 seconds long. Watch where you're walking.",
            "The clips go into the shared log at the end."
        ], log: log) {
            CameraPanel(camera: model.camera, onStart: { model.startCamera() }, onStop: { model.leave() })
            ForEach(P9Model.clips) { spec in
                ClipRow(model: model, camera: model.camera, spec: spec)
            }
        }
        .background(HingeHost(probe: model.hinge))
        .onDisappear { model.leave() }
    }
}

struct ClipRow: View {
    @ObservedObject var model: P9Model
    @ObservedObject var camera: CameraController
    let spec: ClipSpec

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(spec.title).font(.headline)
                if model.saved.contains(spec.id) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green)
                }
            }
            Text(spec.how).font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if model.recordingID == spec.id {
                BigButton("Stop") { model.stopRecording() }
            } else {
                BigButton("Record", enabled: model.recordingID == nil && camera.isRunning) { model.record(spec) }
            }
        }
        .padding(8)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
