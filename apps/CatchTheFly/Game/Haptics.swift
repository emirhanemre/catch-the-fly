import UIKit

/// Haptic thud on a hit, a tap on a miss. Uses `init(style:view:)` (iOS 17.5), the initialiser
/// that isn't deprecated in iOS 27. iPads have no Taptic Engine, so nothing is felt there.
@MainActor
final class Haptics {
    private var heavy: UIImpactFeedbackGenerator?
    private var light: UIImpactFeedbackGenerator?

    func attach(to view: UIView) {
        heavy = UIImpactFeedbackGenerator(style: .heavy, view: view)
        light = UIImpactFeedbackGenerator(style: .light, view: view)
        heavy?.prepare()
    }

    func hit() {
        heavy?.impactOccurred()
        heavy?.prepare()
    }

    func miss() {
        light?.impactOccurred()
    }
}
