# API notes: what the app layer codes against

The single source of truth for app-layer signatures. Engineers can't compile iOS code, so copy declarations from here exactly.

- **Verified**: seen on 2026-10-26 in Apple's documentation JSON (`https://developer.apple.com/tutorials/data/documentation/<path>.json`) or in a tech talk's transcript or code.
- **Unverified**: from memory, inference or third-party sources. Treat it as a guess and isolate it behind a protocol or a runtime check.
- **Avail.**: `introducedAt` for iOS from the JSON. Doc links drop the `tutorials/data` prefix and the `.json` suffix.

Doc base for the links below: `https://developer.apple.com/documentation/`

## 0. The headline: the SDK gap

| Finding | Status | Evidence |
|---|---|---|
| Every Duo-specific API is **iOS 27.1** (`UIHingeInteraction`, `UIHinge`, SwiftUI `onHingeChange`, `DeviceHinge`, `CameraCaptureAccessory`, `UISceneAccessory.cameraCapture`, `AVCaptureDeviceDirectionCoordinator`, `.builtInInnerUltraWideCamera`, `.builtInOuterUltraWideCamera`, `ReservedRegion`). `sceneAccessory(content:)`, `UISceneAccessory` and `registerSceneAccessory(_:)` are 27.0 | Verified | Apple docs JSON |
| The latest Swift Playground (now singular, "Swift Playground") found is **4.7, March 2026: Swift 6 + iOS 26 SDK**. I found no 27.x-SDK release as of 2026-10-26. Apple's release-notes page is stale (it stops at 4.6) | Unverified: App Store text quoted by search results, plus a DTS forum post confirming that 4.7 shipped | [Forum 812429](https://developer.apple.com/forums/thread/812429), [release notes](https://developer.apple.com/swift-playground/release-notes/) |
| **Consequence:** in Playgrounds, none of the 27.x symbols above will compile, even inside `if #available(iOS 27.1, *)`, because the SDK doesn't declare them. Reach them through the Objective-C runtime (section 6) or not at all. Settle this in P5 by checking the iPad's Playground version and seeing whether `UIHingeInteraction` compiles | Inference | Follows from the two rows above |
| An app built with a pre-27 SDK still runs on the Duo, in a compatibility layout: closed, it uses the space left of the status bar and camera. Open, it runs at "a familiar size and aspect ratio" (letterboxed). Full-screen edge-to-edge needs the 27.1 SDK | Verified | Tech talk [111461](https://developer.apple.com/videos/play/tech-talks/111461/) |
| App Store Connect has required the iOS 26 SDK or later since 28 April 2026, so a 4.7 build can be uploaded. Also since 9 Sept 2026: apps must target iOS 13 or later | Verified | [Upcoming requirements](https://developer.apple.com/news/upcoming-requirements/) |

## 1. Hinge

### UIKit (Verified, iOS 27.1, all `@MainActor`)

| API | Declaration | Doc | Note |
|---|---|---|---|
| Class | `@MainActor class UIHingeInteraction` (NSObject, `UIInteraction`, `Sendable`) | `uikit/uihingeinteraction` | Add it to a view with `view.addInteraction(_:)` |
| Init | `init(updateHandler: @escaping (UIHingeInteraction, UIHingeInteraction.Update) -> Void)` | `uikit/uihingeinteraction/init(updatehandler:)` | Called with the **initial state**, then on every change, and again when the interaction moves between hierarchies. The closure escapes: use `[weak self]` |
| Enable | `var isEnabled: Bool { get set }` | `uikit/uihingeinteraction/isenabled` | While disabled, updates are dropped, not queued. On re-enable, the handler is called with the current state |
| Update | `@MainActor class Update` (`UIHingeInteraction.Update`) | `uikit/uihingeinteraction/update` | Its only member is `hinge` |
| | `var hinge: UIHinge?` | `uikit/uihingeinteraction/update/hinge` | nil = the view left a hierarchy that provides hinge updates (or there is no hinge) |
| Hinge | `@MainActor class UIHinge` (NSObject, `NSCopying`, `Sendable`) | `uikit/uihinge` | It has **only** `angle` and `status`. There is no identifier, axis or frame. For the hinge's position, use reserved regions (below) |
| | `var angle: CGFloat { get }` | `uikit/uihinge/angle` | Radians. Rate and precision are system policy. The docs don't say which way 0 and π go (see DUO_FACTS: Reported 0 = shut) |
| | `var status: UIHinge.Status { get }` | `uikit/uihinge/status-swift.property` | Prefer it when you only need closed, partly open or open |
| Status | `enum Status` with `init?(rawValue: Int)` | `uikit/uihinge/status-swift.enum` | Cases: **`closed`, `partiallyOpen`, `fullyOpen`, `unknown`**. Handle `unknown`. Raw values aren't documented (ObjC `NS_ENUM UIHingeStatus : NSInteger`) |

ObjC names (Verified), for runtime lookup: `UIHingeInteraction`, `UIHingeInteractionUpdate`, `UIHinge`, `- initWithUpdateHandler:(void (^)(UIHingeInteraction *, UIHingeInteractionUpdate *))`, `@property BOOL enabled` (getter `isEnabled`), `@property UIHinge *hinge` (on the update), `@property CGFloat angle`, `@property UIHingeStatus status`. Status constants are `UIHingeStatusClosed`, `UIHingeStatusPartiallyOpen`, `UIHingeStatusFullyOpen` and `UIHingeStatusUnknown`. **Their integer values are Unverified, so P5 must log the raw `status` integers next to the angle.**

### SwiftUI (Verified, iOS 27.1)

| API | Declaration | Doc | Note |
|---|---|---|---|
| Modifier | `nonisolated func onHingeChange(isEnabled: Bool = true, _ action: @escaping (DeviceHingeContext, DeviceHingeContext) -> Void) -> some View` | `swiftui/view/onhingechange(isenabled:_:)` | Arguments are (old, new) |
| Context | `struct DeviceHingeContext` with `var hinge: DeviceHinge?` | `swiftui/devicehingecontext` | nil = no hinge |
| Hinge | `struct DeviceHinge` with `var angle: Angle` and `var status: DeviceHinge.Status` | `swiftui/devicehinge` | **The angle is SwiftUI `Angle`, not `CGFloat`**, so use `.radians` |
| Status | `struct Status` with `static var closed`, `partiallyOpen`, `fullyOpen` | `swiftui/devicehinge/status-swift.struct` | **It's a struct, not an enum**, and it has no `unknown`. Compare with `==`; a `switch` needs `default` |

Apple's guidance: hinge data is "ideal for driving interactions or effects". For layout, use arrangement and reserved-region APIs (Verified, talk [111464](https://developer.apple.com/videos/play/tech-talks/111464)).

### Other hinge and posture APIs

- `UIDevice`, `UIScreen`, `UIWindowScene`, `UIScene`: **no hinge or posture members** (Verified, from walking their topic lists). The talk says to avoid `UIScreen.main` on a two-display device (it "will be deprecated") and to use `window?.windowScene?.screen` or `traitCollection.displayScale` (Verified, 111461).
- Reserved regions (Verified, 27.1). In SwiftUI: `GeometryProxy.reservedRegions(kind: ReservedRegion.Kind, options: ReservedRegion.QueryOptions = [], layoutDirectionBehavior: LayoutDirectionBehavior = .mirrors) -> [ReservedRegion]`. `ReservedRegion` has `frame: CGRect`, `margins: EdgeInsets`, `isActive: Bool`, `kind`, `id`. `Kind` is `.occlusion` or `.division`, and the query option is `.includeInactive`. In UIKit: `UIView.reservedRegions(kind: UIView.ReservedRegion.Kind, options: UIView.ReservedRegion.QueryOptions) -> [UIView.ReservedRegion]`. The fold is a `.division` region, active only while folded. The inner (under-display) camera is an `.occlusion` region on the inner display, active while that camera is in use. Doc: `swiftui/reservedregion`, `uikit/uiview/reservedregions(kind:options:)`.
- Size classes: the outer display behaves like an iPhone, and the inner display is regular × regular. **The inner display doesn't honour supported interface orientations** (Verified, 111461).

## 2. Duo cameras

### Device types (Verified)

| API | Declaration | Avail. | Doc | Note |
|---|---|---|---|---|
| Inner front | `static let builtInInnerUltraWideCamera: AVCaptureDevice.DeviceType` | 27.1 | `avfoundation/avcapturedevice/devicetype-swift.struct/builtininnerultrawidecamera` | Discoverable only through `DiscoverySession`. Full capabilities: up to 1080p at 60 fps |
| Outer front | `static let builtInOuterUltraWideCamera: AVCaptureDevice.DeviceType` | 27.1 | `…/builtinouterultrawidecamera` | Up to 4K at 120 fps |
| Virtual front camera | **No new device type.** Use `DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera], mediaType: .video, position: .front)`. On the Duo, this returns the virtual front camera | old types | `avkit/choosing-a-camera-by-the-direction-it-faces` | It streams from the camera over the display the app is on, and follows the app when the phone opens or closes. `isVirtualDevice == true`. Limited to the shared feature set: 1080p, 60 fps, no depth. **This compiles with the iOS 26 SDK** |
| Which camera is live | `var activePrimaryConstituent: AVCaptureDevice? { get }` (iOS 15) | 15.0 | `avfoundation/avcapturedevice/activeprimaryconstituent` | On the virtual front camera it gives the physical camera that's streaming. nil until the session runs |
| Constituents | `var constituentDevices: [AVCaptureDevice] { get }` (iOS 13) | 13.0 | `avfoundation/avcapturedevice/constituentdevices` | Should list the inner and outer devices. **Unverified:** whether you can add a constituent as an input directly. That's the old-SDK route to the inner camera, so P2 should log it |

ObjC constants (Verified): `AVCaptureDeviceTypeBuiltInInnerUltraWideCamera`, `AVCaptureDeviceTypeBuiltInOuterUltraWideCamera`. The string raw values are **Unverified**. Existing types use the constant's own name as the raw value, so `AVCaptureDevice.DeviceType(rawValue: "AVCaptureDeviceTypeBuiltInInnerUltraWideCamera")` is a plausible old-SDK fallback. P2 must log `deviceType.rawValue` for every device it finds.

**Posture A warning (Inference):** with the phone open, the virtual front camera streams from the camera over the display the app is on. If the main UI is on the inner display (the `CameraCaptureAccessory` case), that's the inner camera, which is what we want. But the system picks, so check `activePrimaryConstituent`.

### Direction coordinator (Verified, AVKit, iOS 27.1, `import AVKit`)

| API | Declaration | Doc | Note |
|---|---|---|---|
| Class | `class AVCaptureDeviceDirectionCoordinator` (NSObject, not `Sendable`) | `avkit/avcapturedevicedirectioncoordinator` | Create and use it **on the main actor only**. Keep a strong reference while the view is on screen. Create one per preview view |
| Init | `init(view: UIView, deviceTypes: [AVCaptureDevice.DeviceType], changeHandler: ((AVCaptureDeviceDirectionMap) -> Void)? = nil)` | `…/init(view:devicetypes:changehandler:)` | List the physical cameras (`.builtInOuterUltraWideCamera`, `.builtInInnerUltraWideCamera`) and the rear ones. It ignores the virtual front camera and external cameras. The handler runs on the main actor soon after init, then on every change. Don't call AVFoundation from it |
| State | `var deviceDirections: AVCaptureDeviceDirectionMap { get }` | `…/devicedirections` | Empty until the first callback |
| Map | `class AVCaptureDeviceDirectionMap` (`Sendable`) | `avkit/avcapturedevicedirectionmap` | Members: `var forwardFacingDeviceDescriptors: [AVCaptureDeviceDescriptor]` (same way as the view, towards its viewer) and `var backwardFacingDeviceDescriptors: [AVCaptureDeviceDescriptor]`. Either can be empty |
| Descriptor | `class AVCaptureDeviceDescriptor` (`Sendable`, `Equatable`) | `avkit/avcapturedevicedescriptor` | Members: `uniqueID: String`, `localizedName: String`, `deviceType: AVCaptureDevice.DeviceType`, `mediaTypes: Set<AVMediaType>`, `position: AVCaptureDevice.Position`. Resolve it on the capture actor with `AVCaptureDevice(uniqueID:)`, which can return nil |
| ObjC | `- initWithView:(UIView *)view deviceTypes:(NSArray<NSString *> *)deviceTypes changeHandler:(void (^)(AVCaptureDeviceDirectionMap *))changeHandler` | | For runtime lookup |

How it applies to Posture A (Inference from the docs): if the view is on the **cover display**, the inner front camera faces *away* from the viewer. Look for it in `backwardFacingDeviceDescriptors`, not forward. Decide mirroring from the map, not from `position`. To override mirroring, set `connection.automaticallyAdjustsVideoMirroring = false` **before** `isVideoMirrored`, or it raises an exception (Verified). Apple recommends reconfiguring one input over using multi-cam.

### Rotation and orientation

- `AVCaptureDevice.RotationCoordinator` (iOS 17): `init(device: AVCaptureDevice, previewLayer: CALayer?)`, `videoRotationAngleForHorizonLevelPreview: CGFloat`, `videoRotationAngleForHorizonLevelCapture: CGFloat`. Make a new one per camera switch. On the Duo, the angle also changes when the app moves between displays. Apply it with `AVCaptureConnection.videoRotationAngle: CGFloat` (check `isVideoRotationAngleSupported(_:)` first). Verified. Doc: `avfoundation/avcapturedevice/rotationcoordinator`.
- **Sensor orientation compensation** is `AVCapturePhotoOutput.isCameraSensorOrientationCompensationEnabled: Bool { get set }` and `isCameraSensorOrientationCompensationSupported: Bool { get }`, iOS **26.0**. Per the docs it rotates **still photos only** (HEIC, JPEG, processed). **It doesn't touch `AVCaptureVideoDataOutput`**, so we can ignore it: we never add a photo output. Verified. Doc: `avfoundation/avcapturephotooutput/iscamerasensororientationcompensationenabled`.
- The front sensors are square. `AVCaptureDevice.dynamicAspectRatio: AVCaptureDevice.AspectRatio?` and `setDynamicAspectRatio(_:completionHandler:)` exist (Verified, from the topic list). Not needed for us.
- ARKit (iOS 27, "June 2026"): orientation-independent `viewRotationAngle` variants on `ARCamera` and `ARFrame`. Relevant because the inner display ignores interface orientation. Exact signatures **Unverified** (`updates/arkit`).

## 3. Displays, scenes and the cover display

### SwiftUI scene accessory (Verified; our app is SwiftUI, so this is the route)

| API | Declaration | Avail. | Doc |
|---|---|---|---|
| Modifier | `nonisolated func sceneAccessory<C>(@ContentBuilder content: () -> C) -> some View where C : SceneAccessoryContent` | 27.0 | `swiftui/view/sceneaccessory(content:)` |
| Accessory | `nonisolated struct CameraCaptureAccessory<Content> where Content : View`, conforms to `SceneAccessoryContent` | **27.1** | `swiftui/cameracaptureaccessory` |
| | `nonisolated init(@ContentBuilder content: @escaping () -> Content)` | 27.1 | `…/init(content:)` |
| | `nonisolated init(isEnabled: Binding<Bool>, @ContentBuilder content: @escaping () -> Content)` | 27.1 | `…/init(isenabled:content:)` |
| Availability | `func onAvailabilityChange(perform: (Bool) -> Void) -> some SceneAccessoryContent` (on `SceneAccessoryContent`, a `@MainActor protocol`) | 27.0 | `swiftui/sceneaccessorycontent` |
| Sibling | `ExternalNonInteractiveAccessory` (external display or AirPlay, non-interactive) | 27.0 | `swiftui/externalnoninteractiveaccessory` |

(`ContentBuilder` is a typealias for `ViewBuilder`.) Usage, from talk 111464:

```swift
CameraView(model: model)
    .sceneAccessory {
        CameraCaptureAccessory(isEnabled: $model.isEnabled) {
            CoverView(model: model)
        }
        .onAvailabilityChange { model.isAvailable = $0 }
    }
```

### UIKit equivalent (Verified)

- `@MainActor class UISceneAccessory` (27.0): `class func cameraCapture(sceneConfiguration: UISceneConfiguration) -> Self` and `class func cameraCapture(sceneConfiguration: UISceneConfiguration, userInfo: Any) -> Self` (both 27.1). ObjC: `+cameraCaptureSceneAccessoryWithConfiguration:` and `+cameraCaptureSceneAccessoryWithConfiguration:userInfo:`.
- `UIViewController.registerSceneAccessory(_ accessory: UISceneAccessory) -> UISceneAccessoryRegistration` and `unregisterSceneAccessory(_ registration: UISceneAccessoryRegistration)` (27.0).
- `@MainActor class UISceneAccessoryRegistration` (27.0): `var isAvailable: Bool { get }` and `var isEnabled: Bool { get set }`.
- `UISceneSession.Role.windowCameraCaptureAccessory` (27.1). The system assigns it; use it to identify the accessory scene in a scene delegate. `UIScene.ConnectionOptions.sceneAccessoryUserInfo: Any?` (27.0).

### Rules (Verified: the article `avfoundation/registering-a-camera-capture-accessory-on-iphone-duo`, talk 111464, `updates/swiftui`)

- **Where content appears:** on the **outer (cover) display**, while the device is **open**, the app is in the **foreground**, a **capture session is running**, and the main capture UI is **on the inner display** ("full screen on the inner display", from the talk). The system decides whether and where, and can withdraw it at any time.
- The content **can be interactive**: the outer display accepts touch. Apple suggests a single task, such as tapping the preview to focus, and gives "show how much of the subject the camera sees" as an example, which implies a preview there is in scope.
- Attach it to the same view as the capture UI. Only the top-most registration of a kind is presented.
- **No Info.plist or scene-manifest entry is needed.** A manifest entry for an accessory scene has no effect.
- Content goes away when capture stops, when the app leaves the foreground, or **when the device is folded closed**.
- New windows can't be created on the outer display (use `UIWindowSceneActivationAction`, which hides itself when unavailable).

What this means for Posture A (Inference): the intended shape is "main UI on the inner display, which faces the room in Posture A; game UI on the cover display through `CameraCaptureAccessory`". That fits our posture. Three things only P4 can settle: (a) whether a roughly 90° "L" counts as open, (b) whether a second preview of the same session works inside the accessory, or whether we draw frames from `AVCaptureVideoDataOutput` ourselves, (c) whether a **letterboxed pre-27-SDK build** counts as "full screen on the inner display". And it needs the 27.1 SDK to compile (section 0).

### On fold close (Verified, 111461, 111465, the accessory article)

The app moves to the outer display and resizes. Size classes change. The accessory content is dismissed. The virtual front camera switches to the outer camera. A direction coordinator calls its handler, and the rotation angle changes. That folding doesn't background the app, and that capture keeps running, is Inference: the talks describe the app continuing on the outer display. P5 and P6 should log scene-phase changes and capture interruptions during a close.

## 4. Long-established APIs (Verified in the JSON unless marked)

### Capture

| API | Declaration | Avail. |
|---|---|---|
| Discovery | `convenience init(deviceTypes: [AVCaptureDevice.DeviceType], mediaType: AVMediaType?, position: AVCaptureDevice.Position)` and `var devices: [AVCaptureDevice] { get }` | 10.0 |
| Device by ID | `init?(uniqueID deviceUniqueID: String)` | 4.0 |
| Input | `AVCaptureDeviceInput.init(device: AVCaptureDevice) throws` | 4.0 |
| Session | `class AVCaptureSession` (**not `Sendable`**): `beginConfiguration()`, `commitConfiguration()`, `canAddInput(_:) -> Bool`, `addInput(_:)`, `canAddOutput(_:)`, `addOutput(_:)`, `sessionPreset`, `startRunning()`, `stopRunning()` (both block, so call them off the main thread), `isRunning`, `isInterrupted` | 4.0 |
| Video output | `setSampleBufferDelegate(_ sampleBufferDelegate: (any AVCaptureVideoDataOutputSampleBufferDelegate)?, queue sampleBufferCallbackQueue: dispatch_queue_t?)`, `var videoSettings: [String : Any]!`, `var alwaysDiscardsLateVideoFrames: Bool` | 4.0 |
| Delegate | `protocol AVCaptureVideoDataOutputSampleBufferDelegate : NSObjectProtocol` with `optional func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection)` and `optional func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection)` | 4.0 / 6.0 |
| Multi-cam | `class var isMultiCamSupported: Bool { get }` on `AVCaptureMultiCamSession` | 13.0 |
| Auth | `class func authorizationStatus(for mediaType: AVMediaType) -> AVAuthorizationStatus`, `class func requestAccess(for mediaType: AVMediaType, completionHandler handler: @escaping @Sendable (Bool) -> Void)` and `class func requestAccess(for mediaType: AVMediaType) async -> Bool` | 7.0 |
| Virtual device | `var isVirtualDevice: Bool { get }` | 13.0 |

Interruption notifications (all `class let …: NSNotification.Name` on `AVCaptureSession`):

- `wasInterruptedNotification`. Its userInfo key is `AVCaptureSessionInterruptionReasonKey: String`, whose value is an `NSNumber` holding `AVCaptureSession.InterruptionReason.RawValue` (Int). Build it with `InterruptionReason(rawValue:)`. The other key is `AVCaptureSessionInterruptionSystemPressureStateKey`.
- `interruptionEndedNotification`
- `runtimeErrorNotification`, with the userInfo key `AVCaptureSessionErrorKey`, whose value is an `NSError`
- `didStartRunningNotification` and `didStopRunningNotification`

`InterruptionReason` cases: `videoDeviceNotAvailableInBackground`, `audioDeviceInUseByAnotherClient`, `videoDeviceInUseByAnotherClient`, `videoDeviceNotAvailableWithMultipleForegroundApps` (relevant to Duo split view), `videoDeviceNotAvailableDueToSystemPressure`, `sensitiveContentMitigationActivated`. Log every case P7 hits.

### ARKit

- `class var isSupported: Bool { get }` on `ARConfiguration` (inherited by `ARWorldTrackingConfiguration` and `ARFaceTrackingConfiguration`). `ARFaceTrackingConfiguration.supportsWorldTracking: Bool` (13.0). Also `ARWorldTrackingConfiguration.supportsUserFaceTracking: Bool` (13.0), which is worth logging in P1.
- `ARSession`: `func run(_ configuration: ARConfiguration, options: ARSession.RunOptions = [])`, `pause()`, `var delegate: (any ARSessionDelegate)?`, `var delegateQueue: dispatch_queue_t?`, `var currentFrame: ARFrame?`.
- `ARSessionDelegate`: `optional func session(_ session: ARSession, didUpdate frame: ARFrame)`. `ARSessionObserver`: `session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera)`, `sessionWasInterrupted(_ session: ARSession)`, `sessionInterruptionEnded(_ session: ARSession)`, `session(_ session: ARSession, didFailWithError error: any Error)`.
- `@frozen enum ARCamera.TrackingState`: `notAvailable`, `limited(ARCamera.TrackingState.Reason)`, `normal`. `ARFrame` is `Sendable`.

### Core Motion

- `CMMotionManager` (not `Sendable`): `var isDeviceMotionAvailable: Bool`, `var deviceMotionUpdateInterval: TimeInterval`, `func startDeviceMotionUpdates(using referenceFrame: CMAttitudeReferenceFrame, to queue: OperationQueue, withHandler handler: @escaping CMDeviceMotionHandler)`, `func startDeviceMotionUpdates(to queue: OperationQueue, withHandler handler: @escaping CMDeviceMotionHandler)`, `var deviceMotion: CMDeviceMotion?`, `class func availableAttitudeReferenceFrames() -> CMAttitudeReferenceFrame`.
- `typealias CMDeviceMotionHandler = (CMDeviceMotion?, (any Error)?) -> Void` (**not `@Sendable`**). `CMDeviceMotion.attitude: CMAttitude`, `rotationRate: CMRotationRate`, `userAcceleration: CMAcceleration`. `CMAttitude` has `roll`, `pitch`, `yaw: Double`, `quaternion`, `rotationMatrix` and `multiply(byInverseOf:)`.
- Duo unknown: which half holds the IMU, so which half the attitude describes. P5 or P7 should log attitude through a close.

### Vision (classic API, not deprecated)

- `VNDetectedObjectObservation`: `convenience init(boundingBox: CGRect)` (normalised, origin bottom-left) and `var boundingBox: CGRect`. `VNObservation.confidence: VNConfidence`.
- `VNTrackObjectRequest`: `init(detectedObjectObservation observation: VNDetectedObjectObservation)` and `init(detectedObjectObservation observation: VNDetectedObjectObservation, completionHandler: VNRequestCompletionHandler? = nil)`. Inherited from `VNTrackingRequest`: `var inputObservation: VNDetectedObjectObservation`, `var trackingLevel: VNRequestTrackingLevel` (`.accurate` or `.fast`), `var isLastFrame: Bool`. `VNRequest.results: [VNObservation]?`.
- `VNSequenceRequestHandler`: `init()`, `func perform(_ requests: [VNRequest], on pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) throws`, `func perform(_ requests: [VNRequest], on sampleBuffer: CMSampleBuffer, orientation: CGImagePropertyOrientation) throws` (14.0).
- The Swift-native `TrackObjectRequest` (`final class`, iOS 18) exists, with `async` `perform(on:orientation:)`. Stick to the VN API, which is simpler to keep synchronous on the capture queue.

### Audio

- `AVAudioEngine`: `attach(_ node: AVAudioNode)`, `start() throws`, `mainMixerNode: AVAudioMixerNode`, `connect(_ node1: AVAudioNode, to node2: AVAudioNode, format: AVAudioFormat?)`.
- `AVAudioPlayerNode` (`Sendable`): `play()`, `scheduleBuffer(_ buffer: AVAudioPCMBuffer, at when: AVAudioTime?, options: AVAudioPlayerNodeBufferOptions = [], completionHandler: (@Sendable () -> Void)? = nil)` (plus an `async` overload), `scheduleFile(_:at:completionHandler:)`. `var pan: Float { get set }` comes from `AVAudioStereoMixing`, and `var volume: Float { get set }` from `AVAudioMixing`.
- `AVAudioSession.setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions = []) throws`.

### Haptics

- `@MainActor class UIImpactFeedbackGenerator`: `init(style: UIImpactFeedbackGenerator.FeedbackStyle)`, `convenience init(style:view:)` (17.5), `prepare()`, `impactOccurred()`, `impactOccurred(intensity: CGFloat)` (13.0), `impactOccurred(at: CGPoint)` and `impactOccurred(intensity:at:)`.

### Deprecated in iOS 27.0 (Verified; warnings only, not errors)

| Deprecated | Replacement | What we do |
|---|---|---|
| `AVAudioEngine.connect(_:to:format:)` | `connectNode(_:to:format:) throws` (27.0) | Keep `connect`. The replacement isn't in the iOS 26 SDK |
| `AVAudioPlayerNode.play()` | `playAudio() throws` (27.0) | Keep `play()` |
| `UIImpactFeedbackGenerator.init(style:)` | `init(style:view:)` (17.5) | **Use `init(style:view:)` now**: it's in both SDKs |
| `AVCaptureDevice.DeviceType.builtInDuoCamera` (deprecated since 10.2, unrelated to the iPhone Duo) | `.builtInDualCamera` | Don't let the name mislead you |

### Swift 6 strict-concurrency traps (Unverified for the iOS 26 SDK; annotations taken from the 27.x docs)

1. `AVCaptureSession`, `AVCaptureDevice`, `CMMotionManager`, `CMDeviceMotion` and `VNTrackObjectRequest` are **not `Sendable`**. Keep each one owned by a single actor or a serial queue. Don't capture them in a `Task` that hops actors.
2. A sample-buffer delegate that is `@MainActor` (for example a SwiftUI `@Observable` model) and receives callbacks on a background queue gives a conformance-isolation error, or a runtime isolation trap. Make the delegate a separate `final class … : NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable` and mark its methods `nonisolated`.
3. `CMDeviceMotionHandler` isn't `@Sendable`. A closure written inside `@MainActor` code is inferred as main-actor isolated, and **traps at run time** if the handler runs on a background `OperationQueue`. Pass `OperationQueue.main`, or build the closure in a `nonisolated` function.
4. `CMSampleBuffer` and `CVPixelBuffer` are not `Sendable` in the docs. Process frames on the capture queue, and send only value types (FlyCore inputs) to the main actor.
5. `UIHingeInteraction`'s handler and the direction coordinator's handler run on the main actor. That suits SmashDetector input, provided timestamps come from `CACurrentMediaTime()` at callback time (the hinge update carries no timestamp: Verified, it has no time member).

## 5. Swift Playground (app on the iPad)

| Item | Status | Detail |
|---|---|---|
| Latest version | Unverified | 4.7 (March 2026), "includes Swift 6 and the iOS 26 SDK" (App Store text quoted in search results). No later version found. **Developer: check Settings → Apps / the App Store page on the iPad and report the version** |
| Builds with the iOS 27.1 SDK? | Unverified, probably not | So `UIHingeInteraction`, `CameraCaptureAccessory` and the rest won't compile. P5 confirms it with a one-line compile test |
| Language mode | Unverified | Swift 6 compiler. Whether new projects default to Swift 6 *language mode* (strict concurrency errors) depends on `swift-tools-version` in the generated `Package.swift`. Write code that is Swift 6-clean anyway (section 4) |
| App Store Connect upload | Verified (requirement), Unverified (that it works) | The iOS 26 SDK minimum since 28 April 2026 is met by 4.7. Needs a paid developer account signed in to Playgrounds |
| Capabilities and privacy strings | Unverified | Set in the app's settings in Playgrounds (Capabilities: Camera, Motion…). Playgrounds writes them into `Package.swift` as `capabilities: [.camera(purposeString: "…"), .motion(purposeString: "…")]` in the `.iOSApplication` product. Don't hand-edit it. A forum report says adding a capability once crashed Playgrounds and a reinstall fixed it |
| On-disk layout | Unverified (from memory; inspect in Phase 0) | `Name.swiftpm/` holds `Package.swift` (`import PackageDescription`, `import AppleProductTypes`, `products: [.iOSApplication(name:targets:bundleIdentifier:teamIdentifier:displayVersion:bundleVersion:appIcon:accentColor:supportedDeviceFamilies:supportedInterfaceOrientations:capabilities:)]`, `targets: [.executableTarget(name: "AppModule", path: ".")]`), **root-level** `.swift` files (`MyApp.swift` with `@main`, `ContentView.swift`) and `Assets.xcassets`. Because `path: "."` (if confirmed), any `.swift` file in the project folder or its subfolders compiles. So the sync script can copy into a subfolder such as `Synced/FlyCore/` and `Synced/App/`, and never touch root files or `Package.swift`. **Confirm `path:` before writing `to-ipad.ps1`** |

## 6. Runtime-lookup sketch for the 27.x APIs on an iOS 26 SDK (Unverified: untested pattern)

The ObjC class and selector names are Verified. The calling technique is a standard Objective-C runtime pattern, but nobody has tested it against these classes.

```swift
// Hinge without compile-time symbols. Returns nil when unavailable.
@MainActor
func makeHingeInteraction(_ onUpdate: @escaping (_ angle: Double?, _ statusRaw: Int?) -> Void) -> UIInteraction? {
    guard let cls = NSClassFromString("UIHingeInteraction") as? NSObject.Type else { return nil }
    let block: @convention(block) (AnyObject, AnyObject) -> Void = { _, update in
        guard let hinge = update.value(forKey: "hinge") as? NSObject else { onUpdate(nil, nil); return }
        onUpdate((hinge.value(forKey: "angle") as? NSNumber)?.doubleValue,
                 (hinge.value(forKey: "status") as? NSNumber)?.intValue)
    }
    let sel = NSSelectorFromString("initWithUpdateHandler:")
    typealias Init = @convention(c) (AnyObject, Selector, Any) -> AnyObject
    guard let alloc = (cls as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
          let imp = (alloc as AnyObject).method(for: sel) else { return nil }
    let obj = unsafeBitCast(imp, to: Init.self)(alloc, sel, block)
    return obj as? UIInteraction
}
```

- Hold the returned interaction (the view retains it once added). The status raw-value mapping is unknown until P5.
- Inner camera on an old SDK, in order of preference: (1) the virtual front camera plus `activePrimaryConstituent`, which works in compiled code; (2) `constituentDevices`, choosing the one whose `deviceType.rawValue` contains `Inner`; (3) `AVCaptureDevice.DeviceType(rawValue: "AVCaptureDeviceTypeBuiltInInnerUltraWideCamera")` in a `DiscoverySession`.
- `CameraCaptureAccessory` is a generic SwiftUI struct, so it **can't** be reached through the ObjC runtime. A UIKit route via `registerSceneAccessory:` and `+cameraCaptureSceneAccessoryWithConfiguration:` is possible in theory, but it needs a `UISceneConfiguration` with our own `UIWindowSceneDelegate` class and the hosting controller of the SwiftUI view. That's high risk. Try it in P4 only as an experiment, and log every step.

## Sources consulted (2026-10-26)

- Apple docs JSON: every `uikit/`, `swiftui/`, `avkit/`, `avfoundation/`, `arkit/`, `coremotion/`, `vision/`, `avfaudio/` path cited above, and `updates/swiftui`, `updates/uikit`, `updates/avkit`, `updates/arkit`.
- Articles: `avkit/choosing-a-camera-by-the-direction-it-faces`, `avfoundation/registering-a-camera-capture-accessory-on-iphone-duo`, `avfoundation/supporting-device-rotation-in-your-camera-app`.
- Tech talks (transcripts and code on the page): [111465](https://developer.apple.com/videos/play/tech-talks/111465/), [111464](https://developer.apple.com/videos/play/tech-talks/111464/), [111461](https://developer.apple.com/videos/play/tech-talks/111461/), [111463](https://developer.apple.com/videos/play/tech-talks/111463/).
- [Upcoming requirements](https://developer.apple.com/news/upcoming-requirements/), [Swift Playground release notes](https://developer.apple.com/swift-playground/release-notes/) (stale), [Forum 812429](https://developer.apple.com/forums/thread/812429).
