# For the iPad: DuoProbe (phase 1 spike)

## Files

All new, all in `apps/DuoProbe/` (Swift only, one module, its own `@main`):

| File | What it does |
|---|---|
| `ProbeApp.swift` | `@main`, the test list, scene-phase logging |
| `ProbeLog.swift` | The session log (timestamped, written to a .txt as it goes), results, attached clips and CSVs |
| `ProbeSupport.swift` | Thread-safe queues and boxes, a main-actor poller, the CSV writer |
| `ProbeUI.swift` | Shared screen layout, answer buttons, Share log button, full log view |
| `CameraCapture.swift`, `CameraController.swift`, `CameraFinder.swift` | Capture session, luma per frame, preview, camera discovery and "inner camera" choice |
| `MotionRecorder.swift`, `HingeProbe.swift`, `DisplayInfo.swift`, `ARProbe.swift`, `CloseMath.swift` | Motion, hinge (runtime lookup), screens and lifecycle, ARKit, per-close maths and CSV sidecars |
| `P01DeviceInfo.swift` … `P12PostureB.swift` | One file per test (P4 and P4b share a file) |

Nothing in `FlyCore/` or any `Package.swift` was touched.

## Getting the files across

On Windows, from the repo folder, the **first time**:

```
.\scripts\to-ipad.ps1 -App DuoProbe -AdoptTemplate
```

`-AdoptTemplate` renames the template's `MyApp.swift` and `ContentView.swift` to `.orig`, because our `ProbeApp.swift` has its own `@main`. After that, plain `.\scripts\to-ipad.ps1 -App DuoProbe` is enough. Wait for iCloud to finish, then close and reopen DuoProbe in Swift Playground on the iPad.

## Set these in Swift Playground (don't edit Package.swift)

Open the project, tap the app settings (the project name / gear at the top of the sidebar), then **Capabilities → +**:

| Capability | Purpose string to paste |
|---|---|
| **Camera** | DuoProbe uses the cameras to test what this iPhone's cameras can see. Images stay on the phone unless you share the log. |
| **Motion & Fitness** | DuoProbe uses motion data to measure how the phone moves while it opens and closes. |
| **Photo Library (add only)**, if Playground offers it | DuoProbe saves its test clips to your photo library when you choose Save Video. |

No microphone is needed: the clips have no audio. If there's no add-only Photos capability, tell the tester **not** to tap "Save Video" in the share sheet. Without that string iOS closes the app. Sending through WhatsApp, Messages or AirDrop is fine.

A forum report says adding a capability once crashed Playground and a reinstall fixed it. If that happens, reinstall and add them again.

## Run it on the iPad: what "pass" looks like

Tap the ▶ Run button. Then go through the list. Nothing should crash; every test either logs a result or says why not.

| Test | Expected on the iPad |
|---|---|
| P1 | VALUE lines; build says "Playgrounds runtime"; every 27.x class is `nil`; ends PASS |
| P2 | Lists the iPad's cameras; tapping one shows its picture (sideways is normal) |
| P3, P4, P6, P9, P10 | Log "N/A: Duo inner camera not found here; using Front Camera instead" and then run on the front camera. P6: cover the camera with your hand 5 times and it should count 5 darkening events. P9: three .mov clips plus CSVs appear in Share log (if the log says the video data output can't be added alongside the movie output, the clips still record but the CSVs' luma column stays empty) |
| P4b | N/A "this is the Playgrounds build" |
| P5 | N/A "hinge runtime path failed at step 1: … class doesn't exist" |
| P7 | AR runs on the rear camera, then the front camera starts alongside; PASS or FAIL depending on the iPad, either is fine |
| P8 | PASS on iPads that support multi-cam, otherwise N/A |
| P11 | Runs, but on a one-piece iPad the conclusion will be "unclear" |
| P12 | AR on the rear camera for 10 s, PASS once tracking reaches normal |

Then tap **Share log** and AirDrop it to the PC: it should contain the .txt plus the clips and CSVs. Paste any compile errors back to Claude Code exactly as Playground shows them.

## Upload to App Store Connect and add to TestFlight

1. In App Store Connect, make sure there's an app record for DuoProbe (Apps → + → New App, English (U.K.), any SKU). Playground can create the record for you on the first upload if you choose that option.
2. In Swift Playground, open the app settings and set a version (e.g. 0.1) and build number (1). Raise the build number for every upload.
3. Use **App Store Connect → Upload** in the app settings (the menu wording may differ slightly). Sign in with the developer account if asked. Wait for "Upload complete".
4. In App Store Connect → DuoProbe → **TestFlight**, wait for the build to finish processing (from a few minutes up to an hour). Answer the export compliance question: no custom encryption.
5. Add the build to the internal testing group that has the Duo tester. Internal testers don't need Beta App Review, so they get a TestFlight notification straight away.
6. Send them `docs/SPIKE_CHECKLIST.md` (or read it out to them). It takes about 20 minutes.

## The CI build (optional, answers P4b)

The same files also build in CI with Xcode 27.1 (`project.yml`, `IOS_27_1_SDK`). That build uses the native hinge API, the native inner/outer camera types and runs P4b (camera picture on the cover display through `CameraCaptureAccessory`). It isn't letterboxed. If you upload both, give the tester the CI build too and ask them to run P1, P2, P4b and P5 in it. P1's first line says which build he's running.
