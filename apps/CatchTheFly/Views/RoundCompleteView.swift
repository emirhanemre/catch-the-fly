import SwiftUI

/// The round result on the start card: the time, the best time, and a little celebration for
/// a new best. The "Play again" button stays in StartView, just below this.
struct RoundCompleteView: View {
    let roundTime: Double
    let bestTime: Double?
    let fliesPerRound: Int
    let isNewBest: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(isNewBest ? "New best time!" : "Round complete!")
                .font(.title2.bold())
                .foregroundStyle(isNewBest ? Color.orange : Color.primary)
            Text(GameText.clock(roundTime))
                .font(.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit())
            Text("All \(fliesPerRound) flies caught. Lovely work.")
                .font(.headline)
                .multilineTextAlignment(.center)
            if let best = bestTime {
                Text(isNewBest ? "That's your fastest round yet." : "Best time: \(GameText.clock(best))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background {
            if isNewBest {
                CelebrationBurst()
                    .accessibilityHidden(true)
            }
        }
        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

/// Soft confetti in splat-and-fly colours, looping gently. Paused with Reduce Motion.
struct CelebrationBurst: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 1.0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                CelebrationArt.draw(&ctx, size: size, t: t)
            }
        }
        .allowsHitTesting(false)
    }
}

enum CelebrationArt {
    static func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let colours: [Color] = [.orange, .yellow, .green, .pink, .mint]
        let w = Double(size.width)
        let h = Double(size.height)
        guard w > 0, h > 0 else { return }
        var rng = FlyRNG(seed: 42)
        for i in 0..<28 {
            let x0 = rng.nextUnit() * w
            let speed = rng.nextDouble(from: 0.12, to: 0.3)
            let offset = rng.nextUnit()
            let r = rng.nextDouble(from: 2.5, to: 5)
            let fall = (t * speed + offset).truncatingRemainder(dividingBy: 1)
            let x = x0 + sin(t * 1.5 + Double(i)) * 8
            let y = fall * (h + 20) - 10
            let colour = colours[i % colours.count]
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                     with: .color(colour.opacity(0.55)))
        }
    }
}
