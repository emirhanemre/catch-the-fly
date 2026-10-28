#if IOS_27_1_SDK
import Foundation
import AVFoundation
import AVKit
import Combine
import CoreGraphics
import QuartzCore
import SwiftUI
import UIKit

// Phase 5, CI build only (Xcode 27.1 / iOS 27.1 SDK). Swift Playgrounds never defines
// IOS_27_1_SDK, so on the iPad this whole file is parsed and skipped.
//
// Everything Duo-specific that the views and Platform.swift share lives here: the posture
// choice, the native sources, the cover-display state and the "last result" banner.

/// The two ways to hold the Duo (PLAN.md section 1).
enum DuoPosture: String, CaseIterable, Sendable {
    /// Half open as an L, cover display facing the player, inner camera looking into the room.
    case a
    /// Open wide like a book, inner display facing the player, rear camera looking into the room.
    case b

    var title: String {
        switch self {
        case .a: return "Posture A: half open as an L, small screen facing you"
        case .b: return "Posture B: open wide, big screen facing you"
        }
    }

    var shortName: String {
        switch self {
        case .a: return "A"
        case .b: return "B"
        }
    }

    /// FlyCore's preset for this posture: tunables plus the hinge-side hit region.
    /// A: `FlyPreset.duoPostureA` (its edge is a guess until spike P3). B: `FlyPreset.duoPostureB`.
    var preset: FlyPreset {
        switch self {
        case .a: return FlyPreset.duoPostureA
        case .b: return FlyPreset.duoPostureB
        }
    }

    var hingeEdge: HingeEdge { return preset.hingeEdge }
}

/// Plain facts and settings, readable from any thread.
enum DuoNative {
    /// The API has no synchronous "is there a hinge?" query (UIHingeInteraction reports
    /// asynchronously). The Duo is the only device with an inner ultra wide camera, and that
    /// device type is discoverable at once, so it stands in for "this device has a hinge".
    static let hasHinge: Bool = detectHinge()

    static let postureKey = "CatchTheFly.duoPosture"
    static let axisFlipKey = "CatchTheFly.duoInnerAxisFlipped"

    static var savedPosture: DuoPosture {
        return DuoPosture(rawValue: UserDefaults.standard.string(forKey: postureKey) ?? "") ?? .a
    }

    private static func detectHinge() -> Bool {
        if #available(iOS 27.1, *) {
            let found = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInInnerUltraWideCamera],
                                                         mediaType: .video, position: .unspecified).devices
            return !found.isEmpty
        }
        return false
    }
}

/// Which way the inner camera looks in CoreMotion's device frame. Which half holds the motion
/// sensors is unknown (spike P11), so the tester can flip it on the device. Read on the capture
/// queue, written on the main actor.
final class DuoAxisSetting: @unchecked Sendable {
    static let shared = DuoAxisSetting()

    private let lock = NSLock()
    private var flippedValue: Bool

    private init() {
        flippedValue = UserDefaults.standard.bool(forKey: DuoNative.axisFlipKey)
    }

    var flipped: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return flippedValue
        }
        set {
            lock.lock()
            flippedValue = newValue
            lock.unlock()
            UserDefaults.standard.set(newValue, forKey: DuoNative.axisFlipKey)
        }
    }
}

/// A result kept on screen long enough to be seen after the phone is reopened: the cover
/// accessory disappears while the phone is shut, and FlyOverlay's splat fades after 3 s.
struct DuoResult: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case hit
        case miss
        case roundDone
    }

    var kind: Kind
    var time: Double
    var title: String
    var detail: String
    var splat: SplatMark?
    var lifetime: Double

    func isActive(at now: Double) -> Bool {
        return now - time < lifetime
    }
}

/// The Duo's shared state (main actor). Created on first use by Platform.swift, and only on a
/// device with a hinge.
@MainActor
final class DuoRuntime: ObservableObject {
    static let shared = DuoRuntime()

    @Published private(set) var posture: DuoPosture
    /// Bound to CameraCaptureAccessory(isEnabled:). On in Posture A only.
    @Published var accessoryEnabled: Bool
    /// From onAvailabilityChange; nil until the system first reports.
    @Published private(set) var accessoryAvailable: Bool?
    @Published private(set) var coverShowing = false
    /// The cover accessory's content size. The inner display lays the game out at this aspect
    /// ratio, so FlyCore's screen space (the main preview's crop) matches the cover picture.
    @Published private(set) var coverSize = CGSize(width: 9, height: 19.5)
    @Published private(set) var innerAxisFlipped: Bool
    @Published private(set) var result: DuoResult?
    @Published private(set) var lastSizeClass = "unknown"

    let frameSource: DuoFrameSource
    let hinge: NativeHingeSmashSource
    let luma: PostureGatedLumaSource
    let smashSources: [any SmashInputSource]

    private var appearedOnce = false
    private var coverAppearCount = 0
    private weak var coverView: UIView?
    private var coverDirectionObject: AnyObject?

    private init() {
        let p = DuoNative.savedPosture
        let hingeSource = NativeHingeSmashSource()
        let lumaSource = PostureGatedLumaSource()
        lumaSource.enabled = (p == .a)
        posture = p
        accessoryEnabled = (p == .a)
        innerAxisFlipped = DuoAxisSetting.shared.flipped
        frameSource = DuoFrameSource(posture: p)
        hinge = hingeSource
        luma = lumaSource
        smashSources = [lumaSource, hingeSource, DebugButtonSmashSource()]
    }

    var coverAspect: CGFloat {
        let w = coverSize.width
        let h = coverSize.height
        guard w > 1, h > 1 else { return 9.0 / 19.5 }
        return min(3, max(0.3, w / h))
    }

    var coverStatusText: String {
        if posture == .b { return "off (Posture B)" }
        if coverShowing { return "showing the game (\(Int(coverSize.width))x\(Int(coverSize.height)) pt)" }
        switch accessoryAvailable {
        case .some(true): return "available, waiting for the system to show it"
        case .some(false): return "not available right now"
        case .none: return "not reported yet"
        }
    }

    // MARK: Logging (through the frame pipeline into the session log)

    func note(_ message: String) {
        frameSource.note(message)
    }

    // MARK: Lifecycle and posture

    func appeared(game: GameController) {
        guard !appearedOnce else { return }
        appearedOnce = true
        game.applyPreset(posture.preset)
        note("DUO native build: posture \(posture.rawValue), hit region \(posture.hingeEdge.rawValue), accessory enabled \(accessoryEnabled), inner axis flipped \(innerAxisFlipped)")
    }

    func select(_ p: DuoPosture, game: GameController) {
        guard p != posture else { return }
        posture = p
        UserDefaults.standard.set(p.rawValue, forKey: DuoNative.postureKey)
        accessoryEnabled = (p == .a)
        luma.enabled = (p == .a)
        frameSource.select(p)
        game.applyPreset(p.preset)
        game.resetTracking()
        result = nil
        note("DUO posture \(p.rawValue) selected: camera \(p == .a ? "inner" : "rear"), hit region \(p.hingeEdge.rawValue), luma smash \(p == .a ? "on" : "off"), accessory \(p == .a ? "on" : "off")")
    }

    func setInnerAxisFlipped(_ flipped: Bool) {
        guard flipped != innerAxisFlipped else { return }
        innerAxisFlipped = flipped
        DuoAxisSetting.shared.flipped = flipped
        note("DUO inner camera axis flipped=\(flipped) (forward \(flipped ? "-z" : "+z") in the device frame)")
    }

    func sizeClassChanged(_ name: String) {
        guard name != lastSizeClass else { return }
        lastSizeClass = name
        note("DUO main window size class \(name) (regular = inner display, compact = outer display)")
    }

    // MARK: Cover accessory

    func accessoryAvailabilityChanged(_ available: Bool) {
        accessoryAvailable = available
        note("DUO CameraCaptureAccessory availability \(available)")
    }

    func coverAppeared(size: CGSize) {
        coverShowing = true
        coverAppearCount += 1
        coverResized(size)
        note("DUO cover content appeared (#\(coverAppearCount)) size \(Int(size.width))x\(Int(size.height)) hinge \(hinge.lastStatusName)")
    }

    func coverResized(_ size: CGSize) {
        guard size.width > 1, size.height > 1, size != coverSize else { return }
        coverSize = size
        note("DUO cover size \(Int(size.width))x\(Int(size.height))")
    }

    func coverDisappeared() {
        guard coverShowing else { return }
        coverShowing = false
        frameSource.setCoverLayer(nil)
        note("DUO cover content disappeared, hinge \(hinge.lastStatusName)")
    }

    /// The cover preview's view was created. It gets the capture session, and while it exists
    /// it drives preview and frame rotation (the player looks at the cover in Posture A).
    @available(iOS 27.1, *)
    func coverPreviewCreated(_ view: CoverPreviewUIView) {
        coverView = view
        frameSource.setCoverLayer(view.previewLayer)
        // Diagnostic only: which cameras face the cover's viewer. Expected (API_NOTES section 2):
        // the inner camera is backward-facing relative to the cover, the outer one forward.
        let coordinator = AVCaptureDeviceDirectionCoordinator(
            view: view,
            deviceTypes: [.builtInInnerUltraWideCamera, .builtInOuterUltraWideCamera, .builtInWideAngleCamera],
            changeHandler: { [weak self] map in
                MainActor.assumeIsolated {
                    self?.coverDirectionsChanged(map)
                }
            })
        coverDirectionObject = coordinator
    }

    func coverPreviewGone(_ view: UIView) {
        guard coverView === view else { return }
        coverView = nil
        coverDirectionObject = nil
        frameSource.setCoverLayer(nil)
    }

    @available(iOS 27.1, *)
    private func coverDirectionsChanged(_ map: AVCaptureDeviceDirectionMap) {
        let forward = map.forwardFacingDeviceDescriptors.map { "\($0.localizedName) [\($0.deviceType.rawValue)]" }
        let backward = map.backwardFacingDeviceDescriptors.map { "\($0.localizedName) [\($0.deviceType.rawValue)]" }
        note("DUO cover directions: forward=[\(forward.joined(separator: ", "))] backward=[\(backward.joined(separator: ", "))]")
    }

    // MARK: Results that survive a fold

    func caughtChanged(from old: Int, to new: Int, state: GameViewState) {
        guard new > old else { return }
        let splat = state.splats.last
        if state.phase == .finished {
            var detail = "All \(state.fliesPerRound) flies"
            if let t = state.lastRoundTime {
                detail += " in \(GameText.clock(t))"
            }
            if state.lastRoundWasBest {
                detail += ". New best time!"
            }
            result = DuoResult(kind: .roundDone, time: state.time, title: "Splat! Round complete", detail: detail,
                               splat: splat, lifetime: 3600)
        } else {
            result = DuoResult(kind: .hit, time: state.time, title: "Splat!",
                               detail: "Fly \(new) of \(state.fliesPerRound) caught", splat: splat, lifetime: 10)
        }
        note("DUO result shown: \(result?.title ?? "") / \(result?.detail ?? "")")
    }

    func smugChanged(state: GameViewState) {
        guard state.smugUntil > state.time else { return }
        result = DuoResult(kind: .miss, time: state.time, title: "Missed!",
                           detail: "The fly got away. Creep up again.", splat: nil, lifetime: 6)
        note("DUO result shown: missed")
    }

    func phaseChanged(_ phase: FlyRoundPhase) {
        if phase == .playing, result?.kind == .roundDone {
            result = nil
        }
    }
}
#endif
