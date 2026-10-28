import Foundation
import AVFoundation
import CoreMedia
import CoreVideo

/// One camera frame, reduced to plain values on the capture queue.
struct FrameSample: Sendable {
    let t: TimeInterval
    let luma: Double     // mean of the Y plane, 0...255; -1 if it couldn't be read
    let width: Int
    let height: Int
}

struct ClipResult: Sendable {
    let url: URL
    let ok: Bool
    let message: String
}

enum LumaMeter {
    /// Mean luma of a 420v/420f buffer, sampling every 8th pixel of every 8th row.
    static func meanLuma(_ pb: CVPixelBuffer) -> Double {
        let format = CVPixelBufferGetPixelFormatType(pb)
        guard format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange else { return -1 }
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pb, 0) else { return -1 }
        let width = CVPixelBufferGetWidthOfPlane(pb, 0)
        let height = CVPixelBufferGetHeightOfPlane(pb, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var sum = 0
        var count = 0
        var y = 0
        while y < height {
            let row = y * stride
            var x = 0
            while x < width {
                sum += Int(bytes[row + x])
                count += 1
                x += 8
            }
            y += 8
        }
        return count > 0 ? Double(sum) / Double(count) : -1
    }
}

/// Sample-buffer delegate. Lives off the main actor; hands plain values to the main actor
/// through a LockedQueue that the owner drains.
final class FrameTap: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let name: String
    let frames = LockedQueue<FrameSample>()
    let latest: LockedBox<FrameSample?>
    private let lock = NSLock()
    private var received = 0
    private var dropped = 0

    init(name: String, latest: LockedBox<FrameSample?>) {
        self.name = name
        self.latest = latest
        super.init()
    }

    var counts: (received: Int, dropped: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (received, dropped)
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        var t = now
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if pts.isValid {
            let s = pts.seconds
            if abs(s - now) < 1.0 { t = s }
        }
        var luma = -1.0
        var w = 0
        var h = 0
        if let pb = CMSampleBufferGetImageBuffer(sampleBuffer) {
            luma = LumaMeter.meanLuma(pb)
            w = CVPixelBufferGetWidth(pb)
            h = CVPixelBufferGetHeight(pb)
        }
        let sample = FrameSample(t: t, luma: luma, width: w, height: h)
        frames.append(sample)
        latest.set(sample)
        lock.lock()
        received += 1
        lock.unlock()
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didDrop sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        lock.lock()
        dropped += 1
        lock.unlock()
    }
}

/// One AVCaptureSession with one camera, a video data output (luma per frame) and,
/// optionally, a movie file output (P9). Every session call runs on `sessionQueue`.
final class CameraCapture: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    let tap: FrameTap
    let events = LockedQueue<ProbeEvent>()
    let finishedClips = LockedQueue<ClipResult>()
    let deviceID: String
    let label: String
    private let wantMovie: Bool
    private let sessionQueue = DispatchQueue(label: "duoprobe.session")
    private let videoQueue = DispatchQueue(label: "duoprobe.video")
    private let videoOutput = AVCaptureVideoDataOutput()
    private var movieOutput: AVCaptureMovieFileOutput?
    private var device: AVCaptureDevice?
    private var observers: [NSObjectProtocol] = []

    init(deviceID: String, label: String, wantMovie: Bool, latest: LockedBox<FrameSample?>) {
        self.deviceID = deviceID
        self.label = label
        self.wantMovie = wantMovie
        self.tap = FrameTap(name: label, latest: latest)
        super.init()
    }

    private func emit(_ text: String) {
        events.append(ProbeEvent(t: ProcessInfo.processInfo.systemUptime, text: text))
    }

    func start() {
        sessionQueue.async {
            self.configureAndRun()
        }
    }

    func stop() {
        sessionQueue.async {
            if let m = self.movieOutput, m.isRecording {
                m.stopRecording()
            }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            let c = self.tap.counts
            self.emit("camera stopped: \(c.received) frames received, \(c.dropped) dropped")
            for o in self.observers {
                NotificationCenter.default.removeObserver(o)
            }
            self.observers.removeAll()
        }
    }

    func startRecording(to url: URL) {
        sessionQueue.async {
            guard let m = self.movieOutput else {
                self.emit("FAIL: no movie output in this session, so no clip can be recorded")
                self.finishedClips.append(ClipResult(url: url, ok: false, message: "no movie output"))
                return
            }
            guard !m.isRecording else {
                self.emit("already recording; ignored")
                return
            }
            if let c = m.connection(with: .video) {
                self.emit("clip connection: \(CameraCapture.describe(c))")
            }
            m.startRecording(to: url, recordingDelegate: self)
            self.emit("clip recording requested: \(url.lastPathComponent)")
        }
    }

    func stopRecording() {
        sessionQueue.async {
            if let m = self.movieOutput, m.isRecording {
                m.stopRecording()
                self.emit("clip stop requested")
            }
        }
    }

    func logActiveConstituent() {
        sessionQueue.async {
            guard let d = self.device else { return }
            if d.isVirtualDevice {
                if let p = d.activePrimaryConstituent {
                    self.emit("activePrimaryConstituent = \(p.localizedName), type \(p.deviceType.rawValue), id \(p.uniqueID)")
                } else {
                    self.emit("activePrimaryConstituent = nil")
                }
            } else {
                self.emit("camera is a physical device (not virtual): \(d.localizedName)")
            }
        }
    }

    // MARK: - Session queue only

    private func configureAndRun() {
        guard let device = AVCaptureDevice(uniqueID: deviceID) else {
            emit("FAIL: AVCaptureDevice(uniqueID: \(deviceID)) returned nil")
            return
        }
        self.device = device
        let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let maxFps = device.activeFormat.videoSupportedFrameRateRanges.map { $0.maxFrameRate }.max() ?? 0
        emit("camera: \(device.localizedName), type \(device.deviceType.rawValue), position \(CameraFinder.positionName(device.position)), virtual \(device.isVirtualDevice), active format \(dims.width)x\(dims.height) up to \(fmt(maxFps, 0)) fps")

        session.beginConfiguration()
        // The default preset (.high) works with every camera. Pick 720p only after the
        // input is in, so canAddInput is never refused because of a preset this camera
        // (e.g. the square-sensor Duo inner camera) can't do.
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                emit("FAIL: session.canAddInput is false for this camera")
                session.commitConfiguration()
                return
            }
            session.addInput(input)
        } catch {
            emit("FAIL: AVCaptureDeviceInput error: \(error.localizedDescription)")
            session.commitConfiguration()
            return
        }
        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        }

        // P9's clips matter more than its luma readings, so the movie output goes in
        // first; if the two can't coexist on this device, the video data output loses.
        if wantMovie {
            let m = AVCaptureMovieFileOutput()
            if session.canAddOutput(m) {
                session.addOutput(m)
                movieOutput = m
                emit("movie file output added (no audio)")
            } else {
                emit("FAIL: can't add a movie file output to this session")
            }
        }

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(tap, queue: videoQueue)
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        } else {
            emit("FAIL: can't add the video data output\(wantMovie ? " alongside the movie output" : "") (no luma readings)")
        }
        session.commitConfiguration()

        if let c = videoOutput.connection(with: .video) {
            emit("luma frames connection: \(CameraCapture.describe(c))")
        }
        addObservers()
        session.startRunning()
        emit("startRunning returned; isRunning = \(session.isRunning), preset \(session.sessionPreset.rawValue)")
    }

    private func addObservers() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVCaptureSession.wasInterruptedNotification,
                                        object: session, queue: nil) { [weak self] note in
            var reason = "no reason given"
            if let n = note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber {
                if let r = AVCaptureSession.InterruptionReason(rawValue: n.intValue) {
                    reason = CameraCapture.describe(r)
                } else {
                    reason = "raw \(n.intValue)"
                }
            }
            self?.emit("camera INTERRUPTED: \(reason)")
        })
        observers.append(nc.addObserver(forName: AVCaptureSession.interruptionEndedNotification,
                                        object: session, queue: nil) { [weak self] _ in
            self?.emit("camera interruption ended")
        })
        observers.append(nc.addObserver(forName: AVCaptureSession.runtimeErrorNotification,
                                        object: session, queue: nil) { [weak self] note in
            let err = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
            let text = err.map { "\($0.domain) \($0.code): \($0.localizedDescription)" } ?? "unknown error"
            self?.emit("camera RUNTIME ERROR: \(text)")
        })
        observers.append(nc.addObserver(forName: AVCaptureSession.didStartRunningNotification,
                                        object: session, queue: nil) { [weak self] _ in
            self?.emit("camera didStartRunning")
        })
        observers.append(nc.addObserver(forName: AVCaptureSession.didStopRunningNotification,
                                        object: session, queue: nil) { [weak self] _ in
            self?.emit("camera didStopRunning")
        })
    }

    static func describe(_ c: AVCaptureConnection) -> String {
        var text = "mirrored \(c.isVideoMirrored)"
        if #available(iOS 17.0, *) {
            text += ", rotation \(fmt(Double(c.videoRotationAngle), 0))°"
        }
        return text
    }

    static func describe(_ r: AVCaptureSession.InterruptionReason) -> String {
        switch r {
        case .videoDeviceNotAvailableInBackground: return "videoDeviceNotAvailableInBackground"
        case .audioDeviceInUseByAnotherClient: return "audioDeviceInUseByAnotherClient"
        case .videoDeviceInUseByAnotherClient: return "videoDeviceInUseByAnotherClient"
        case .videoDeviceNotAvailableWithMultipleForegroundApps: return "videoDeviceNotAvailableWithMultipleForegroundApps"
        case .videoDeviceNotAvailableDueToSystemPressure: return "videoDeviceNotAvailableDueToSystemPressure"
        case .sensitiveContentMitigationActivated: return "sensitiveContentMitigationActivated"
        @unknown default: return "other reason (raw \(r.rawValue))"
        }
    }

    // MARK: - AVCaptureFileOutputRecordingDelegate

    nonisolated func fileOutput(_ output: AVCaptureFileOutput,
                                didStartRecordingTo fileURL: URL,
                                from connections: [AVCaptureConnection]) {
        emit("clip recording STARTED: \(fileURL.lastPathComponent)")
    }

    nonisolated func fileOutput(_ output: AVCaptureFileOutput,
                                didFinishRecordingTo outputFileURL: URL,
                                from connections: [AVCaptureConnection],
                                error: (any Error)?) {
        var ok = true
        var message = "finished cleanly"
        if let e = error as NSError? {
            let finished = (e.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? NSNumber)?.boolValue ?? false
            ok = finished
            message = "error \(e.code): \(e.localizedDescription) (file usable: \(finished))"
        }
        emit("clip recording ENDED: \(outputFileURL.lastPathComponent): \(message)")
        finishedClips.append(ClipResult(url: outputFileURL, ok: ok, message: message))
    }
}
