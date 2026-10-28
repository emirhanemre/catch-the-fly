import SwiftUI

/// Draws FlyCore's output over the camera picture: the fly, splats, the smug fly-off and an
/// arrow towards an off-screen fly. No image assets: everything is Path drawing.
struct FlyOverlay: View {
    let state: GameViewState

    var body: some View {
        Canvas { context, size in
            FlyArtist.drawScene(&context, size: size, state: state)
        }
    }
}

/// Nonisolated on purpose: pure drawing into a GraphicsContext, callable from any Canvas renderer
/// whatever isolation the SDK gives that closure.
enum FlyArtist {
    /// Exaggerated fly body length (m) used to size the sprite by distance.
    static let flyLength = 0.03

    static func drawScene(_ ctx: inout GraphicsContext, size: CGSize, state: GameViewState) {
        let w = Double(size.width)
        let h = Double(size.height)
        guard w > 0, h > 0 else { return }

        for splat in state.splats {
            let age = state.time - splat.time
            let alpha = age < 3 ? 1.0 : max(0, 1 - (age - 3))
            drawSplat(&ctx, at: CGPoint(x: splat.x * w, y: splat.y * h), radius: min(w, h) * 0.07,
                      seed: splat.id, alpha: alpha, showWord: age < 1.5)
        }

        guard let fly = state.fly, fly.state != .smashed else { return }
        let smug = state.time < state.smugUntil
        if let p = fly.screenPosition, p.isOnScreen {
            let pixels = w * state.focalWidth * flyLength / max(fly.cameraDistance, 0.05)
            let s = min(220, max(14, pixels))
            let centre = CGPoint(x: p.x * w, y: p.y * h)
            drawFly(&ctx, at: centre, size: s, time: state.time, state: fly.state, smug: smug)
            if smug {
                drawBubble(&ctx, text: "Too slow!", near: centre, offset: s)
            }
        } else {
            drawOffScreenArrow(&ctx, size: size, fly: fly)
            if smug, let sp = state.smugPoint, sp.isOnScreen {
                drawBubble(&ctx, text: "Ha! Missed.", near: CGPoint(x: sp.x * w, y: sp.y * h), offset: 30)
            }
        }
    }

    static func drawFly(_ ctx: inout GraphicsContext, at p: CGPoint, size s: Double, time: Double, state: FlyState, smug: Bool) {
        let flying = state != .landed
        // Small shadow below, further away when flying.
        let lift = flying ? s * 0.7 : s * 0.35
        let shadow = CGRect(x: p.x - s * 0.4, y: p.y + lift, width: s * 0.8, height: s * 0.22)
        ctx.fill(Path(ellipseIn: shadow), with: .color(.black.opacity(flying ? 0.22 : 0.35)))

        var body = ctx
        body.translateBy(x: p.x, y: p.y)
        let wobble = flying ? 0.25 * sin(time * 9) : 0.08 * sin(time * 1.7)
        body.rotate(by: .radians(wobble + (smug ? 0.35 : 0)))

        // Wings: a fast blur when flying, folded back and twitching when landed.
        let flap = flying ? sin(time * 2 * Double.pi * 23) : 0.15 * sin(time * 4)
        for side in [-1.0, 1.0] {
            var wing = body
            let spread = flying ? (0.75 + 0.55 * flap) : (0.28 + 0.05 * flap)
            wing.rotate(by: .radians(side * spread))
            let rect = CGRect(x: -s * 0.17, y: -s * 0.78, width: s * 0.34, height: s * 0.72)
            let path = Path(ellipseIn: rect)
            wing.fill(path, with: .color(Color(white: 0.92).opacity(flying ? 0.45 : 0.6)))
            wing.stroke(path, with: .color(.black.opacity(0.35)), lineWidth: max(0.5, s * 0.02))
        }

        // Body, head, eyes.
        let abdomen = Path(ellipseIn: CGRect(x: -s * 0.2, y: -s * 0.15, width: s * 0.4, height: s * 0.6))
        body.fill(abdomen, with: .color(Color(red: 0.12, green: 0.13, blue: 0.1)))
        let stripe = Path(ellipseIn: CGRect(x: -s * 0.16, y: s * 0.12, width: s * 0.32, height: s * 0.08))
        body.fill(stripe, with: .color(Color(white: 0.35)))
        let thorax = Path(ellipseIn: CGRect(x: -s * 0.18, y: -s * 0.32, width: s * 0.36, height: s * 0.3))
        body.fill(thorax, with: .color(Color(red: 0.2, green: 0.2, blue: 0.17)))
        let head = Path(ellipseIn: CGRect(x: -s * 0.15, y: -s * 0.5, width: s * 0.3, height: s * 0.22))
        body.fill(head, with: .color(Color(red: 0.15, green: 0.15, blue: 0.13)))
        for side in [-1.0, 1.0] {
            let eye = Path(ellipseIn: CGRect(x: side * s * 0.09 - s * 0.075, y: -s * 0.53, width: s * 0.15, height: s * 0.15))
            body.fill(eye, with: .color(Color(red: 0.75, green: 0.1, blue: 0.08)))
        }
        if smug {
            // A smug little grin.
            var grin = Path()
            grin.move(to: CGPoint(x: -s * 0.07, y: -s * 0.38))
            grin.addQuadCurve(to: CGPoint(x: s * 0.07, y: -s * 0.38), control: CGPoint(x: 0, y: -s * 0.31))
            body.stroke(grin, with: .color(.white), lineWidth: max(1, s * 0.03))
        }
    }

    static func drawSplat(_ ctx: inout GraphicsContext, at p: CGPoint, radius r: Double, seed: Int, alpha: Double, showWord: Bool) {
        var layer = ctx
        layer.opacity = alpha
        var rng = FlyRNG(seed: UInt64(seed &* 7919 &+ 17))
        let goo = Color(red: 0.32, green: 0.36, blue: 0.12)
        layer.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.6, y: p.y - r * 0.5, width: r * 1.2, height: r)), with: .color(goo))
        for _ in 0..<9 {
            let a = rng.nextDouble(from: 0, to: 2 * Double.pi)
            let d = rng.nextDouble(from: r * 0.5, to: r * 1.3)
            let blob = rng.nextDouble(from: r * 0.12, to: r * 0.32)
            let c = CGPoint(x: p.x + cos(a) * d, y: p.y + sin(a) * d)
            layer.fill(Path(ellipseIn: CGRect(x: c.x - blob / 2, y: c.y - blob / 2, width: blob, height: blob)), with: .color(goo))
        }
        for _ in 0..<3 {
            let a = rng.nextDouble(from: 0, to: 2 * Double.pi)
            let d = rng.nextDouble(from: 0, to: r * 0.4)
            let blob = r * 0.18
            let c = CGPoint(x: p.x + cos(a) * d, y: p.y + sin(a) * d)
            layer.fill(Path(ellipseIn: CGRect(x: c.x - blob / 2, y: c.y - blob / 2, width: blob, height: blob)),
                       with: .color(Color(red: 0.6, green: 0.08, blue: 0.05)))
        }
        if showWord {
            let word = Text("Splat!").font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(Color.white)
            layer.draw(word, at: CGPoint(x: p.x, y: p.y - r * 1.6))
        }
    }

    static func drawBubble(_ ctx: inout GraphicsContext, text: String, near p: CGPoint, offset: Double) {
        let at = CGPoint(x: p.x + offset * 0.9 + 40, y: p.y - offset * 0.9 - 20)
        let rect = CGRect(x: at.x - 70, y: at.y - 20, width: 140, height: 40)
        let bubble = Path(roundedRect: rect, cornerRadius: 14)
        ctx.fill(bubble, with: .color(.white.opacity(0.92)))
        ctx.draw(Text(text).font(.headline).foregroundStyle(Color.black), at: at)
    }

    static func drawOffScreenArrow(_ ctx: inout GraphicsContext, size: CGSize, fly: FlyRenderState) {
        let w = Double(size.width)
        let h = Double(size.height)
        let toRight = fly.bearing >= 0
        var y = h / 2
        if let p = fly.screenPosition {
            y = min(h - 80, max(80, p.y * h))
        }
        let x = toRight ? w - 34 : 34
        let dir = toRight ? 1.0 : -1.0
        var arrow = Path()
        arrow.move(to: CGPoint(x: x + dir * 22, y: y))
        arrow.addLine(to: CGPoint(x: x - dir * 14, y: y - 20))
        arrow.addLine(to: CGPoint(x: x - dir * 14, y: y + 20))
        arrow.closeSubpath()
        ctx.fill(arrow, with: .color(.yellow.opacity(0.85)))
        ctx.stroke(arrow, with: .color(.black.opacity(0.5)), lineWidth: 1.5)
        let label = abs(fly.bearing) > Double.pi / 2 ? "Behind you" : "This way"
        ctx.draw(Text(label).font(.caption.bold()).foregroundStyle(Color.yellow), at: CGPoint(x: toRight ? x - 30 : x + 30, y: y + 36))
    }
}

/// Debug overlay: tracked patches, the patch the fly is using, and the hit region.
struct DebugOverlay: View {
    let state: GameViewState

    var body: some View {
        Canvas { context, size in
            let w = Double(size.width)
            let h = Double(size.height)
            let hr = state.hitRect
            if hr.width > 0 {
                let rect = CGRect(x: hr.minX * w, y: hr.minY * h, width: hr.width * w, height: hr.height * h)
                context.stroke(Path(rect), with: .color(.red.opacity(0.8)), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                context.draw(Text("hit region").font(.caption2).foregroundStyle(Color.red), at: CGPoint(x: rect.midX, y: rect.minY + 10))
            }
            for p in state.patches {
                let rect = CGRect(x: p.rect.minX * w, y: p.rect.minY * h, width: p.rect.width * w, height: p.rect.height * h)
                let colour: Color = p.isFlySpot ? .green : .yellow
                context.stroke(Path(rect), with: .color(colour), lineWidth: p.isFlySpot ? 3 : 1.5)
                let label = "#\(p.id) x\(FlyLog.fixed(p.ratio, decimals: 2)) \(FlyLog.fixed(p.distance, decimals: 2))m c\(FlyLog.fixed(p.confidence, decimals: 2))"
                context.draw(Text(label).font(.system(size: 11, design: .monospaced)).foregroundStyle(colour),
                             at: CGPoint(x: rect.midX, y: rect.maxY + 9))
            }
        }
    }
}
