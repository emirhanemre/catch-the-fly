import Foundation

/// FlyCore's BestTimeStore over UserDefaults.
struct DefaultsBestTimeStore: BestTimeStore {
    static let key = "CatchTheFly.bestRoundTime"

    func loadBestTime() -> Double? {
        let v = UserDefaults.standard.double(forKey: DefaultsBestTimeStore.key)
        return (v.isFinite && v > 0) ? v : nil
    }

    func saveBestTime(_ seconds: Double) {
        guard seconds.isFinite, seconds > 0 else { return }
        UserDefaults.standard.set(seconds, forKey: DefaultsBestTimeStore.key)
    }

    /// Settings: "Reset best time".
    func clearBestTime() {
        UserDefaults.standard.removeObject(forKey: DefaultsBestTimeStore.key)
    }
}
