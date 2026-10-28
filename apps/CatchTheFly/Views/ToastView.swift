import SwiftUI

/// The latest game toast ("Splat!", "Missed!", "Too fast"), high on the screen, on a dark
/// capsule so it reads over any camera picture. It goes by itself: GameViewState is published
/// every frame and GameToast.isVisible compares game time.
struct ToastLayer: View {
    let state: GameViewState
    /// False on the Duo, whose DuoResultBanner already shows hits and misses.
    let showHitMiss: Bool

    var body: some View {
        VStack {
            Spacer()
                .frame(height: 96)
            if let toast = visibleToast {
                Text(toast.text)
                    .font(.title3.bold())
                    .foregroundStyle(ToastLayer.colour(for: toast.kind))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.72), in: Capsule())
                    .padding(.horizontal, 16)
                    .id(toast.id)
            }
            Spacer()
        }
        .allowsHitTesting(false)
    }

    private var visibleToast: GameToast? {
        guard state.phase == .playing, let t = state.toast, t.isVisible(at: state.time) else { return nil }
        if !showHitMiss && t.kind != .spooked { return nil }
        return t
    }

    static func colour(for kind: GameToast.Kind) -> Color {
        switch kind {
        case .splat: return Color.green
        case .missed: return Color.orange
        case .spooked: return Color.yellow
        }
    }
}
