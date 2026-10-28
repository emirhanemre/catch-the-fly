#!/usr/bin/env bash
# Builds a ready-to-open Swift Playgrounds project for one app, plus a zip of it:
#
#   build/swiftpm/<App>.swiftpm/
#     Package.swift   from ipad/<App>/Package.swift
#     App/            apps/<App>/** (everything except .md, .DS_Store, .orig and Package.swift)
#     FlyCore/        FlyCore/Sources/FlyCore/*.swift (CatchTheFly only)
#   build/swiftpm/<App>.swiftpm.zip
#
# The same layout scripts/to-ipad.ps1 puts into an existing project, so both routes
# compile the same files. CI runs this and publishes the zips (ipad-packages.yml);
# it also runs locally in Git Bash. Usage: scripts/pack-swiftpm.sh CatchTheFly|DuoProbe

set -euo pipefail

app="${1:?usage: scripts/pack-swiftpm.sh CatchTheFly|DuoProbe}"
case "$app" in
  CatchTheFly) with_flycore=1 ;;
  DuoProbe)    with_flycore=0 ;;
  *) echo "Unknown app: $app (expected CatchTheFly or DuoProbe)" >&2; exit 1 ;;
esac

repo="$(cd "$(dirname "$0")/.." && pwd)"
out="$repo/build/swiftpm"
proj="$out/$app.swiftpm"

[ -f "$repo/ipad/$app/Package.swift" ] || { echo "Missing ipad/$app/Package.swift" >&2; exit 1; }
[ -d "$repo/apps/$app" ] || { echo "Missing apps/$app" >&2; exit 1; }

rm -rf "$proj" "$proj.zip"
mkdir -p "$proj/App"
cp "$repo/ipad/$app/Package.swift" "$proj/Package.swift"

# App sources, keeping their subfolders.
(cd "$repo/apps/$app" && find . -type f \
    ! -name '*.md' ! -name '.DS_Store' ! -name '*.orig' ! -name 'Package.swift' -print) |
  while IFS= read -r f; do
    mkdir -p "$proj/App/$(dirname "$f")"
    cp "$repo/apps/$app/$f" "$proj/App/$f"
  done

if [ "$with_flycore" = 1 ]; then
  mkdir -p "$proj/FlyCore"
  cp "$repo"/FlyCore/Sources/FlyCore/*.swift "$proj/FlyCore/"
fi

count=$(find "$proj" -name '*.swift' ! -name 'Package.swift' | wc -l | tr -d ' ')
(cd "$out" && rm -f "$app.swiftpm.zip" && zip -qrX "$app.swiftpm.zip" "$app.swiftpm")
echo "Packed $app.swiftpm: $count Swift files -> build/swiftpm/$app.swiftpm.zip"
