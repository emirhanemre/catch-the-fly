import Foundation
import SwiftUI

/// THE place where the iPad stand-ins and the Duo versions are chosen: one line per source.
///
/// Phase 4 (now): iPad rear camera, route B, smash by covering the camera or the debug button.
/// Phase 5, Playgrounds build (iOS 26 SDK, runtime lookups only):
///   makeFrameSource -> InnerCameraFrameSource()   (or InnerCameraFrameSource(strategy: .constituent))
///   hingeEdge       -> the edge spike P3 measured
///   makeTunables    -> FlyTunables.duoPostureA
///   HingeSmashSource is already in the smash list and switches itself on when the class exists.
/// Phase 5, CI build (Xcode 27.1, defines IOS_27_1_SDK): put each native implementation in its
/// own file wrapped in `#if IOS_27_1_SDK` (for example a NativeInnerCameraFrameSource using
/// .builtInInnerUltraWideCamera, a NativeHingeSmashSource using UIHingeInteraction, and a
/// CameraCaptureAccessory cover-display modifier), conforming to the same protocols, then pick
/// them here with
///     #if IOS_27_1_SDK
///     static func makeFrameSource() -> any FrameSource { NativeInnerCameraFrameSource() }
///     #else
///     static func makeFrameSource() -> any FrameSource { InnerCameraFrameSource() }
///     #endif
/// No other file needs to change.
/// Done for phase 5 (CI build): on a device with a hinge (DuoNative.hasHinge) the Duo sources
/// come from DuoRuntime (Sources/DuoRuntime.swift); the posture (A or B) is chosen at run time.
@MainActor
enum Platform {
    #if IOS_27_1_SDK
    static let name = DuoNative.hasHinge ? "iPhone Duo native (iOS 27.1 SDK): phase 5, route B, Posture A/B" : "iOS 27.1 SDK build without a hinge: phase 4 sources"
    #else
    static let name = "iPad prototype: phase 4, route B, rear camera"
    #endif

    /// Camera frames.                     Duo: InnerCameraFrameSource()
    #if IOS_27_1_SDK
    static func makeFrameSource() -> any FrameSource {
        if DuoNative.hasHinge { return DuoRuntime.shared.frameSource }
        return RearCameraFrameSource()
    }
    #else
    static func makeFrameSource() -> any FrameSource { return RearCameraFrameSource() }
    #endif

    /// Device attitude.                   Duo: the same (which half holds the IMU: spike P11)
    static func makePoseSource() -> any PoseSource { return CoreMotionPoseSource() }

    /// Landing spots and distance.        Duo: the same (route B), unless phase 2 picks A2
    static func makeSpotTracker() -> any SpotTracker { return PatchTracker() }

    /// Smash inputs, all fed to FlyCore's SmashDetector.  Duo: the same list
    static func makeSmashSources() -> [any SmashInputSource] {
        #if IOS_27_1_SDK
        if DuoNative.hasHinge { return DuoRuntime.shared.smashSources }   // inner-camera luma (Posture A only), native hinge, debug button
        #endif
        return [LumaSmashSource(), HingeSmashSource(), DebugButtonSmashSource()]
    }

    /// Hinge-side hit region.             Duo: FlyPreset.duoPostureA.hingeEdge (a guess until spike P3)
    #if IOS_27_1_SDK
    static let hingeEdge: HingeEdge = DuoNative.hasHinge ? DuoRuntime.shared.posture.preset.hingeEdge : FlyPreset.iPadPrototype.hingeEdge
    #else
    static let hingeEdge: HingeEdge = FlyPreset.iPadPrototype.hingeEdge
    #endif

    /// Gameplay numbers.                  Duo: FlyTunables.duoPostureA (or .duoPostureB)
    /// iPadPrototype: smashDistance 0.25 m (see FlyCore's FlyPresets.swift).
    #if IOS_27_1_SDK
    static func makeTunables() -> FlyTunables { return DuoNative.hasHinge ? DuoRuntime.shared.posture.preset.tunables : FlyTunables.iPadPrototype }
    #else
    static func makeTunables() -> FlyTunables { return FlyTunables.iPadPrototype }
    #endif

    /// Content for the cover display.     CI/Duo: a CameraCaptureAccessory modifier (27.1 only)
    #if IOS_27_1_SDK
    static func coverDisplay(game: GameController) -> some ViewModifier { return DuoCoverDisplay(game: game, isDuo: DuoNative.hasHinge) }
    #else
    static func coverDisplay(game: GameController) -> some ViewModifier { return NoCoverDisplay() }
    #endif

    /// Which way to hold it, for the onboarding drawing (Views/OnboardingView.swift).
    static func onboardingPosture() -> OnboardingPosture {
        #if IOS_27_1_SDK
        if DuoNative.hasHinge { return DuoRuntime.shared.posture == .a ? .duoPostureA : .duoPostureB }
        #endif
        return .iPad
    }

    /// "Splat!" and "Missed!" toasts in the main window. The Duo build has its own result banner
    /// (DuoResultBanner) for those, so there only "Too fast" shows as a toast.
    #if IOS_27_1_SDK
    static let showsHitMissToasts: Bool = !DuoNative.hasHinge
    #else
    static let showsHitMissToasts = true
    #endif
}
