<#
.SYNOPSIS
  Copies an app's sources (plus FlyCore) into its Swift Playgrounds project in iCloud Drive.

.DESCRIPTION
  Playgrounds app projects compile every .swift file inside the .swiftpm folder, so the
  script puts our files in two managed subfolders:

    <Project>.swiftpm/FlyCore/   copies of FlyCore/Sources/FlyCore/*.swift
    <Project>.swiftpm/App/       copies of apps/<App>/**/*.swift (and resources)

  It records what it placed in <Project>.swiftpm/.ctf-sync-manifest.txt. On the next run it
  only removes files listed there, so it never deletes anything it didn't put there. It never
  touches Package.swift.

  The Playgrounds template's own MyApp.swift and ContentView.swift clash with ours (two @main
  entry points). Pass -AdoptTemplate on the first sync: the script then renames them to
  *.swift.orig (Playgrounds ignores those) instead of leaving them in place.

.EXAMPLE
  .\scripts\to-ipad.ps1 -App DuoProbe -AdoptTemplate
  .\scripts\to-ipad.ps1 -App CatchTheFly -WhatIf
  .\scripts\to-ipad.ps1 -App DuoProbe -Project "D:\iCloudDrive\Playgrounds\DuoProbe.swiftpm"
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('DuoProbe', 'CatchTheFly')]
    [string]$App,

    # Path to the .swiftpm folder. Defaults to iCloud Drive\Playgrounds\<App>.swiftpm.
    [string]$Project,

    [switch]$AdoptTemplate,

    # Skip FlyCore (DuoProbe doesn't need it).
    [switch]$NoFlyCore
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

if (-not $Project) {
    $candidates = @()
    if ($env:USERPROFILE) {
        $candidates += Join-Path $env:USERPROFILE "iCloudDrive\Playgrounds\$App.swiftpm"
        $candidates += Join-Path $env:USERPROFILE "iCloudDrive\iCloud~com~apple~Playgrounds\Documents\$App.swiftpm"
    }
    if ($env:HOME) {
        $candidates += Join-Path $env:HOME "iCloudDrive/Playgrounds/$App.swiftpm"
    }
    $Project = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $Project) {
        throw "Couldn't find $App.swiftpm. Looked in:`n  $($candidates -join "`n  ")`nPass -Project <path to the .swiftpm folder>."
    }
}

if (-not (Test-Path -LiteralPath (Join-Path $Project 'Package.swift'))) {
    throw "$Project doesn't contain a Package.swift, so it doesn't look like a Playgrounds app project."
}

$manifestPath = Join-Path $Project '.ctf-sync-manifest.txt'
$oldManaged = @()
if (Test-Path -LiteralPath $manifestPath) {
    $oldManaged = @(Get-Content -LiteralPath $manifestPath | Where-Object { $_.Trim() -ne '' })
}

# Build the list of (source, relative destination) pairs.
$plan = @()
if (-not $NoFlyCore -and $App -ne 'DuoProbe') {
    $flyCoreDir = Join-Path $repo 'FlyCore/Sources/FlyCore'
    Get-ChildItem -LiteralPath $flyCoreDir -Filter '*.swift' -File | ForEach-Object {
        $plan += [pscustomobject]@{ Source = $_.FullName; Rel = "FlyCore/$($_.Name)" }
    }
}
$appDir = Join-Path $repo "apps/$App"
$appRoot = (Resolve-Path -LiteralPath $appDir).Path
Get-ChildItem -LiteralPath $appDir -Recurse -File |
    Where-Object { $_.Name -notmatch '^(README|NOTES).*\.md$' -and $_.Name -ne '.DS_Store' } |
    ForEach-Object {
        $rel = $_.FullName.Substring($appRoot.Length).TrimStart('\', '/') -replace '\\', '/'
        $plan += [pscustomobject]@{ Source = $_.FullName; Rel = "App/$rel" }
    }

if ($plan.Count -eq 0) { throw "Nothing to copy from $appDir." }

# Refuse to overwrite files we don't manage.
foreach ($item in $plan) {
    $dest = Join-Path $Project $item.Rel
    if ((Test-Path -LiteralPath $dest) -and ($oldManaged -notcontains $item.Rel)) {
        throw "$($item.Rel) already exists in the project and wasn't put there by this script. Move it away and re-run."
    }
}

# Deal with the template's entry point files.
foreach ($name in @('MyApp.swift', 'ContentView.swift')) {
    $path = Join-Path $Project $name
    if (Test-Path -LiteralPath $path) {
        if ($AdoptTemplate) {
            if ($PSCmdlet.ShouldProcess($name, 'Rename to .swift.orig')) {
                Move-Item -LiteralPath $path -Destination "$path.orig" -Force
                Write-Host "Renamed template $name to $name.orig"
            }
        } else {
            Write-Warning "$name from the Playgrounds template is still in the project and will clash with our @main. Re-run with -AdoptTemplate, or delete it in Playgrounds."
        }
    }
}

# Remove files we placed last time that are no longer in the plan.
$newRels = $plan | ForEach-Object { $_.Rel }
foreach ($rel in $oldManaged) {
    if ($newRels -notcontains $rel) {
        $path = Join-Path $Project $rel
        if ((Test-Path -LiteralPath $path) -and $PSCmdlet.ShouldProcess($rel, 'Remove stale managed file')) {
            Remove-Item -LiteralPath $path -Force
            Write-Host "Removed $rel"
        }
    }
}

# Copy.
$copied = 0
foreach ($item in $plan) {
    $dest = Join-Path $Project $item.Rel
    $destDir = Split-Path -Parent $dest
    if ($PSCmdlet.ShouldProcess($item.Rel, 'Copy')) {
        if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        Copy-Item -LiteralPath $item.Source -Destination $dest -Force
        $copied++
    }
}

if (-not $WhatIfPreference) {
    $newRels | Sort-Object | Set-Content -LiteralPath $manifestPath -Encoding utf8
}

Write-Host ""
Write-Host "Synced $copied file(s) into $Project"
Write-Host "On the iPad: wait for iCloud to finish, then close and reopen $App in Swift Playgrounds."
