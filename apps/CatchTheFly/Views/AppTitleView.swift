import SwiftUI

/// The start screen's title: the name in heavy rounded type, with a little fly buzzing along a
/// dotted flight path above it. Drawn, no image assets.
struct AppTitleView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
                let t = reduceMotion ? 0.6 : timeline.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    TitleArt.draw(&ctx, size: size, t: t)
                }
            }
            .frame(height: 34)
            .accessibilityHidden(true)
            Text("Catch the Fly")
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Nonisolated on purpose: pure drawing into a GraphicsContext, callable from any Canvas renderer
/// whatever isolation the SDK gives that closure.
enum TitleArt {
    static func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let w = Double(size.width)
        let h = Double(size.height)
        guard w > 0, h > 0 else { return }
        // A lazy wave across the middle of the width.
        let left = w * 0.25
        let span = w * 0.5
        func point(_ u: Double) -> CGPoint {
            return CGPoint(x: left + span * u, y: h * 0.5 + sin(u * Double.pi * 3) * h * 0.25)
        }
        var trail = Path()
        trail.move(to: point(0))
        for i in 1...40 {
            trail.addLine(to: point(Double(i) / 40))
        }
        ctx.stroke(trail, with: .color(Color.secondary.opacity(0.6)), style: StrokeStyle(lineWidth: 1.5, dash: [2, 5]))
        // The fly runs along it and back, 4 s each way.
        let cycle = (t / 4).truncatingRemainder(dividingBy: 2)
        let u = cycle < 1 ? cycle : 2 - cycle
        FlyArtist.drawFly(&ctx, at: point(u), size: 22, time: t, state: .wandering, smug: false)
    }
}
