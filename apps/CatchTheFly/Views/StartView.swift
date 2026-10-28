import SwiftUI

/// Start screen and round result: how to hold the device, how to play, the safety reminder.
struct StartView: View {
    @ObservedObject var game: GameController
    @State private var showSettings = false
    @State private var showGallery = false
    @State private var replayAfterSettings = false

    var body: some View {
        let s = game.state
        let finished = s.phase == .finished && s.lastRoundTime != nil
        ScrollView {
            VStack(spacing: 14) {
                AppTitleView()
                if finished, let t = s.lastRoundTime {
                    RoundCompleteView(roundTime: t, bestTime: s.bestTime, fliesPerRound: s.fliesPerRound,
                                      isNewBest: s.lastRoundWasBest)
                } else if let best = s.bestTime {
                    Text("Best time: \(GameText.clock(best))").font(.headline.monospacedDigit())
                }

                menuRow

                if !finished {
                    PostureSketch()
                        .frame(height: 170)
                        .accessibilityHidden(true)
                    steps
                }

                Label(GameText.safety, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.bold())
                    .foregroundStyle(Color.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    game.startRound()
                } label: {
                    Text(s.phase == .finished ? "Play again" : "Start round")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .accessibilityHint("Starts a round of \(s.fliesPerRound) flies")

                Text(s.cameraStatus)
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)
            }
            .padding(22)
            .frame(maxWidth: 560)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .padding()
        }
        .sheet(isPresented: $showSettings, onDismiss: {
            if replayAfterSettings {
                replayAfterSettings = false
                AppSettings.shared.replayOnboarding()
            }
        }) {
            SettingsView(game: game, settings: AppSettings.shared) {
                replayAfterSettings = true
            }
        }
        .sheet(isPresented: $showGallery) {
            GalleryView(gallery: SplatGallery.shared)
        }
    }

    /// How to play, the splat gallery and settings.
    private var menuRow: some View {
        HStack(spacing: 10) {
            Button {
                AppSettings.shared.replayOnboarding()
            } label: {
                Label("How to play", systemImage: "questionmark.circle")
            }
            .accessibilityHint("Shows the introduction again")
            Button {
                showGallery = true
            } label: {
                Label("Splats", systemImage: "square.grid.2x2")
            }
            .accessibilityLabel("Splat gallery")
            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .buttonStyle(.bordered)
        .font(.subheadline.bold())
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 6) {
            step("1", "Stand about 1 m from something busy: a bookshelf, a poster, a patterned cushion.")
            step("2", "Listen for the buzz and turn until you spot the fly. A yellow arrow points the way.")
            step("3", "Creep up slowly. Rush at it or swing the iPad about and it'll fly off.")
            step("4", "When you're close it takes off and hovers. Get it in the middle of the screen.")
            step("5", "Cover the camera with your hand, calmly, to smash it. Three flies make a round.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func step(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(n).font(.headline).frame(width: 22)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A simple drawing of the two postures: the iPad prototype, and the iPhone Duo held as an L
/// and folded shut (seen from above).
struct PostureSketch: View {
    var body: some View {
        Canvas { ctx, size in
            let w = Double(size.width)
            let h = Double(size.height)
            let ink = Color.primary
            let half = w / 2

            // Left: player, iPad, busy wall.
            let head = CGRect(x: half * 0.12, y: h * 0.25, width: 26, height: 26)
            ctx.stroke(Path(ellipseIn: head), with: .color(ink), lineWidth: 2)
            var torso = Path()
            torso.move(to: CGPoint(x: head.midX, y: head.maxY))
            torso.addLine(to: CGPoint(x: head.midX, y: h * 0.8))
            ctx.stroke(torso, with: .color(ink), lineWidth: 2)
            let pad = CGRect(x: half * 0.3, y: h * 0.3, width: 10, height: 52)
            ctx.fill(Path(roundedRect: pad, cornerRadius: 3), with: .color(ink))
            var view = Path()
            view.move(to: CGPoint(x: pad.maxX + 2, y: pad.midY))
            view.addLine(to: CGPoint(x: half * 0.78, y: pad.midY - 24))
            view.move(to: CGPoint(x: pad.maxX + 2, y: pad.midY))
            view.addLine(to: CGPoint(x: half * 0.78, y: pad.midY + 24))
            ctx.stroke(view, with: .color(.green), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            for i in 0..<6 {
                let r = CGRect(x: half * 0.8, y: h * 0.12 + Double(i) * h * 0.12, width: 12, height: h * 0.1)
                ctx.fill(Path(r), with: .color(i % 2 == 0 ? .orange : .blue))
            }
            ctx.draw(Text("iPad: about 1 m from a busy surface").font(.caption), at: CGPoint(x: half * 0.5, y: h * 0.93))

            // Right: Duo from above, half-open L, then folding.
            let hinge = CGPoint(x: half + half * 0.42, y: h * 0.62)
            var lShape = Path()
            lShape.move(to: CGPoint(x: hinge.x - half * 0.3, y: hinge.y))
            lShape.addLine(to: hinge)
            lShape.addLine(to: CGPoint(x: hinge.x, y: hinge.y - h * 0.4))
            ctx.stroke(lShape, with: .color(ink), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            var fold = Path()
            fold.addArc(center: hinge, radius: h * 0.3, startAngle: .degrees(-90), endAngle: .degrees(-160), clockwise: true)
            ctx.stroke(fold, with: .color(.orange), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
            let fly = CGRect(x: hinge.x - half * 0.16, y: hinge.y - h * 0.2, width: 9, height: 9)
            ctx.fill(Path(ellipseIn: fly), with: .color(.red))
            ctx.draw(Text("iPhone Duo: hold it as an L, fold gently").font(.caption), at: CGPoint(x: half * 1.5, y: h * 0.93))
        }
    }
}
