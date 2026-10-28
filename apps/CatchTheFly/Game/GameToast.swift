import Foundation

/// A short message over the camera view, driven by FlyCore's cues. GameController keeps the
/// latest one in GameViewState; ToastLayer shows it for `lifetime` seconds of game time.
struct GameToast: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case splat
        case missed
        case spooked
    }

    static let lifetime = 1.8

    let id: Int
    let kind: Kind
    /// Game clock (CACurrentMediaTime), the same clock as GameViewState.time.
    let time: Double

    var text: String {
        switch kind {
        case .splat: return "Splat!"
        case .missed: return "Missed! It got away."
        case .spooked: return "Too fast – it got spooked. Creep up slowly."
        }
    }

    func isVisible(at now: Double) -> Bool {
        let age = now - time
        return age >= 0 && age < GameToast.lifetime
    }
}
