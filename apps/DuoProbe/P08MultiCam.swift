import SwiftUI
import AVFoundation
import CoreMedia

/// Rear wide + inner (or front) camera in one AVCaptureMultiCamSession.
final class MultiCamCapture: @unchecked Sendable {
    let session = AVCaptureMultiCamSession()
    let rearTap = FrameTap(name: "rear", latest: LockedBox<FrameSample?>(nil))
    let innerTap = FrameTap(name: "inner", latest: LockedBox<FrameSample?>(nil))
    let events = LockedQueue<ProbeEvent>()
    private let rearID: String
    private let innerID: String
    private let sessionQueue = DispatchQueue(label: "duoprobe.multicam")
    private let rearQueue = DispatchQueue(label: "duoprobe.multicam.rear")
    private let innerQueue = DispatchQueue(label: "duoprobe.multicam.inner")
    private var observers: [NSObjectProtocol] = []

    init(rearID: String, innerID: String) {
        self.rearID = rearID
        self.innerID = innerID
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
            if self.session.isRunning {
                self.session.stopRunning()
            }
            for o in self.observers {
                NotificationCenter.default.removeObserver(o)
            }
            self.observers.removeAll()
            self.emit("multi-cam session stopped")
        }
    }

    private func configureAndRun() {
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            emit("FAIL: multi-cam not supported")
            return
        }
        guard let rear = AVCaptureDevice(uniqueID: rearID), let inner = AVCaptureDevice(uniqueID: innerID) else {
            emit("FAIL: couldn't open one of the cameras by uniqueID")
            return
        }
        session.beginConfiguration()
        let rearOK = add(rear, tap: rearTap, queue: rearQueue)
        let innerOK = add(inner, tap: innerTap, queue: innerQueue)
        session.commitConfiguration()
        emit("configured: rear \(rearOK ? "OK" : "FAILED"), inner \(innerOK ? "OK" : "FAILED"); hardwareCost \(fmt(Double(session.hardwareCost), 2)), systemPressureCost \(fmt(Double(session.systemPressureCost), 2))")
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] note in
            let err = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
            self?.emit("multi-cam RUNTIME ERROR: \(err.map { "\($0.code) \($0.localizedDescription)" } ?? "unknown")")
        })
        observers.append(nc.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] note in
            let raw = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)?.intValue
            self?.emit("multi-cam INTERRUPTED (reason raw \(raw.map { "\($0)" } ?? "none"))")
        })
        session.startRunning()
        emit("startRunning returned; isRunning = \(session.isRunning)")
    }

    private func add(_ device: AVCaptureDevice, tap: FrameTap, queue: DispatchQueue) -> Bool {
        preferMultiCamFormat(device)
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            emit("FAIL: input for \(device.localizedName): \(error.localizedDescription)")
            return false
        }
        guard session.canAddInput(input) else {
            emit("FAIL: canAddInput false for \(device.localizedName)")
            return false
        }
        session.addInputWithNoConnections(input)
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(tap, queue: queue)
        guard session.canAddOutput(output) else {
            emit("FAIL: canAddOutput false for \(device.localizedName)")
            return false
        }
        session.addOutputWithNoConnections(output)
        let ports = input.ports(for: .video, sourceDeviceType: device.deviceType, sourceDevicePosition: device.position)
        guard !ports.isEmpty else {
            emit("FAIL: no video port for \(device.localizedName)")
            return false
        }
        let connection = AVCaptureConnection(inputPorts: ports, output: output)
        guard session.canAddConnection(connection) else {
            emit("FAIL: canAddConnection false for \(device.localizedName)")
            return false
        }
        session.addConnection(connection)
        emit("added \(device.localizedName) [\(device.deviceType.rawValue)]")
        return true
    }

    private func preferMultiCamFormat(_ device: AVCaptureDevice) {
        if device.activeFormat.isMultiCamSupported {
            emit("\(device.localizedName): active format already supports multi-cam")
            return
        }
        let candidates = device.formats.filter { $0.isMultiCamSupported }
        let pick = candidates.first { f in
            CMVideoFormatDescriptionGetDimensions(f.formatDescription).width <= 1920
        } ?? candidates.first
        guard let format = pick else {
            emit("\(device.localizedName): no multi-cam format at all")
            return
        }
        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            device.unlockForConfiguration()
            let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            emit("\(device.localizedName): switched to multi-cam format \(d.width)x\(d.height)")
        } catch {
            emit("\(device.localizedName): lockForConfiguration failed: \(error.localizedDescription)")
        }
    }
}

@MainActor
final class P8Model: ObservableObject {
    @Published private(set) var status = "Not started"
    @Published private(set) var running = false
    private var capture: MultiCamCapture?
    private var task: Task<Void, Never>?
    private let log: ProbeLog

    init(log: ProbeLog) {
        self.log = log
    }

    func run() {
        guard !running else { return }
        log.add("P8", "---- P8 multi-cam ----")
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            log.result("P8", .notAvailable, "AVCaptureMultiCamSession.isMultiCamSupported is false")
            status = "Multi-cam isn't supported on this device."
            return
        }
        guard let rear = CameraFinder.rearWide() else {
            log.result("P8", .notAvailable, "no rear wide camera")
            status = "No rear camera."
            return
        }
        guard let inner = CameraFinder.pickInner(testerPick: log.testerPickedCameraID) else {
            log.result("P8", .notAvailable, "no front or inner camera")
            status = "No front camera."
            return
        }
        log.add("P8", "rear: \(rear.label); inner: \(inner.label) (\(inner.note))")
        running = true
        status = "Running for 8 seconds…"
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            guard await CameraPermission.ensure(log: self.log, testID: "P8") else {
                self.running = false
                self.status = "No camera permission."
                return
            }
            // Left while the permission prompt was up: don't start a session nobody stops.
            if Task.isCancelled { return }
            let c = MultiCamCapture(rearID: rear.id, innerID: inner.id)
            self.capture = c
            c.start()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled { return }
            let r0 = c.rearTap.counts.received
            let i0 = c.innerTap.counts.received
            let t0 = uptimeNow()
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if Task.isCancelled { return }
            let t1 = uptimeNow()
            let rearFps = Double(c.rearTap.counts.received - r0) / max(t1 - t0, 0.001)
            let innerFps = Double(c.innerTap.counts.received - i0) / max(t1 - t0, 0.001)
            self.flush(c)
            c.stop()
            self.log.result("P8", .value, "rear \(fmt(rearFps, 1)) fps, inner/front \(fmt(innerFps, 1)) fps (measured over \(fmt(t1 - t0, 1)) s)")
            if rearFps > 5 && innerFps > 5 {
                self.log.result("P8", .pass, "rear wide and \(inner.label) ran together")
            } else {
                self.log.result("P8", .fail, "they didn't both deliver frames")
            }
            self.status = "Done: rear \(fmt(rearFps, 0)) fps, inner \(fmt(innerFps, 0)) fps."
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            self.flush(c)
            self.capture = nil
            self.running = false
        }
    }

    private func flush(_ c: MultiCamCapture) {
        for e in c.events.drain() {
            log.add("P8", e.text, at: e.t)
        }
        _ = c.rearTap.frames.drain()
        _ = c.innerTap.frames.drain()
    }

    func leave() {
        task?.cancel()
        if let c = capture {
            flush(c)
            c.stop()
        }
        capture = nil
        running = false
    }
}

struct P8View: View {
    let log: ProbeLog
    @StateObject private var model: P8Model

    init(log: ProbeLog) {
        self.log = log
        _model = StateObject(wrappedValue: P8Model(log: log))
    }

    var body: some View {
        TestPage(id: "P8", title: "Two cameras at once", steps: [
            "Hold the phone however you like.",
            "Tap Start and wait about 10 seconds until it says Done."
        ], log: log) {
            ReadoutBox(text: model.status)
            BigButton("Start", enabled: !model.running) { model.run() }
        }
        .onDisappear { model.leave() }
    }
}
