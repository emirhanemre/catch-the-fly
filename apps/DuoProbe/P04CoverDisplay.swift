import SwiftUI
import UIKit

@MainActor
final class P4Model: ObservableObject {
    let camera: CameraController
    private let log: ProbeLog

    init(log: ProbeLog) {
        self.log = log
        camera = CameraController(testID: "P4", log: log)
    }

    func start() {
        log.add("P4", "---- P4 cover display while open (old-SDK build: no CameraCaptureAccessory) ----")
        logScenes()
        Task { @MainActor in
            await InnerCamera.start(camera, testID: "P4", log: log)
        }
    }

    func stop() {
        camera.stop()
    }

    func logScenes() {
        for line in DisplayInfo.describeScenes() {
            log.add("P4", "scenes: " + line)
        }
    }

    func geometryChanged(_ text: String) {
        log.add("P4", "geometry: " + text)
    }
}

struct P4View: View {
    let log: ProbeLog
    @StateObject private var model: P4Model

    init(log: ProbeLog) {
        self.log = log
        _model = StateObject(wrappedValue: P4Model(log: log))
    }

    var body: some View {
        TestPage(id: "P4", title: "Outer screen while open", steps: [
            "Open the phone fully and look at the big inner screen. Tap Start camera.",
            "Answer the first question about the big inner screen.",
            "Now fold it to Posture A (half-open like an L) and turn it so the small outer screen faces you.",
            "Look at the small outer screen and answer the second question. You may need to open the phone again to tap the answer: that's fine.",
            "Tap Stop camera when you're done."
        ], log: log) {
            CameraPanel(camera: model.camera, onStart: { model.start() }, onStop: { model.stop() })
            AnswerButtons(testID: "P4", question: "With the phone fully open, how does this app look on the big inner screen?",
                          options: ["Fills the whole screen", "Black bars at the sides", "Black bars at the top and bottom",
                                    "A small window in the middle", "Not sure"], log: log)
            AnswerButtons(testID: "P4", question: "In Posture A, what does the small outer screen show?",
                          options: ["Nothing / black", "This app (DuoProbe)", "A camera picture",
                                    "The lock screen or home screen", "Something else"], log: log)
            BigButton("Log screen info now") { model.logScenes() }
        }
        .background(WindowWatcher { text in model.geometryChanged(text) })
        .onDisappear { model.stop() }
    }
}

// MARK: - P4b: the inner camera on the cover display via CameraCaptureAccessory (CI build only)

@MainActor
final class P4bModel: ObservableObject {
    let camera: CameraController
    @Published var accessoryEnabled = true
    @Published private(set) var accessoryAvailable: Bool?
    private let log: ProbeLog

    init(log: ProbeLog) {
        self.log = log
        camera = CameraController(testID: "P4b", log: log)
    }

    func appeared() {
        #if IOS_27_1_SDK
        log.add("P4b", "---- P4b cover display via CameraCaptureAccessory (SDK 27.1 build) ----")
        #else
        log.result("P4b", .notAvailable, "this is the Playgrounds build (iOS 26 SDK): CameraCaptureAccessory can't be compiled. Use the CI build for P4b")
        #endif
    }

    func start() {
        Task { @MainActor in
            await InnerCamera.start(camera, testID: "P4b", log: log)
        }
    }

    func stop() {
        camera.stop()
    }

    func availabilityChanged(_ available: Bool) {
        accessoryAvailable = available
        log.result("P4b", .value, "CameraCaptureAccessory availability changed: \(available ? "available" : "not available")")
    }

    func coverContentAppeared() {
        log.result("P4b", .value, "accessory content appeared (the system is showing our cover view)")
    }

    func coverContentDisappeared() {
        log.add("P4b", "accessory content disappeared")
    }

    func geometryChanged(_ text: String) {
        log.add("P4b", "geometry: " + text)
    }
}

struct P4bView: View {
    let log: ProbeLog
    @StateObject private var model: P4bModel

    init(log: ProbeLog) {
        self.log = log
        _model = StateObject(wrappedValue: P4bModel(log: log))
    }

    private var page: some View {
        TestPage(id: "P4b", title: "Camera picture on the outer screen", steps: [
            "Only in the CI build made with the iOS 27.1 SDK (it says \"SDK 27.1 native\" at the top of this screen). Otherwise go back and skip it.",
            "Open the phone fully, big inner screen facing you, and tap Start camera.",
            "Look at the small outer screen (turn the phone round). It should show a camera picture with \"DuoProbe P4b\" at the top.",
            "Fold slowly to Posture A (half-open like an L), outer screen facing you. Is the picture still there?",
            "Answer the questions, then tap Stop camera."
        ], log: log) {
            Text("Build: \(DeviceInfoProbe.buildKind)").font(.caption.bold())
            #if IOS_27_1_SDK
            CameraPanel(camera: model.camera, onStart: { model.start() }, onStop: { model.stop() })
            Toggle("Show the picture on the outer screen", isOn: $model.accessoryEnabled)
            Text("Accessory available: \(model.accessoryAvailable.map { $0 ? "yes" : "no" } ?? "not reported yet")")
                .font(.caption)
            AnswerButtons(testID: "P4b", question: "With the phone fully open, what does the small outer screen show?",
                          options: ["Camera picture with \"DuoProbe P4b\"", "Nothing / black", "Something else"], log: log)
            AnswerButtons(testID: "P4b", question: "In Posture A (half-open like an L), is the picture on the outer screen?",
                          options: ["Yes, and it moves smoothly", "Yes, but it's jerky or frozen", "No, it went away",
                                    "Something else"], log: log)
            AnswerButtons(testID: "P4b", question: "Opening wider and folding back, roughly when does it disappear?",
                          options: ["It never disappears while open", "Below about 90°", "Below about 45°",
                                    "Only when fully shut", "Not sure"], log: log)
            #else
            Text("This build can't run P4b. Go back and carry on with P5.")
                .font(.headline)
            #endif
        }
    }

    var body: some View {
        #if IOS_27_1_SDK
        page
            .modifier(CoverAccessoryModifier(model: model))
            .background(WindowWatcher { text in model.geometryChanged(text) })
            .onAppear { model.appeared() }
            .onDisappear { model.stop() }
        #else
        page
            .onAppear { model.appeared() }
        #endif
    }
}

/// What the cover display shows in P4b: the live camera picture and a label.
struct CoverView: View {
    @ObservedObject var model: P4bModel
    @ObservedObject var camera: CameraController

    var body: some View {
        VStack(spacing: 4) {
            Text("DuoProbe P4b")
                .font(.headline)
            CameraPreview(session: camera.session)
            Text("\(camera.frameCount) frames, \(fmt(camera.fps, 0)) fps")
                .font(.caption)
        }
        .background(Color.black)
        .foregroundStyle(Color.white)
        .onAppear { model.coverContentAppeared() }
        .onDisappear { model.coverContentDisappeared() }
    }
}

#if IOS_27_1_SDK
/// API_NOTES section 3: `.sceneAccessory { CameraCaptureAccessory(isEnabled:) { … }.onAvailabilityChange { … } }`.
struct CoverAccessoryModifier: ViewModifier {
    @ObservedObject var model: P4bModel

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content
                .sceneAccessory {
                    CameraCaptureAccessory(isEnabled: $model.accessoryEnabled) {
                        CoverView(model: model, camera: model.camera)
                    }
                    .onAvailabilityChange { available in
                        model.availabilityChanged(available)
                    }
                }
        } else {
            content
        }
    }
}
#endif
