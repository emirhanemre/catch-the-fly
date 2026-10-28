import Foundation
import ARKit

/// ARSession delegate on its own serial queue. Only counts frames and reports state
/// changes as plain text; it never keeps an ARFrame.
final class ARTap: NSObject, ARSessionDelegate, @unchecked Sendable {
    let events = LockedQueue<ProbeEvent>()
    private let lock = NSLock()
    private var frames = 0
    private var state = "-"

    var frameCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return frames
    }

    var trackingState: String {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    private func emit(_ text: String) {
        events.append(ProbeEvent(t: ProcessInfo.processInfo.systemUptime, text: text))
    }

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        lock.lock()
        frames += 1
        lock.unlock()
    }

    nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let s = ARTap.describe(camera.trackingState)
        lock.lock()
        state = s
        lock.unlock()
        emit("AR tracking state -> \(s)")
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        emit("AR session INTERRUPTED")
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        emit("AR session interruption ended")
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: any Error) {
        let e = error as NSError
        emit("AR session FAILED: \(e.domain) \(e.code): \(e.localizedDescription)")
    }

    static func describe(_ s: ARCamera.TrackingState) -> String {
        switch s {
        case .notAvailable: return "notAvailable"
        case .normal: return "normal"
        case .limited(let reason): return "limited(\(reason))"
        }
    }
}

/// Rear-camera world tracking (P7, P12).
@MainActor
final class ARController: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var frames = 0
    @Published private(set) var state = "-"
    private(set) var events: [ProbeEvent] = []

    private var session: ARSession?
    private var tap: ARTap?
    private let queue = DispatchQueue(label: "duoprobe.ar")
    private let poller = Poller()
    private let testID: String
    private let log: ProbeLog

    init(testID: String, log: ProbeLog) {
        self.testID = testID
        self.log = log
    }

    var readout: String {
        running ? "AR: \(frames) frames, tracking \(state)" : "AR: stopped (\(frames) frames)"
    }

    var isSupported: Bool {
        ARWorldTrackingConfiguration.isSupported
    }

    @discardableResult
    func start() -> Bool {
        guard ARWorldTrackingConfiguration.isSupported else {
            log.result(testID, .notAvailable, "ARWorldTrackingConfiguration.isSupported is false")
            return false
        }
        stop()
        let s = ARSession()
        let t = ARTap()
        s.delegateQueue = queue
        s.delegate = t
        session = s
        tap = t
        events = []
        frames = 0
        state = "starting"
        running = true
        s.run(ARWorldTrackingConfiguration(), options: [.resetTracking, .removeExistingAnchors])
        log.add(testID, "AR world tracking started (rear camera)")
        poller.start { [weak self] in
            self?.drain()
        }
        return true
    }

    func stop() {
        guard let s = session else { return }
        s.pause()
        drain()
        poller.stop()
        log.add(testID, "AR paused after \(frames) frames, last tracking state \(state)")
        session = nil
        tap = nil
        running = false
    }

    private func drain() {
        guard let t = tap else { return }
        for e in t.events.drain() {
            events.append(e)
            log.add(testID, e.text, at: e.t)
        }
        frames = t.frameCount
        state = t.trackingState
    }
}
