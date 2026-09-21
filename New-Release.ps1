<#
.SYNOPSIS
Cut a new release of Sync-D365FONuGet: bump version, rebuild EXE, zip, and publish to GitHub.

.DESCRIPTION
Maintainer-only helper. It:
  1. Updates the version in Sync-D365FONuGet.ps1 (both the .NOTES line and $script:CurrentVersion).
  2. Rebuilds Sync-D365FONuGet.exe with ps2exe.
  3. Builds Sync-D365FONuGet.zip (exe + ps1 + bat + README + LICENSE).
  4. Commits the version bump (and pushes with -Push).
  5. Creates the GitHub release vX.Y.Z with the zip, exe and ps1 attached.

Requires: ps2exe module and the GitHub CLI (gh), authenticated as the repo owner.

.EXAMPLE
    .\New-Release.ps1 -Version 1.0.1 -Push
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string] $Version,

    # Also push the version-bump commit to origin/main before creating the release.
    [switch] $Push
)

$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

$ps1  = Join-Path $PSScriptRoot 'Sync-D365FONuGet.ps1'
$exe  = Join-Path $PSScriptRoot 'Sync-D365FONuGet.exe'
$zip  = Join-Path $PSScriptRoot 'Sync-D365FONuGet.zip'
$tag  = "v$Version"

# --- Prerequisites -----------------------------------------------------------
if (-not (Get-Module -ListAvailable -Name ps2exe)) { throw 'ps2exe module not found. Install-Module ps2exe -Scope CurrentUser' }
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'GitHub CLI (gh) not found.' }

# --- 1. Bump version in the script -------------------------------------------
Write-Host "Setting version to $Version ..." -ForegroundColor Cyan
$src = Get-Content -LiteralPath $ps1 -Raw
$src = $src -replace "(?m)^(\s*Version\s*:\s*)[\d.]+", "`${1}$Version"
$src = $src -replace "(\`$script:CurrentVersion\s*=\s*')[\d.]+(')", "`${1}$Version`${2}"
Set-Content -LiteralPath $ps1 -Value $src -Encoding UTF8 -NoNewline

# Sanity check the file still parses
$errs = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($ps1, [ref]$null, [ref]$errs)
if ($errs) { throw "Script has parse errors after version bump: $($errs[0].Message)" }

# --- 2. Rebuild the EXE ------------------------------------------------------
Write-Host 'Building EXE ...' -ForegroundColor Cyan
Import-Module ps2exe
Invoke-ps2exe -inputFile $ps1 -outputFile $exe `
    -title 'D365 F&O NuGet Sync' -product 'D365 F&O NuGet Sync' `
    -company 'Vinod Kumar K J' -copyright "Copyright (c) $(Get-Date -Format yyyy) Vinod Kumar K J. MIT License." `
    -version "$Version.0" | Out-Null
if (-not (Test-Path $exe) -or (Get-Item $exe).Length -lt 20KB) { throw 'EXE build failed or too small.' }

# --- 3. Build the zip --------------------------------------------------------
Write-Host 'Building zip ...' -ForegroundColor Cyan
$stage = Join-Path $env:TEMP "d365sync-rel-$Version"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null
Copy-Item $exe, $ps1, (Join-Path $PSScriptRoot 'Sync-D365FONuGet.bat'), (Join-Path $PSScriptRoot 'README.md'), (Join-Path $PSScriptRoot 'LICENSE') $stage
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -Force

# --- 4. Commit the bump ------------------------------------------------------
git add Sync-D365FONuGet.ps1
git commit -m "$tag" | Out-Null
if ($Push) { git push origin main }

# --- 5. Create the GitHub release --------------------------------------------
Write-Host "Creating release $tag ..." -ForegroundColor Cyan
# Use the matching CHANGELOG.md section as the release notes (keeps them in sync).
$notes = "Release $tag"
$clPath = Join-Path $PSScriptRoot 'CHANGELOG.md'
if (Test-Path $clPath) {
    $cl = Get-Content $clPath -Raw
    $m = [regex]::Match($cl, "(?ms)^##\s*\[?$([regex]::Escape($Version))\]?.*?(?=^\s*##\s|\z)")
    if ($m.Success) { $notes = $m.Value.Trim() }
}
gh release create $tag --target main --title "$tag" --notes $notes $zip $exe $ps1

Write-Host "Done: https://github.com/vjanardhana12/d365fo-nuget-sync/releases/tag/$tag" -ForegroundColor Green
