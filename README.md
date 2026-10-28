# Catch the Fly

An AR fly-swatting game for iPhone Duo, where folding the phone shut is the swat.

This folder is the handoff pack for Claude Code:

| File | What it is |
|---|---|
| `CLAUDE.md` | Standing rules Claude Code loads automatically: the no-Mac build reality, the repo layout, the workflow. Kept on the developer's PC, not published |
| `docs/PLAN.md` | Game spec, tracking and smash routes, phases with acceptance criteria, risks |
| `docs/DUO_FACTS.md` | What's verified about the Duo and its APIs (with sources), and what's still unknown |
| `docs/SPIKE_CHECKLIST.md` | The test-session script for whoever holds the Duo |

## Getting started

1. Do the Phase 0 checklist in `docs/PLAN.md`. The Apple Developer enrolment takes longest, so start that first.
2. Put this folder somewhere outside iCloud Drive (for example `C:\dev\catch-the-fly`) and run `git init`.
3. Open Claude Code in the folder and paste the kickoff prompt below.

## Kickoff prompt

```
Read CLAUDE.md and every file in docs/ before doing anything.

1. Tell me anything in the plan you think is wrong, risky or missing, and any
   questions you need answered. Keep it short.
2. Then start Phase 1: read the Apple sources under "Read before coding" in
   docs/DUO_FACTS.md, record the exact API signatures you confirm, and write the
   DuoProbe sources in apps/DuoProbe/ covering tests P1 to P9. Duo-only tests
   must report "not available" on my iPad instead of crashing.
3. Write scripts/to-ipad.ps1 once I've told you where the DuoProbe.swiftpm
   project shows up in iCloud Drive.
4. Hand over with a "For the iPad" note. Then start Phase 3 (FlyCore) while I
   build and upload DuoProbe.
```
