# Catch the Fly: plan

## 1. The game

### Posture A (the design)

Hold the phone half-open at about 90°, hinge vertical, like a book standing upright:

- The **static half** faces you. Its outside is the **cover display**, which is your viewfinder.
- Its inside is the inner display, with the **inner front camera** under it. Both face forward into the room.
- The **other half** sticks out forward, forming the second wall of the L.
- **Smash** = fold the forward half shut onto the static half, like a sideways clap.

The game shows the inner camera's view on the cover display, with a fly drawn into the room.

The developer confirmed that the inner camera sits on the same half as the cover display (2026-10-26). The spike re-checks this.

### Posture B (fallback)

Use this if the app can't draw on the cover display while the phone is open:

- Open the phone wide (about 120 to 150°), inner display facing you.
- The rear cameras look into the room.
- The fly is drawn on the inner display, across the fold.
- Smash = close the book on it.

This gets full ARKit world tracking on the rear cameras for free. It loses the "fly inside the L" joke, so it's the safety net, not the plan.

### Core loop

1. **Find it.** A fly buzzes around the room and lands on things. Stereo buzzing, panned by bearing and louder when closer, guides you when it's off-screen.
2. **Sneak up.** Moving the phone too fast, or closing distance too quickly, alarms the fly. It takes off and lands somewhere else.
3. **Catch it in the air.** When you get close (around 30 cm, tunable), the fly takes off and hovers in a short lazy loop near its spot. That hover is the catch window.
   - Flies are caught in the air, not on walls. With the second half sticking forward, the inner display physically can't get close to a flat wall.
4. **Smash.** Fold the phone shut while the hovering fly is inside the wedge in front of the inner camera, on the side of the folding half.
   - Hit: splat on the cover display, a haptic thud and a sound.
   - Miss: the fly buzzes off, smugly.
5. **Score.** Time to catch, over rounds of 3 flies. Best time is kept locally in UserDefaults.

### Judging a smash

The camera view is useless mid-fold, so the hit is judged on game state from just before the fold began.

FlyCore keeps a short ring buffer of state (about 1 s) and evaluates the snapshot at the smash start time. A smash is a hit when all of these hold:

- the fly is hovering or slow, not mid-escape
- its estimated distance is below `smashDistance`
- its screen position lies in the hinge-side region of the frame

Which frame edge is nearest the hinge depends on orientation, and the spike measures it.

### Rendering

The fly is a 2D animated sprite drawn over the camera preview, in every route:

- With world tracking, project its 3D position to the screen.
- Without it, place it relative to the tracked landing patch.

There is no 3D engine to start with.

## 2. Tracking routes

| Route | How it works | Works when |
|---|---|---|
| **A1** | `ARFaceTrackingConfiguration` with world tracking: front-camera frames, back-camera world tracking | Duo supports it. Unlikely: it needs a TrueDepth front camera, and the Duo has Touch ID, not Face ID |
| **A2** | ARKit world tracking on the rear cameras for pose, plus a separate capture of the inner camera for the picture | Both can run at once. Doubtful, because ARKit normally owns the camera |
| **B** | Inner camera frames + CoreMotion attitude for turning + Vision tracking of the patch the fly sits on. How much the patch grows in the frame gives distance | Always works. **Most likely Duo route**, and it works identically on the iPad's rear camera |
| **P-B** | Posture B with plain ARKit world tracking on the rear cameras | Always works, but only with Posture B |

## 3. Smash triggers

| Trigger | Signal | Notes |
|---|---|---|
| **Hinge** | `UIHingeInteraction` angle falling fast towards 0 (radians, 0 = shut) | Apple says the update rate is system policy and not guaranteed, so the spike measures samples per fast close |
| **Darkening** | Mean brightness of inner camera frames collapses as the half swings over the lens | Works with no hinge API. Confirm with hinge `status == closed` when available, to reject a hand over the lens |
| **Stand-ins** | On the iPad: covering the camera with your hand (exercises the darkening path), plus a debug button | iPad only |

## 4. Phases

Owners: **D** = the developer, **CC** = Claude Code, **T** = the tester with the Duo.

Phases 1 and 3 can run in parallel. Phase 4 waits for phase 2 if the spike happens soon. Otherwise start it on route B, which is the likely outcome anyway.

### Phase 0: setup (D)

- [ ] Join the Apple Developer Program, which is needed for App Store Connect upload and TestFlight. Enrolment can take a day or two, so start now.
- [ ] Install Swift Playgrounds on the iPad and sign in with the developer account.
- [ ] Install iCloud for Windows and turn on iCloud Drive.
- [ ] Create a blank app project called `DuoProbe` in Swift Playgrounds, then check it appears on Windows in iCloud Drive's `Playgrounds` folder. If it doesn't, tell CC, and you'll use the GitHub + Working Copy fallback.
- [ ] Install the Swift toolchain for Windows (swift.org), so CC can run `swift test`.
- [ ] Put this folder somewhere outside iCloud Drive, run `git init`, and start Claude Code in it.
- [ ] In App Store Connect, add the tester as a user, then as an **internal tester**. Internal builds skip Beta App Review. They install the TestFlight app.
- [ ] Note your iPad model in `docs/DUO_FACTS.md`.

### Phase 1: DuoProbe spike app (CC writes, D builds and uploads)

A throwaway app that answers every Duo-only question in one session. It's a list of tests; each one:

- logs PASS, FAIL or a measured value with timestamps to an on-screen log
- adds to a single **Share log** button that exports the log (plus any recorded clips) through the share sheet

CC first reads the Apple sources listed under "Read before coding" in DUO_FACTS.

| ID | Test | Records |
|---|---|---|
| P1 | Device and support flags | Model identifier, iOS version, `ARWorldTrackingConfiguration.isSupported`, `ARFaceTrackingConfiguration.isSupported` and `.supportsWorldTracking`, `AVCaptureMultiCamSession.isMultiCamSupported` |
| P2 | Camera inventory | Every device from an `AVCaptureDevice.DiscoverySession` across all device types and positions: type, position, name. The tester notes which one shows the room in Posture A |
| P3 | Inner camera preview | Live preview from the inner camera. The tester rates sharpness and notes which frame edge is nearest the hinge in Posture A |
| P4 | Cover display while open | Try to show the live preview on the cover display while partially open, via scene accessories (`CameraCaptureAccessory` if that's what Apple's docs say). Decides Posture A vs B |
| P5 | Hinge API | Does `UIHingeInteraction` compile in Playgrounds? Is it available at runtime (`NSClassFromString`)? Log angle and status with timestamps during a slow close and 5 normal-speed closes. Report samples per close and the time from motion start to `closed` |
| P6 | Darkening during a close | Mean inner-camera brightness per frame during 5 closes. Report the time from motion start to dark |
| P7 | ARKit with the inner camera | Run rear world tracking in Posture A and log tracking state. Then start an inner-camera capture alongside it and log what happens (interruption, errors, frames received) |
| P8 | Multi-cam | If supported, run rear wide + inner front together and log success and frame rates |
| P9 | Clips | Record 3 inner-camera clips: walking up to a textured wall, a slow close, a normal close. These are for developing route B on Windows between sessions |

Acceptance criteria:

- [ ] Builds and runs on the iPad, where Duo-only tests report "not available" without crashing.
- [ ] Uploaded through App Store Connect and installed by T via TestFlight.
- [ ] Every test either produces a result or fails with a logged reason. Nothing crashes.

### Phase 2: decide (D + CC, from the spike log)

- [ ] **Posture**: if P4 passes, Posture A; otherwise Posture B.
- [ ] **Tracking**:
  - Posture A: A1 if P1 shows support (unlikely), then A2 if P7 shows it works, else B.
  - Posture B: P-B.
- [ ] **Smash**: hinge if P5 shows at least 4 samples per normal close and `closed` arrives within about 150 ms of the fold ending. Otherwise darkening (P6), confirmed by hinge status where available.
- [ ] Update DUO_FACTS with everything learned, and update this plan with the routes chosen.

### Phase 3: FlyCore (CC, on Windows, start straight away)

A pure Swift package with XCTest tests. Everything is driven by explicit time and a seeded RNG, so tests are deterministic.

- **Tunables**: one struct holding every gameplay number. Starting values: alarm speed, alarm approach rate, `takeOffDistance` (30 cm), `smashDistance` (12 cm), hover duration, hinge-side region width, smash angle velocity, darkening threshold.
- **Fly**: a state machine with states wandering, landed, alarmed, hovering, escaping and smashed, ticked by `dt` and a player-motion input.
- **Distance estimate**: route-agnostic. It takes either a world distance (A routes) or a patch-scale ratio plus a reference distance (route B), and outputs a smoothed metres estimate with a confidence.
- **SmashDetector**: consumes hinge samples (angle, time) and brightness samples (luma, time). It emits a smash event with its motion start time and debounces repeats. It's tested on synthetic streams, including "hand over the lens" (dark but no hinge movement) and "slow close" (should count).
- **HitJudge**: takes the state ring buffer and a smash event and returns hit or miss with a reason.
- **Round**: rounds, timer, best time.
- **AudioMath**: bearing to stereo pan, distance to gain.

Written 2026-10-26. 2026-10-26: `swift test` passes on Linux with Swift 6.2.4 (148 tests, 0 failures), and the library also builds with `-default-isolation MainActor`. Windows is still to run, either on the PC or in the CI workflow. Public API reference: `FlyCore/API.md`.

Acceptance criteria:

- [ ] `swift test` passes on Windows.
- [x] Every module above is covered.
- [x] No imports beyond Foundation.

### Phase 4: iPad prototype (CC writes, D runs on the iPad)

Playable end to end on the iPad's rear camera, using the route chosen in phase 2 (or route B if phase 2 hasn't happened). Smash uses the stand-ins: cover the camera with your hand, or the debug button. A debug overlay shows tracking state, estimated distance, fly state and smash events. A session log can be shared.

Acceptance criteria:

- [ ] The fly lands on a textured surface and stays visually pinned while the iPad pans slowly.
- [ ] Lunging at it makes it take off.
- [ ] Buzzing pans correctly as you turn away.
- [ ] Covering the camera while the fly hovers close and hinge-side scores a hit. Otherwise it's a miss.
- [ ] A full 3-fly round can be played and the best time is saved.

### Phase 5: Duo integration (CC writes, D uploads, T tests)

Swap in the Duo versions chosen in phase 2: the inner camera feed, the chosen tracking route, the real smash trigger, and the splat plus haptic on the cover display (Posture A) or inner display (Posture B). Each TestFlight build ships with a short test script added to `docs/SPIKE_CHECKLIST.md`.

Acceptance criteria:

- [ ] A full round can be won by folding.
- [ ] No false smashes during 2 minutes of normal searching.
- [ ] At least 7 of 10 deliberate, normal-speed smashes on an in-zone fly register as hits.

### Phase 6: polish and playtest (all)

Onboarding that shows the posture (a short animation), a reminder to watch your surroundings, sensitivity settings, sounds, a splat gallery, and tuning from playtest logs.

Acceptance criteria:

- [ ] Someone who hasn't seen the game can learn the posture from onboarding alone.
- [ ] Tunables are adjusted from at least 2 playtest sessions.

## 5. Risks

| Risk | Fallback |
|---|---|
| Swift Playgrounds builds against an SDK older than iOS 27.1, so hinge or scene-accessory APIs don't compile | Runtime lookup; darkening trigger; Posture B |
| The cover display can't show the game while open | Posture B |
| ARKit can't run alongside the inner camera | Route B |
| The under-display camera image is too soft for patch tracking | Flies only land on high-contrast spots; use a larger patch; the game hints "find it near something busy" |
| Hinge updates are too sparse for a fast close | Darkening trigger |
| Duo sessions are rare | Every build carries a test script and a shareable log. P9 clips let CC work on route B without the phone |
| TestFlight processing delays | Batch questions into fewer, bigger builds |

## 6. Build routes

Swift Playground on the iPad builds with the iOS 26 SDK, so it can't compile the iOS 27.1 APIs that Posture A needs. The proposed Mac-free route is GitHub Actions on GitHub's `xcode-27` runner, which has Xcode 27.1. It compile-checks every push and uploads Duo builds to TestFlight on demand, while Playgrounds stays for fast iPad iteration. Options, costs, the recommendation and step-by-step setup: [MAC_FREE_BUILD.md](MAC_FREE_BUILD.md). The decision is the developer's.
