# Getting the apps onto the iPad by download

The quickest route: no iCloud for Windows and no script. Every push to `main` that changes app code makes CI pack each app into a ready-to-open Swift Playgrounds project and publish it on GitHub.

- **Where:** https://github.com/emirhanemre/catch-the-fly/releases/tag/ipad-latest
- **What:** `CatchTheFly.swiftpm.zip` (the game, with FlyCore) and `DuoProbe.swiftpm.zip` (the spike app)
- **How it's made:** `scripts/pack-swiftpm.sh`, from the manifests in `ipad/<App>/Package.swift`, by `.github/workflows/ipad-packages.yml`. CI builds each project with the iOS 26 SDK before publishing it.

The other route, syncing into a project you created yourself through iCloud Drive, still works: see `scripts/to-ipad.ps1` and the `FOR_THE_IPAD_*.md` notes.

## Steps

1. On the iPad, install **Swift Playgrounds** from the App Store. Running apps on your own iPad doesn't need the paid developer membership.
2. In Safari, open the release link above and tap **CatchTheFly.swiftpm.zip**. Choose **Download**.
3. Open the **Files** app → **Downloads**, and tap the zip. Files unzips it into a `CatchTheFly.swiftpm` folder next to it.
4. Tap **CatchTheFly.swiftpm**. It opens in Swift Playgrounds. If Files doesn't offer that, open Swift Playgrounds, tap **Locations** (or the folder icon), and open it from Downloads.
5. Tap **Run** (▶). The first time, allow camera and motion access when iOS asks.

Camera and Motion are already set in the project, with their purpose strings. Nothing needs adding in the app settings.

## Updating

Each download is a complete fresh copy. Before you download a newer one, delete or rename the old project in Playgrounds, otherwise you end up with "CatchTheFly 2". Any changes you made in Playgrounds itself are not kept, so make changes in the repo instead.

The release notes say which commit the zips were built from. Compare it with the latest commit on `main` if you're not sure you have the newest build.

## When it doesn't build

The game hasn't been built in Playgrounds before, so the first run may show errors. Screenshot them, or copy them from the issue list, and paste them into Claude Code. CI builds the same files with the same SDK, so most problems are caught before a zip is published. Playgrounds-only differences, such as its Swift version, can still slip through.

## Playing

The game guide is `FOR_THE_IPAD_CatchTheFly.md`, from "Before you test" on: stand about 1 m from something busy, and smash by calmly covering the camera with your palm.
