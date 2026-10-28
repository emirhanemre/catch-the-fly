# Building for iOS 27.1 without a Mac

Researched 2026-10-26. This is a decision paper for the developer, and the setup guide for the route it recommends.

## The short version

- **Problem.** Swift Playground on the iPad builds with the iOS 26 SDK ([API_NOTES](API_NOTES.md) section 0). So no iOS 27.1 symbol compiles there: no `UIHingeInteraction`, no `CameraCaptureAccessory`/`.sceneAccessory`, and the app runs letterboxed on the Duo. Posture A needs a build made with Xcode 27.1. Also, nobody can compile the app layer before it reaches the iPad, so every typo costs a round trip.
- **Recommendation: GitHub Actions on GitHub's `xcode-27` macOS runner.** On 2026-10-26 that image has **Xcode 27.1 (27A9275, the final release) as its default, with the iOS 27.1 SDK and an iPhone Duo simulator** ([runner-images readme](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md), image 20261022). Every push gets a real iOS 27.1 compile of every app-layer file. A button-press run signs the app, archives it and uploads it to TestFlight. All of it runs from a browser on Windows.
- **Cost.** £0 if the repo is public. If it's private, the Free plan's 2,000 minutes cover very roughly 200 macOS minutes a month (about 20 to 30 builds), then $0.062 a minute (about $0.50 per build). Linux tests cost almost nothing.
- **Backup:** Codemagic, which also has Xcode 27.1 and gives 500 free macOS minutes a month to a personal account. The build steps below would carry over almost unchanged.
- **Swift Playground stays** for quick iPad iteration (phase 4 on the iPad's rear camera). CI does the 27.1 builds that go to the Duo.

Files ready to use: [`.github/workflows/ios-build.yml`](../.github/workflows/ios-build.yml), [`.github/workflows/flycore-tests.yml`](../.github/workflows/flycore-tests.yml), [`project.yml`](../project.yml). None of them has run yet, because they can't run from here. Expect one or two fix-ups on the first real run (see "First-run risks").

## 1. Facts found (with sources)

| Fact | Source, date seen |
|---|---|
| Xcode 27.1 (27A9275) was released on 15 Oct 2026. It includes Swift 6.4 and the iOS 27.1 SDK, and needs macOS Tahoe 26.6 or later | [Apple Developer news](https://developer.apple.com/news/releases?id=10152026a), [Xcode 27.1 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_1-release-notes), 2026-10-26 |
| GitHub's runner images include an **`xcode-27`** image (labels `xcode-27`, `xcode-27-xlarge`), marked "preview". It has Xcode 27.0, **27.1 (default)** and 27.2 RC at `/Applications/Xcode_27.1.app`, the SDKs `iphoneos27.1` and `iphonesimulator27.1`, and an "iPhone Duo" simulator. Image version 20261022.0305.3 | [runner-images README](https://github.com/actions/runner-images), [xcode-27 readme](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md), 2026-10-26 |
| The preview was announced on 16 Jul 2026. The announcement warns that "some software can be unstable" and that "there could be queueing issues". No GA date was given | [runner-images #14404](https://github.com/actions/runner-images/issues/14404) |
| `macos-latest` / `macos-26` stop at Xcode 26.6, and `macos-15` is older still. The image policy is one major Xcode per image, with betas and RCs only on the newest image. So 27.x exists **only** on `xcode-27` for now | runner-images README and the [macos-26-arm64 readme](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md) |
| `xcode-27` is a **standard** runner (3-core M1, 7 GB) on both the public-repo and the private-repo lists. Standard runners are "free and unlimited on public repositories" | GitHub docs source, [`supported-github-runners.md`](https://github.com/github/docs/blob/main/data/reusables/actions/supported-github-runners.md), [`github-actions.md`](https://github.com/github/docs/blob/main/content/billing/concepts/product-billing/github-actions.md), 2026-10-26 |
| Private repos: the Free plan includes 2,000 minutes a month and Pro 3,000. The per-minute rates are Linux $0.006, Windows $0.010 and **macOS $0.062**, so macOS costs about 10× Linux. GitHub now quotes rates rather than "multipliers" (the old macOS multiplier was 10×). Without a payment method on file, jobs just stop when the quota runs out, so there are no surprise bills | GitHub docs source: [`actions-included-quotas.md`](https://github.com/github/docs/blob/main/data/reusables/billing/actions-included-quotas.md), [`actions-standard-runner-prices.md`](https://github.com/github/docs/blob/main/data/reusables/billing/actions-standard-runner-prices.md), 2026-10-26. *Inference*: how many macOS minutes 2,000 included minutes buy now that usage is billed in dollars. Check it on the billing page after the first runs |
| Xcode Cloud: the Developer Program includes **25 compute hours a month**. Extra plans cost $49.99/month (100 h) and up. Builds can be started and workflows edited from App Store Connect on the web, but **setup starts in Xcode**: the App Store Connect API can list and delete Xcode Cloud *products* but has no call to create one. Apple also warns that a tool which "dynamically generates" the project (XcodeGen) can make Xcode Cloud fail | [Xcode Cloud](https://developer.apple.com/xcode-cloud/), [Setting up your project to use Xcode Cloud](https://developer.apple.com/documentation/xcode/setting-up-your-project-to-use-xcode-cloud), [API: ciProducts](https://developer.apple.com/documentation/appstoreconnectapi/products) (only GET and DELETE), 2026-10-26 |
| Xcode Cloud's release notes stop at Xcode 26.2 (19 Dec 2025), so whether it offers 27.1 isn't documented there. Apple usually adds releases quickly | [Xcode Cloud release notes](https://developer.apple.com/xcode-cloud/release-notes/), 2026-10-26. Unverified |
| Codemagic: an "Xcode 27.1.x" machine with Xcode 27.1 (27A9275) on M2 or M4 Mac minis, from a base-image update on 23 Oct 2026. 500 free M2 minutes a month on a personal account (not Teams), then $0.095 a minute | [codemagic-docs: `xcode-27-1.md`](https://github.com/codemagic-ci-cd/codemagic-docs/blob/main/content/specs-macos/xcode-27-1.md), [`pricing.md`](https://github.com/codemagic-ci-cd/codemagic-docs/blob/main/content/billing/pricing.md), 2026-10-26 |
| Bitrise: a stable "Xcode 27.1" stack, updated v2026-10-23 (released 2026-10-26). Pricing could only be checked through aggregator sites: a free Hobby tier (reported as 300 credits a month) and paid plans at about $89 to $225 a month | [bitrise-io/stacks](https://github.com/bitrise-io/stacks/blob/main/content/changelogs/osx-xcode-27.1.x.md), [agentdeals](https://agentdeals.dev/vendor/bitrise), [cicdcalculator](https://cicdcalculator.com/bitrise-pricing-mobile-ci). Prices unverified (bitrise.io wasn't reachable from here) |
| MacinCloud: about $1 an hour pay-as-you-go and about $25 to $30 a month for shared "managed" servers, per third-party pages. On managed plans you can't install apps yourself (Trustpilot reviews, Sept 2026). Whether Xcode 27.1 is installed is unknown | [Green Mini comparison](https://www.greenmini.nl/compare/macincloud-alternative/), [Trustpilot](https://ch.trustpilot.com/review/www.macincloud.com). Unverified (macincloud.com wasn't reachable from here) |
| Upload: fastlane, which is current and preinstalled on the runner, still uploads with `xcrun altool --upload-app --apiKey … --apiIssuer …` and treats the output line "UPLOAD SUCCEEDED with no errors" as success. A 2026 Bitrise changelog says Xcode 26's altool can return exit code 0 even on failure, and calls `--upload-app` deprecated but still working | [fastlane `itunes_transporter.rb`](https://github.com/fastlane/fastlane/blob/master/fastlane_core/lib/fastlane_core/itunes_transporter.rb), search result for the Bitrise step changelog (not fetched) |
| Signing on a fresh CI machine with only an API key (`xcodebuild -allowProvisioningUpdates -authenticationKeyPath/-ID/-IssuerID`) is documented by `man xcodebuild` ("will create and update profiles, app IDs, and certificates"). In practice it often fails at the **archive** step, because it wants a development certificate. Ephemeral runners also leave "Created via API" certificates behind until the account hits its limit | [Apple forum 764554](https://developer.apple.com/forums/thread/764554) (DTS quoting the man page), [forum 695759](https://developer.apple.com/forums/thread/695759), search summaries of [zenn.dev](https://zenn.dev/ohtsuki/scraps/799e5b7c3f2498) and [rxliuli.com](https://rxliuli.com/blog/two-pitfalls-of-safari-cloud-signing-in-github-actions) (2026) |
| codemagic-cli-tools 0.70.0 (7 Oct 2026, open source, a pip package). `app-store-connect fetch-signing-files <bundle-id> --type IOS_APP_STORE --create` uses the API key to find or create the bundle ID, the distribution certificate (from a private key you supply) and the profile. `xcode-project use-profiles` then applies them, and `app-store-connect publish` uploads. It runs on any CI, not only Codemagic | [cli-tools docs](https://github.com/codemagic-ci-cd/cli-tools/tree/master/docs), [PyPI](https://pypi.org/project/codemagic-cli-tools/), 2026-10-26 |
| XcodeGen 2.46.0 (16 Jul 2026) is the latest release. Its unreleased changelog adds an `xcode27_0` project format and fixes a resources-phase bug that broke **Xcode 27.2** project conversion. 27.1 isn't mentioned | [XcodeGen CHANGELOG](https://github.com/yonaskolb/XcodeGen/blob/master/CHANGELOG.md), 2026-10-26 |
| Swift 6.4.1 was released on 12 Oct 2026, with Linux and Windows builds. The Docker Hub `swift:6.4.1-noble` image exists | [swift.org release data](https://github.com/swiftlang/swift-org-website/blob/main/_data/builds/swift_releases.yml), Docker Hub, 2026-10-26 |

## 2. Options compared

| Option | Cost for us | Setup effort | iOS 27.1 SDK? | What the developer does by hand |
|---|---|---|---|---|
| **Swift Playground on iPad** (today) | £0 | None | **No**: iOS 26 SDK (4.7, March 2026). A newer version may arrive, but none was found | Everything: build, run, upload. Still the fastest loop for iPad testing |
| **GitHub Actions, `xcode-27` runner** (recommended) | Public repo £0. Private: free quota (very roughly 200 macOS min/month), then $0.062/min | About an hour, all in a browser, plus one `openssl` command | **Yes, today**: 27.1 is the image default (preview image) | Create the repo, an API key, one private key, 4 secrets, 3 variables. Press "Run workflow" for each TestFlight build |
| **Codemagic** | 500 free M2 min/month (personal), then $0.095/min | About the same; needs a `codemagic.yaml` (not written yet) | **Yes, today** (27.1 machine, image of 23 Oct 2026) | The same Apple steps, plus connecting the GitHub repo on codemagic.io |
| **Bitrise** | Free Hobby tier (reported); paid plans about $89+/month (unverified) | Medium: their web workflow editor or `bitrise.yml` | **Yes** (stable 27.1 stack, 2026-10-26) | The same Apple steps, plus Bitrise's own signing set-up |
| **Xcode Cloud** | 25 h/month free with the Developer Program | **Needs Xcode once** to create the product and first workflow, so a Mac must be rented for a session. It also dislikes generated projects, so the `.xcodeproj` would have to be committed | Not documented: the release notes are stale at 26.2. Probably soon | Rent a Mac once, onboard in Xcode, commit the generated project, then start builds from App Store Connect on the web |
| **Rent-a-Mac** (MacinCloud, AWS EC2 Mac, Scaleway…) | MacinCloud about $1/h or $25 to $30/month (unverified). AWS and Scaleway bill a 24 h minimum (from memory, unverified) | High: remote desktop, install or update Xcode yourself (not allowed on MacinCloud managed plans) | Only if you can install 27.1 | Everything Xcode needs, by remote desktop, every time |

Why GitHub Actions wins: it's the only route that is **free or nearly free, already has 27.1, needs no Mac even once, and lives where the code lives**. The same push that the iPad pulls through Working Copy also gets compile-checked. Codemagic is a close second, and better if the repo must be private and builds get frequent (500 free minutes against roughly 200). Xcode Cloud is out until someone has a Mac for an afternoon.

**The catch: `xcode-27` is a preview image.** If it's slow to queue or flaky, move to Codemagic (same Apple setup, different YAML). When GitHub ships the GA macOS 27 image, change `runs-on` in `ios-build.yml`. That's a one-line edit.

## 3. Who does what after this

| Swift Playground on the iPad | CI (GitHub Actions) |
|---|---|
| Fast edit, build and run on the iPad (phase 4 prototype on the rear camera, stand-in smash) | Compile check on every push of `apps/**`, `FlyCore/Sources/**` or `project.yml` against the **iOS 27.1 SDK**: catches type errors and typos before anyone opens the iPad |
| iOS 26 SDK builds. The `#if IOS_27_1_SDK` blocks are skipped (see below) | iOS 27.1 SDK builds. The 27.1 code paths are compiled in: `UIHingeInteraction`, `CameraCaptureAccessory`, `.builtInInnerUltraWideCamera`… |
| Can still upload to TestFlight, but the result runs letterboxed on the Duo | **Duo builds:** full screen, native hinge, cover-display accessory. Uploaded to TestFlight for the Duo tester |
| — | `swift test` for FlyCore on Linux (Swift 6.4.1 and 6.2.4) and Windows (6.4.1), plus `swiftc -parse` of all app files, on every push |

**Upload each app from one place.** Once CI has uploaded DuoProbe, upload DuoProbe only from CI (or use a different version number in Playgrounds). CI build numbers look like `20261026.1532` (the UTC date and time). They always increase, and Playgrounds' small numbers would sit below them.

### Writing code for both builds

Both builds compile the same files, but the iPad SDK doesn't know any 27.x symbol, and `#available` doesn't help with that (it's a runtime check, and the code still has to compile). `project.yml` therefore defines a compilation condition, `IOS_27_1_SDK`, in CI builds only:

```swift
#if IOS_27_1_SDK
if #available(iOS 27.1, *) {
    let hinge = UIHingeInteraction { _, update in /* … */ }   // compiled only in CI
    view.addInteraction(hinge)
}
#else
// iPad / Playground build: runtime lookup (API_NOTES section 6) or the darkening fallback
#endif
```

On the iPad the `#if` block is parsed but never type-checked, so it costs nothing there. CI fails the build if the runner's SDK isn't 27.1, so the flag can't be set on the wrong SDK. This is a proposed convention: whoever writes the Duo code should adopt it, and CLAUDE.md rule 3 could mention it.

## 4. Setup, step by step, from Windows

You need: the Apple Developer Program (Account Holder or Admin role), a GitHub account, and Git for Windows (it includes `openssl`). Nothing is paid for unless you add a payment method.

### Step 1: put the code on GitHub

1. On github.com: **New repository** → name `catch-the-fly`. Choose **Public** (macOS minutes free and unlimited) or **Private** (free quota, then paid, see section 2). **Don't** tick "Add a README".
2. In the project folder on Windows (PowerShell or Git Bash), using the commands GitHub shows under "push an existing repository":
   ```
   git remote add origin https://github.com/<you>/catch-the-fly.git
   git branch -M main
   git add -A
   git commit -m "Initial import"
   git push -u origin main
   ```
3. On github.com, open **Actions**. You should see "FlyCore tests" and "iOS build" start. "iOS build" without secrets just compiles. That's the first check: see section 5.

(This is also the GitHub + Working Copy fallback route in CLAUDE.md, so the iPad can pull from the same repo.)

### Step 2: bundle IDs and Team ID

1. **Team ID:** [developer.apple.com/account](https://developer.apple.com/account) → **Membership details** → Team ID (10 characters).
2. **Bundle IDs:** if Playgrounds has already uploaded DuoProbe, use its existing ID: App Store Connect → Apps → DuoProbe → **App Information** → Bundle ID. Otherwise pick one per app, e.g. `com.<yourname>.duoprobe` and `com.<yourname>.catchthefly`, and register each one: developer.apple.com → **Certificates, IDs & Profiles** → **Identifiers** → **+** → App IDs → App → Explicit. No capabilities are needed (camera and motion are only Info.plist strings).
3. **App records:** each app needs one in App Store Connect before its first upload: **Apps** → **+** → **New App** → iOS, a name, primary language English (U.K.), the bundle ID from the list, and any SKU. DuoProbe may already have one.
4. **TestFlight:** add the Duo tester as an internal tester (Phase 0 in PLAN.md). Internal testers get every processed build without Beta App Review.

### Step 3: App Store Connect API key

1. [App Store Connect](https://appstoreconnect.apple.com) → **Users and Access** → **Integrations** → **App Store Connect API** → **Team Keys** → **+** (Generate API Key).
2. Name it `GitHub CI`, with access **Admin**. Creating certificates and profiles through the API needs more than the Developer role. You can revoke the key at any time.
3. Note the **Key ID** and the **Issuer ID** (shown above the list). **Download** `AuthKey_<KEYID>.p8`. Apple lets you download it only once. Keep it out of the repo folder.

### Step 4: a private key for the distribution certificate

CI creates the "Apple Distribution" certificate itself, through the API, from a private key that only you hold. Make the key once, in Git Bash:

```
openssl genrsa -out dist_cert_key.pem 2048
```

(In PowerShell, use `& "C:\Program Files\Git\usr\bin\openssl.exe" genrsa -out dist_cert_key.pem 2048`.) Keep this file safe and outside the repo. Every CI run reuses the same certificate made from it. An account can have only a few distribution certificates, so don't make a new key each time.

### Step 5: secrets and variables in GitHub

Repo → **Settings** → **Secrets and variables** → **Actions**.

**Secrets** tab → **New repository secret**, four times:

| Name | Value |
|---|---|
| `ASC_KEY_ID` | the Key ID from step 3 |
| `ASC_ISSUER_ID` | the Issuer ID from step 3 |
| `ASC_PRIVATE_KEY` | open `AuthKey_<KEYID>.p8` in Notepad and paste **all** of it, including the `-----BEGIN PRIVATE KEY-----` and `-----END…` lines |
| `DIST_CERT_PRIVATE_KEY` | all of `dist_cert_key.pem`, including the BEGIN and END lines |

**Variables** tab → **New repository variable**:

| Name | Value |
|---|---|
| `CTF_TEAM_ID` | the Team ID from step 2 |
| `CTF_BUNDLE_ID_DUOPROBE` | e.g. `com.<yourname>.duoprobe` |
| `CTF_BUNDLE_ID_CATCHTHEFLY` | e.g. `com.<yourname>.catchthefly` |
| `CTF_MARKETING_VERSION` | optional, e.g. `0.2.0` (default `0.1.0`) |

### Step 6: the first TestFlight build

1. **Actions** → **iOS build** → **Run workflow** → branch `main`, **upload** = `DuoProbe` → **Run workflow**.
2. It takes about 10 to 15 minutes: compile, then fetch signing files, archive, export and upload. The log ends with "Uploaded DuoProbe 0.1.0 (2026…)".
3. Within roughly 5 to 30 minutes the build appears in App Store Connect → DuoProbe → **TestFlight**. The tester's TestFlight app offers it.
4. If a step fails, the job's **Artifacts** hold the full `xcodebuild` logs (`ios-build-logs-<n>`). Paste the error to Claude Code.

## 5. What the workflows do

### `flycore-tests.yml` (every push touching `FlyCore/**` or `apps/**`)

- **Linux:** `swift test` in the official `swift:6.4.1-noble` and `swift:6.2.4-noble` Docker images. 6.4.1 is the current release and matches Xcode 27.1's Swift 6.4. 6.2.4 is a conservative floor for Playground 4.7, whose exact Swift version is unverified. Docker images are maintained by the Swift project and pinned by tag, so there's no third-party setup action. The job also checks that FlyCore imports only Foundation.
- **Windows:** `swift test` with Swift 6.4.1 via `compnerd/gha-setup-swift` (pinned to the v0.5.1 commit), the setup action maintained by the Swift-on-Windows people. It's the same toolchain as the developer's PC.
- **App parse:** `swiftc -parse` on every `apps/**/*.swift`, which is CLAUDE.md rule 4 in CI. It takes seconds, so typos are caught even without macOS minutes.
- Note: `swift test` fails until `FlyCore/Tests/FlyCoreTests/` contains a test file, because git doesn't store empty folders.

### `ios-build.yml`

- **Every push or PR** touching app code: select Xcode 27.1 (one variable, `XCODE_VERSION`, and the build fails if the SDK isn't 27.1), download XcodeGen 2.46.0 (checksum pinned), generate `CatchTheFly.xcodeproj` from `project.yml`, and build each app that has `.swift` files for `generic/platform=iOS` with `CODE_SIGNING_ALLOWED=NO`. No Apple account is involved. Errors show as annotations on the files.
- **Manual run with "upload"**: also checks that every secret and variable is set (with a clear message if not), then uses codemagic-cli-tools 0.70.0 to fetch or create the certificate and App Store profile into a temporary keychain, archives Release, exports the IPA and uploads it.
- **Placeholder icon:** App Store Connect rejects builds without an app icon. If `apps/<App>/` has no `AppIcon.appiconset` (or Icon Composer `AppIcon.icon`), CI generates a plain green (Catch the Fly) or blue (DuoProbe) 1024×1024 icon under `build/`, never in `apps/`. Add a real `Assets.xcassets/AppIcon.appiconset` to `apps/<App>/` and CI uses that instead.
- Why not plain `xcodebuild -allowProvisioningUpdates` with the API key? It's Apple's own route, but on a fresh runner it typically fails at archive (it wants a development certificate) and leaks a new certificate per run (section 1). The codemagic tool keeps one certificate made from our key and uses manual profiles, which is predictable. If you'd rather try Apple's route, the swap is: archive with `CODE_SIGNING_ALLOWED=NO`, then export with `-allowProvisioningUpdates -authenticationKeyPath … -authenticationKeyID … -authenticationKeyIssuerID …`, `method` `app-store-connect` and `signingStyle` `automatic` (needs an Admin key with cloud-managed certificate access). That swap is untested.

### `project.yml`

- Two iPhone-only app targets, iOS 26.0 deployment target, Swift 6, nonisolated by default (like a `.swiftpm`):
  - **CatchTheFly** = `apps/CatchTheFly/**` + `FlyCore/Sources/FlyCore/*.swift`, in one module, exactly as `to-ipad.ps1` assembles the Playgrounds project. That's why app code never imports FlyCore.
  - **DuoProbe** = `apps/DuoProbe/**`.
- Whole folders, not file lists, so new files need no spec change. `README*`/`NOTES*`-style `.md`, `.DS_Store` and `.orig` files are excluded. Missing or empty folders are allowed.
- Info.plist generated with British English purpose strings: `NSCameraUsageDescription`, `NSMotionUsageDescription`, plus `NSPhotoLibraryAddUsageDescription` for DuoProbe (the share sheet's "Save Video" needs it). It also sets `UILaunchScreen` (needed for full screen) and `ITSAppUsesNonExemptEncryption = NO` (skips TestFlight's export-compliance question). **If an app ever records audio, add `NSMicrophoneUsageDescription`** here and in Playgrounds.
- Bundle IDs, Team ID and version come from the variables above. FlyCoreTests isn't a target, because Linux and Windows run those tests more cheaply.

## 6. First-run risks and what to check

| Risk | What you'd see | Fix |
|---|---|---|
| The `xcode-27` preview queues slowly or is withdrawn | Job waits "Waiting for a runner" | Wait, or move to Codemagic. When a GA macOS 27 image appears, change `runs-on` |
| A future image renames the app bundle (e.g. `Xcode_27.1.0.app` only) | "Select Xcode" fails and lists the installed Xcodes | Edit `XCODE_VERSION` or the path |
| XcodeGen 2.46.0 output trips Xcode 27.1 | "Generate" or "Build" fails with a project-format error | Bump `XCODEGEN_VERSION` and the checksum once 2.47 ships with `xcode27_0` |
| CI is stricter than Playgrounds (Swift 6 mode, 27.1 SDK deprecations) | Errors that the iPad doesn't show | Usually a real issue: fix the code. If Playgrounds uses Swift 5 mode, `SWIFT_VERSION` could go to 5, but strict is safer |
| A Playgrounds-only file (its own `@main` or `ContentView.swift`) ends up in `apps/<App>/` | "multiple @main" | Keep only our sources in `apps/` (to-ipad.ps1 already renames the template files on the iPad side) |
| Signing: the bundle ID or app record doesn't exist, or the key isn't Admin | "Fetch signing files" or "Upload" fails with an API error | Re-check steps 2 and 3 |
| Too many distribution certificates already exist | "Fetch signing files" can't create one | Revoke an unused one at developer.apple.com → Certificates (check first that it isn't one Playgrounds relies on) |
| Upload rejected (e.g. a duplicate build number, a missing icon) | "Upload" step error | Re-run (the build number changes every minute), or add a real icon |

## 7. Not done (deliberately)

- No GitHub repo was created, nothing was pushed or committed, and nothing was signed up for. The workflows have never run.
- No `codemagic.yaml`. Write one only if GitHub's preview image lets us down.
- No UI tests on the iPhone Duo simulator. The `xcode-27` image has it, and its camera support is limited, but it could later give us screenshots of cover and inner layouts on every push.
