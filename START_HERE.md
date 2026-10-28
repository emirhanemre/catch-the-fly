# Start here

The studio has written a first full version of Catch the Fly: the engine, a spike app for the Duo, the game itself (iPad prototype, Duo Posture A and Posture B, plus polish) and a build pipeline. **The engine is compiled and tested**: FlyCore builds with Swift 6.2.4 and passes all 148 tests. All the app code passes `swiftc -parse`, but it can only be type-checked with Apple's SDKs (by CI or the iPad), so expect a round of compile fixes there. Paste the errors into Claude Code and they'll get fixed.

## What's in the box

| Part | Where | State |
|---|---|---|
| FlyCore, the game engine (Foundation only) | `FlyCore/` | Compiles; 148/148 tests pass (Linux, Swift 6.2.4) |
| DuoProbe, the spike app (P1–P12) | `apps/DuoProbe/` | Written and desk-checked |
| Catch the Fly, the game | `apps/CatchTheFly/` | Phases 4, 5 and 6 written and desk-checked |
| iPad sync script | `scripts/to-ipad.ps1` | Tested with PowerShell 7 against a mock project |
| CI: FlyCore tests, iOS 27.1 builds, TestFlight upload | `.github/workflows/`, `project.yml` | Written; never run |
| Docs | `docs/` | `API_NOTES.md` (verified Apple signatures), `MAC_FREE_BUILD.md`, `FOR_THE_IPAD_*.md`, `SPIKE_CHECKLIST.md`, `STUDIO.md` (decisions log) |

## The key finding

Swift Playgrounds on the iPad builds against the iOS 26 SDK, so it can't use any iPhone Duo API directly. The studio's answer is two builds from the same files:

- **Playgrounds (iPad):** quick iteration. Duo features are reached at runtime, and you get the iPad prototype plus Posture B.
- **GitHub Actions on the `xcode-27` macOS runner:** Xcode 27.1, the real Duo APIs (hinge, inner camera, the game on the cover display = Posture A). It uploads straight to TestFlight. It's free on a public repo, with roughly 20–30 builds a month free on a private one.

## Your steps, in order

1. **Optional:** run `swift test` in `FlyCore/` on your PC (Swift from swift.org). It already passes on Linux, and CI also runs it on Windows.
2. **Phase 0** from `docs/PLAN.md`: Apple Developer enrolment, Swift Playgrounds, iCloud for Windows, and the Duo tester as an internal TestFlight tester.
3. **GitHub + CI:** follow `docs/MAC_FREE_BUILD.md` section 4, steps 1–6. Once pushed, every commit compiles FlyCore on Linux and Windows and compiles both apps twice: once against iOS 26 with no flag (just like Playgrounds) and once against iOS 27.1. This is the fastest way to flush out compile errors.
4. **The spike:** build DuoProbe (CI is preferred, because it also answers P4b, Posture A). Send it to the Duo tester through TestFlight with `docs/SPIKE_CHECKLIST.md`. Bring the log back to Claude Code; it updates `DUO_FACTS.md`, the presets and the hinge-status mapping.
5. **The game:** play the iPad prototype (`docs/FOR_THE_IPAD_CatchTheFly.md`), then the Duo build ("Build: CatchTheFly Duo 1" in the spike checklist).

## Values the spike will replace (guesses today)

- The hinge status raw values: `FlyTunables.hingeStatusMapping`.
- Which frame edge is nearest the hinge in Posture A: `FlyPreset` (`.right` for now).
- How much of the inner camera's view the forward half blocks: the hit region's blocked margin.
- Whether the runtime hinge works in a Playgrounds build, and the inner camera's raw device-type string.
