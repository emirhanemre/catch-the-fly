#if IOS_27_1_SDK
import Foundation
import QuartzCore
import UIKit

// Phase 5, CI build only. The native hinge (UIHingeInteraction, iOS 27.1) and the luma
// source gated by posture. Both feed FlyCore's SmashDetector through SmashInputs, which
// combines them: with a live hinge, darkness only counts when the hinge confirms it.

/// UIHingeInteraction(updateHandler:) (API_NOTES section 1). Samples carry the mapped status,
/// timestamped with CACurrentMediaTime() on arrival (the update has no timestamp), which is
/// the game's clock.
@MainActor
final class NativeHingeSmashSource: SmashInputSource {
    let name = "Hinge (native UIHingeInteraction, iOS 27.1 SDK)"

    /// A close faster than this (rad/s, a lower bound from sparse samples) shows a "gently"
    /// reminder. It never changes the verdict: nothing rewards slamming.
    static let slamSpeed = 10.0

    private var interaction: AnyObject?
    private weak var hostView: UIView?
    private var samples: [HingeSample] = []
    private var recent: [HingeSample] = []
    private var notes: [String] = []
    private let tunables = FlyTunables()
    private var closeHandled = false
    private var closedArrival: Double?

    private(set) var providesHinge = false
    private(set) var lastAngle: Double?
    private(set) var lastStatus: HingeStatus?
    private(set) var lastStatusName = "none"
    private(set) var updateCount = 0
    private(set) var lastCloseSpeed: Double?
    private(set) var gentleReminderUntil: Double = 0

    var isAvailable: Bool { return interaction != nil }

    var statusText: String {
        guard interaction != nil else { return "hinge unavailable" }
        let degrees = lastAngle.map { FlyLog.fixed($0 * 180 / Double.pi, decimals: 0) + "deg" } ?? "none"
        return "hinge \(degrees) \(lastStatusName) updates=\(updateCount)"
    }

    func attach(to view: UIView) {
        if #available(iOS 27.1, *) {
            attachNative(to: view)
        } else {
            notes.append("HINGE native source on an iOS older than 27.1: unavailable")
        }
    }

    func receiveLuma(_ samples: [LumaSample]) {}

    func drain(into inputs: inout SmashInputs) {
        if let t = closedArrival {
            closedArrival = nil
            let ms = (CACurrentMediaTime() - t) * 1000
            notes.append("HINGE closed sample reached the game \(FlyLog.fixed(ms, decimals: 1)) ms after it arrived")
        }
        inputs.hinge.append(contentsOf: samples)
        inputs.notes.append(contentsOf: notes)
        samples.removeAll()
        notes.removeAll()
    }

    @available(iOS 27.1, *)
    private func attachNative(to view: UIView) {
        if let existing = interaction as? UIHingeInteraction {
            if hostView !== view {
                hostView?.removeInteraction(existing)
                view.addInteraction(existing)
                hostView = view
                notes.append("HINGE interaction moved to a new view")
            }
            return
        }
        let made = UIHingeInteraction(updateHandler: { [weak self] _, update in
            // UIKit calls this on the main actor. assumeIsolated keeps it compiling however
            // the SDK annotates the handler.
            MainActor.assumeIsolated {
                self?.receive(update.hinge)
            }
        })
        view.addInteraction(made)
        interaction = made
        hostView = view
        notes.append("HINGE native UIHingeInteraction attached, isEnabled=\(made.isEnabled)")
    }

    @available(iOS 27.1, *)
    private func receive(_ hinge: UIHinge?) {
        let t = CACurrentMediaTime()
        updateCount += 1
        guard let h = hinge else {
            lastStatusName = "no hinge"
            notes.append("HINGE t=\(FlyLog.fixed(t)) update.hinge is nil")
            return
        }
        let angle = Double(h.angle)
        let status: HingeStatus?
        let statusName: String
        switch h.status {
        case .closed:
            status = HingeStatus.closed
            statusName = "closed"
        case .partiallyOpen:
            status = HingeStatus.partiallyOpen
            statusName = "partiallyOpen"
        case .fullyOpen:
            status = HingeStatus.fullyOpen
            statusName = "fullyOpen"
        case .unknown:
            status = nil
            statusName = "unknown"
        @unknown default:
            status = nil
            statusName = "other"
        }
        lastAngle = angle
        lastStatus = status
        lastStatusName = statusName
        notes.append("HINGE t=\(FlyLog.fixed(t)) angle=\(FlyLog.fixed(angle)) status=\(statusName) raw=\(h.status.rawValue)")
        guard angle.isFinite else { return }
        providesHinge = true
        let sample = HingeSample(angle: angle, time: t, status: status)
        samples.append(sample)
        watchCloseSpeed(sample)
    }

    /// Only for the reminder and the log. FlyCore does the real detection.
    private func watchCloseSpeed(_ s: HingeSample) {
        recent.append(s)
        recent.removeAll { s.time - $0.time > 1.0 }
        let closed = s.status == HingeStatus.closed || s.angle <= tunables.hingeClosedAngle
        if !closed {
            if s.angle >= tunables.hingeArmAngle {
                closeHandled = false
            }
            return
        }
        guard !closeHandled else { return }
        closeHandled = true
        closedArrival = s.time
        var fastest = 0.0
        if recent.count >= 2 {
            for i in 1..<recent.count {
                let a = recent[i - 1]
                let b = recent[i]
                let dt = b.time - a.time
                let drop = a.angle - b.angle
                if dt >= 0.008 && drop > 0 {
                    fastest = max(fastest, drop / dt)
                }
            }
        }
        lastCloseSpeed = fastest > 0 ? fastest : nil
        notes.append("HINGE close seen: \(recent.count) samples in the last second, fastest segment \(FlyLog.fixed(fastest, decimals: 2)) rad/s")
        if fastest > NativeHingeSmashSource.slamSpeed {
            gentleReminderUntil = s.time + 4
            notes.append("HINGE fast close: showing the 'fold gently' reminder (the verdict is unchanged)")
        }
    }
}

/// The darkening trigger, on only in Posture A. In Posture B the rear camera keeps looking at
/// the room while the book closes, so its luma says nothing about a smash: the hinge alone is
/// the trigger there.
@MainActor
final class PostureGatedLumaSource: SmashInputSource {
    let name = "Camera darkening (inner camera, Posture A only)"
    var enabled = true
    private let base = LumaSmashSource()

    var isAvailable: Bool { return enabled && base.isAvailable }
    var providesHinge: Bool { return false }
    var statusText: String {
        return enabled ? base.statusText : "luma off (Posture B)"
    }

    func attach(to view: UIView) {
        base.attach(to: view)
    }

    func receiveLuma(_ samples: [LumaSample]) {
        if enabled {
            base.receiveLuma(samples)
        }
    }

    func drain(into inputs: inout SmashInputs) {
        base.drain(into: &inputs)
    }
}
#endif
