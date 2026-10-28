import SwiftUI

struct ContentView: View {
    @StateObject private var game = GameController()
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ZStack {
            CameraPreview(game: game)
                .ignoresSafeArea()
            FlyOverlay(state: game.state)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            if game.showDebug {
                DebugOverlay(state: game.state)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            ToastLayer(state: game.state, showHitMiss: Platform.showsHitMissToasts)
            if game.state.phase != .playing {
                StartView(game: game)
            }
            // Above the start card, so Debug and Share log stay reachable there too.
            HUDView(game: game)
        }
        .background(Color.black)
        .modifier(Platform.coverDisplay(game: game))
        .onAppear {
            game.start()
        }
        .onChange(of: scenePhase) { _, newPhase in
            game.scenePhaseChanged(newPhase)
        }
        .fullScreenCover(isPresented: $settings.showOnboarding) {
            OnboardingView(posture: Platform.onboardingPosture()) {
                settings.finishOnboarding()
            }
        }
    }
}
