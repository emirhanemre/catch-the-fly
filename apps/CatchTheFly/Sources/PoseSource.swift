import Foundation
import CoreMotion
import QuartzCore

/// Device orientation as plain values: the device's x, y and z axes expressed in a world frame
/// (z up, yaw arbitrary), plus how fast it is turning.
struct PoseSample: Sendable, Equatable {
    var deviceX: Vec3
    var deviceY: Vec3
    var deviceZ: Vec3
    /// Magnitude of the rotation rate (rad/s).
    var rotationRate: Double
    /// CACurrentMediaTime() at arrival.
    var time: Double

    /// A device-frame direction in world coordinates.
    func toWorld(_ v: Vec3) -> Vec3 {
        return deviceX * v.x + deviceY * v.y + deviceZ * v.z
    }
}

/// Where the camera is pointing. iPad and Duo both use CoreMotion; route A would use ARKit.
protocol PoseSource: AnyObject, Sendable {
    var displayName: String { get }
    /// `notes` may be called from any thread.
    func start(notes: @escaping @Sendable (String) -> Void)
    func stop()
    /// The newest sample, or nil before the first. Any thread.
    func latest() -> PoseSample?
}

/// CoreMotion device motion on its own serial OperationQueue. Only plain values leave the queue.
final class CoreMotionPoseSource: PoseSource, @unchecked Sendable {
    let displayName = "CoreMotion device motion (xArbitraryZVertical)"

    private let manager = CMMotionManager()
    private let queue: OperationQueue
    private let lock = NSLock()
    private var sample: PoseSample?
    // Motion queue only.
    private var rowsAreDeviceAxes = true
    private var conventionLogged = false

    init() {
        let q = OperationQueue()
        q.name = "catchthefly.motion"
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInteractive
        queue = q
    }

    func start(notes: @escaping @Sendable (String) -> Void) {
        guard manager.isDeviceMotionAvailable else {
            notes("POSE device motion not available")
            return
        }
        guard !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue, withHandler: makeHandler(notes: notes))
        notes("POSE started")
    }

    func stop() {
        if manager.isDeviceMotionActive {
            manager.stopDeviceMotionUpdates()
        }
    }

    func latest() -> PoseSample? {
        lock.lock()
        defer { lock.unlock() }
        return sample
    }

    /// Built outside any actor, so the closure isn't main-actor isolated (API_NOTES trap 3).
    private func makeHandler(notes: @escaping @Sendable (String) -> Void) -> CMDeviceMotionHandler {
        return { [weak self] motion, error in
            guard let self = self else { return }
            if let motion = motion {
                self.ingest(motion, notes: notes)
            } else if let error = error {
                notes("POSE error: \(error.localizedDescription)")
            }
        }
    }

    /// Motion queue.
    private func ingest(_ motion: CMDeviceMotion, notes: @Sendable (String) -> Void) {
        let m = motion.attitude.rotationMatrix
        let g = motion.gravity
        // Which way round is the matrix? Check against measured gravity rather than trusting
        // memory: if it maps reference -> device, gravity = -(m13, m23, m33); if device ->
        // reference, gravity = -(m31, m32, m33). Keep the last choice when they agree.
        let errRows = sq(g.x + m.m13) + sq(g.y + m.m23) + sq(g.z + m.m33)
        let errCols = sq(g.x + m.m31) + sq(g.y + m.m32) + sq(g.z + m.m33)
        let before = rowsAreDeviceAxes
        if errRows + 0.05 < errCols {
            rowsAreDeviceAxes = true
        } else if errCols + 0.05 < errRows {
            rowsAreDeviceAxes = false
        }
        if before != rowsAreDeviceAxes || !conventionLogged {
            if abs(errRows - errCols) > 0.05 {
                conventionLogged = true
                notes("POSE matrix convention: \(rowsAreDeviceAxes ? "rows" : "columns") are device axes (errRows=\(FlyLog.fixed(errRows)) errCols=\(FlyLog.fixed(errCols)))")
            }
        }
        let x: Vec3
        let y: Vec3
        let z: Vec3
        if rowsAreDeviceAxes {
            x = Vec3(m.m11, m.m12, m.m13)
            y = Vec3(m.m21, m.m22, m.m23)
            z = Vec3(m.m31, m.m32, m.m33)
        } else {
            x = Vec3(m.m11, m.m21, m.m31)
            y = Vec3(m.m12, m.m22, m.m32)
            z = Vec3(m.m13, m.m23, m.m33)
        }
        let r = motion.rotationRate
        let rate = (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot()
        let s = PoseSample(deviceX: x, deviceY: y, deviceZ: z, rotationRate: rate.isFinite ? rate : 0, time: CACurrentMediaTime())
        lock.lock()
        sample = s
        lock.unlock()
    }

    private func sq(_ v: Double) -> Double { return v * v }
}
