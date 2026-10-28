import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import QuartzCore

/// Shared AVCaptureSession plumbing. Subclasses only choose the camera and describe which way
/// it faces. Everything AVFoundation happens on `sessionQueue` (configuration) and
/// `captureQueue` (frames); `attachPreview` / `refreshOrientation` run on the main actor.
class CaptureFrameSource: NSObject, FrameSource, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let captureSession = AVCaptureSession()

    private let output = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "catchthefly.session")
    private let captureQueue = DispatchQueue(label: "catchthefly.capture", qos: .userInteractive)

    // Shared between queues: guarded by `lock`.
    private let lock = NSLock()
    private var consumer: (any FrameConsumer)?
    private var device: AVCaptureDevice?
    private var fieldOfViewDegrees: Double = 60
    private var rotationDegrees: Double = 90

    // Session queue only.
    private var configured = false
    private var observers: [any NSObjectProtocol] = []

    // Main actor only.
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    private var appliedPreviewAngle: Double = -1

    // MARK: Subclass hooks

    var displayName: String { return "camera" }

    /// Picks the device (session queue). `note` writes to the session log.
    func chooseDevice(note: (String) -> Void) -> AVCaptureDevice? {
        return nil
    }

    /// Viewing direction in the device frame: rear cameras look along -z.
    var forwardInDevice: Vec3 { return Vec3(0, 0, -1) }

    /// Whether to force mirroring off (a front camera that looks into the room, not at the player).
    var forcesUnmirrored: Bool { return false }

    /// Picture "up" in the device frame for a preview rotation angle (degrees, multiples of 90).
    /// Rear camera: 90 = portrait (up = +y), 0 = landscape with the top edge on the left (+x),
    /// 180 = landscape with the top edge on the right (-x), 270 = upside down (-y).
    func upInDevice(rotationDegrees: Double) -> Vec3 {
        let quarter = ((Int((rotationDegrees / 90).rounded()) % 4) + 4) % 4
        switch quarter {
        case 0: return Vec3(1, 0, 0)
        case 1: return Vec3(0, 1, 0)
        case 2: return Vec3(-1, 0, 0)
        default: return Vec3(0, -1, 0)
        }
    }

    /// Called on the session queue after `startRunning()`.
    func didStartRunning(device: AVCaptureDevice, note: (String) -> Void) {}

    // MARK: FrameSource

    func start(consumer: any FrameConsumer) {
        lock.lock()
        self.consumer = consumer
        lock.unlock()

        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            sessionQueue.async { self.configureAndRun() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.sessionQueue.async { self.configureAndRun() }
                } else {
                    consumer.note("CAM permission refused by the player")
                }
            }
        case .denied:
            consumer.note("CAM permission denied: Settings > Privacy & Security > Camera")
        case .restricted:
            consumer.note("CAM permission restricted on this device")
        @unknown default:
            consumer.note("CAM unknown authorisation status \(status.rawValue)")
        }
    }

    func stop() {
        sessionQueue.async {
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
                self.currentConsumer()?.note("CAM stopped")
            }
        }
    }

    @MainActor
    func attachPreview(_ layer: AVCaptureVideoPreviewLayer) {
        previewLayer = layer
        layer.videoGravity = .resizeAspectFill
        layer.session = captureSession
        appliedPreviewAngle = -1
        rotationCoordinator = nil
        refreshOrientation()
    }

    @MainActor
    func refreshOrientation() {
        guard let layer = previewLayer else { return }
        if rotationCoordinator == nil, let dev = currentDevice() {
            rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: dev, previewLayer: layer)
        }
        if forcesUnmirrored, let conn = layer.connection, conn.isVideoMirroringSupported,
           conn.automaticallyAdjustsVideoMirroring || conn.isVideoMirrored {
            // Order matters: switching off the automatic adjustment first, or it raises.
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = false
        }
        guard let coordinator = rotationCoordinator else { return }
        let angle = Double(coordinator.videoRotationAngleForHorizonLevelPreview)
        guard angle.isFinite else { return }
        if let conn = layer.connection, conn.isVideoRotationAngleSupported(CGFloat(angle)),
           conn.videoRotationAngle != CGFloat(angle) {
            conn.videoRotationAngle = CGFloat(angle)
        }
        if angle != appliedPreviewAngle {
            appliedPreviewAngle = angle
            // Frames are rotated to the same angle as the preview, so tracker coordinates and the
            // displayed picture agree.
            sessionQueue.async { self.applyFrameRotation(angle) }
        }
    }

    // MARK: Session queue

    private func configureAndRun() {
        let c = currentConsumer()
        if !configured {
            guard let dev = chooseDevice(note: { c?.note($0) }) else {
                c?.note("CAM no usable camera found")
                return
            }
            captureSession.beginConfiguration()
            if captureSession.canSetSessionPreset(.hd1280x720) {
                captureSession.sessionPreset = .hd1280x720
            } else if captureSession.canSetSessionPreset(.medium) {
                captureSession.sessionPreset = .medium
            }
            do {
                let input = try AVCaptureDeviceInput(device: dev)
                guard captureSession.canAddInput(input) else {
                    captureSession.commitConfiguration()
                    c?.note("CAM can't add input for \(dev.localizedName)")
                    return
                }
                captureSession.addInput(input)
            } catch {
                captureSession.commitConfiguration()
                c?.note("CAM input error: \(error.localizedDescription)")
                return
            }
            let fullRange = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            let videoRange = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            let formats = output.availableVideoPixelFormatTypes
            if formats.contains(fullRange) {
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: fullRange]
            } else if formats.contains(videoRange) {
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: videoRange]
            }
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: captureQueue)
            guard captureSession.canAddOutput(output) else {
                captureSession.commitConfiguration()
                c?.note("CAM can't add the video data output")
                return
            }
            captureSession.addOutput(output)
            if let conn = output.connection(with: .video) {
                if forcesUnmirrored, conn.isVideoMirroringSupported {
                    conn.automaticallyAdjustsVideoMirroring = false
                    conn.isVideoMirrored = false
                }
                if conn.isVideoRotationAngleSupported(90) {
                    conn.videoRotationAngle = 90
                }
            }
            captureSession.commitConfiguration()

            let fov = Double(dev.activeFormat.videoFieldOfView)
            lock.lock()
            device = dev
            fieldOfViewDegrees = (fov.isFinite && fov > 1) ? fov : 60
            rotationDegrees = 90
            lock.unlock()
            configured = true
            c?.note("CAM using '\(dev.localizedName)' type=\(dev.deviceType.rawValue) virtual=\(dev.isVirtualDevice) fov=\(FlyLog.fixed(fov, decimals: 1))deg preset=\(captureSession.sessionPreset.rawValue)")
            addObservers()
        }
        if !captureSession.isRunning {
            captureSession.startRunning()
            c?.note("CAM running=\(captureSession.isRunning)")
            if let dev = currentDevice() {
                didStartRunning(device: dev, note: { c?.note($0) })
            }
        }
    }

    private func applyFrameRotation(_ angle: Double) {
        if let conn = output.connection(with: .video), conn.isVideoRotationAngleSupported(CGFloat(angle)) {
            conn.videoRotationAngle = CGFloat(angle)
            lock.lock()
            rotationDegrees = angle
            lock.unlock()
            currentConsumer()?.note("CAM rotation \(FlyLog.fixed(angle, decimals: 0))deg")
        }
    }

    private func addObservers() {
        let centre = NotificationCenter.default
        let c = currentConsumer()
        observers.append(centre.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: captureSession, queue: nil) { note in
            var reason = "unknown"
            if let n = note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber {
                reason = CaptureFrameSource.describeInterruption(n.intValue)
            }
            c?.note("CAM interrupted: \(reason)")
        })
        observers.append(centre.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: captureSession, queue: nil) { _ in
            c?.note("CAM interruption ended")
        })
        observers.append(centre.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: captureSession, queue: nil) { note in
            let err = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
            c?.note("CAM runtime error: \(err?.localizedDescription ?? "unknown")")
        })
    }

    static func describeInterruption(_ raw: Int) -> String {
        guard let reason = AVCaptureSession.InterruptionReason(rawValue: raw) else { return "raw \(raw)" }
        switch reason {
        case .videoDeviceNotAvailableInBackground: return "videoDeviceNotAvailableInBackground"
        case .audioDeviceInUseByAnotherClient: return "audioDeviceInUseByAnotherClient"
        case .videoDeviceInUseByAnotherClient: return "videoDeviceInUseByAnotherClient"
        case .videoDeviceNotAvailableWithMultipleForegroundApps: return "videoDeviceNotAvailableWithMultipleForegroundApps"
        case .videoDeviceNotAvailableDueToSystemPressure: return "videoDeviceNotAvailableDueToSystemPressure"
        default: return "raw \(raw)"
        }
    }

    // MARK: Capture queue

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.lock()
        let c = consumer
        let fov = fieldOfViewDegrees
        let rotation = rotationDegrees
        lock.unlock()
        guard let consumer = c else { return }

        let now = CACurrentMediaTime()
        let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        var time = now
        var offset = 0.0
        if pts.isFinite {
            offset = now - pts
            // Capture timestamps are expected on the host clock (same as CACurrentMediaTime).
            // If they aren't, fall back to the arrival time.
            if offset >= 0 && offset < 0.5 {
                time = pts
            }
        }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let geometry = makeGeometry(width: width, height: height, fovDegrees: fov, rotation: rotation)
        let info = FrameInfo(time: time, luma: LumaMath.meanLuma(pixelBuffer), geometry: geometry, clockOffset: offset)
        consumer.consume(pixelBuffer, info: info)
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        currentConsumer()?.frameDropped()
    }

    // MARK: Helpers

    private func makeGeometry(width: Int, height: Int, fovDegrees: Double, rotation: Double) -> CameraGeometry {
        let w = Double(max(width, 1))
        let h = Double(max(height, 1))
        // videoFieldOfView is across the sensor's long side.
        let longFOV = fovDegrees * Double.pi / 180
        let t = tan(longFOV / 2)
        let hFOV: Double
        let vFOV: Double
        if w >= h {
            hFOV = longFOV
            vFOV = 2 * atan(t * h / w)
        } else {
            vFOV = longFOV
            hFOV = 2 * atan(t * w / h)
        }
        let forward = forwardInDevice
        let up = upInDevice(rotationDegrees: rotation)
        let right = forward.cross(up).normalised()
        return CameraGeometry(imageWidth: width, imageHeight: height,
                              horizontalFOV: hFOV, verticalFOV: vFOV,
                              rightInDevice: right, upInDevice: up, forwardInDevice: forward)
    }

    private func currentConsumer() -> (any FrameConsumer)? {
        lock.lock()
        defer { lock.unlock() }
        return consumer
    }

    private func currentDevice() -> AVCaptureDevice? {
        lock.lock()
        defer { lock.unlock() }
        return device
    }
}

/// Phase 4: the iPad's back wide camera.
final class RearCameraFrameSource: CaptureFrameSource, @unchecked Sendable {
    override var displayName: String { return "Rear wide camera" }

    override func chooseDevice(note: (String) -> Void) -> AVCaptureDevice? {
        if let d = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            return d
        }
        note("CAM no back wide camera, trying any back camera")
        let session = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInDualWideCamera],
                                                       mediaType: .video, position: .back)
        return session.devices.first
    }
}

/// Phase 5 stand-in: the Duo inner (under-display) camera, reached with old-SDK means only
/// (API_NOTES section 6). Falls back to any front camera, then to the back camera, so it also
/// runs on the iPad. Its axis and mirroring choices are UNVERIFIED until spike P2/P3/P11.
final class InnerCameraFrameSource: CaptureFrameSource, @unchecked Sendable {
    enum Strategy: String, Sendable {
        /// The virtual front camera; the system picks the physical one (log activePrimaryConstituent).
        case virtualFront
        /// A constituent of the virtual front camera whose device type mentions "Inner".
        case constituent
        /// `AVCaptureDevice.DeviceType(rawValue: "AVCaptureDeviceTypeBuiltInInnerUltraWideCamera")`.
        case rawDeviceType
    }

    private let strategy: Strategy

    init(strategy: Strategy = .virtualFront) {
        self.strategy = strategy
        super.init()
    }

    override var displayName: String { return "Inner camera (\(strategy.rawValue))" }

    /// In Posture A the inner camera looks out of the inner display, into the room.
    /// Which half the motion sensors sit in is unknown (P11), so this may need flipping.
    override var forwardInDevice: Vec3 { return Vec3(0, 0, 1) }

    /// It looks into the room, so the picture must not be mirrored.
    override var forcesUnmirrored: Bool { return true }

    override func chooseDevice(note: (String) -> Void) -> AVCaptureDevice? {
        let fronts = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera],
                                                      mediaType: .video, position: .front).devices
        for d in fronts {
            let parts = d.constituentDevices.map { $0.deviceType.rawValue }.joined(separator: ",")
            note("CAM front candidate '\(d.localizedName)' type=\(d.deviceType.rawValue) virtual=\(d.isVirtualDevice) constituents=[\(parts)]")
        }
        let virtual = fronts.first(where: { $0.isVirtualDevice })

        if strategy == .constituent, let v = virtual,
           let inner = v.constituentDevices.first(where: { $0.deviceType.rawValue.contains("Inner") }) {
            note("CAM strategy constituent: \(inner.deviceType.rawValue)")
            return inner
        }
        if strategy == .rawDeviceType {
            // Only ask DiscoverySession for an unknown device type on an OS that has it.
            if #available(iOS 27.1, *) {
                let raw = AVCaptureDevice.DeviceType(rawValue: "AVCaptureDeviceTypeBuiltInInnerUltraWideCamera")
                if let d = AVCaptureDevice.DiscoverySession(deviceTypes: [raw], mediaType: .video, position: .unspecified).devices.first {
                    note("CAM strategy rawDeviceType: found")
                    return d
                }
            }
            note("CAM strategy rawDeviceType: not found")
        }
        if let v = virtual {
            note("CAM using the virtual front camera")
            return v
        }
        if let f = fronts.first {
            note("CAM no virtual front camera (not a Duo?), using '\(f.localizedName)'")
            return f
        }
        note("CAM no front camera, falling back to the back camera")
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    override func didStartRunning(device: AVCaptureDevice, note: (String) -> Void) {
        if device.isVirtualDevice {
            let active = device.activePrimaryConstituent?.deviceType.rawValue ?? "nil"
            note("CAM activePrimaryConstituent=\(active)")
        }
    }
}
