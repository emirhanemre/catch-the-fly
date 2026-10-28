import SwiftUI

enum GameText {
    static let safety = "Watch your surroundings: look up before you move. Smash calmly, never slam."

    /// "0:23.4"
    static func clock(_ seconds: Double) -> String {
        let t = max(0, seconds.isFinite ? seconds : 0)
        let minutes = Int(t) / 60
        let rest = t - Double(minutes * 60)
        return String(format: "%ld:%04.1f", minutes, rest)
    }
}

/// Round, fly n/3, timer, best time, the buttons and the safety line.
struct HUDView: View {
    @ObservedObject var game: GameController

    var body: some View {
        let s = game.state
        VStack(spacing: 8) {
            if s.phase == .playing {
                HStack(spacing: 10) {
                    chip("Round \(s.roundNumber)")
                    chip("Fly \(min(s.fliesCaught + 1, s.fliesPerRound))/\(s.fliesPerRound)")
                    chip(GameText.clock(s.elapsed))
                    chip("Best " + (s.bestTime.map { GameText.clock($0) } ?? "–"))
                }
            }
            if game.showDebug {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(s.debugLines.enumerated()), id: \.offset) { item in
                        Text(item.element)
                    }
                    Text("camera: \(s.cameraStatus)")
                    if !s.smashLines.isEmpty {
                        Text("smash events:").bold()
                        ForEach(Array(s.smashLines.enumerated()), id: \.offset) { item in
                            Text(item.element)
                        }
                    }
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.white)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
            }
            Spacer()
            HStack(spacing: 10) {
                if s.phase == .playing {
                    Button {
                        game.pressDebugSmash()
                    } label: {
                        Label("Smash (debug)", systemImage: "hand.raised.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    Button("End round") {
                        game.endRound()
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
                if game.showDebug {
                    Button("Reset tracking") {
                        game.resetTracking()
                    }
                    .buttonStyle(.bordered)
                }
                Button(game.showDebug ? "Hide debug" : "Debug") {
                    game.showDebug.toggle()
                }
                .buttonStyle(.bordered)
                ShareLink(item: game.logFileURL) {
                    Label("Share log", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
            .tint(.white)
            Text(GameText.safety)
                .font(.footnote)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.45), in: Capsule())
        }
        .padding()
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.headline.monospacedDigit())
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.5), in: Capsule())
    }
}
