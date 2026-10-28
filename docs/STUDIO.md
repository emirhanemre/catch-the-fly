# Studio board

Who's doing what. The developer is the supervisor and gets pulled in only at dead ends and at release.

## Roles

| Role | Owns | Status |
|---|---|---|
| Producer (lead Claude session) | Plan, task board, hand-offs, integration, the final report | Running |
| API Scout | `docs/API_NOTES.md`, the API facts in `docs/DUO_FACTS.md` | Done 2026-10-26 |
| FlyCore engineer | `FlyCore/` (engine + XCTest), `FlyCore/API.md` | Done 2026-10-26 (148 tests, all passing on Linux, Swift 6.2.4) |
| DuoProbe engineer | `apps/DuoProbe/`, `docs/FOR_THE_IPAD_DuoProbe.md`, `docs/SPIKE_CHECKLIST.md` | Done 2026-10-26 (P1–P12, QA-checked) |
| Build infrastructure | `docs/MAC_FREE_BUILD.md`, `.github/`, `project.yml` | Done 2026-10-26 |
| Game app engineer | `apps/CatchTheFly/` (phase 4 iPad prototype) | Done 2026-10-26 |
| Duo integration | `#if IOS_27_1_SDK` files in `apps/CatchTheFly/` (phase 5, Posture A and B) | Done 2026-10-26 |
| Polish | Onboarding, settings, splat gallery, toasts (phase 6) | Done 2026-10-26 |
| QA reviewer | A desk-check of every Swift file, since nothing can be compiled in the studio | FlyCore, DuoProbe and CatchTheFly passes done |

## Decisions so far

- 2026-10-26: Swift Playgrounds 4.7 probably builds against the iOS 26 SDK, so the source mentions no iOS 27.x symbols. Duo APIs are reached through the Objective-C runtime or raw-value strings (see `API_NOTES.md` sections 0 and 6).
- 2026-10-26: Posture A (the camera view on the cover display) needs `CameraCaptureAccessory`, which is SwiftUI-only and iOS 27.1 only. So the Playgrounds route can only reach Posture B. Getting Posture A needs an Xcode 27.1 build (see `MAC_FREE_BUILD.md`).
- 2026-10-26: The spike gains P10 (close signals), P11 (which half holds the motion sensors) and P12 (Posture B check).
- 2026-10-26: `scripts/to-ipad.ps1` copies into the managed subfolders `FlyCore/` and `App/` inside the `.swiftpm`, and tracks what it placed in a manifest. It was tested with PowerShell 7 against a mock project.
- 2026-10-26: GitHub Actions' `xcode-27` runner has Xcode 27.1 and the iOS 27.1 SDK, so Posture A is reachable without a Mac. Native 27.1 code goes inside `#if IOS_27_1_SDK`, a flag only CI defines, so Playgrounds and CI build the same files.
- 2026-10-28: The iPad can also download ready-made projects. `ipad/<App>/Package.swift` holds a Playgrounds app manifest per app (format checked against real Playgrounds projects on GitHub: `.camera`, `.motion`, `.photoLibraryAdd`, `.placeholder(icon:)`). `scripts/pack-swiftpm.sh` packs it with the sources, in `to-ipad.ps1`'s layout, and CI publishes the zips to the `ipad-latest` release (`docs/IPAD_DOWNLOAD.md`). This is the default route for testing on the iPad; the iCloud sync stays as an alternative.

## Known gaps

- 2026-10-26: FlyCore compiles and all 148 tests pass with Swift 6.2.4 on Linux, with no warnings, including a build with `-default-isolation MainActor`. All 58 app files pass `swiftc -parse`. The app layer can't be type-checked without Apple's SDKs, so it waits for CI or the iPad.
- Every file passes a tree-sitter syntax check and a scan for 27.x symbols that leak outside `#if IOS_27_1_SDK`. Type checking was done by desk review only.
- CI gained a job that builds with the iOS 26 SDK and no flag, to mimic Playgrounds.
