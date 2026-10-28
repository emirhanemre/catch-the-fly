# For the iPad: Catch the Fly, phase 4 prototype

Written 2026-10-26. This build is not compiled yet: the first Playgrounds build is the first compile, so expect a round of errors to paste back.

What it is: the game, playable on the iPad's **rear camera** with **route B**: Vision follows a few busy patches in the picture, CoreMotion follows how you turn, and how much a patch grows tells the game how close you are. You smash by **covering the camera with your hand** (the stand-in for folding the Duo), or with the **Smash (debug)** button.

## Files

All new, in `apps/CatchTheFly/`:

| File | What it does |
|---|---|
| `CatchTheFlyApp.swift` | `@main` entry point |
| `Platform.swift` | **The one place** where the iPad and Duo implementations are chosen, one line per source |
| `Sources/FrameSource.swift` | `FrameSource` protocol, frame values, `SessionInbox` (thread-safe hand-off to the main actor), `FramePipeline` |
| `Sources/CaptureFrameSource.swift` | AVCaptureSession plumbing; `RearCameraFrameSource` (iPad) and `InnerCameraFrameSource` (Duo stand-in, old-SDK camera lookup) |
| `Sources/LumaMath.swift` | Reads the Y plane: mean brightness, per-cell contrast |
| `Sources/PoseSource.swift` | `PoseSource` protocol, `CoreMotionPoseSource` |
| `Sources/PatchTracker.swift` | `SpotTracker` protocol, `PatchTracker` (route B) |
| `Sources/SmashSources.swift` | `SmashInputSource` protocol; luma, debug-button and hinge sources |
| `Sources/RuntimeHinge.swift` | `UIHingeInteraction` through the Objective-C runtime (unavailable on the iPad, by design) |
| `Game/GameController.swift` | Owns FlyGame, steps it once per display frame, drives sound, haptics and views |
| `Game/RouteBAdapter.swift` | Converts camera, pose and patches into FlyCore's camera, landing spots and distance |
| `Game/GameAudio.swift` | Synthesised buzz (looped, panned) and effects |
| `Game/Haptics.swift`, `Game/SessionLog.swift`, `Game/DefaultsBestTimeStore.swift` | Haptics, the shareable log, best time in UserDefaults |
| `Views/*.swift` | Camera preview, fly drawing, debug overlay, HUD, start screen, cover-display slot |

## Getting it across

1. In Swift Playgrounds, create a new **App** project called `CatchTheFly` (if it doesn't exist yet) and wait for it to appear in iCloud Drive on the PC.
2. On the PC, from the repo folder. The first time:

   ```powershell
   .\scripts\to-ipad.ps1 -App CatchTheFly -AdoptTemplate
   ```

   After that, just `.\scripts\to-ipad.ps1 -App CatchTheFly`. `-AdoptTemplate` renames the template's `MyApp.swift` and `ContentView.swift` to `.orig`, because ours has its own `@main` and `ContentView`.
3. On the iPad, wait for iCloud to finish, then close and reopen the project.

The script copies FlyCore's sources into `CatchTheFly.swiftpm/FlyCore/` and ours into `CatchTheFly.swiftpm/App/`. It all compiles as one module.

## Set in Playgrounds (app settings → Capabilities)

| Capability | Purpose string |
|---|---|
| **Camera** | Catch the Fly uses the camera to show the room around you, so you can hunt the fly in it. Nothing is recorded or uploaded. |
| **Motion & Fitness** | Catch the Fly uses motion data to follow how you turn and move the phone while you stalk the fly. |

Without the camera string the app is killed the moment it starts the camera. Allow any orientation. If adding a capability crashes Playgrounds, reinstalling it fixed that in a forum report (API_NOTES §5).

## Before you test

- Headphones help for the panning test (iPad speakers are close together).
- Stand about **1 m** from something busy: a bookshelf, a poster, a patterned cushion. Plain walls give the tracker nothing to hold on to. Route B assumes the first patches are about 1 m away.
- iPads have no Taptic Engine, so the hit haptic does nothing there. That's expected.
- Tap **Debug** to see the tracked patches (yellow boxes; the fly's patch turns green), the centre hit region (red dashed square), the distance and its confidence, the fly's state, and the last smash events with their verdict and reason.
- Safety: look up before you move. A smash is a calm hand over the lens. Nothing in the game rewards speed.

## Play-testing against the phase 4 acceptance criteria

Tap **Start round**, with Debug on.

1. **The fly lands on a textured surface and stays pinned while the iPad pans slowly.** Yellow boxes appear on busy spots within a second. The fly appears about 1.5 m ahead, flies to one box and lands on it (the box turns green). Pan slowly left and right: the fly should stay on its spot. *Pass:* it stays on the spot to within a few millimetres on screen. *Fail cases to note:* the boxes slide off their texture, the boxes vanish while you pan, or the fly drifts relative to its box (that would point at the camera/pose axes).
2. **Lunging at it makes it take off.** Move the iPad quickly towards the landed fly (roughly half a metre in under a second). *Pass:* an alarm chirp, then the fly bolts to another spot. The log shows `FLY landed->alarmed alarmed`. Walking up slowly should make it rise and hover instead (`landed->hovering playerClose`).
3. **Buzzing pans correctly as you turn away.** With headphones, face the fly, then turn to the left. *Pass:* the buzz moves to your right ear and gets a little quieter as the fly goes behind you, and a yellow arrow points back to it. In Debug, `pan=` goes positive when the fly is to your right.
4. **Covering the camera while the fly hovers close and hinge-side scores a hit. Otherwise it's a miss.** Creep up until the fly hovers, keep it inside the red square, then cover the lens with your palm, calmly. *Pass:* Splat!, a thud sound, the debug line `HIT reason=hit`. Then try covering it while the fly is landed far away, and while it's outside the red square. *Pass:* `MISS reason=tooFar` and `MISS reason=outsideHitRegion`, with the fly zipping off smugly ("Too slow!"). A very slow cover should give `REJECTED collapseTooSlow`. The debug button should also hit when the conditions hold.
5. **A full 3-fly round can be played and the best time is saved.** Catch three flies. *Pass:* "Round complete!" with the time, and "New best time!" the first time. Quit the app fully (swipe it away), reopen it: the start screen shows the best time.

Then tap **Share log** and save or send the file. Even when everything passes, it's the evidence for ticking the boxes in PLAN.md.

## What to paste back if something fails

- **A compile error:** the file name, line number and the message, word for word, for every error (a screenshot of Playgrounds' issue list is fine). Also the Swift Playground version (Settings → Apps, or the App Store page).
- **A crash or a failed criterion:** the shared session log, plus one line on which criterion failed and what you saw. The lines we most want are near the top: `CAM using …`, `CAM rotation …`, `POSE matrix convention: …`, and the `FRAME fps=… tracker=…ms clockOffset=…` lines.
- Your iPad model, if it isn't in DUO_FACTS yet.

## Known guesses to check in the log

- `clockOffset` should be small and positive (a few hundredths of a second). Larger values mean frame timestamps aren't on the same clock as the game, and the app has fallen back to arrival times.
- `POSE matrix convention` tells us which way round CoreMotion's rotation matrix is. The app works it out from gravity, so either answer is fine. A fly that slides when you pan, while its box stays put, means the camera axes are wrong.
- `tracker=` above about 30 ms means Vision is too slow at 720p, so frames are dropped. Say if the picture feels laggy.

## Phase 6 polish: new screens (added 2026-10-26)

Not compiled yet either: expect a round of errors from the first Playgrounds build. Get the files across the usual way (`.\scripts\to-ipad.ps1 -App CatchTheFly`). Nothing new to set in Playgrounds: no new capabilities, no image assets.

New files in `apps/CatchTheFly/`:

| File | What it does |
|---|---|
| `Game/AppSettings.swift` | Settings in UserDefaults; maps the sensitivity choices to FlyTunables multipliers (`SensitivityMath`) |
| `Game/SplatGallery.swift` | One small record per caught fly (date, catch time, fly and round number, splat seed), the last 30 |
| `Game/GameToast.swift` | The "Splat!", "Missed!" and "Too fast" messages |
| `Views/OnboardingView.swift` | Four-page introduction with looping drawings |
| `Views/SettingsView.swift`, `Views/GalleryView.swift` | Settings sheet, splat gallery |
| `Views/RoundCompleteView.swift`, `Views/AppTitleView.swift`, `Views/ToastView.swift` | Round result with new-best confetti, title, toasts |

Changed: `GameController.swift` (settings applied on top of the preset, toasts, gallery records, sound and haptics switches, reset best time), `DefaultsBestTimeStore.swift` (`clearBestTime`), `Platform.swift` (`onboardingPosture()`, `showsHitMissToasts`), `ContentView.swift`, `StartView.swift`, `CoverDisplayAccessory.swift` (Duo only: the "Too fast" toast on the cover).

### How to test them

1. **Onboarding on first launch.** Delete the app from the iPad (or start from a fresh install), then run. *Pass:* the introduction covers the screen: (1) "Hold the iPad up like a window" with a hand calmly covering the camera, (2) "Sneak up, then swat" with the fly growing, hovering and getting splatted, (3) "Play it safe" with an eye looking round, (4) "Ready?". Swipe or tap **Next**; the last button reads **Let's catch a fly**. Quit and reopen: it doesn't come back. **Skip** also counts as done.
2. **Replay it.** On the start screen tap **How to play**, and in **Settings** tap **Replay the introduction** (the sheet closes first, then the introduction opens).
3. **Settings** (start screen, **Settings**):
   - *Fly alarm*: Relaxed / Normal / Twitchy. With Twitchy, a medium-speed approach that a Normal fly tolerates should spook it. The session log gets a `sensitivity ...` line with the new thresholds each time you change it.
   - *Swat*: Easy / Normal / Strict. Easy should accept a looser hand over the lens; Strict needs the lens properly covered. None of them asks for a faster cover or fold.
   - *Sound* off: no buzz and no effects. *Haptics* off: nothing to feel on the iPad anyway; check it on the Duo.
   - *Debug overlay*: the same as the Debug button, and now remembered after a relaunch.
   - *Reset best time*: asks first; afterwards the start screen shows no best time, also after a relaunch.
   - Quit and reopen: every choice is kept.
4. **Toasts while playing.** Lunge at a landed fly: *"Too fast – it got spooked. Creep up slowly."* in yellow. Cover the lens with the fly far away: *"Missed! It got away."* in orange. A hit: *"Splat!"* in green. Each goes after about 2 seconds. They sit on a dark capsule, so check they read well over a bright window too.
5. **Round complete.** Catch three flies. *Pass:* "Round complete!" with the time in big digits and your best time, then **Play again**. On a new best the heading reads "New best time!" with soft confetti behind it.
6. **Splat gallery** (start screen, **Splats**). Every fly you caught shows as its own drawn splat with its catch time, fly and round number and date, newest first. Catch more than 30 and the oldest drop off. **Clear the gallery** asks first.
7. **Accessibility.** In Settings → Accessibility → Display & Text Size → Larger Text, turn the size right up: the start card, settings, gallery and introduction should wrap and scroll rather than cut words off. With VoiceOver on, the buttons read "How to play", "Splat gallery", "Settings", "Start round"; the toasts are read out as they appear; each gallery splat reads as one item. With Reduce Motion on, the drawings hold still.

On the Duo (CI build), the introduction draws Posture A or B, whichever is selected. Hits and misses there keep using the existing result banner (and the "Gently does it" reminder after a fast fold); only the "Too fast" toast is new, on both screens.
