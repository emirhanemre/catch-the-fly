import SwiftUI

/// Which way to hold the device. Platform.onboardingPosture() picks it for the current build.
enum OnboardingPosture: Sendable {
    /// iPad prototype: rear camera, cover the lens with your hand to swat.
    case iPad
    /// iPhone Duo held like a book standing up, small cover screen facing you.
    case duoPostureA
    /// iPhone Duo opened wide, big screen facing you.
    case duoPostureB
}

/// First-launch introduction, four short pages. Re-opened from the start screen ("How to play")
/// and from Settings. Fixed dark colours so it reads the same in light and dark mode.
struct OnboardingView: View {
    let posture: OnboardingPosture
    let onFinish: () -> Void
    @State private var page = 0

    private static let pageCount = 4

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Spacer()
                Button("Skip") {
                    onFinish()
                }
                .font(.headline)
                .foregroundStyle(Color.white)
                .accessibilityHint("Closes the introduction")
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            TabView(selection: $page) {
                OnboardingPage(art: .posture(posture), title: OnboardingCopy.postureTitle(posture),
                               lines: OnboardingCopy.postureLines(posture))
                    .tag(0)
                OnboardingPage(art: .flyBehaviour, title: "Sneak up, then swat",
                               lines: OnboardingCopy.flyLines(posture))
                    .tag(1)
                OnboardingPage(art: .safety, title: "Play it safe",
                               lines: OnboardingCopy.safetyLines(posture))
                    .tag(2)
                OnboardingPage(art: .ready, title: "Ready?",
                               lines: OnboardingCopy.readyLines)
                    .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < OnboardingView.pageCount - 1 {
                    withAnimation {
                        page += 1
                    }
                } else {
                    onFinish()
                }
            } label: {
                Text(page < OnboardingView.pageCount - 1 ? "Next" : "Let's catch a fly")
                    .font(.title3.bold())
                    .frame(maxWidth: 420)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .accessibilityHint(page < OnboardingView.pageCount - 1 ? "Shows the next page" : "Closes the introduction")
        }
        .background(OnboardingView.backdrop.ignoresSafeArea())
    }

    static let backdrop = Color(red: 0.07, green: 0.09, blue: 0.11)
}

/// One page: the looping drawing, a title and a few short lines.
struct OnboardingPage: View {
    let art: OnboardingArt.Kind
    let title: String
    let lines: [String]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                OnboardingAnimation(kind: art)
                    .frame(height: 230)
                    .frame(maxWidth: 520)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
                Text(title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                                .padding(.top, 7)
                                .accessibilityHidden(true)
                            Text(item.element)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: 520, alignment: .leading)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 48)
        }
    }
}

/// The page's drawing, looping. With Reduce Motion it holds one clear frame.
struct OnboardingAnimation: View {
    let kind: OnboardingArt.Kind
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? kind.stillTime : timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                OnboardingArt.draw(kind, ctx: &ctx, size: size, t: t)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.accessibilityText)
    }
}

// MARK: - Words

enum OnboardingCopy {
    static func postureTitle(_ p: OnboardingPosture) -> String {
        switch p {
        case .iPad: return "Hold the iPad up like a window"
        case .duoPostureA: return "Hold it like a book"
        case .duoPostureB: return "Open it wide"
        }
    }

    static func postureLines(_ p: OnboardingPosture) -> [String] {
        switch p {
        case .iPad:
            return ["Point the back camera at the room, about 1 m from something busy: a bookshelf, a poster, a patterned cushion.",
                    "To swat the fly, calmly cover the camera with your hand.",
                    "No hand free? The Smash button does the same."]
        case .duoPostureA:
            return ["Open the phone halfway, like a book standing up, hinge upright.",
                    "Turn it so the small cover screen faces you. That's your viewfinder.",
                    "Get the fly into the corner of the L, then fold the far half shut gently, like a slow clap."]
        case .duoPostureB:
            return ["Open the phone wide, like a book you're reading, big screen facing you.",
                    "The fly sits right across the fold.",
                    "Close the book on it gently to swat it."]
        }
    }

    static func flyLines(_ p: OnboardingPosture) -> [String] {
        let swat: String
        switch p {
        case .iPad: swat = "While it hovers, keep it in the middle and cover the camera. Splat!"
        case .duoPostureA: swat = "While it hovers, keep it on the hinge side and fold. Splat!"
        case .duoPostureB: swat = "While it hovers, keep it over the fold and close the book. Splat!"
        }
        return ["Listen for the buzz and turn until you spot the fly. A yellow arrow points the way.",
                "Creep up slowly. Rush at it or swing about and it'll get spooked and fly off.",
                "When you're close, it takes off and hovers for a few seconds. That's your moment.",
                swat]
    }

    static func safetyLines(_ p: OnboardingPosture) -> [String] {
        let calm: String
        switch p {
        case .iPad: calm = "Cover the lens calmly. A gentle hand catches it just as well as a quick one."
        case .duoPostureA, .duoPostureB: calm = "Fold at a normal speed. Never slam it: the phone is precious, and a gentle fold catches the fly just as well."
        }
        return ["Watch your surroundings. Look up before you move, and keep clear of people, pets, stairs and anything breakable.",
                calm,
                "Take a break if your arms get tired."]
    }

    static let readyLines = [
        "Three flies make a round. Your best time is kept.",
        "Every fly you catch goes into your splat gallery.",
        "Settings has fly sensitivity, sound and haptics. You can replay this introduction from there too."
    ]
}

// MARK: - Drawings

/// Nonisolated on purpose: pure drawing into a GraphicsContext, callable from any Canvas renderer
/// whatever isolation the SDK gives that closure.
enum OnboardingArt {
    enum Kind: Equatable, Sendable {
        case posture(OnboardingPosture)
        case flyBehaviour
        case safety
        case ready

        /// The frame held when Reduce Motion is on.
        var stillTime: Double {
            switch self {
            case .posture: return 0.5
            case .flyBehaviour: return 3.0
            case .safety: return 1.0
            case .ready: return 1.0
            }
        }

        var accessibilityText: String {
            switch self {
            case .posture(.iPad):
                return "Drawing: a player holds an iPad up to the room, and a hand calmly covers the camera to swat the fly."
            case .posture(.duoPostureA):
                return "Drawing, seen from above: the phone half open like a book standing up, the small screen facing the player, the far half folding gently shut on the fly."
            case .posture(.duoPostureB):
                return "Drawing, seen from above: the phone opened wide, the big screen facing the player, the book closing gently on the fly."
            case .flyBehaviour:
                return "Drawing: you creep up on the fly, it takes off and hovers, then it's swatted."
            case .safety:
                return "Drawing: an eye looking around the room."
            case .ready:
                return "Drawing: a fly buzzing about."
            }
        }
    }

    static let ink = Color.white
    static let accent = Color.green
    static let warm = Color.orange

    static func draw(_ kind: Kind, ctx: inout GraphicsContext, size: CGSize, t: Double) {
        guard size.width > 0, size.height > 0 else { return }
        switch kind {
        case .posture(.iPad): drawIPad(&ctx, size: size, t: t)
        case .posture(.duoPostureA): drawDuoA(&ctx, size: size, t: t)
        case .posture(.duoPostureB): drawDuoB(&ctx, size: size, t: t)
        case .flyBehaviour: drawFlyBehaviour(&ctx, size: size, t: t)
        case .safety: drawSafety(&ctx, size: size, t: t)
        case .ready: drawReady(&ctx, size: size, t: t)
        }
    }

    // MARK: Helpers

    /// 0...1 through a loop of `period` seconds.
    static func loop(_ t: Double, _ period: Double) -> Double {
        let p = t.truncatingRemainder(dividingBy: period) / period
        return p < 0 ? p + 1 : p
    }

    static func smooth(_ x: Double) -> Double {
        let c = min(1, max(0, x))
        return c * c * (3 - 2 * c)
    }

    /// 0 before `a`, 1 after `b`, eased between.
    static func ramp(_ p: Double, _ a: Double, _ b: Double) -> Double {
        return smooth((p - a) / max(0.0001, b - a))
    }

    static func label(_ ctx: inout GraphicsContext, _ text: String, at p: CGPoint) {
        ctx.draw(Text(text).font(.caption.bold()).foregroundStyle(Color.white.opacity(0.85)), at: p)
    }

    static func player(_ ctx: inout GraphicsContext, at p: CGPoint) {
        let head = CGRect(x: p.x - 13, y: p.y - 13, width: 26, height: 26)
        ctx.stroke(Path(ellipseIn: head), with: .color(ink), lineWidth: 2)
        // Nose: which way the player faces (up the drawing).
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 19, width: 6, height: 6)), with: .color(ink))
        var shoulders = Path()
        shoulders.move(to: CGPoint(x: p.x - 28, y: p.y + 18))
        shoulders.addQuadCurve(to: CGPoint(x: p.x + 28, y: p.y + 18), control: CGPoint(x: p.x, y: p.y + 4))
        ctx.stroke(shoulders, with: .color(ink), lineWidth: 2)
    }

    static func viewCone(_ ctx: inout GraphicsContext, from p: CGPoint, towards angle: Double, length: Double, dark: Double) {
        var cone = Path()
        cone.move(to: p)
        cone.addLine(to: CGPoint(x: p.x + cos(angle - 0.35) * length, y: p.y + sin(angle - 0.35) * length))
        cone.addLine(to: CGPoint(x: p.x + cos(angle + 0.35) * length, y: p.y + sin(angle + 0.35) * length))
        cone.closeSubpath()
        ctx.fill(cone, with: .color(accent.opacity(0.12 * (1 - dark))))
        ctx.stroke(cone, with: .color(accent.opacity(0.6 * (1 - dark) + 0.15)), style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
    }

    static func hoverOffset(_ t: Double, radius: Double) -> CGPoint {
        return CGPoint(x: sin(t * 2.4) * radius, y: sin(t * 4.8) * radius * 0.5)
    }

    // MARK: iPad

    /// Seen from above: player, iPad, the camera's view, the fly; a hand comes in and covers
    /// the lens, the view goes dark, splat; the hand goes away.
    static func drawIPad(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let w = Double(size.width)
        let h = Double(size.height)
        let p = loop(t, 6)
        let cx = w / 2
        label(&ctx, "Seen from above", at: CGPoint(x: cx, y: 14))

        player(&ctx, at: CGPoint(x: cx, y: h * 0.86))
        label(&ctx, "You", at: CGPoint(x: cx + 46, y: h * 0.88))

        let padY = h * 0.66
        let pad = CGRect(x: cx - 48, y: padY - 5, width: 96, height: 10)
        ctx.fill(Path(roundedRect: pad, cornerRadius: 3), with: .color(ink))
        let lens = CGPoint(x: cx + 30, y: padY - 6)

        let handIn = ramp(p, 0.42, 0.55) * (1 - ramp(p, 0.82, 0.95))
        viewCone(&ctx, from: lens, towards: -Double.pi / 2, length: h * 0.5, dark: handIn)

        let flyPos = CGPoint(x: cx + 30, y: h * 0.3)
        let splatted = p > 0.55 && p < 0.97
        if splatted {
            let fade = 1 - ramp(p, 0.85, 0.97)
            FlyArtist.drawSplat(&ctx, at: flyPos, radius: 16, seed: 3, alpha: fade, showWord: false)
            label(&ctx, "Splat!", at: CGPoint(x: flyPos.x, y: flyPos.y - 30))
        } else {
            let o = hoverOffset(t, radius: 10)
            FlyArtist.drawFly(&ctx, at: CGPoint(x: flyPos.x + o.x, y: flyPos.y + o.y), size: 26, time: t, state: .hovering, smug: false)
        }

        // The hand: an open palm drifting in from the right, calmly.
        let rest = CGPoint(x: cx + 120, y: padY + 4)
        let over = CGPoint(x: lens.x + 4, y: lens.y - 12)
        let hp = CGPoint(x: rest.x + (over.x - rest.x) * handIn, y: rest.y + (over.y - rest.y) * handIn)
        drawHand(&ctx, at: hp)
        if handIn > 0.9 {
            label(&ctx, "Cover the camera, calmly", at: CGPoint(x: cx, y: h * 0.53))
        }
    }

    static func drawHand(_ ctx: inout GraphicsContext, at p: CGPoint) {
        let skin = Color(red: 0.95, green: 0.76, blue: 0.6)
        let palm = CGRect(x: p.x - 16, y: p.y - 12, width: 32, height: 26)
        ctx.fill(Path(roundedRect: palm, cornerRadius: 10), with: .color(skin))
        for i in 0..<4 {
            let finger = CGRect(x: p.x - 15 + Double(i) * 8, y: p.y - 26, width: 6, height: 18)
            ctx.fill(Path(roundedRect: finger, cornerRadius: 3), with: .color(skin))
        }
        let thumb = CGRect(x: p.x - 26, y: p.y - 6, width: 14, height: 7)
        ctx.fill(Path(roundedRect: thumb, cornerRadius: 3.5), with: .color(skin))
    }

    // MARK: Duo, Posture A

    /// Seen from above: the static half faces the player (cover screen on its outside), the far
    /// half sticks out forwards, the fly hovers in the corner of the L, and the far half folds
    /// gently onto the static half.
    static func drawDuoA(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let w = Double(size.width)
        let h = Double(size.height)
        let p = loop(t, 7)
        let cx = w / 2
        label(&ctx, "Seen from above", at: CGPoint(x: cx, y: 14))
        player(&ctx, at: CGPoint(x: cx, y: h * 0.86))
        label(&ctx, "You", at: CGPoint(x: cx + 46, y: h * 0.88))

        let len = min(w * 0.32, h * 0.42)
        let hinge = CGPoint(x: cx + len / 2, y: h * 0.62)
        let staticEnd = CGPoint(x: hinge.x - len, y: hinge.y)

        // Fold angle: open (90 degrees) -> gently shut -> hold -> open again.
        let closing = ramp(p, 0.38, 0.62) * (1 - ramp(p, 0.84, 0.97))
        let angle = (Double.pi / 2) * (1 - closing) + 0.05 * closing
        let farEnd = CGPoint(x: hinge.x - cos(angle) * len, y: hinge.y - sin(angle) * len)

        // The inner camera on the inside of the static half, looking into the room.
        let lens = CGPoint(x: hinge.x - len * 0.5, y: hinge.y - 4)
        viewCone(&ctx, from: lens, towards: -Double.pi / 2, length: h * 0.45, dark: closing)

        // Fly in the corner of the L, or a splat once it's folded on.
        let flyPos = CGPoint(x: hinge.x - len * 0.4, y: hinge.y - len * 0.42)
        if p > 0.62 && p < 0.97 {
            let fade = 1 - ramp(p, 0.86, 0.97)
            FlyArtist.drawSplat(&ctx, at: CGPoint(x: flyPos.x, y: hinge.y - 8), radius: 14, seed: 5, alpha: fade, showWord: false)
            label(&ctx, "Splat!", at: CGPoint(x: flyPos.x, y: hinge.y - 46))
        } else {
            let o = hoverOffset(t, radius: 8)
            FlyArtist.drawFly(&ctx, at: CGPoint(x: flyPos.x + o.x, y: flyPos.y + o.y), size: 24, time: t, state: .hovering, smug: false)
        }

        // The two halves.
        var halves = Path()
        halves.move(to: staticEnd)
        halves.addLine(to: hinge)
        halves.addLine(to: farEnd)
        ctx.stroke(halves, with: .color(ink), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
        // The cover screen, on the side facing the player.
        var cover = Path()
        cover.move(to: CGPoint(x: staticEnd.x + 6, y: hinge.y + 6))
        cover.addLine(to: CGPoint(x: hinge.x - 6, y: hinge.y + 6))
        ctx.stroke(cover, with: .color(Color.cyan), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        label(&ctx, "Small screen faces you", at: CGPoint(x: hinge.x - len / 2, y: hinge.y + 22))

        if closing > 0.05 && closing < 0.98 {
            label(&ctx, "Fold gently", at: CGPoint(x: hinge.x + 44, y: hinge.y - len * 0.6))
        }
    }

    // MARK: Duo, Posture B

    /// Seen from above: the book open wide towards the player, the fly across the fold, and the
    /// two halves closing gently on it.
    static func drawDuoB(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let w = Double(size.width)
        let h = Double(size.height)
        let p = loop(t, 7)
        let cx = w / 2
        label(&ctx, "Seen from above", at: CGPoint(x: cx, y: 14))
        player(&ctx, at: CGPoint(x: cx, y: h * 0.86))
        label(&ctx, "You", at: CGPoint(x: cx + 46, y: h * 0.88))

        let len = min(w * 0.3, h * 0.4)
        let hinge = CGPoint(x: cx, y: h * 0.3)
        let closing = ramp(p, 0.38, 0.62) * (1 - ramp(p, 0.84, 0.97))
        // Each half is 70 degrees off the centre line when open, nearly 0 when shut.
        let spread = (70.0 * Double.pi / 180) * (1 - closing) + 0.03 * closing
        let down = Double.pi / 2
        let leftEnd = CGPoint(x: hinge.x + cos(down + spread) * len, y: hinge.y + sin(down + spread) * len)
        let rightEnd = CGPoint(x: hinge.x + cos(down - spread) * len, y: hinge.y + sin(down - spread) * len)

        // The rear cameras look into the room, away from the player.
        viewCone(&ctx, from: CGPoint(x: hinge.x, y: hinge.y - 6), towards: -Double.pi / 2, length: h * 0.26, dark: 0)

        let flyPos = CGPoint(x: hinge.x, y: hinge.y + len * 0.45)
        if p > 0.62 && p < 0.97 {
            let fade = 1 - ramp(p, 0.86, 0.97)
            FlyArtist.drawSplat(&ctx, at: flyPos, radius: 12, seed: 8, alpha: fade, showWord: false)
            label(&ctx, "Splat!", at: CGPoint(x: flyPos.x + 46, y: flyPos.y))
        } else {
            let o = hoverOffset(t, radius: 6)
            FlyArtist.drawFly(&ctx, at: CGPoint(x: flyPos.x + o.x, y: flyPos.y + o.y), size: 22, time: t, state: .hovering, smug: false)
        }

        var book = Path()
        book.move(to: leftEnd)
        book.addLine(to: hinge)
        book.addLine(to: rightEnd)
        ctx.stroke(book, with: .color(ink), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
        if closing < 0.05 {
            label(&ctx, "Big screen faces you", at: CGPoint(x: cx, y: hinge.y + len + 14))
        } else if closing < 0.98 {
            label(&ctx, "Close it gently", at: CGPoint(x: cx, y: hinge.y + len + 14))
        }
    }

    // MARK: How the fly behaves

    /// A busy poster with the fly on it. 1: you creep closer (it grows). 2: it hovers.
    /// 3: a fold sweeps over it. Splat.
    static func drawFlyBehaviour(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let w = Double(size.width)
        let h = Double(size.height)
        let p = loop(t, 8)
        let cx = w / 2
        let cy = h * 0.52

        let approach = ramp(p, 0.0, 0.32)
        let scale = 0.6 + 0.4 * approach
        // The poster: a grid of coloured tiles.
        let tile = 18 * scale
        let colours: [Color] = [.orange, .blue, .pink, .yellow, .teal, .purple]
        for row in 0..<4 {
            for col in 0..<5 {
                let r = CGRect(x: cx + (Double(col) - 2.5) * tile * 1.15, y: cy + (Double(row) - 2) * tile * 1.15,
                               width: tile, height: tile)
                ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(colours[(row * 5 + col) % colours.count].opacity(0.55)))
            }
        }

        let spot = CGPoint(x: cx + tile * 0.3, y: cy - tile * 0.2)
        let hovering = ramp(p, 0.36, 0.42)
        let swept = ramp(p, 0.62, 0.7) * (1 - ramp(p, 0.76, 0.84))
        let splatted = p >= 0.7

        if splatted {
            let fade = 1 - ramp(p, 0.93, 1.0)
            FlyArtist.drawSplat(&ctx, at: CGPoint(x: spot.x, y: spot.y - 18), radius: 18, seed: 11, alpha: fade, showWord: false)
        } else {
            let o = hoverOffset(t, radius: 12 * hovering)
            let lift = 18 * hovering
            let state: FlyState = hovering > 0.5 ? .hovering : .landed
            FlyArtist.drawFly(&ctx, at: CGPoint(x: spot.x + o.x, y: spot.y - lift + o.y), size: 30 * scale + 6,
                              time: t, state: state, smug: false)
        }

        // The swat: a dark half sweeping in from the right, like the folding half.
        if swept > 0 {
            let r = CGRect(x: w - w * 0.75 * swept, y: 0, width: w * 0.75 * swept, height: h)
            ctx.fill(Path(r), with: .color(Color.black.opacity(0.85)))
        }

        // Viewfinder corners, so it reads as "your camera's view".
        let inset = 16.0
        for (x, y, dx, dy) in [(inset, inset, 1.0, 1.0), (w - inset, inset, -1.0, 1.0),
                               (inset, h - inset, 1.0, -1.0), (w - inset, h - inset, -1.0, -1.0)] {
            var c = Path()
            c.move(to: CGPoint(x: x, y: y + dy * 18))
            c.addLine(to: CGPoint(x: x, y: y))
            c.addLine(to: CGPoint(x: x + dx * 18, y: y))
            ctx.stroke(c, with: .color(ink.opacity(0.7)), lineWidth: 2)
        }

        let step: String
        if p < 0.34 {
            step = "1  Creep up slowly"
        } else if p < 0.62 {
            step = "2  Close enough: it hovers"
        } else {
            step = "3  Swat it. Splat!"
        }
        ctx.draw(Text(step).font(.headline).foregroundStyle(Color.white), at: CGPoint(x: cx, y: h - 22))
    }

    // MARK: Safety

    /// An eye glancing round the room, slowly.
    static func drawSafety(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let w = Double(size.width)
        let h = Double(size.height)
        let cx = w / 2
        let cy = h * 0.45
        let ew = min(w * 0.5, 200)
        let eh = ew * 0.45

        var eye = Path()
        eye.move(to: CGPoint(x: cx - ew / 2, y: cy))
        eye.addQuadCurve(to: CGPoint(x: cx + ew / 2, y: cy), control: CGPoint(x: cx, y: cy - eh * 1.1))
        eye.addQuadCurve(to: CGPoint(x: cx - ew / 2, y: cy), control: CGPoint(x: cx, y: cy + eh * 1.1))
        eye.closeSubpath()
        ctx.fill(eye, with: .color(Color.white.opacity(0.92)))

        let look = sin(t * 0.9) * ew * 0.22
        let iris = eh * 0.75
        var inner = ctx
        inner.clip(to: eye)
        inner.fill(Path(ellipseIn: CGRect(x: cx + look - iris / 2, y: cy - iris / 2, width: iris, height: iris)),
                   with: .color(Color(red: 0.2, green: 0.5, blue: 0.35)))
        inner.fill(Path(ellipseIn: CGRect(x: cx + look - iris / 4, y: cy - iris / 4, width: iris / 2, height: iris / 2)),
                   with: .color(Color.black))
        ctx.stroke(eye, with: .color(warm), lineWidth: 3)

        // Little "look around" arrows either side.
        for side in [-1.0, 1.0] {
            let x = cx + side * (ew / 2 + 26)
            var a = Path()
            a.move(to: CGPoint(x: x - side * 8, y: cy - 12))
            a.addLine(to: CGPoint(x: x + side * 6, y: cy))
            a.addLine(to: CGPoint(x: x - side * 8, y: cy + 12))
            let pulse = 0.4 + 0.6 * max(0, sin(t * 0.9) * side)
            ctx.stroke(a, with: .color(warm.opacity(pulse)), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
        ctx.draw(Text("Look around before you move").font(.headline).foregroundStyle(Color.white),
                 at: CGPoint(x: cx, y: h - 26))
    }

    // MARK: Ready

    static func drawReady(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let w = Double(size.width)
        let h = Double(size.height)
        let cx = w / 2
        let cy = h * 0.5
        // A figure-of-eight flight, with a fading dotted trail.
        func path(_ s: Double) -> CGPoint {
            return CGPoint(x: cx + sin(s) * w * 0.28, y: cy + sin(2 * s) * h * 0.22)
        }
        let s = t * 1.1
        for i in 1...14 {
            let q = path(s - Double(i) * 0.09)
            let r = 2.5
            ctx.fill(Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: r * 2, height: r * 2)),
                     with: .color(Color.white.opacity(0.5 * (1 - Double(i) / 15))))
        }
        FlyArtist.drawFly(&ctx, at: path(s), size: 34, time: t, state: .wandering, smug: false)
        // Three splat badges: a round is three flies.
        for i in 0..<3 {
            let x = cx + (Double(i) - 1) * 44
            FlyArtist.drawSplat(&ctx, at: CGPoint(x: x, y: h - 24), radius: 9, seed: 20 + i, alpha: 0.9, showWord: false)
        }
    }
}
