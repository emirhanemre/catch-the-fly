#if IOS_27_1_SDK
import Foundation
import AVFoundation
import CoreMedia

// Phase 5, CI build only. The Duo's inner camera through its native iOS 27.1 device type,
// and the posture-switching frame source that Platform.swift picks on a device with a hinge.

/// The Duo inner (under-display) ultra wide camera, found by `.builtInInnerUltraWideCamera`
/// (API_NOTES section 2). Falls back to the virtual front camera if discovery finds nothing.
final class NativeInnerCameraFrameSource: CaptureFrameSource, @unchecked Sendable {
    override var displayName: String { return "Inner ultra wide camera (native .builtInInnerUltraWideCamera)" }

    /// In Posture A the inner camera looks into the room, away from the player. +z follows
    /// InnerCameraFrameSource's assumption; the tester can flip it (which half holds the
    /// motion sensors is spike P11).
    override var forwardInDevice: Vec3 {
        return DuoAxisSetting.shared.flipped ? Vec3(0, 0, -1) : Vec3(0, 0, 1)
    }

    /// It looks into the room, so the picture must not be mirrored.
    override var forcesUnmirrored: Bool { return true }

    override func chooseDevice(note: (String) -> Void) -> AVCaptureDevice? {
        if #available(iOS 27.1, *) {
            let found = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInInnerUltraWideCamera],
                                                         mediaType: .video, position: .unspecified).devices
            if let d = found.first {
                note("CAM native inner camera '\(d.localizedName)' type=\(d.deviceType.rawValue) position=\(d.position.rawValue)")
                return d
            }
            note("CAM .builtInInnerUltraWideCamera found nothing, falling back to the virtual front camera")
        }
        let fronts = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera],
                                                      mediaType: .video, position: .front).devices
        if let f = fronts.first {
            return f
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    override func didStartRunning(device: AVCaptureDevice, note: (String) -> Void) {
        let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        note("CAM inner camera running, active format \(dims.width)x\(dims.height)")
    }
}

/// The Duo's camera: the inner camera in Posture A, the rear wide camera in Posture B. It
/// wraps one source per camera and forwards to the active one, so the posture can change at
/// run time behind the single FrameSource that GameController holds.
///
/// Preview layers: the main one (GameController's PreviewView) and, while the cover accessory
/// shows, the cover one. Whichever is "attached" drives preview and frame rotation; the cover
/// wins while it exists, because in Posture A that's the screen the player looks at.
final class DuoFrameSource: FrameSource, @unchecked Sendable {
    private let inner = NativeInnerCameraFrameSource()
    private let rear = RearCameraFrameSource()

    // Guarded by `lock` (any thread).
    private let lock = NSLock()
    private var posture: DuoPosture
    private var consumer: (any FrameConsumer)?
    private var running = false
    private var pendingNotes: [String] = []

    // Main actor only.
    private weak var mainLayer: AVCaptureVideoPreviewLayer?
    private weak var coverLayer: AVCaptureVideoPreviewLayer?
    private var coverAttached = false

    init(posture: DuoPosture) {
        self.posture = posture
    }

    var displayName: String {
        return "Duo native: inner ultra wide camera (Posture A) / rear wide camera (Posture B)"
    }

    var captureSession: AVCaptureSession {
        return active().captureSession
    }

    func start(consumer: any FrameConsumer) {
        lock.lock()
        self.consumer = consumer
        running = true
        let source = sourceLocked(posture)
        let notes = pendingNotes
        pendingNotes.removeAll()
        lock.unlock()
        for n in notes {
            consumer.note(n)
        }
        source.start(consumer: consumer)
    }

    func stop() {
        lock.lock()
        running = false
        let source = sourceLocked(posture)
        lock.unlock()
        source.stop()
    }

    /// A line for the session log. Kept until the pipeline is connected. Any thread.
    func note(_ message: String) {
        lock.lock()
        guard let c = consumer else {
            if pendingNotes.count < 50 {
                pendingNotes.append(message)
            }
            lock.unlock()
            return
        }
        lock.unlock()
        c.note(message)
    }

    @MainActor
    func attachPreview(_ layer: AVCaptureVideoPreviewLayer) {
        mainLayer = layer
        let source = active()
        if coverLayer == nil {
            source.attachPreview(layer)
        } else {
            layer.videoGravity = .resizeAspectFill
            layer.session = source.captureSession
        }
    }

    @MainActor
    func refreshOrientation() {
        active().refreshOrientation()
    }

    /// The cover preview layer while the accessory shows, nil when it goes.
    @MainActor
    func setCoverLayer(_ layer: AVCaptureVideoPreviewLayer?) {
        if layer == nil && !coverAttached { return }
        if let l = layer, coverAttached, l === coverLayer { return }
        let source = active()
        coverLayer = layer
        coverAttached = (layer != nil)
        if let l = layer {
            source.attachPreview(l)
            note("CAM rotation now follows the cover display")
        } else if let m = mainLayer {
            source.attachPreview(m)
            note("CAM rotation now follows the main window")
        }
    }

    /// Switches camera. Stops the old session, then starts the new one if the game is running.
    @MainActor
    func select(_ newPosture: DuoPosture) {
        lock.lock()
        guard newPosture != posture else {
            lock.unlock()
            return
        }
        let old = sourceLocked(posture)
        posture = newPosture
        let new = sourceLocked(newPosture)
        let c = consumer
        let wasRunning = running
        lock.unlock()

        old.stop()
        if let cover = coverLayer, newPosture == .a {
            new.attachPreview(cover)
            mainLayer?.session = new.captureSession
        } else if let main = mainLayer {
            new.attachPreview(main)
            coverLayer?.session = new.captureSession
        }
        if wasRunning, let c = c {
            new.start(consumer: c)
        }
        note("CAM switched to \(new.displayName)")
    }

    private func active() -> CaptureFrameSource {
        lock.lock()
        defer { lock.unlock() }
        return sourceLocked(posture)
    }

    /// Call with `lock` held.
    private func sourceLocked(_ p: DuoPosture) -> CaptureFrameSource {
        switch p {
        case .a: return inner
        case .b: return rear
        }
    }
}
#endif
