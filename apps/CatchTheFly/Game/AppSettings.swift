import Foundation
import Combine

/// How readily the fly takes fright. Maps to FlyTunables' alarm thresholds (see SensitivityMath).
enum AlarmSensitivity: String, CaseIterable, Identifiable, Sendable {
    case relaxed
    case normal
    case twitchy

    var id: String { return rawValue }

    var title: String {
        switch self {
        case .relaxed: return "Relaxed"
        case .normal: return "Normal"
        case .twitchy: return "Twitchy"
        }
    }

    var detail: String {
        switch self {
        case .relaxed: return "A sleepy fly. It forgives a bit of wobble while you creep up."
        case .normal: return "The fly as designed."
        case .twitchy: return "A nervy fly. Move smoothly or it's off."
        }
    }
}

/// How readily a swat registers: a hand over the lens, or a fold. It never asks for a faster
/// fold or cover: the minimum closing speed is left alone, and slower covers are accepted.
enum SmashSensitivity: String, CaseIterable, Identifiable, Sendable {
    case easy
    case normal
    case strict

    var id: String { return rawValue }

    var title: String {
        switch self {
        case .easy: return "Easy"
        case .normal: return "Normal"
        case .strict: return "Strict"
        }
    }

    var detail: String {
        switch self {
        case .easy: return "A smaller fold or a looser cover still counts as a swat."
        case .normal: return "The swat as designed."
        case .strict: return "Needs a full fold, or the lens properly covered. Never faster, just more complete."
        }
    }
}

/// Pure mapping from the player's settings to FlyTunables. The base values come from the
/// platform's preset (FlyCore's FlyPresets), so posture changes and settings combine.
enum SensitivityMath {
    static func adjusted(_ base: FlyTunables, alarm: AlarmSensitivity, smash: SmashSensitivity) -> FlyTunables {
        var t = base
        switch alarm {
        case .relaxed:
            t.alarmAngularSpeed = base.alarmAngularSpeed * 1.35
            t.alarmApproachRate = base.alarmApproachRate * 1.35
            t.alarmRadius = base.alarmRadius * 0.85
        case .normal:
            break
        case .twitchy:
            t.alarmAngularSpeed = base.alarmAngularSpeed * 0.8
            t.alarmApproachRate = base.alarmApproachRate * 0.8
            t.alarmRadius = base.alarmRadius * 1.15
        }
        // smashMinAngularSpeed is deliberately never touched: nothing rewards slamming.
        switch smash {
        case .easy:
            t.darkeningThreshold = min(base.darkeningThreshold * 1.5, base.litThreshold * 0.8)
            t.lumaCollapseMaxDuration = base.lumaCollapseMaxDuration * 1.3
            t.hingeMinCloseDrop = base.hingeMinCloseDrop * 0.8
        case .normal:
            break
        case .strict:
            t.darkeningThreshold = base.darkeningThreshold * 0.7
            // A darker threshold is reached a little later in a cover, so allow a little longer:
            // strict never means faster.
            t.lumaCollapseMaxDuration = base.lumaCollapseMaxDuration * 1.15
            t.hingeMinCloseDrop = base.hingeMinCloseDrop * 1.2
        }
        return t
    }
}

/// The player's settings, kept in UserDefaults. Main actor only.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Key {
        static let alarm = "CatchTheFly.settings.alarmSensitivity"
        static let smash = "CatchTheFly.settings.smashSensitivity"
        static let sound = "CatchTheFly.settings.soundOn"
        static let haptics = "CatchTheFly.settings.hapticsOn"
        static let debug = "CatchTheFly.settings.debugOverlay"
        static let onboarding = "CatchTheFly.settings.onboardingDone"
    }

    @Published var alarmSensitivity: AlarmSensitivity {
        didSet { UserDefaults.standard.set(alarmSensitivity.rawValue, forKey: Key.alarm) }
    }
    @Published var smashSensitivity: SmashSensitivity {
        didSet { UserDefaults.standard.set(smashSensitivity.rawValue, forKey: Key.smash) }
    }
    @Published var soundOn: Bool {
        didSet { UserDefaults.standard.set(soundOn, forKey: Key.sound) }
    }
    @Published var hapticsOn: Bool {
        didSet { UserDefaults.standard.set(hapticsOn, forKey: Key.haptics) }
    }
    /// Mirrors GameController.showDebug, so the overlay comes back after a relaunch.
    @Published var debugOverlay: Bool {
        didSet { UserDefaults.standard.set(debugOverlay, forKey: Key.debug) }
    }
    @Published private(set) var onboardingDone: Bool
    /// Drives the onboarding full-screen cover in ContentView.
    @Published var showOnboarding: Bool

    private init() {
        let d = UserDefaults.standard
        let done = AppSettings.readBool(d, Key.onboarding, fallback: false)
        alarmSensitivity = AlarmSensitivity(rawValue: d.string(forKey: Key.alarm) ?? "") ?? .normal
        smashSensitivity = SmashSensitivity(rawValue: d.string(forKey: Key.smash) ?? "") ?? .normal
        soundOn = AppSettings.readBool(d, Key.sound, fallback: true)
        hapticsOn = AppSettings.readBool(d, Key.haptics, fallback: true)
        debugOverlay = AppSettings.readBool(d, Key.debug, fallback: false)
        onboardingDone = done
        showOnboarding = !done
    }

    /// The platform's tunables with the player's sensitivity applied.
    func adjusted(_ base: FlyTunables) -> FlyTunables {
        return SensitivityMath.adjusted(base, alarm: alarmSensitivity, smash: smashSensitivity)
    }

    var sensitivitySummary: String {
        return "alarm \(alarmSensitivity.rawValue), smash \(smashSensitivity.rawValue)"
    }

    func finishOnboarding() {
        onboardingDone = true
        showOnboarding = false
        UserDefaults.standard.set(true, forKey: Key.onboarding)
    }

    func replayOnboarding() {
        showOnboarding = true
    }

    /// A missing or mistyped value gives the fallback rather than `false`.
    private static func readBool(_ d: UserDefaults, _ key: String, fallback: Bool) -> Bool {
        guard let value = d.object(forKey: key) else { return fallback }
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return fallback
    }
}
