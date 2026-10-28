import Foundation
import AVFoundation
import SwiftUI
import UIKit

/// Main-actor face of a CameraCapture: starts and stops it, drains its frames and events
/// into the log, and publishes a live readout.
@MainActor
final class CameraController: ObservableObject {
    @Published private(set) var session: AVCaptureSession?
    @Published private(set) var fps: Double = 0
    @Published private(set) var luma: Double = -1
    @Published private(set) var frameCount = 0
    @Published private(set) var frameSize = CGSize(width: 4, height: 3)
    @Published private(set) var isRunning = false
    @Published private(set) var label = "-"

    /// Latest frame, readable from any thread (CSV sidecars use it).
    let latestFrame = LockedBox<FrameSample?>(nil)
    /// Called on the main actor with every batch of new frames.
    var onFrames: (([FrameSample]) -> Void)?
    /// Called on the main actor when a clip has finished writing.
    var onClipFinished: ((ClipResult) -> Void)?
    /// Every event this camera reported, for the tests' analysis.
    private(set) var events: [ProbeEvent] = []

    private var capture: CameraCapture?
    private let poller = Poller()
    private var recentTimes: [TimeInterval] = []
    private let testID: String
    private let log: ProbeLog

    init(testID: String, log: ProbeLog) {
        self.testID = testID
        self.log = log
    }

    var readout: String {
        guard isRunning else { return "Camera: stopped" }
        return "Camera: \(label)\nframes \(frameCount), \(fmt(fps, 0)) fps, luma \(fmt(luma, 0)), \(Int(frameSize.width))x\(Int(frameSize.height))"
    }

    @discardableResult
    func start(deviceID: String, label: String, wantMovie: Bool = false) async -> Bool {
        stop()
        guard await CameraPermission.ensure(log: log, testID: testID) else { return false }
        let c = CameraCapture(deviceID: deviceID, label: label, wantMovie: wantMovie, latest: latestFrame)
        capture = c
        session = c.session
        self.label = label
        frameCount = 0
        fps = 0
        recentTimes = []
        events = []
        isRunning = true
        log.add(testID, "camera start: \(label) [\(deviceID)]\(wantMovie ? " with movie output" : "")")
        c.start()
        poller.start { [weak self] in
            self?.drainCurrent()
        }
        return true
    }

    func stop() {
        poller.stop()
        guard let c = capture else { return }
        drain(c)
        c.stop()
        log.add(testID, "camera stop requested after \(frameCount) frames")
        capture = nil
        session = nil
        isRunning = false
        fps = 0
        // Collect the last events (didStopRunning, clip finished) a moment later.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            self?.drain(c)
        }
    }

    func startRecording(to url: URL) {
        capture?.startRecording(to: url)
    }

    func stopRecording() {
        capture?.stopRecording()
    }

    func logActiveConstituent() {
        capture?.logActiveConstituent()
    }

    private func drainCurrent() {
        if let c = capture {
            drain(c)
        }
    }

    private func drain(_ c: CameraCapture) {
        for e in c.events.drain() {
            events.append(e)
            log.add(testID, e.text, at: e.t)
        }
        let frames = c.tap.frames.drain()
        if !frames.isEmpty, c === capture {
            frameCount += frames.count
            if let last = frames.last {
                luma = last.luma
                if last.width > 0 && last.height > 0 {
                    frameSize = CGSize(width: last.width, height: last.height)
                }
            }
            recentTimes.append(contentsOf: frames.map { $0.t })
            let cutoff = (recentTimes.last ?? 0) - 1.0
            recentTimes.removeAll { $0 <= cutoff }
            fps = Double(recentTimes.count)
            onFrames?(frames)
        } else if c === capture, let last = recentTimes.last, uptimeNow() - last > 1.0 {
            fps = 0
        }
        for clip in c.finishedClips.drain() {
            onClipFinished?(clip)
        }
    }
}

@MainActor
enum CameraPermission {
    static func ensure(log: ProbeLog, testID: String) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            log.add(testID, "camera permission asked: \(granted ? "allowed" : "refused")")
            return granted
        case .denied, .restricted:
            log.result(testID, .fail, "camera access is off. Turn it on in Settings > DuoProbe > Camera")
            return false
        @unknown default:
            log.result(testID, .fail, "unknown camera permission state")
            return false
        }
    }
}

/// Shows a capture session. The preview is deliberately left in the sensor's own
/// orientation and unmirrored, so "top/bottom/left/right of the picture" means the same
/// edges as in the frames the game will process.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession?

    func makeUIView(context: Context) -> PreviewUIView {
        let v = PreviewUIView()
        v.backgroundColor = .black
        v.previewLayer?.videoGravity = .resizeAspect
        v.previewLayer?.session = session
        return v
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        if uiView.previewLayer?.session !== session {
            uiView.previewLayer?.session = session
        }
        uiView.setNeedsLayout()
    }
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer? {
        layer as? AVCaptureVideoPreviewLayer
    }

    private weak var configuredConnection: AVCaptureConnection?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let conn = previewLayer?.connection, conn !== configuredConnection else { return }
        configuredConnection = conn
        if conn.isVideoMirroringSupported {
            conn.automaticallyAdjustsVideoMirroring = false   // must come before isVideoMirrored
            conn.isVideoMirrored = false
        }
        if #available(iOS 17.0, *) {
            if conn.isVideoRotationAngleSupported(0) {
                conn.videoRotationAngle = 0
            }
        }
    }
}

/// Preview with TOP / BOTTOM / LEFT / RIGHT labels on the picture's edges.
struct LabelledPreview: View {
    let session: AVCaptureSession?
    let frameSize: CGSize

    var body: some View {
        ZStack {
            CameraPreview(session: session)
            VStack {
                EdgeTag(text: "TOP")
                Spacer()
                EdgeTag(text: "BOTTOM")
            }
            HStack {
                EdgeTag(text: "LEFT")
                Spacer()
                EdgeTag(text: "RIGHT")
            }
        }
        .aspectRatio(frameSize, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: 340)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct EdgeTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .padding(4)
            .background(Color.yellow)
            .foregroundStyle(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(4)
    }
}

/// Live preview plus readout, observing the camera so it refreshes with every batch.
struct CameraPanel: View {
    @ObservedObject var camera: CameraController
    var startTitle = "Start camera"
    var onStart: (() -> Void)? = nil
    var onStop: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let start = onStart, let stop = onStop {
                HStack {
                    BigButton(startTitle, enabled: !camera.isRunning, action: start)
                    BigButton("Stop camera", enabled: camera.isRunning, action: stop)
                }
            }
            if camera.isRunning {
                LabelledPreview(session: camera.session, frameSize: camera.frameSize)
            }
            ReadoutBox(text: camera.readout)
        }
    }
}

/// Picks the inner camera (or the fallback), logs the choice and starts it.
@MainActor
enum InnerCamera {
    @discardableResult
    static func start(_ camera: CameraController, testID: String, log: ProbeLog,
                      wantMovie: Bool = false) async -> CameraChoice? {
        guard let choice = CameraFinder.pickInner(testerPick: log.testerPickedCameraID) else {
            log.result(testID, .notAvailable, "no camera found at all")
            return nil
        }
        log.add(testID, "camera choice: \(choice.label) [\(choice.id)]: \(choice.note)")
        if !choice.isDuoInner {
            log.result(testID, .notAvailable, "Duo inner camera not found here; using \(choice.label) instead (\(choice.note))")
        }
        guard await camera.start(deviceID: choice.id, label: choice.label, wantMovie: wantMovie) else { return nil }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        camera.logActiveConstituent()
        return choice
    }
}
