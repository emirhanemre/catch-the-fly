# FlyCore API reference

FlyCore is the game logic for Catch the Fly: Foundation only, no UIKit/ARKit/simd, deterministic, unit tested.
The app layer converts platform data into FlyCore's input types, calls `FlyGame.step` once per frame, and draws
and plays what comes back.

The app does **not** `import FlyCore`: `scripts/to-ipad.ps1` copies `Sources/FlyCore/*.swift` into the app
module, so every type below is used by its bare name. Every public type is a value type (`struct` or `enum`),
`Sendable` and `Equatable`, except the `BestTimeStore` protocol.

Units everywhere: metres, seconds, radians, radians per second, metres per second. Screen positions are
normalised: x 0 (left) to 1 (right), y 0 (top) to 1 (bottom), of the camera picture **as displayed**.

## Contents

1. [Each frame: how the app layer uses FlyCore](#1-each-frame-how-the-app-layer-uses-flycore)
2. [FlyGame (the façade)](#2-flygame-the-façade)
3. [Math: Vec3, FlyMath, FlyRNG](#3-math-vec3-flymath-flyrng)
4. [FlyCamera, FlyScreenPoint](#4-flycamera-flyscreenpoint)
5. [FlyTunables and presets](#5-flytunables-and-presets)
6. [The fly: FlyAgent and friends](#6-the-fly-flyagent-and-friends)
7. [DistanceEstimator, PatchReferencePolicy](#7-distanceestimator-patchreferencepolicy)
8. [SmashDetector](#8-smashdetector)
9. [HitJudge](#9-hitjudge)
10. [FlyRound and BestTimeStore](#10-flyround-and-besttimestore)
11. [AudioMath](#11-audiomath)
12. [FlyLog](#12-flylog)

---

## 1. Each frame: how the app layer uses FlyCore

### Setup (once)

```swift
// The app implements the store (FlyCore never touches UserDefaults).
struct DefaultsBestTimeStore: BestTimeStore {
    func loadBestTime() -> Double? {
        let v = UserDefaults.standard.double(forKey: "bestTime")
        return v > 0 ? v : nil
    }
    func saveBestTime(_ seconds: Double) {
        UserDefaults.standard.set(seconds, forKey: "bestTime")
    }
}

let store = DefaultsBestTimeStore()
let preset = FlyPreset.iPadPrototype                  // or .duoPostureA / .duoPostureB
var game = FlyGame(tunables: preset.tunables,
                   seed: UInt64(42),                  // any seed; fixed seeds replay identically
                   hingeEdge: preset.hingeEdge,       // `.centre` on the iPad; Duo: from spike P3
                   hingeAvailable: hingeAPIFound,     // e.g. NSClassFromString("UIHingeInteraction") != nil
                   store: store)
game.startRound()                                     // first fly appears on the next step
```

### Every frame (main thread)

Hinge updates arrive on the main thread; camera frames usually arrive on a capture queue. Buffer both into
arrays on the main thread (hop with `DispatchQueue.main.async` or `@MainActor` in the app layer) and hand
them over once per frame. All times must come from **one clock**, for example
`ProcessInfo.processInfo.systemUptime`. If you use camera frame timestamps for luma, check in the spike log
that they line up with that clock (they are expected to share the host clock, but this is not yet verified).

```swift
let now = ProcessInfo.processInfo.systemUptime
let input = FlyGameInput(
    time: now,
    camera: camera,                  // FlyCamera built from ARKit's transform or CoreMotion attitude
    spots: spots,                    // [LandingSpot]: tracked patches (route B) or world points (route A)
    distanceMeasurement: measurement,// .patchScale(...) in route B, nil to use world geometry
    distanceConfidence: trackerConfidence,
    distanceMeasuredAt: frameTime,   // the reading's camera-frame time; pass the latest every tick
    angularSpeed: rotationRateMagnitude,
    hingeSamples: pendingHinge,      // [HingeSample] since last frame, oldest first
    lumaSamples: pendingLuma,        // [LumaSample] since last frame, oldest first
    manualSmash: debugButtonTapped)
let out = game.step(input: input, dt: now - lastFrameTime)
lastFrameTime = now
pendingHinge.removeAll(); pendingLuma.removeAll(); debugButtonTapped = false

// Draw
if let fly = out.fly, let p = fly.screenPosition, p.isOnScreen { drawFly(at: p, state: fly.state) }
for splat in out.splats { drawSplat(at: splat.screenPosition) }

// Sound
buzzPlayer.volume = Float(out.audioGain)      // 0 when !out.buzzing
buzzPlayer.pan = Float(out.audioPan)          // -1 ... 1
for cue in out.cues { play(cue) }             // hit, miss, flyAlarmed, ... (see FlyGameCue)

// Persist and log
if let best = out.newBestTime { store.saveBestTime(best) }
sessionLog.append(contentsOf: out.logLines)
overlay.lines = FlyLog.overlayLines(out)
```

When `out.round.phase == .finished`, show the result and call `game.startRound()` for another go.

### Building the inputs

- **FlyCamera from ARKit** (routes A2 / P-B): with `let m = frame.camera.transform` (columns c0...c3):
  `right = c0.xyz`, `up = c1.xyz`, `forward = -c2.xyz`, `position = c3.xyz`. Fields of view must describe the
  picture as displayed (after any aspect-fill crop and rotation).
- **FlyCamera in route B**: `position = Vec3.zero` (the player is assumed to stand still), basis from the
  CoreMotion attitude rotation matrix, mapped to the displayed picture's right/up/forward.
- **LandingSpot in route B**: one per tracked patch, with a stable `id` while tracked:
  `position = camera.position + directionToPatch * estimatedPatchDistance`. A landed fly follows its spot.
  Drop a spot from the list when tracking is lost; the fly reacts (`spotLost`).
- **Distance**: route B keeps a `PatchReferenceBook` (section 7), calls `book.update(readings)` with each
  new tracker report, and passes `book.measurement(for:)` (a `.patchScale(ratio:referenceDistance:)`) for
  the patch the fly is on (`out.fly?.spotID`), with the tracker's confidence and `distanceMeasuredAt` set
  to the frame's timestamp. Pass the latest frame's reading on **every** tick: FlyCore counts each frame
  once and holds the distance in between. Spot positions use `book.distance(for:)`. Route A passes nil
  and FlyGame uses the camera-to-fly geometry.
- **HingeSample**: from `UIHingeInteraction`'s update handler: `HingeSample(angle: Double(hinge.angle),
  time: now, statusRaw: rawStatusInt)`. FlyCore maps the raw integer with `tunables.hingeStatusMapping`
  (a guess until spike P5). If the app has a typed status (native 27.1 build), pass `status:` instead.
- **LumaSample**: mean luma of each inner-camera frame, 0...1, with the frame's timestamp on the shared clock.
- **angularSpeed**: magnitude of `CMDeviceMotion.rotationRate` (rad/s).

---

## 2. FlyGame (the façade)

### `struct FlyGameInput`

| Member | Type | Notes |
|---|---|---|
| `time` | `Double` | Game clock (s). Same clock as all sample times. |
| `camera` | `FlyCamera` | |
| `spots` | `[LandingSpot]` | |
| `distanceMeasurement` | `DistanceMeasurement?` | nil: FlyGame uses `camera.distance(to: fly.position)` as `.world` with confidence 1. |
| `distanceConfidence` | `Double` | 0...1, used only with a measurement. |
| `distanceMeasuredAt` | `Double?` | When the measurement was made (camera frame time, same clock). nil: at `time`. A reading not newer than the last one counted is treated as none (distance held). |
| `angularSpeed` | `Double` | rad/s. |
| `hingeSamples` | `[HingeSample]` | Oldest first. |
| `lumaSamples` | `[LumaSample]` | Oldest first. |
| `manualSmash` | `Bool` | Debug button. |

```swift
public init(time: Double,
            camera: FlyCamera,
            spots: [LandingSpot] = [],
            distanceMeasurement: DistanceMeasurement? = nil,
            distanceConfidence: Double = 1.0,
            distanceMeasuredAt: Double? = nil,
            angularSpeed: Double = 0,
            hingeSamples: [HingeSample] = [],
            lumaSamples: [LumaSample] = [],
            manualSmash: Bool = false)
```

### `enum FlyGameCue: String, CaseIterable`

`roundStarted`, `newFly`, `flyAlarmed`, `flyTookOff`, `hit`, `miss`, `roundFinished`, `newBestTime`.

Suggested mapping: `hit` = heavy haptic + splat sound; `miss` = light haptic + smug buzz; `flyAlarmed` = alarm
buzz; `flyTookOff` = hover hum; `roundFinished` / `newBestTime` = fanfare. A miss also produces `flyAlarmed`
(the fly bolts).

### `struct SplatEvent`

| Member | Type | Notes |
|---|---|---|
| `time` | `Double` | |
| `screenPosition` | `FlyScreenPoint?` | Where the fly was just before the fold (from the judged snapshot). |
| `worldPosition` | `Vec3` | |

`public init(time: Double, screenPosition: FlyScreenPoint?, worldPosition: Vec3)`

### `struct FlyRenderState`

| Member | Type | Notes |
|---|---|---|
| `state` | `FlyState` | |
| `position` | `Vec3` | World position. |
| `spotID` | `Int?` | Spot it is on/near/heading to. |
| `screenPosition` | `FlyScreenPoint?` | Projection; may be outside 0...1; nil when behind the camera. |
| `bearing` | `Double` | rad, 0 ahead, positive right. |
| `cameraDistance` | `Double` | Straight-line camera-to-fly distance (m). |
| `speed` | `Double` | m/s. |

`public init(state: FlyState, position: Vec3, spotID: Int?, screenPosition: FlyScreenPoint?, bearing: Double, cameraDistance: Double, speed: Double)`

### `struct FlyGameOutput`

| Member | Type | Notes |
|---|---|---|
| `time` | `Double` | `input.time`. |
| `fly` | `FlyRenderState?` | nil before a round. A smashed fly stays (state `.smashed`) until the next one spawns. |
| `distance` | `DistanceEstimate` | The smoothed estimate the fly reacted to. |
| `buzzing` | `Bool` | True while a live fly exists in a playing round. |
| `audioPan` | `Double` | -1...1; 0 when not buzzing. |
| `audioGain` | `Double` | 0...1; 0 when not buzzing. |
| `cues` | `[FlyGameCue]` | This frame's one-off cues, in order. |
| `splats` | `[SplatEvent]` | |
| `smashEvents` | `[SmashEvent]` | Every detected smash, judged or not. |
| `verdicts` | `[HitVerdict]` | One per smash judged (only while a live fly exists in a playing round). |
| `rejections` | `[SmashRejection]` | Possible smashes the detector turned down. |
| `transitions` | `[FlyTransition]` | |
| `round` | `FlyRound` | Copy of the round after this frame. |
| `newBestTime` | `Double?` | Set on the frame a round finishes with a new best: save it. |
| `logLines` | `[String]` | Session log lines (FlyLog format). |

`public init(time: Double = 0, round: FlyRound = FlyRound())` (everything else empty/zero/nil).

### `struct FlyGame`

| Member | Type | Notes |
|---|---|---|
| `tunables` | `FlyTunables` (`var`) | Live-tunable; applied on the next `step`. |
| `hingeEdge` | `HingeEdge` (`var`) | Builds the hit region with `tunables.hitRegionWidth` / `hitBlockedMargin`. |
| `hingeAvailable` | `Bool` (`var`, computed) | Forwards to the detector. |
| `round` | `FlyRound` (read-only) | |
| `fly` | `FlyAgent?` (read-only) | |
| `estimator` | `DistanceEstimator` (read-only) | |
| `detector` | `SmashDetector` (read-only) | |
| `judge` | `HitJudge` (read-only) | |
| `lastStepTime` | `Double?` (read-only) | |

```swift
public init(tunables: FlyTunables = FlyTunables(),
            seed: UInt64,
            hingeEdge: HingeEdge,
            hingeAvailable: Bool,
            fliesPerRound: Int = 3,
            bestTime: Double? = nil)

public init<S: BestTimeStore>(tunables: FlyTunables = FlyTunables(),
                              seed: UInt64,
                              hingeEdge: HingeEdge,
                              hingeAvailable: Bool,
                              fliesPerRound: Int = 3,
                              store: S)          // loads the best time from the store

public mutating func startRound()               // resets the round; first fly spawns on the next step
public mutating func cancelRound()              // round back to idle, fly removed
public mutating func step(input: FlyGameInput, dt: Double) -> FlyGameOutput
```

`step` order: respawn/spawn → distance estimate (`estimator.update(_:measuredAt:…)` when
`distanceMeasuredAt` is set, else `update(_:sourceConfidence:time:)`) → fly tick → round clock → snapshot recorded →
hinge and luma samples fed in time order (ties: hinge first) → `detector.advance(to: input.time)` → manual
smash → each smash judged → render and audio. `dt` is clamped to `0...tunables.maxStepDt` (NaN becomes 0).

Behaviour details:

- A new fly spawns at `camera.position + camera.forward * spawnDistance` plus a seeded jitter of up to
  ±0.3 m (x, z) and ±0.15 m (y), and the distance estimator is reset.
- When the fly lands, the estimator is `rebase()`d so the fly's own flight does not read as the player lunging.
- Hit: fly `.smashed`, a `SplatEvent`, cue `.hit`, `round.recordCatch()`. If the round is not finished, the
  next fly spawns `respawnDelay` seconds later; if it is, cues `.roundFinished` (and `.newBestTime` with
  `newBestTime` set).
- Miss: cue `.miss`, and the fly is startled (`alarm`), so it bolts.

---

## 3. Math: Vec3, FlyMath, FlyRNG

### `struct Vec3`

`var x, y, z: Double`

```swift
public init(x: Double, y: Double, z: Double)
public init(_ x: Double, _ y: Double, _ z: Double)
public static let zero: Vec3
// Operators: Vec3 + Vec3, Vec3 - Vec3, Vec3 * Double, Double * Vec3, Vec3 / Double (÷0 gives .zero), -Vec3
public func dot(_ other: Vec3) -> Double
public func cross(_ other: Vec3) -> Vec3
public var lengthSquared: Double { get }
public var length: Double { get }
public func normalised() -> Vec3                // .zero for a (near-)zero vector
public func distance(to other: Vec3) -> Double
```

### `enum FlyMath` (namespace)

```swift
public static func clamp(_ value: Double, _ lo: Double, _ hi: Double) -> Double   // NaN gives lo
public static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double
public static func wrapAngle(_ angle: Double) -> Double                          // into (-pi, pi]; non-finite gives 0
public static func smoothingAlpha(dt: Double, timeConstant: Double) -> Double     // 1 - exp(-dt/tau); 1 if tau <= 0; 0 if dt <= 0
```

### `struct FlyRNG` (SplitMix64)

```swift
public private(set) var state: UInt64
public init(seed: UInt64)
public mutating func next() -> UInt64
public mutating func nextUnit() -> Double                          // [0, 1)
public mutating func nextDouble(from lo: Double, to hi: Double) -> Double   // [lo, hi)
public mutating func nextInt(below upperBound: Int) -> Int          // 0..<upperBound; 0 if upperBound <= 0
```

---

## 4. FlyCamera, FlyScreenPoint

### `struct FlyScreenPoint`

```swift
public var x: Double
public var y: Double
public init(x: Double, y: Double)
public var isOnScreen: Bool { get }     // both in 0...1
```

### `struct FlyCamera`

```swift
public var position: Vec3
public var forward: Vec3          // unit, view direction
public var right: Vec3            // unit, screen +x
public var up: Vec3               // unit, screen up (= screen -y)
public var horizontalFOV: Double  // full angle, radians
public var verticalFOV: Double    // full angle, radians

public init(position: Vec3, forward: Vec3, right: Vec3, up: Vec3, horizontalFOV: Double, verticalFOV: Double)
public init(position: Vec3 = Vec3.zero, horizontalFOV: Double, verticalFOV: Double)  // looks along -Z, +X right, +Y up

public static let nearPlane: Double                    // 0.01 m
public func project(_ point: Vec3) -> FlyScreenPoint?  // nil if behind / nearer than nearPlane; may be off-screen
public func bearing(to point: Vec3) -> Double          // atan2(side, ahead): 0 ahead, + right, ±pi behind
public func distance(to point: Vec3) -> Double
```

Projection: `x = 0.5 + (d·right / d·forward) / (2 tan(hFOV/2))`, `y = 0.5 - (d·up / d·forward) / (2 tan(vFOV/2))`.

---

## 5. FlyTunables and presets

`public struct FlyTunables` with `public init()`; every property is a `public var` with the default below.
Change one with `var t = FlyTunables(); t.smashDistance = 0.15`.

**Fly flight**

| Property | Type | Default | Meaning |
|---|---|---|---|
| `wanderSpeed` | Double | `0.5` | Cruising speed while wandering between landing spots (m/s). |
| `escapeSpeed` | Double | `2.0` | Speed while escaping after an alarm or a miss (m/s). |
| `arrivalRadius` | Double | `0.03` | Within this distance of a spot the fly snaps onto it and lands (m). |
| `landedMinDuration` | Double | `3.0` | Shortest time the fly sits on a spot before getting restless (s). |
| `landedMaxDuration` | Double | `8.0` | Longest time the fly sits on a spot before getting restless (s). |
| `minSpotQuality` | Double | `0.3` | Spots with a quality below this are avoided when better ones exist (0...1). |
| `noSpotLoopRadius` | Double | `0.4` | Radius of the lazy circle the fly flies when the app supplies no spots (m). |
| `spawnDistance` | Double | `1.5` | A new fly appears this far in front of the camera (m). |
| `respawnDelay` | Double | `1.5` | Delay between a hit and the next fly of the round appearing (s). |

**Alarm and escape**

| Property | Type | Default | Meaning |
|---|---|---|---|
| `alarmRadius` | Double | `1.5` | The fly only notices the player within this distance (m). |
| `alarmAngularSpeed` | Double | `2.0` | Device rotation rate above which a nearby fly is alarmed ("alarm speed", rad/s). |
| `alarmApproachRate` | Double | `0.6` | Closing speed above which a nearby fly is alarmed ("alarm approach rate", m/s). |
| `hoverAlarmMultiplier` | Double | `2.0` | While hovering, both alarm thresholds are multiplied by this (the catch window is forgiving). |
| `alarmDuration` | Double | `0.25` | How long the fly freezes, startled, before bolting (s). |
| `escapeMinDistance` | Double | `0.5` | When escaping, prefer spots at least this far from where the fly was (m). |
| `escapeNoSpotDuration` | Double | `1.5` | With no spot to escape to, the fly flies off in a straight line for this long (s). |

**Hover (the catch window)**

| Property | Type | Default | Meaning |
|---|---|---|---|
| `takeOffDistance` | Double | `0.30` | A landed fly takes off and hovers when the player is this close (m). |
| `hoverDuration` | Double | `4.0` | How long the fly hovers before getting bored and escaping (s). |
| `hoverStandoff` | Double | `0.06` | Hover centre sits this far off the spot, along the spot's normal (m). |
| `hoverLiftTime` | Double | `0.3` | Time to rise from the spot to the hover centre (s). |
| `hoverRadius` | Double | `0.04` | Size of the lazy figure-of-eight loop while hovering (m). |
| `hoverAngularSpeed` | Double | `2.5` | Phase speed of the hover loop (rad/s). |

**Distance estimate**

| Property | Type | Default | Meaning |
|---|---|---|---|
| `minDistanceConfidence` | Double | `0.3` | Distance readings with a confidence below this are ignored by the fly (0...1). |
| `distanceSmoothingTime` | Double | `0.12` | Smoothing time constant for the distance (s). |
| `approachRateSmoothingTime` | Double | `0.25` | Smoothing time constant for the approach rate (s). |
| `distanceStaleTime` | Double | `0.5` | Confidence fades to zero this long after the last measurement (s). |
| `distanceJumpRate` | Double | `4.0` | A raw change faster than this is treated as a glitch or a patch switch, not motion (m/s). |
| `minimumDistance` | Double | `0.02` | Measurements are clamped to at least this (m). |
| `maximumDistance` | Double | `20.0` | Measurements are clamped to at most this (m). |

**Route B patch reference distance** (used by `PatchReferencePolicy(tunables:)`)

| Property | Type | Default | Meaning |
|---|---|---|---|
| `patchDefaultReferenceDistance` | Double | `1.0` | Distance assumed for a patch seeded with no tracked peers to borrow from (m). |
| `patchReferenceMinimumPeers` | Int | `1` | A new patch borrows the peers' median distance only when at least this many qualify (values below 1 act as 1). |
| `patchReferenceMinimumPeerConfidence` | Double | `0.3` | Peers with a tracking confidence below this are not borrowed from (0...1). |
| `patchReferenceMinimumDistance` | Double | `0.2` | The distance a new patch is seeded at is clamped to at least this (m). |
| `patchReferenceMaximumDistance` | Double | `5.0` | The distance a new patch is seeded at is clamped to at most this (m). |

**Smash detection: hinge**

| Property | Type | Default | Meaning |
|---|---|---|---|
| `hingeArmAngle` | Double | `0.7` | The hinge counts as open (and arms the detector) at or above this angle (rad, about 40 degrees). |
| `hingeClosedAngle` | Double | `0.12` | The hinge counts as shut at or below this angle, or when status is `.closed` (rad, about 7 degrees). |
| `hingeMinCloseDrop` | Double | `0.5` | A close must fold through at least this much angle (rad). |
| `smashMinAngularSpeed` | Double | `0.6` | Slowest average closing speed that still counts as a smash ("smash angle velocity", rad/s). Deliberately low: a slow, careful close counts. Nothing rewards slamming. |
| `smashNominalAngularSpeed` | Double | `2.5` | Typical closing speed, used to estimate when motion began between sparse hinge samples (rad/s). |
| `hingeStillSpeed` | Double | `0.2` | Hinge segments slower than this, and smaller than `hingeSegmentMinDrop`, are drift, not the close (rad/s). |
| `hingeSegmentMinDrop` | Double | `0.1` | A hinge segment dropping at least this much is part of the close however slow it looks (rad). |
| `closeMaxDuration` | Double | `2.5` | Longest close that counts, from motion start to shut (s). |
| `hingeCorroborationDrop` | Double | `0.15` | With the hinge available, darkness is confirmed when the hinge has fallen at least this much (rad). |
| `hingeCorroborationWindow` | Double | `0.25` | How long a dark camera waits for the hinge to confirm before it is rejected as a hand (s). |
| `hingeStatusMapping` | HingeStatusMapping | `.declarationOrderGuess` | Maps raw `UIHinge.status` integers (`HingeSample.statusRaw`) to `HingeStatus`. A guess until spike P5 (section 8). |

**Smash detection: camera darkening**

| Property | Type | Default | Meaning |
|---|---|---|---|
| `darkeningThreshold` | Double | `0.06` | Mean luma at or below this counts as dark ("darkening threshold", 0...1). |
| `litThreshold` | Double | `0.15` | Mean luma at or above this counts as lit, and re-arms the luma path (0...1). |
| `lumaLookback` | Double | `1.0` | How far back to look for the lit baseline before a collapse (s). |
| `lumaStartFraction` | Double | `0.85` | The collapse starts at the last sample at or above this fraction of the baseline. |
| `lumaCollapseMaxDuration` | Double | `0.5` | Without a hinge, the collapse from lit to dark must take no longer than this (s). |
| `lumaMotionLead` | Double | `0.1` | The half starts moving this long before the luma starts falling; subtracted from the luma start (s). |
| `lumaStallTimeout` | Double | `0.15` | A luma stream silent for this long counts as stopped (s). |
| `lumaStallDropRatio` | Double | `0.6` | A stopped stream counts as a collapse if its last value had fallen to this fraction of the baseline. |
| `lumaStallCountsAlone` | Bool | `true` | Without a hinge, may a stream that stopped while dropping fire a smash on its own? |

**Smash detection: both**

| Property | Type | Default | Meaning |
|---|---|---|---|
| `smashDebounce` | Double | `0.8` | Minimum time between two smash events (s). |

**Hit judging**

| Property | Type | Default | Meaning |
|---|---|---|---|
| `snapshotBufferDuration` | Double | `1.0` | Length of the game-state ring buffer (s). |
| `judgeLeadTime` | Double | `0.03` | The judged snapshot is taken this long before the smash's motion start (s). |
| `smashDistance` | Double | `0.12` | The fly must be nearer than this to be hit (m). |
| `hitMaxFlySpeed` | Double | `0.4` | A fly that is not hovering must be slower than this to be hit (m/s). |
| `hitRegionWidth` | Double | `0.5` | Width of the hinge-side hit region, as a fraction of the frame measured from the hinge edge. For `HingeEdge.centre` it is the side of a centred square. |
| `hitBlockedMargin` | Double | `0.06` | Strip at the very hinge edge excluded from the hit region (occluded by the forward half). |

**Audio**

| Property | Type | Default | Meaning |
|---|---|---|---|
| `audioReferenceDistance` | Double | `0.3` | At or nearer than this the buzz plays at full gain (m). |
| `audioMinimumGain` | Double | `0.05` | The buzz never drops below this gain from distance alone (0...1). |
| `audioRearAttenuation` | Double | `0.4` | Directly behind, the gain is reduced by this fraction (0...1). |

**Simulation**

| Property | Type | Default | Meaning |
|---|---|---|---|
| `maxStepDt` | Double | `0.1` | Longest simulation step; bigger `dt` values (after a pause) are clamped to this (s). |

### Presets

```swift
extension FlyTunables {
    public static let iPadPrototype: FlyTunables   // FlyTunables() with smashDistance 0.25
    public static let duoPostureA: FlyTunables     // FlyTunables() unchanged (the design values)
    public static let duoPostureB: FlyTunables     // closeMaxDuration 4.0, smashDistance 0.15, hitRegionWidth 0.6
}

public struct FlyPreset {
    public var name: String
    public var tunables: FlyTunables
    public var hingeEdge: HingeEdge                // pass to FlyGame(hingeEdge:)
    public init(name: String, tunables: FlyTunables, hingeEdge: HingeEdge)
    public static let iPadPrototype: FlyPreset     // "iPadPrototype", FlyTunables.iPadPrototype, .centre
    public static let duoPostureA: FlyPreset       // "duoPostureA", FlyTunables.duoPostureA, .right (guess until P3)
    public static let duoPostureB: FlyPreset       // "duoPostureB", FlyTunables.duoPostureB, .centre
    public static let all: [FlyPreset]             // the three above, in that order
}
```

Every value that differs from `FlyTunables()` is a guess until measured:

- **iPadPrototype**: the iPad can't focus or track a patch from 12 cm and the smash is a hand over the lens,
  so `smashDistance` 0.25 m accepts the whole hover window (hover starts at `takeOffDistance`, 0.30 m).
- **duoPostureA**: the design values. The hinge edge `.right` is a placeholder for spike P3's answer.
- **duoPostureB**: the fold starts from about 2.4 rad (opened 120 to 150 degrees), so a slow, careful close at
  `smashMinAngularSpeed` needs up to `closeMaxDuration` 4.0 s (nothing rewards slamming); the wide book
  sweeps a bigger wedge (`smashDistance` 0.15 m); the fly is drawn across the fold, so the region is a
  centred square (`.centre`), `hitRegionWidth` 0.6.

---

## 6. The fly: FlyAgent and friends

### `enum FlyState: String, CaseIterable`

`wandering`, `landed`, `alarmed`, `hovering`, `escaping`, `smashed`.

### `struct LandingSpot`

```swift
public var id: Int          // stable, unique within one frame's list
public var position: Vec3   // world position
public var normal: Vec3     // unit, out of the surface; Vec3.zero if unknown
public var quality: Double  // 0...1
public init(id: Int, position: Vec3, normal: Vec3 = Vec3.zero, quality: Double = 1.0)
```

### `struct PlayerMotion`

```swift
public var distance: Double?          // m, nil if unknown
public var distanceConfidence: Double // 0...1
public var approachRate: Double       // m/s, positive = closing
public var angularSpeed: Double       // rad/s
public init(distance: Double? = nil, distanceConfidence: Double = 0, approachRate: Double = 0, angularSpeed: Double = 0)
public static let still: PlayerMotion
```

### `enum FlyTransitionReason: String, CaseIterable`

`arrived`, `restless`, `playerClose`, `alarmed`, `startled`, `startleEnded`, `hoverEnded`, `spotLost`,
`escapeEnded`, `smashed`.

### `struct FlyTransition`

```swift
public var from: FlyState
public var to: FlyState
public var reason: FlyTransitionReason
public init(from: FlyState, to: FlyState, reason: FlyTransitionReason)
```

### `struct FlyAgent`

Read-only state: `state: FlyState`, `position: Vec3`, `velocity: Vec3`, `spotID: Int?`, `stateTime: Double`,
`timeRemaining: Double`; computed `speed: Double`.

```swift
public init(position: Vec3, seed: UInt64)                                     // wandering
public init(landedOn spot: LandingSpot, seed: UInt64, landedDuration: Double)  // already landed
@discardableResult public mutating func tick(dt: Double, motion: PlayerMotion, spots: [LandingSpot], tunables: FlyTunables) -> FlyTransition?
@discardableResult public mutating func alarm(tunables: FlyTunables) -> FlyTransition?   // from wandering/landed/hovering only
@discardableResult public mutating func markSmashed() -> FlyTransition?                  // nil if already smashed
```

At most one transition per tick; `dt <= 0` (or non-finite) does nothing.

| From | Condition | To (reason) |
|---|---|---|
| wandering | reaches its target spot (within `arrivalRadius`) | landed (`arrived`), timer random in `landedMinDuration...landedMaxDuration` |
| wandering | no spots at all | stays wandering, lazy circle of `noSpotLoopRadius` |
| landed | spot no longer in the list | wandering (`spotLost`) |
| landed | alarm condition (below) | alarmed (`alarmed`) |
| landed | distance ≤ `takeOffDistance` (confidence ≥ `minDistanceConfidence`) | hovering (`playerClose`) |
| landed | timer runs out | wandering (`restless`) to a different spot when one exists |
| hovering | alarm condition with thresholds × `hoverAlarmMultiplier` | alarmed (`alarmed`) |
| hovering | `hoverDuration` runs out | escaping (`hoverEnded`) |
| alarmed | `alarmDuration` runs out | escaping (`startleEnded`) |
| escaping | reaches target spot | landed (`arrived`) |
| escaping (no other spot) | `escapeNoSpotDuration` runs out | wandering (`escapeEnded`) |
| any but alarmed/escaping/smashed | `alarm(tunables:)` | alarmed (`startled`) |
| any but smashed | `markSmashed()` | smashed (`smashed`) |

Alarm condition (landed and hovering only; a flying fly ignores the player): distance known with confidence
≥ `minDistanceConfidence`, distance ≤ `alarmRadius`, and `approachRate > alarmApproachRate` or
`angularSpeed > alarmAngularSpeed`.

Spot choice: random (seeded) among spots with `quality ≥ minSpotQuality`, avoiding the current spot, falling
back to any spot. Escape target: never the current spot; random among those ≥ `escapeMinDistance` away, else
the farthest; with no other spot the fly flies straight off in a random direction at `escapeSpeed`.

Hovering: the fly rises from the spot to `spot.position + normal * hoverStandoff` over `hoverLiftTime`, then
traces a figure-of-eight of size `hoverRadius` in the plane perpendicular to the normal, following the spot
if it moves.

---

## 7. DistanceEstimator, PatchReferencePolicy

### `enum DistanceMeasurement`

```swift
case world(metres: Double)
case patchScale(ratio: Double, referenceDistance: Double)   // distance = referenceDistance / ratio
public var metres: Double? { get }                          // nil if invalid (non-finite, <= 0)
```

### `struct DistanceEstimate`

```swift
public var metres: Double?        // nil until the first valid measurement
public var confidence: Double     // 0...1
public var approachRate: Double   // m/s, positive = closing
public var time: Double
public init(metres: Double?, confidence: Double, approachRate: Double, time: Double)
public static let unknown: DistanceEstimate   // nil, 0, 0, 0
```

### `struct DistanceEstimator`

```swift
public var smoothingTime: Double, rateSmoothingTime: Double, staleTime: Double
public var jumpRate: Double, minimumDistance: Double, maximumDistance: Double
public private(set) var estimate: DistanceEstimate

public init(smoothingTime: Double = 0.12, rateSmoothingTime: Double = 0.25, staleTime: Double = 0.5,
            jumpRate: Double = 4.0, minimumDistance: Double = 0.02, maximumDistance: Double = 20.0)
public init(tunables: FlyTunables)
public mutating func apply(_ tunables: FlyTunables)     // copy settings, keep state
@discardableResult
public mutating func update(_ measurement: DistanceMeasurement?, sourceConfidence: Double = 1.0, time: Double) -> DistanceEstimate
@discardableResult    // a reading made at `measuredAt` (camera frame time), estimate at `time` (the tick)
public mutating func update(_ measurement: DistanceMeasurement?, measuredAt: Double, sourceConfidence: Double = 1.0, time: Double) -> DistanceEstimate
public mutating func rebase()                           // distance = last raw reading, approach rate = 0
public mutating func reset()
```

- First valid reading is taken as is. Later readings are smoothed exponentially (`smoothingTime`); the
  approach rate is the smoothed derivative (`rateSmoothingTime`). Readings are clamped to
  `minimumDistance...maximumDistance`; confidence is `sourceConfidence` clamped to 0...1.
- Re-seed (distance snaps, rate 0) when the raw change implies more than `jumpRate` m/s, when the
  measurement kind switches (world ↔ patchScale), or after a gap longer than `staleTime`.
- nil or invalid reading: distance held; confidence and rate fade linearly to 0 over `staleTime`.
- Updates earlier than the previous update are ignored (the current estimate is returned).
- `update(_:sourceConfidence:time:)` takes the reading as made at `time`.
- `update(_:measuredAt:sourceConfidence:time:)`: a reading whose `measuredAt` is not newer than the last
  reading counted is **stale** and treated exactly like nil (held, fading), so the app can pass the latest
  frame's reading on every tick. Smoothing and the jump and gap tests use reading times. `measuredAt` later
  than `time` counts as `time`; a non-finite `measuredAt` counts as no reading. Confidence and approach rate
  are scaled by the reading's freshness at `time` (`1 - (time - measuredAt) / staleTime`, clamped to 0...1),
  the same fade as between readings.
- A new reading continues the approach-rate smoothing from the last measured rate, not from the faded
  rate reported on ticks in between.

### `struct PatchReferencePolicy` (route B)

A tracked patch only has a scale ratio, so its reference distance (its distance at ratio 1) is assumed when
it is first seen: the median of the current distances of already-tracked peers (mean of the middle two for
an even count) when at least `minimumPeers` qualify, else `defaultDistance`; clamped to
`minimumDistance...maximumDistance`.

```swift
public var defaultDistance: Double, minimumPeers: Int, minimumPeerConfidence: Double
public var minimumDistance: Double, maximumDistance: Double
public init(defaultDistance: Double = 1.0, minimumPeers: Int = 1, minimumPeerConfidence: Double = 0.3,
            minimumDistance: Double = 0.2, maximumDistance: Double = 5.0)
public init(tunables: FlyTunables)                          // the patch… tunables (section 5)
public func seedDistance(peerDistances: [Double]) -> Double // non-finite and <= 0 peers ignored
public static func median(_ values: [Double]) -> Double?    // nil if empty
```

### `struct PatchScaleReading`

```swift
public var id: Int            // the tracker's patch id, stable while tracked
public var ratio: Double      // current size / size when seeded (> 1 = closer)
public var confidence: Double // 0...1
public init(id: Int, ratio: Double, confidence: Double = 1.0)
```

### `struct PatchReferenceBook`

```swift
public var policy: PatchReferencePolicy
public private(set) var references: [Int: Double]          // reference distance (m) per patch id
public init(policy: PatchReferencePolicy = PatchReferencePolicy())
@discardableResult public mutating func update(_ readings: [PatchScaleReading]) -> [Int]   // ids seeded now, in input order
public func referenceDistance(for id: Int) -> Double?
public func distance(for reading: PatchScaleReading) -> Double?             // reference / ratio
public func measurement(for reading: PatchScaleReading) -> DistanceMeasurement?   // .patchScale(ratio:referenceDistance:)
public mutating func reset()
```

`update` rules (call it with each new tracker report):

- Ids missing from `readings` are forgotten (tracking lost; a reused id later counts as new).
- A new id with a valid ratio gets `policy.seedDistance(peers) * ratio`, so its current distance equals the
  peers' median even if it has already grown since its seed frame. Peers are readings whose id already had a
  reference before the call, with a valid ratio and `confidence >= policy.minimumPeerConfidence`; patches new
  in the same call never borrow from each other.
- A new id with an invalid ratio (non-finite or <= 0) is not seeded yet; a known id with an invalid ratio
  keeps its reference (and `distance`/`measurement` return nil for it). A repeated id is handled once.

---

## 8. SmashDetector

### Inputs and outputs

```swift
public enum HingeStatus: String, CaseIterable { case closed, partiallyOpen, fullyOpen }   // unknown = nil

public struct HingeStatusMapping {               // raw UIHinge.status integer -> HingeStatus
    public var closed: Int?, partiallyOpen: Int?, fullyOpen: Int?, unknown: Int?
    public init(closed: Int?, partiallyOpen: Int?, fullyOpen: Int?, unknown: Int?)
    public static let declarationOrderGuess: HingeStatusMapping   // closed 0, partiallyOpen 1, fullyOpen 2, unknown 3
    public static let ignoreStatus: HingeStatusMapping            // all nil: the angle alone counts
    public func status(forRaw raw: Int?) -> HingeStatus?          // nil for nil, `unknown` or no match
    public func rawValue(for status: HingeStatus) -> Int?
}

public struct HingeSample { var angle: Double; var time: Double; var status: HingeStatus?; var statusRaw: Int?
    public init(angle: Double, time: Double, status: HingeStatus? = nil, statusRaw: Int? = nil)   // angle rad, 0 = shut
    public func resolvedStatus(_ mapping: HingeStatusMapping) -> HingeStatus? }  // status, else mapped statusRaw

public struct LumaSample { var mean: Double; var time: Double
    public init(mean: Double, time: Double) }                                  // mean 0...1

public enum SmashSource: String, CaseIterable { case hinge, luma, hingeAndLuma, manual }

public struct SmashEvent { var time: Double; var motionStartTime: Double; var source: SmashSource; var lumaStalled: Bool
    public init(time: Double, motionStartTime: Double, source: SmashSource, lumaStalled: Bool = false) }

public enum SmashRejectReason: String, CaseIterable {
    case debounced, handOverLens, closeTooSlow, closeTooSmall, collapseTooSlow, stallOnly }

public struct SmashRejection { var time: Double; var reason: SmashRejectReason
    public init(time: Double, reason: SmashRejectReason) }
```

(All their properties are `public var`.)

**Hinge status mapping.** The `UIHingeStatus` integers are undocumented (API_NOTES section 1); spike P5 logs
them. `declarationOrderGuess` assumes `NS_ENUM` numbering from 0 in the order Apple's docs list the cases
(closed, partiallyOpen, fullyOpen, unknown). DuoProbe assumes no values (it logs the raw integer). When P5
has the real values, set `tunables.hingeStatusMapping` (for example in the app's `Platform.makeTunables()`);
no other code changes. In `status(forRaw:)` a raw value equal to `unknown` gives nil; otherwise closed,
partiallyOpen, fullyOpen are tried in that order.

### `struct SmashDetector`

```swift
public var tunables: FlyTunables
public var hingeAvailable: Bool
public private(set) var lastEvent: SmashEvent?
public private(set) var rejections: [SmashRejection]     // at most 32 kept
public var isHingeArmed: Bool { get }
public var isLumaArmed: Bool { get }
public var isAwaitingHinge: Bool { get }                  // darkness waiting for hinge confirmation

public init(tunables: FlyTunables = FlyTunables(), hingeAvailable: Bool)
@discardableResult public mutating func addHinge(_ sample: HingeSample) -> SmashEvent?
@discardableResult public mutating func addLuma(_ sample: LumaSample) -> SmashEvent?
@discardableResult public mutating func advance(to time: Double) -> SmashEvent?   // call once per frame
@discardableResult public mutating func manualSmash(at time: Double) -> SmashEvent?
public mutating func drainRejections() -> [SmashRejection]
public mutating func reset()
```

Rules (all thresholds are `FlyTunables`):

- **Arming.** The hinge path arms when a sample is open (`angle ≥ hingeArmAngle`, not closed); the luma path
  arms on a sample with `mean ≥ litThreshold`. Any smash disarms both. Both start disarmed.
- **Hinge close.** A sample is closed when `status == .closed`, or `status` is nil, `angle < hingeArmAngle`
  and `tunables.hingeStatusMapping` maps `statusRaw` to `.closed` (so a wrong guess can never make an open
  hinge look shut), or `angle ≤ hingeClosedAngle`. On the first
  closed sample while armed, take the strictly falling run of samples ending there (a trailing plateau of equal
  angles is skipped). Motion starts in the run's first segment that is faster than `hingeStillSpeed` or drops
  at least `hingeSegmentMinDrop`, at `max(segmentStart.time, segmentEnd.time - segmentDrop / smashNominalAngularSpeed)`.
  Then: total drop < `hingeMinCloseDrop` → `closeTooSmall`; duration > `closeMaxDuration` or average speed
  < `smashMinAngularSpeed` → `closeTooSlow`; else a `.hinge` event at the closed sample's time. Works with
  2 to 4 samples per close; a slow close (about 1.5 s) counts.
- **Luma collapse.** On a dark sample (`mean ≤ darkeningThreshold`) while luma is armed: baseline = brightest
  sample in the previous `lumaLookback`; the collapse starts at the last sample ≥ `baseline * lumaStartFraction`;
  `motionStartTime = start - lumaMotionLead`. A baseline below `litThreshold` disarms luma (and, without a
  hinge, rejects `collapseTooSlow`).
  - **Hinge available:** the darkness needs the hinge to confirm it: the newest hinge sample is closed, or is
    at least `hingeCorroborationDrop` below the last sample at or before the luma motion start. If not
    confirmed at once, it waits up to `hingeCorroborationWindow`; a hinge sample in that window can confirm it.
    Confirmed → `.hingeAndLuma` event with `motionStartTime = min(luma start, hinge run start)`. Unconfirmed →
    `handOverLens`, luma disarmed.
  - **No hinge:** collapse longer than `lumaCollapseMaxDuration` → `collapseTooSlow`; else a `.luma` event at
    the dark sample's time. (A fast hand over the lens counts: that is the iPad stand-in.)
- **Stream stopped mid-drop** (checked in `advance`): luma armed, no sample for more than `lumaStallTimeout`,
  the last sample lower than the one before it and at most `lumaStallDropRatio * baseline`. Treated like a dark
  sample (with `lumaStalled = true`): with a hinge it still needs hinge confirmation; without one it fires a
  `.luma` event unless `lumaStallCountsAlone` is false (`stallOnly`). Evaluated once per stopped stream.
- **Debounce.** Any event within `smashDebounce` of the last one is rejected `debounced`.
- **Manual.** `manualSmash(at:)` ignores arming but respects the debounce; motion start = `time`.
- Samples older than the newest of their kind, and non-finite values, are ignored. History kept: hinge
  `closeMaxDuration + 1` s (at least the last 4 samples), luma `lumaLookback + 1` s.

---

## 9. HitJudge

### `enum HingeEdge: String, CaseIterable`

`left`, `right`, `top`, `bottom`, `centre` (iPad: centred square).

### `struct HitRegion`

```swift
public var hingeEdge: HingeEdge
public var width: Double           // fraction of the frame, from the hinge edge inwards
public var blockedMargin: Double   // edge strip excluded (occluded by the forward half)
public init(hingeEdge: HingeEdge, width: Double, blockedMargin: Double)
public init(hingeEdge: HingeEdge, tunables: FlyTunables)   // hitRegionWidth, hitBlockedMargin
public func contains(_ p: FlyScreenPoint) -> Bool
```

| Edge | Contains (and the point must be on screen) |
|---|---|
| `.left` | `blockedMargin ≤ x ≤ width` |
| `.right` | `1 - width ≤ x ≤ 1 - blockedMargin` |
| `.top` | `blockedMargin ≤ y ≤ width` |
| `.bottom` | `1 - width ≤ y ≤ 1 - blockedMargin` |
| `.centre` | `|x - 0.5| ≤ width/2` and `|y - 0.5| ≤ width/2` (margin ignored) |

### `struct FlySnapshot`

```swift
public var time: Double
public var flyState: FlyState
public var flySpeed: Double
public var distance: Double?
public var distanceConfidence: Double
public var screenPosition: FlyScreenPoint?
public init(time: Double, flyState: FlyState, flySpeed: Double, distance: Double?, distanceConfidence: Double, screenPosition: FlyScreenPoint?)
```

### `enum HitReason: String, CaseIterable`

Checked in this order: `noSnapshot`, `alreadySmashed`, `flyEscaping`, `flyTooFast` (not hovering and speed >
`hitMaxFlySpeed`), `distanceUnknown` (nil or confidence < `minDistanceConfidence`), `tooFar` (> `smashDistance`),
`offScreen`, `outsideHitRegion`; otherwise `hit`.

### `struct HitVerdict`

```swift
public var isHit: Bool
public var reason: HitReason
public var event: SmashEvent
public var snapshot: FlySnapshot?
public var judgedTime: Double      // event.motionStartTime - judgeLeadTime
public init(isHit: Bool, reason: HitReason, event: SmashEvent, snapshot: FlySnapshot?, judgedTime: Double)
```

### `struct HitJudge`

```swift
public var bufferDuration: Double
public private(set) var snapshots: [FlySnapshot]       // oldest first
public static let maxSnapshots: Int                    // 480
public init(bufferDuration: Double = 1.0)
public mutating func record(_ snapshot: FlySnapshot)   // older-than-newest ignored; prunes to bufferDuration
public mutating func clear()
public func snapshot(at time: Double) -> FlySnapshot?  // newest at or before time; oldest if time predates the buffer; nil if empty
public func judge(_ event: SmashEvent, region: HitRegion, tunables: FlyTunables) -> HitVerdict
public static func reason(for s: FlySnapshot, region: HitRegion, tunables: FlyTunables) -> HitReason
```

---

## 10. FlyRound and BestTimeStore

```swift
public protocol BestTimeStore {
    func loadBestTime() -> Double?
    func saveBestTime(_ seconds: Double)
}

public enum FlyRoundPhase: String, CaseIterable { case idle, playing, finished }

public struct FlyRoundProgress {
    public var fliesCaught: Int
    public var flyTime: Double          // since previous catch or round start
    public var roundFinished: Bool
    public var roundTime: Double?
    public var isNewBest: Bool
    public var counted: Bool            // false if no round was playing
    public init(fliesCaught: Int, flyTime: Double, roundFinished: Bool, roundTime: Double?, isNewBest: Bool, counted: Bool)
}

public struct FlyRound {
    public let fliesPerRound: Int
    public private(set) var phase: FlyRoundPhase
    public private(set) var fliesCaught: Int
    public private(set) var elapsed: Double
    public private(set) var flyTimes: [Double]
    public private(set) var bestTime: Double?
    public private(set) var lastRoundTime: Double?
    public var fliesRemaining: Int { get }

    public init(fliesPerRound: Int = 3, bestTime: Double? = nil)   // < 1 becomes 1; invalid bestTime ignored
    public init<S: BestTimeStore>(fliesPerRound: Int = 3, store: S)
    public mutating func start()
    public mutating func cancel()
    public mutating func tick(dt: Double)                           // only while playing
    @discardableResult public mutating func recordCatch() -> FlyRoundProgress
    @discardableResult public mutating func recordCatch<S: BestTimeStore>(savingTo store: S) -> FlyRoundProgress
}
```

A round finishes on the `fliesPerRound`th catch; it is a new best if there was no best or it was strictly faster.

---

## 11. AudioMath

```swift
public struct StereoGains { public var left: Double; public var right: Double
    public init(left: Double, right: Double) }

public enum AudioMath {
    public static func pan(bearing: Double) -> Double        // sin(bearing) within ±90°, ±1 beyond
    public static func distanceGain(distance: Double, referenceDistance: Double, minimumGain: Double) -> Double
        // referenceDistance / max(distance, referenceDistance), clamped to minimumGain...1
    public static func rearFactor(bearing: Double, rearAttenuation: Double) -> Double
        // 1 - rearAttenuation * (1 - cos(bearing)) / 2
    public static func gain(distance: Double, bearing: Double, tunables: FlyTunables) -> Double
        // distanceGain(audioReferenceDistance, audioMinimumGain) * rearFactor(audioRearAttenuation)
    public static func stereoGains(pan: Double) -> StereoGains   // equal power
}
```

---

## 12. FlyLog

```swift
public enum FlyLog {
    public static func fixed(_ value: Double, decimals: Int = 3) -> String     // "1.50"; half away from zero; "nan"/"inf"/"-inf"
    public static func optionalFixed(_ value: Double?, decimals: Int = 3) -> String  // "none" for nil
    public static func line(time: Double, tag: String, message: String) -> String   // "[12.345] TAG message"
    public static func describe(_ p: FlyScreenPoint?) -> String     // "(0.710,0.500)" or "none"
    public static func describe(_ v: Vec3) -> String                // "(1.000,-2.000,0.500)"
    public static func describe(_ t: FlyTransition) -> String       // "wandering->landed arrived"
    public static func describe(_ e: SmashEvent) -> String          // "source=hinge start=1.000 at=1.283 stalled=no"
    public static func describe(_ r: SmashRejection) -> String      // "handOverLens"
    public static func describe(_ v: HitVerdict) -> String
        // "hit reason=hit judged=0.970 state=hovering dist=0.067 conf=1.00 screen=(0.710,0.500)"
    public static func describe(_ d: DistanceEstimate) -> String    // "dist=0.250 conf=1.00 rate=0.000"
    public static func overlayLines(_ out: FlyGameOutput) -> [String]
}
```

`overlayLines` gives five lines: `t=…`, `fly <state> spot=<id|none> screen=<point>` (or `fly none`), the
distance description, `pan=… gain=…`, and `round <phase> <caught>/<total> time=… best=<…|none>`.

Log tags written by `FlyGame`: `ROUND`, `FLY`, `SMASH`, `REJECT`, `JUDGE`.
