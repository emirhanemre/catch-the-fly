import Foundation
import QuartzCore
import UIKit

/// What all smash inputs hand FlyCore's SmashDetector (through FlyGameInput) for one frame.
struct SmashInputs {
    var hinge: [HingeSample] = []
    var luma: [LumaSample] = []
    var manual = false
    var notes: [String] = []
}

/// A smash trigger. Named `SmashInputSource` because FlyCore already has `enum SmashSource`
/// (and both compile in one module). iPad: `LumaSmashSource` + `DebugButtonSmashSource`
/// (+ `HingeSmashSource`, which reports itself unavailable). Main actor only.
@MainActor
protocol SmashInputSource: AnyObject {
    var name: String { get }
    var isAvailable: Bool { get }
    /// True once it has delivered real hinge samples. Decides `FlyGame.hingeAvailable`, which
    /// makes darkness wait for hinge confirmation (rejects a hand over the lens).
    var providesHinge: Bool { get }
    var statusText: String { get }
    /// The game view, for sources that need one (the hinge interaction).
    func attach(to view: UIView)
    /// This frame's camera luma samples, oldest first.
    func receiveLuma(_ samples: [LumaSample])
    /// Moves everything collected since the last call into `inputs`.
    func drain(into inputs: inout SmashInputs)
}

/// Covering the camera: feeds every frame's mean luma to the detector's darkening path.
@MainActor
final class LumaSmashSource: SmashInputSource {
    let name = "Camera darkening"
    private var pending: [LumaSample] = []
    private var lastTime: Double?
    private var lastLuma: Double?

    var isAvailable: Bool {
        guard let t = lastTime else { return false }
        return CACurrentMediaTime() - t < 1.0
    }
    var providesHinge: Bool { return false }
    var statusText: String {
        return "luma " + FlyLog.optionalFixed(lastLuma, decimals: 2) + (isAvailable ? "" : " (no frames)")
    }

    func attach(to view: UIView) {}

    func receiveLuma(_ samples: [LumaSample]) {
        pending.append(contentsOf: samples)
        if let s = samples.last {
            lastLuma = s.mean
            lastTime = s.time
        }
    }

    func drain(into inputs: inout SmashInputs) {
        inputs.luma.append(contentsOf: pending)
        pending.removeAll()
    }
}

/// The on-screen debug button.
@MainActor
final class DebugButtonSmashSource: SmashInputSource {
    let name = "Debug button"
    private var pressed = false
    private var presses = 0

    var isAvailable: Bool { return true }
    var providesHinge: Bool { return false }
    var statusText: String { return "button presses \(presses)" }

    func press() {
        pressed = true
        presses += 1
    }

    func attach(to view: UIView) {}
    func receiveLuma(_ samples: [LumaSample]) {}

    func drain(into inputs: inout SmashInputs) {
        if pressed {
            inputs.manual = true
            pressed = false
        }
    }
}

/// UIHingeInteraction through the Objective-C runtime (no iOS 27 symbol in the source).
/// On the iPad the class doesn't exist, so it stays unavailable. The status raw values are
/// undocumented, so samples carry the angle only (status nil) and the raw value is logged.
@MainActor
final class HingeSmashSource: SmashInputSource {
    let name = "Hinge (runtime UIHingeInteraction)"
    private var interaction: (any UIInteraction)?
    private var samples: [HingeSample] = []
    private var notes: [String] = []
    private var attachTried = false
    private var lastAngle: Double?
    private var lastStatusRaw: Int?
    private(set) var providesHinge = false

    var isAvailable: Bool { return interaction != nil }
    var statusText: String {
        guard interaction != nil else { return "hinge unavailable" }
        return "hinge angle=" + FlyLog.optionalFixed(lastAngle, decimals: 3) + " statusRaw=" + (lastStatusRaw.map { String($0) } ?? "none")
    }

    func attach(to view: UIView) {
        guard !attachTried else { return }
        attachTried = true
        guard RuntimeHinge.isClassPresent else {
            notes.append("HINGE UIHingeInteraction not present (expected on the iPad)")
            return
        }
        let made = RuntimeHinge.makeInteraction { [weak self] angle, statusRaw in
            self?.receive(angle: angle, statusRaw: statusRaw)
        }
        guard let made = made else {
            notes.append("HINGE class present but the interaction couldn't be created")
            return
        }
        view.addInteraction(made)
        interaction = made
        notes.append("HINGE interaction attached")
    }

    func receiveLuma(_ samples: [LumaSample]) {}

    func drain(into inputs: inout SmashInputs) {
        inputs.hinge.append(contentsOf: samples)
        inputs.notes.append(contentsOf: notes)
        samples.removeAll()
        notes.removeAll()
    }

    private func receive(angle: Double?, statusRaw: Int?) {
        let t = CACurrentMediaTime()
        lastAngle = angle
        lastStatusRaw = statusRaw
        notes.append("HINGE t=\(FlyLog.fixed(t)) angle=\(FlyLog.optionalFixed(angle)) statusRaw=\(statusRaw.map { String($0) } ?? "none")")
        guard let a = angle, a.isFinite else { return }
        providesHinge = true
        samples.append(HingeSample(angle: a, time: t, status: nil, statusRaw: statusRaw))
    }
}
