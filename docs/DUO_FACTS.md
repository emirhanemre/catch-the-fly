# iPhone Duo: facts and unknowns

Status key:

- **Apple**: from Apple's own docs, talks or newsroom
- **Reported**: from third-party coverage or packages
- **Inference**: reasoned from other facts, not confirmed
- **Unknown**: to be settled by the spike test named

When a device session or a Playgrounds compile settles a line, update it, and add the date and the evidence.

Last reviewed 2026-10-26.

## Read before coding

Read these before writing any Duo-specific code:

- `UIHingeInteraction`: https://developer.apple.com/documentation/uikit/uihingeinteraction
- `UIHinge`: https://developer.apple.com/documentation/uikit/uihinge
- `UIHinge.angle`: https://developer.apple.com/documentation/uikit/uihinge/angle
- Tech talk, *Build a great camera experience for iPhone Duo*: https://developer.apple.com/videos/play/tech-talks/111465/
- Tech talk, *Leverage multiple displays and scenes on iPhone Duo*: https://developer.apple.com/videos/play/tech-talks/111464
- The related talks *Prepare your app for iPhone Duo* (https://developer.apple.com/videos/play/tech-talks/111461/) and *Strike a pose with adaptive layouts on iPhone Duo* (https://developer.apple.com/videos/play/tech-talks/111463/)
- `docs/API_NOTES.md`: the exact signatures confirmed from Apple's docs JSON on 2026-10-26. Code against that file

## Hardware

| Fact | Status | Source |
|---|---|---|
| Book-style foldable. 5.4-inch cover display, 7.6-inch inner display | Apple | [Newsroom](https://www.apple.com/my/newsroom/2026/09/apple-unveils-iphone-duo/), [iFixit](https://www.ifixit.com/Topic/iPhone_Duo) |
| Two rear cameras: 48 MP Main and 48 MP Ultra Wide. No telephoto | Reported | [PetaPixel](https://petapixel.com/2026/09/09/apples-iphone-duo-argues-no-other-foldable-has-gotten-it-right/) |
| Two front cameras, one per display. The inner one sits under the inner display | Apple (two front cameras); Reported (under-display) | [Tech talk 111465](https://developer.apple.com/videos/play/tech-talks/111465/), [iFixit](https://www.ifixit.com/Topic/iPhone_Duo) |
| Both front cameras are square sensors with an ultrawide field of view | Apple | [Tech talk 111465](https://developer.apple.com/videos/play/tech-talks/111465/) |
| Inner front camera: up to 1080p at 60 fps. Outer front camera: up to 4K at 120 fps. Through the virtual front camera, only the shared set (1080p, 60 fps, no depth) | Apple, 2026-10-26 | [Tech talk 111465](https://developer.apple.com/videos/play/tech-talks/111465/) transcript |
| Touch ID, no Face ID | Reported | [NoypiGeeks](https://www.noypigeeks.com/?p=277500), [Macworld](https://www.macworld.com/article/2629813/iphone-ultra-folding-design-specs-release.html) |
| No TrueDepth front camera, so `ARFaceTrackingConfiguration` is unsupported (rules out route A1) | Inference, strengthened | Follows from no Face ID. The Duo front cameras are documented as ultrawide types (`builtInInnerUltraWideCamera`, `builtInOuterUltraWideCamera`), with no TrueDepth type (Apple docs JSON, 2026-10-26). **P1** confirms |
| The inner camera is on the same half as the cover display | Stated by the developer, 2026-10-26 | **P2/P3** re-confirm |
| Ships on iOS 27.1, a Duo-specific build (other iPhones are moving to 27.2). On sale 23 Oct 2026 | Reported | [iThinkDiff](https://www.ithinkdiff.com/?p=347302), [Macworld](https://www.macworld.com/article/2629813/iphone-ultra-folding-design-specs-release.html) |
| The test Duo: model identifier, iOS version | Unknown | **P1** |
| The developer's iPad model (ARKit-capable, rear camera) | Unknown | Phase 0 |

## Hinge API (iOS 27.1, UIKit and SwiftUI)

| Fact | Status | Source |
|---|---|---|
| Add `UIHingeInteraction(updateHandler:)` to a view. The handler gets `(UIHingeInteraction, UIHingeInteraction.Update)`. `update.hinge` is nil when the view leaves a hierarchy that provides hinge updates. The interaction has `isEnabled` | Apple. Confirmed 2026-10-26 (Apple docs JSON): `@MainActor`, iOS 27.1, `init(updateHandler: @escaping (UIHingeInteraction, UIHingeInteraction.Update) -> Void)`. The handler fires with the initial state, then on each change. `Update` has only `hinge: UIHinge?` | [UIHingeInteraction](https://developer.apple.com/documentation/uikit/uihingeinteraction) |
| `UIHinge.angle: CGFloat` is in radians. `UIHinge.status` gives closed, partially open or fully open | Apple | [UIHinge](https://developer.apple.com/documentation/uikit/uihinge), [angle](https://developer.apple.com/documentation/uikit/uihinge/angle) |
| `UIHinge` has only `angle` and `status`: no identifier, axis or position. `UIHinge.Status` has **four** cases: `closed`, `partiallyOpen`, `fullyOpen` and `unknown`. Raw integer values aren't documented | Apple, 2026-10-26 | Apple docs JSON, [UIHinge.Status](https://developer.apple.com/documentation/uikit/uihinge/status-swift.enum) |
| SwiftUI has its own hinge API: `.onHingeChange(isEnabled:_:)` with `(DeviceHingeContext, DeviceHingeContext)`, then `DeviceHinge`. Its `angle` is SwiftUI `Angle`, and `DeviceHinge.Status` is a struct with `closed`, `partiallyOpen` and `fullyOpen` (no `unknown`) | Apple, 2026-10-26 | Apple docs JSON, [onHingeChange](https://developer.apple.com/documentation/swiftui/view/onhingechange(isenabled:_:)), [Tech talk 111464](https://developer.apple.com/videos/play/tech-talks/111464) |
| `UIDevice`, `UIScreen` and `UIWindowScene` have no hinge or posture members. The fold's position is available as a `.division` reserved region (`reservedRegions(kind:)`, iOS 27.1), active only while folded | Apple, 2026-10-26 | Apple docs JSON, [Tech talk 111463](https://developer.apple.com/videos/play/tech-talks/111463/) |
| Update rate and granularity are system policy and can change. Don't depend on a frequency. Prefer `status` when you only need closed, partial or open | Apple | [angle](https://developer.apple.com/documentation/uikit/uihinge/angle) |
| Angle 0 means folded shut, and 180° (π) is flat | Reported (verified on the Duo simulator by a package author). Apple's docs say only "radians" and don't state the direction (2026-10-26) | [pub.dev foldable](https://pub.dev/packages/foldable). **P5** confirms |
| Apple's guidance: drive interactions and effects from the raw angle, and layout from posture and size classes | Apple, 2026-10-26 (was Reported). The talk says hinge data is "ideal for driving interactions or effects", and points to the arrangement and region APIs for layout | [Tech talk 111464](https://developer.apple.com/videos/play/tech-talks/111464) |
| The hinge API can be reached through the Objective-C runtime, so code compiles on older SDKs | Reported. The ObjC names exist (Apple docs JSON, 2026-10-26): `UIHingeInteraction`, `-initWithUpdateHandler:`, `UIHingeInteractionUpdate.hinge`, `UIHinge.angle` and `.status`. Whether it returns values in an old-SDK build is still unknown | [foldable changelog](https://pub.dev/packages/foldable/changelog), [API_NOTES](API_NOTES.md) section 6 |
| Conflicting claim: hinge values need iOS 27.1 *and* a build made with the 27.1 SDK | Reported | [Expo Hinge](https://docs.expo.dev/versions/unversioned/sdk/hinge.md). **P5** settles it for Playgrounds builds |
| Samples per normal-speed close, and latency to `closed` | Unknown | **P5** |

## Cameras and displays

| Fact | Status | Source |
|---|---|---|
| Each front camera has its own `AVCaptureDevice` device type. Both report position `.front`, so `.front` doesn't mean "facing the user" on the Duo | Apple. Confirmed 2026-10-26 (Apple docs JSON): `AVCaptureDevice.DeviceType.builtInInnerUltraWideCamera` and `.builtInOuterUltraWideCamera`, iOS 27.1, discoverable only through `DiscoverySession` | [Tech talk 111465](https://developer.apple.com/videos/play/tech-talks/111465/), [DeviceType](https://developer.apple.com/documentation/avfoundation/avcapturedevice/devicetype-swift.struct) |
| A "Virtual Front Camera" switches automatically: inner when open, outer when closed. Using individual cameras means the app handles switching | Apple. Refined 2026-10-26 (Apple docs JSON): there's no new device type. `.builtInWideAngleCamera` or `.builtInUltraWideCamera` at `.front` returns it. It streams from the camera over the display the app is on. `isVirtualDevice` is true, and `activePrimaryConstituent` names the live physical camera. It works with pre-27 SDKs | [Tech talk 111465](https://developer.apple.com/videos/play/tech-talks/111465/), [Choosing a camera by the direction it faces](https://developer.apple.com/documentation/avkit/choosing-a-camera-by-the-direction-it-faces) |
| A direction coordinator (main-actor, tied to a view) handles cameras and UI as the phone opens and closes | Apple. Confirmed 2026-10-26 (Apple docs JSON): it's `AVCaptureDeviceDirectionCoordinator` in **AVKit**, iOS 27.1, `init(view:deviceTypes:changeHandler:)`. It reports an `AVCaptureDeviceDirectionMap` (forward- and backward-facing `AVCaptureDeviceDescriptor`s), relative to that view | [AVCaptureDeviceDirectionCoordinator](https://developer.apple.com/documentation/avkit/avcapturedevicedirectioncoordinator) |
| Camera sensor orientation compensation is on for all Duo front cameras. Apple suggests disabling it after adopting the rotation coordinator | Apple, with a limit found 2026-10-26 (Apple docs JSON): the switch is `AVCapturePhotoOutput.isCameraSensorOrientationCompensationEnabled` (iOS 26). It applies to **still photos only**, not to `AVCaptureVideoDataOutput`, so it doesn't affect us | [Tech talk 111465](https://developer.apple.com/videos/play/tech-talks/111465/), [property](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput/iscamerasensororientationcompensationenabled) |
| Scene accessories let an app show content on several displays at once. `CameraCaptureAccessory` pairs UI on the outer display for camera apps. New windows can't be created on the outer display | Apple. Confirmed 2026-10-26 (Apple docs JSON): SwiftUI `.sceneAccessory { CameraCaptureAccessory(isEnabled:) { … } }` (iOS 27.1, modifier 27.0); UIKit `UISceneAccessory.cameraCapture(sceneConfiguration:)` with `UIViewController.registerSceneAccessory(_:)`. No Info.plist entry is needed | [CameraCaptureAccessory](https://developer.apple.com/documentation/swiftui/cameracaptureaccessory), [article](https://developer.apple.com/documentation/avfoundation/registering-a-camera-capture-accessory-on-iphone-duo) |
| The accessory is shown only while the device is open, the app is in the foreground, a capture session is running, and the main capture UI is on the inner display ("full screen", per the talk). It's dismissed when the device is folded closed. Its content can be interactive. The system decides when to show it | Apple, 2026-10-26 | Apple docs JSON, article above, [Tech talk 111464](https://developer.apple.com/videos/play/tech-talks/111464) |
| The system's Duo Preview shows the live camera preview on the outer display | Apple | [Newsroom](https://www.apple.com/my/newsroom/2026/09/apple-unveils-iphone-duo/) |
| There's intentionally no API to ask "am I on the inner or the outer display?" | Apple (forum reply) | [Forum 847995](https://developer.apple.com/forums/thread/847995) |
| A third-party app can show a live inner-camera preview on the cover display while partially open | Unknown, now plausible: the accessory route fits Posture A (main UI on the inner display, game on the cover). Still open: does a roughly 90° "L" count as open? Does a pre-27-SDK (letterboxed) build qualify? Can the accessory show the preview? And it needs the 27.1 SDK to compile (2026-10-26, Apple docs JSON) | **P4** decides Posture A vs B |
| Apps built with a pre-27 SDK run on the Duo in a compatibility (letterboxed) layout. Full screen needs the 27.1 SDK. The inner display doesn't honour supported interface orientations. Avoid `UIScreen.main` | Apple, 2026-10-26 | [Tech talk 111461](https://developer.apple.com/videos/play/tech-talks/111461/) transcript |
| Which half holds the motion sensors (so what `CMDeviceMotion.attitude` describes in Posture A) | Unknown | **P5/P7**: log attitude through a close |
| ARKit world tracking can run alongside an inner-camera capture | Unknown, doubtful | **P7** |
| `AVCaptureMultiCamSession` supports rear + inner front | Unknown | **P8** |
| The inner camera image is sharp enough for patch tracking | Unknown | **P3/P9** |
| Which frame edge is nearest the hinge in Posture A | Unknown | **P3** |

## Tooling

| Fact | Status | Source |
|---|---|---|
| Swift Playgrounds on iPad builds iPhone and iPad apps and uploads to App Store Connect. TestFlight distributes from there. Needs an Apple Developer account | Apple | [Playgrounds guide](https://support.apple.com/guide/playgrounds-ipad/itc65b2d9a15/ipados) |
| Playgrounds has historically lagged the newest SDK. Around the 2026 Swift Student Challenge it still lacked the OS 26 SDK, until version 4.7 shipped | Apple (forum) | [Forum 812429](https://developer.apple.com/forums/thread/812429) |
| Whether current Playgrounds builds against the iOS 27.1 SDK | Probably not. The latest version found is Swift Playground 4.7 (March 2026, "Swift 6 and the iOS 26 SDK"), and no 27.x-SDK update was found on 2026-10-26. If so, no iOS 27.x symbol compiles, even behind `#available` | Reported (App Store text via search results), [Forum 812429](https://developer.apple.com/forums/thread/812429). **P5** (does `UIHingeInteraction` compile?) and the version number on the iPad settle it |
| Since 28 April 2026, App Store Connect uploads need the iOS 26 SDK or later, so a Playground 4.7 build can be uploaded | Apple, 2026-10-26 | [Upcoming requirements](https://developer.apple.com/news/upcoming-requirements/) |
| The app was renamed "Swift Playground" (singular). Release notes now live at developer.apple.com/swift-playground/release-notes/, and are stale (they stop at 4.6) | Apple, 2026-10-26 | [Release notes](https://developer.apple.com/swift-playground/release-notes/) |
| Playgrounds projects can be moved through iCloud Drive, or through git with Working Copy | Reported | [atrinh0/spiro](https://www.github.com/atrinh0/spiro) |
| Xcode 27.1 has an iPhone Duo simulator. Unusable here: no Mac | Reported | [iThinkDiff](https://www.ithinkdiff.com/?p=347302) |
