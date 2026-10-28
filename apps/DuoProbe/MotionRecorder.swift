import Foundation
import CoreMotion

struct MotionSample: Sendable {
    let t: TimeInterval          // CMDeviceMotion.timestamp (same clock as systemUptime)
    let qw: Double, qx: Double, qy: Double, qz: Double
    let rx: Double, ry: Double, rz: Double      // rotationRate, rad/s
    let ax: Double, ay: Double, az: Double      // userAcceleration, g

    var rotationMagnitude: Double {
        (rx * rx + ry * ry + rz * rz).squareRoot()
    }
}

/// CoreMotion device motion on its own serial OperationQueue. The handler is built in
/// this non-isolated class, so it never assumes the main actor (API_NOTES Swift 6 trap 3).
final class MotionRecorder: @unchecked Sendable {
    let samples = LockedQueue<MotionSample>()
    let latest = LockedBox<MotionSample?>(nil)
    private let manager = CMMotionManager()
    private let queue: OperationQueue
    private let lock = NSLock()
    private var hook: (@Sendable (MotionSample) -> Void)?
    private var running = false
    private var errorText: String?

    init() {
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "duoprobe.motion"
    }

    var isAvailable: Bool {
        manager.isDeviceMotionAvailable
    }

    var lastError: String? {
        lock.lock()
        defer { lock.unlock() }
        return errorText
    }

    /// Called on the motion queue for every sample (CSV sidecars use this).
    func setHook(_ newHook: (@Sendable (MotionSample) -> Void)?) {
        lock.lock()
        hook = newHook
        lock.unlock()
    }

    @discardableResult
    func start(hz: Double = 100) -> Bool {
        guard manager.isDeviceMotionAvailable else { return false }
        lock.lock()
        let alreadyRunning = running
        running = true
        lock.unlock()
        if alreadyRunning { return true }
        _ = samples.drain()
        manager.deviceMotionUpdateInterval = 1.0 / hz
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, error in
            self?.handle(motion, error)
        }
        return true
    }

    func stop() {
        lock.lock()
        running = false
        lock.unlock()
        manager.stopDeviceMotionUpdates()
    }

    private func handle(_ motion: CMDeviceMotion?, _ error: (any Error)?) {
        if let error {
            lock.lock()
            errorText = error.localizedDescription
            lock.unlock()
        }
        guard let m = motion else { return }
        let q = m.attitude.quaternion
        let r = m.rotationRate
        let a = m.userAcceleration
        let sample = MotionSample(t: m.timestamp,
                                  qw: q.w, qx: q.x, qy: q.y, qz: q.z,
                                  rx: r.x, ry: r.y, rz: r.z,
                                  ax: a.x, ay: a.y, az: a.z)
        samples.append(sample)
        latest.set(sample)
        lock.lock()
        let h = hook
        lock.unlock()
        h?(sample)
    }
}
