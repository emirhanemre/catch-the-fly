#if IOS_27_1_SDK
import AVFoundation
import AVKit
import SwiftUI
import UIKit

// Phase 5, CI build only: the iPhone Duo screens.
//
// Posture A (API_NOTES section 3): the accessory only shows while the phone is open, the app
// is in the foreground, capture is running and the main UI fills the inner display. So:
//   - inner display (main window, regular size class): the normal game UI laid out at the
//     cover's aspect ratio, so its preview crop is the cover's crop, plus a "hold it like a
//     book" helper with the Duo debug readout. In the L nobody looks at it.
//   - cover display (CameraCaptureAccessory): camera preview, fly, hit zone, HUD, results.
//   - shut (the main window moves to the outer display, compact): the normal game UI full
//     screen, with the last result, so a splat or miss is visible whatever screen is on.
// Posture B: the normal game UI full screen on the inner display; accessory off.

/// What Platform.coverDisplay(game:) returns in the CI build. Does nothing without a hinge.
struct DuoCoverDisplay: ViewModifier {
    @ObservedObject var game: GameController
    let isDuo: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isDuo {
            if #available(iOS 27.1, *) {
                DuoScreens(game: game, runtime: DuoRuntime.shared, content: content)
            } else {
                content
            }
        } else {
            content
        }
    }
}

@available(iOS 27.1, *)
struct DuoScreens<GameContent: View>: View {
    @ObservedObject var game: GameController
    @ObservedObject var runtime: DuoRuntime
    let content: GameContent
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        arranged
            .sceneAccessory {
                CameraCaptureAccessory(isEnabled: $runtime.accessoryEnabled) {
                    CoverGameView(game: game, runtime: runtime)
                }
                .onAvailabilityChange { available in
                    runtime.accessoryAvailabilityChanged(available)
                }
            }
            .onAppear {
                runtime.appeared(game: game)
                runtime.sizeClassChanged(sizeClassName)
            }
            .onChange(of: sizeClass) { _, _ in
                runtime.sizeClassChanged(sizeClassName)
            }
            .onChange(of: game.state.fliesCaught) { old, new in
                runtime.caughtChanged(from: old, to: new, state: game.state)
            }
            .onChange(of: game.state.smugUntil) { _, _ in
                runtime.smugChanged(state: game.state)
            }
            .onChange(of: game.state.phase) { _, new in
                runtime.phaseChanged(new)
            }
    }

    private var sizeClassName: String {
        switch sizeClass {
        case .some(.regular): return "regular"
        case .some(.compact): return "compact"
        default: return "unknown"
        }
    }

    /// `content` (with the camera preview UIView, which hosts the hinge interaction) always
    /// sits at the same place in the tree, so folding never recreates it; only its frame changes.
    private var arranged: some View {
        GeometryReader { geo in
            let inner = runtime.posture == .a && sizeClass == .regular
            let box = inner ? DuoLayoutMath.gameBox(in: geo.size, aspect: runtime.coverAspect)
                            : CGRect(origin: .zero, size: geo.size)
            ZStack(alignment: .topLeading) {
                content
                    .frame(width: box.width, height: box.height)
                    .offset(x: box.minX, y: box.minY)
                if inner {
                    DuoInnerHelper(game: game, runtime: runtime)
                        .frame(width: max(0, geo.size.width - box.maxX - 40), height: max(0, geo.size.height - 48))
                        .offset(x: box.maxX + 24, y: 24)
                } else {
                    DuoResultBanner(game: game, runtime: runtime, showOpenHint: runtime.posture == .a)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .allowsHitTesting(false)
                    if game.state.phase != .playing {
                        DuoPostureMenu(game: game, runtime: runtime)
                            .padding(.leading, 12)
                            .padding(.top, 8)
                    }
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
    }
}

enum DuoLayoutMath {
    /// Left half of the inner display, at the cover's aspect ratio, clear of every edge.
    static func gameBox(in size: CGSize, aspect: CGFloat) -> CGRect {
        let availableWidth = max(40, size.width * 0.5 - 32)
        let availableHeight = max(40, size.height - 48)
        var w = availableWidth
        var h = w / max(aspect, 0.1)
        if h > availableHeight {
            h = availableHeight
            w = h * aspect
        }
        return CGRect(x: 24, y: max(24, (size.height - h) / 2), width: w, height: h)
    }
}

// MARK: - Cover display

/// The game on the cover display: preview, fly, hit zone (when Debug is on), HUD, results.
@available(iOS 27.1, *)
struct CoverGameView: View {
    @ObservedObject var game: GameController
    @ObservedObject var runtime: DuoRuntime

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CoverCameraPreview(runtime: runtime)
                FlyOverlay(state: game.state)
                    .allowsHitTesting(false)
                if game.showDebug {
                    DebugOverlay(state: game.state)
                        .allowsHitTesting(false)
                }
                DuoResultBanner(game: game, runtime: runtime, showOpenHint: false)
                    .allowsHitTesting(false)
                ToastLayer(state: game.state, showHitMiss: false)
                CoverHUD(game: game)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear {
                runtime.coverAppeared(size: geo.size)
            }
            .onChange(of: geo.size) { _, newSize in
                runtime.coverResized(newSize)
            }
        }
        .ignoresSafeArea()
        .background(Color.black)
        .onDisappear {
            runtime.coverDisappeared()
        }
    }
}

@available(iOS 27.1, *)
final class CoverPreviewUIView: UIView {
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // layerClass guarantees the type.
        return layer as! AVCaptureVideoPreviewLayer
    }
}

@available(iOS 27.1, *)
struct CoverCameraPreview: UIViewRepresentable {
    let runtime: DuoRuntime

    func makeUIView(context: Context) -> CoverPreviewUIView {
        let view = CoverPreviewUIView()
        view.backgroundColor = .black
        view.previewLayer.videoGravity = .resizeAspectFill
        runtime.coverPreviewCreated(view)
        return view
    }

    func updateUIView(_ uiView: CoverPreviewUIView, context: Context) {}

    static func dismantleUIView(_ uiView: CoverPreviewUIView, coordinator: ()) {
        DuoRuntime.shared.coverPreviewGone(uiView)
    }
}

/// Compact HUD for the 5.4-inch cover: fly count, clock, best, Start, and the zone toggle.
struct CoverHUD: View {
    @ObservedObject var game: GameController

    var body: some View {
        let s = game.state
        VStack(spacing: 8) {
            if s.phase == .playing {
                HStack(spacing: 6) {
                    chip("Fly \(min(s.fliesCaught + 1, s.fliesPerRound))/\(s.fliesPerRound)")
                    chip(GameText.clock(s.elapsed))
                    chip("Best " + (s.bestTime.map { GameText.clock($0) } ?? "–"))
                }
            }
            Spacer()
            if s.phase != .playing {
                Button {
                    game.startRound()
                } label: {
                    Text(s.phase == .finished ? "Play again" : "Start round")
                        .font(.title3.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            HStack {
                Text("Fold calmly to smash. Never slam.")
                    .font(.caption)
                    .foregroundStyle(Color.white)
                Spacer()
                Button(game.showDebug ? "Hide zone" : "Show zone") {
                    game.showDebug.toggle()
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .tint(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.45), in: Capsule())
        }
        .padding(.top, 40)
        .padding(.horizontal, 10)
        .padding(.bottom, 16)
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.monospacedDigit().bold())
            .foregroundStyle(Color.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.5), in: Capsule())
    }
}

// MARK: - Results that survive a fold

/// The last hit, miss or round result, and the "fold gently" reminder. Drawn on the cover and
/// on the main window when it's full screen (shut, or Posture B).
struct DuoResultBanner: View {
    @ObservedObject var game: GameController
    @ObservedObject var runtime: DuoRuntime
    let showOpenHint: Bool

    var body: some View {
        let now = game.state.time
        let active: DuoResult? = (runtime.result?.isActive(at: now) ?? false) ? runtime.result : nil
        ZStack {
            if let r = active, let splat = r.splat, now - r.time > 3.0 {
                // FlyOverlay's own splat fades after 3 s; keep one on screen for after reopening.
                Canvas { ctx, size in
                    let w = Double(size.width)
                    let h = Double(size.height)
                    FlyArtist.drawSplat(&ctx, at: CGPoint(x: splat.x * w, y: splat.y * h), radius: min(w, h) * 0.07,
                                        seed: splat.id, alpha: 0.85, showWord: false)
                }
            }
            VStack(spacing: 8) {
                Spacer()
                if let r = active {
                    VStack(spacing: 2) {
                        Text(r.title)
                            .font(.title2.bold())
                            .foregroundStyle(r.kind == .miss ? Color.orange : Color.green)
                        Text(r.detail)
                            .font(.headline)
                            .foregroundStyle(Color.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
                }
                if now < runtime.hinge.gentleReminderUntil {
                    Text("Gently does it: a calm fold catches it just as well.")
                        .font(.callout.bold())
                        .foregroundStyle(Color.yellow)
                        .padding(8)
                        .background(Color.black.opacity(0.65), in: Capsule())
                }
                if showOpenHint && runtime.hinge.lastStatus == HingeStatus.closed {
                    Text("Open it to an L and turn it round to carry on.")
                        .font(.callout)
                        .foregroundStyle(Color.white)
                        .padding(8)
                        .background(Color.black.opacity(0.65), in: Capsule())
                }
                Spacer()
                    .frame(height: 140)
            }
            .padding(.horizontal, 12)
        }
    }
}

// MARK: - Inner display in Posture A

struct DuoInnerHelper: View {
    @ObservedObject var game: GameController
    @ObservedObject var runtime: DuoRuntime

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Hold it like a book")
                    .font(.largeTitle.bold())
                Text("In Posture A the game is on the small outer screen. The picture on the left is a copy of it.")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 6) {
                    step("1", "Tap Start round, here or on the small screen.")
                    step("2", "Fold the phone to an L, about a right angle, hinge upright.")
                    step("3", "Turn it round so the small outer screen faces you. This screen faces the room.")
                    step("4", "Find the fly, creep up until it hovers, keep it on the hinge side.")
                    step("5", "Fold the far half shut, calmly, like a slow clap. Never slam.")
                }
                Divider()
                Text("Outer screen: \(runtime.coverStatusText)")
                Text(runtime.hinge.statusText)
                if runtime.accessoryAvailable == false && !runtime.coverShowing {
                    Text("If the small screen stays blank with the phone open, switch to Posture B.")
                        .foregroundStyle(Color.orange)
                }
                Divider()
                Text("Posture").font(.headline)
                ForEach(DuoPosture.allCases, id: \.self) { p in
                    Button {
                        runtime.select(p, game: game)
                    } label: {
                        Label(p.title, systemImage: runtime.posture == p ? "checkmark.circle.fill" : "circle")
                    }
                    .buttonStyle(.bordered)
                }
                Button(runtime.innerAxisFlipped ? "Turning direction: flipped (tap to undo)"
                                                : "Flip the turning direction (only if the fly slides the wrong way when you turn)") {
                    runtime.setInnerAxisFlipped(!runtime.innerAxisFlipped)
                }
                .buttonStyle(.bordered)
                Text("main window \(runtime.lastSizeClass), cover \(Int(runtime.coverSize.width))x\(Int(runtime.coverSize.height)), hit region \(runtime.posture.hingeEdge.rawValue)")
                    .font(.system(size: 11, design: .monospaced))
                Text(game.state.cameraStatus)
                    .font(.system(size: 11, design: .monospaced))
            }
            .foregroundStyle(Color.white)
            .padding(20)
        }
        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 20))
    }

    private func step(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(n).font(.headline).frame(width: 22)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Posture switch when the main window is full screen (Posture B, or shut).
struct DuoPostureMenu: View {
    @ObservedObject var game: GameController
    @ObservedObject var runtime: DuoRuntime

    var body: some View {
        Menu {
            ForEach(DuoPosture.allCases, id: \.self) { p in
                Button(p.title) {
                    runtime.select(p, game: game)
                }
            }
        } label: {
            Text("Posture \(runtime.posture.shortName)")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.6), in: Capsule())
                .foregroundStyle(Color.white)
        }
    }
}
#endif
