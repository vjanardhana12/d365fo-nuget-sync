# ─────────────────────────────────────────────────────────────────────────────
# Copyright (c) 2026 Vinod Kumar K J. Released under the MIT License.
# Contact: github.com/vjanardhana12
# ─────────────────────────────────────────────────────────────────────────────

<#
.SYNOPSIS
    One-click sync of D365 F&O NuGet packages from a local folder to an
    Azure DevOps Artifacts feed. Skips packages that are already up-to-date.

.DESCRIPTION
    Workflow:
      1. Reads/prompts ADO feed config (URL, name, email; PAT every run).
    2. Queries the ADO feed for current versions of the core D365 F&O package set (currently 5).
      3. Reads versions from any *.nupkg files placed next to this script.
      4. Shows a table: package | InFeed | Local | Action (SKIP / PUSH / MISSING).
      5. If anything is MISSING, opens LCS Shared Asset Library in your browser
         and waits for you to drop the .nupkg files in this folder.
      6. Pushes only what's needed.
      7. Re-verifies the feed and reports.

    No LCS API / AAD app required. Works for any user with LCS browser access.

.PARAMETER FeedUrl
    Azure DevOps Artifacts NuGet v3 feed URL. Prompted if omitted.

.PARAMETER FeedName
    Short label for the feed (used internally by NuGet). Prompted if omitted.

.PARAMETER Email
    Your Azure DevOps login email. Prompted if omitted.

.PARAMETER Pat
    ADO Personal Access Token with 'Packaging (Read & Write)' scope.
    Prompted via SecureString if omitted. Can also be set via $env:ADO_PAT.

.PARAMETER Force
    Re-push packages even if the same version is already in the feed.

.PARAMETER NonInteractive
    Fail instead of prompting. Useful for CI.

.EXAMPLE
    .\Sync-D365FONuGet.ps1
    Interactive run. Uses saved config if present.

.EXAMPLE
    .\Sync-D365FONuGet.ps1 -FeedUrl 'https://pkgs.dev.azure.com/myorg/_packaging/MyFeed/nuget/v3/index.json' -FeedName MyFeed -Email me@x.com
    Non-interactive config; will still prompt for PAT.

.NOTES
    Author       : Vinod Kumar K J
    Version      : 1.0.1
    Works on     : Windows PowerShell 5.1 and PowerShell 7+
    Auto-update  : Checks GitHub on startup; prompts user if new version available
#>

[CmdletBinding()]
param(
    [string]   $FeedUrl,
    [string]   $FeedName,
    [string]   $Email,
    [string]   $Pat,
    [string]   $PackageFolder,
    [int]      $MaxParallel = 3,
    [switch]   $Force,
    [switch]   $NonInteractive
)

$ErrorActionPreference = 'Stop'

# =============================================================================
# Constants — core D365 F&O NuGet package IDs we manage (currently 5)
# =============================================================================
$script:KnownPackages = @(
    'Microsoft.Dynamics.AX.Platform.DevALM.BuildXpp',
    'Microsoft.Dynamics.AX.Platform.CompilerPackage',
    'Microsoft.Dynamics.AX.Application1.DevALM.BuildXpp',
    'Microsoft.Dynamics.AX.Application2.DevALM.BuildXpp',
    'Microsoft.Dynamics.AX.ApplicationSuite.DevALM.BuildXpp'
)
$script:LcsAssetLibraryUrl = 'https://lcs.dynamics.com/V2/SharedAssetLibrary'
# $PSScriptRoot is empty when running as compiled EXE — fall back to EXE/script location
if ($PSScriptRoot) {
    $script:ScriptDir = $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    $script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    $script:ScriptDir = [System.IO.Path]::GetDirectoryName([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
}
$script:AppDataDir  = Join-Path $env:LOCALAPPDATA 'd365fo-nuget-sync'
if (-not (Test-Path $script:AppDataDir)) { New-Item -ItemType Directory -Path $script:AppDataDir -Force | Out-Null }
$script:ConfigFile  = Join-Path $script:AppDataDir '.push-config'
# Migrate legacy config that lived next to the script
if ($script:ScriptDir) {
    $legacyConfig = Join-Path $script:ScriptDir '.push-config'
    if ((Test-Path $legacyConfig) -and -not (Test-Path $script:ConfigFile)) {
        try { Move-Item $legacyConfig $script:ConfigFile -Force } catch {}
    }
}
$script:NuGetExeDir = Join-Path $env:LOCALAPPDATA 'd365fo-nuget-push-tool'
$script:NuGetExe    = Join-Path $NuGetExeDir 'nuget.exe'

# Self-update check
$script:CurrentVersion = '1.1.2'
$script:UpdateRepo     = 'vjanardhana12/d365fo-nuget-sync'

# Keep the console window open on unhandled errors when running as a compiled EXE.
# Without this, a terminating exception (e.g. bad PAT, no network) causes the
# window to close instantly and the user never sees the error message.
trap {
    try {
        Write-Host ''
        Write-Host ('   [ERR]  ' + $_.Exception.Message) -ForegroundColor Red
        if ($_.InvocationInfo -and $_.InvocationInfo.PositionMessage) {
            Write-Host ('          ' + $_.InvocationInfo.PositionMessage.Trim()) -ForegroundColor DarkRed
        }
    } catch { }
    if (-not $NonInteractive -and [Environment]::UserInteractive) {
        try {
            Write-Host ''
            Write-Host '   Press any key to exit . . .' -ForegroundColor DarkGray
            $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        } catch { }
    }
    exit 1
}

# Where we look for .nupkg files. Defaults to script folder. -PackageFolder overrides.
if ($PackageFolder) {
    if (-not (Test-Path $PackageFolder)) { throw "PackageFolder not found: $PackageFolder" }
    $script:PkgFolder = (Resolve-Path $PackageFolder).Path
} else {
    $script:PkgFolder = $script:ScriptDir
}

# =============================================================================
# UI Helpers — boxed sections, status icons, coloured table
# =============================================================================
$script:UiWidth = 72
$script:TotalSteps = 5    # default — auto-bumps to 6 if Missing-packages step is needed
$script:CurStep   = 0

# Force UTF-8 on the console so box-drawing chars render. Detect if we can.
$script:UseUnicode = $true
try {
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    $OutputEncoding           = [Text.Encoding]::UTF8
    # cmd.exe code page → 65001 (UTF-8) so legacy host doesn't mangle bytes
    if ($env:OS -eq 'Windows_NT') { & chcp.com 65001 *>$null }
} catch {
    $script:UseUnicode = $false
}
$script:Dash = if ($script:UseUnicode) { [char]0x2500 } else { '-' }

function Write-Banner {
    $line = ('=' * $script:UiWidth)
    Write-Host ''
    Write-Host $line -ForegroundColor DarkCyan
    Write-Host '   D365 F&O NuGet Sync' -ForegroundColor Cyan
    Write-Host '   One-click sync from LCS to Azure DevOps Artifacts feed' -ForegroundColor DarkGray
    Write-Host ('   Vinod Kumar K J  ' + [char]0x00B7 + '  D365 F&O ALM & DevOps') -ForegroundColor DarkGray
    Write-Host $line -ForegroundColor DarkCyan
}

function Test-ForUpdate {
    # Interactive self-update check. Prompts user if update available. Never blocks if offline.
    try {
        $api = "https://api.github.com/repos/$($script:UpdateRepo)/releases/latest"
        $resp = Invoke-RestMethod -Uri $api -TimeoutSec 4 -Headers @{ 'User-Agent' = 'd365fo-nuget-sync' } -ErrorAction Stop
        $latest = ($resp.tag_name -replace '^v','').Trim()
        if ([string]::IsNullOrWhiteSpace($latest)) { return }
        try { $latestVer = [version]$latest } catch { return }
        $currentVer = [version]$script:CurrentVersion
        if ($latestVer -gt $currentVer) {
            Write-Host ''
            Write-Host "   ┌─────────────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
            Write-Host "   │ UPDATE AVAILABLE: v$latest (you have v$($script:CurrentVersion))" -ForegroundColor Yellow
            Write-Host "   │ Release: $($resp.html_url)" -ForegroundColor DarkGray
            Write-Host "   └─────────────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
            
            if (-not $NonInteractive -and [Environment]::UserInteractive) {
                $response = Read-Host -Prompt "   Download and update now? (Y/n)"
                if ($response -ne 'n' -and $response -ne 'N') {
                    Invoke-UpdateSelf -LatestVersion $latest -ReleaseUrl $resp.html_url -Assets $resp.assets
                }
            }
        }
    } catch {
        # Offline / rate-limited / repo not found - silently ignore
    }
}

function Invoke-UpdateSelf {
    # Download latest EXE from GitHub releases and replace current one
    param([string]$LatestVersion, [string]$ReleaseUrl, [object[]]$Assets)
    
    try {
        # Only works when running as compiled EXE (not as script)
        if (-not $PSScriptRoot -and $MyInvocation.MyCommand.Path) {
            $exePath = $MyInvocation.MyCommand.Path
        } elseif (-not $PSScriptRoot) {
            $exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        } else {
            # Running as .ps1 script, not EXE - skip update
            Write-Warn2 'Running as script; auto-update only works with compiled EXE.'
            return
        }
        
        $exeName = [System.IO.Path]::GetFileName($exePath)
        
        # Prefer the EXE asset's actual download URL from the release metadata.
        # Falls back to the conventional path if assets weren't passed in.
        $downloadUrl = $null
        if ($Assets) {
            $exeAsset = $Assets | Where-Object { $_.name -ieq $exeName } | Select-Object -First 1
            if ($exeAsset) { $downloadUrl = $exeAsset.browser_download_url }
        }
        if (-not $downloadUrl) {
            # No EXE asset on this release - can't auto-update. Tell the user and continue.
            Write-Host ''
            Write-Warn2 "Release v$LatestVersion does not include $exeName as an asset."
            Write-Info  "Download manually from: $ReleaseUrl"
            Write-Info  'Continuing with the current version...'
            return
        }
        
        Write-Host ''
        Write-Info "Downloading v$LatestVersion from GitHub..."
        
        # Download to temp file first
        $tempExe = Join-Path $env:TEMP "Sync-D365FONuGet-$LatestVersion.exe"
        try {
            $oldProgress = $ProgressPreference
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $downloadUrl -OutFile $tempExe -UseBasicParsing -ErrorAction Stop
        } finally {
            $ProgressPreference = $oldProgress
        }
        
        if (-not (Test-Path $tempExe) -or (Get-Item $tempExe).Length -lt 1024) {
            Write-Err 'Download failed or file is empty'
            try { Remove-Item $tempExe -Force -ErrorAction SilentlyContinue } catch { }
            return
        }
        
        Write-OK "Downloaded: $tempExe"
        
        # Backup current EXE
        $backupExe = "$exePath.backup"
        if (Test-Path $exePath) {
            Copy-Item -Path $exePath -Destination $backupExe -Force
            Write-Info "Backed up current version to: $backupExe"
        }
        
        # Replace with new EXE
        Copy-Item -Path $tempExe -Destination $exePath -Force
        Write-OK "Updated to v$LatestVersion"
        
        # Clean up temp file
        try { Remove-Item $tempExe -Force } catch { }
        
        Write-Host ''
        Write-Info 'Restarting with new version...'
        Start-Sleep -Milliseconds 800
        
        # Re-invoke with the new EXE
        & $exePath @PSBoundParameters
        exit 0
        
    } catch {
        Write-Err "Update failed: $($_.Exception.Message)"
    }
}

function Write-Step {
    param([string]$Title)
    $script:CurStep++
    $tag = "[ $($script:CurStep)/$($script:TotalSteps) ]"
    Write-Host ''
    Write-Host ("$tag $Title") -ForegroundColor Cyan
    Write-Host (([string]$script:Dash) * $script:UiWidth) -ForegroundColor DarkGray
}

function Write-OK    { param([string]$msg) Write-Host "   [OK]   $msg" -ForegroundColor Green }
function Write-Warn2 { param([string]$msg) Write-Host "   [WARN] $msg" -ForegroundColor Yellow }
function Write-Err   { param([string]$msg) Write-Host "   [ERR]  $msg" -ForegroundColor Red }
function Write-Info  { param([string]$msg) Write-Host "   $msg" -ForegroundColor DarkGray }

function Write-Field { param([string]$Label,[string]$Value)
    Write-Host ("   {0,-12} : " -f $Label) -ForegroundColor DarkGray -NoNewline
    Write-Host $Value -ForegroundColor White
}

function Write-CompareTable {
    param([object[]]$Rows)
    $w1 = 38; $w2 = 14; $w3 = 14; $w4 = 22
    $d  = [string]$script:Dash
    $sep = ('   ' + ($d * $w1) + '  ' + ($d * $w2) + '  ' + ($d * $w3) + '  ' + ($d * $w4))
    Write-Host ('   ' + ('Package'.PadRight($w1)) + '  ' + ('In Feed'.PadRight($w2)) + '  ' + ('Local'.PadRight($w3)) + '  ' + ('Action'.PadRight($w4))) -ForegroundColor White
    Write-Host $sep -ForegroundColor DarkGray
    foreach ($r in $Rows) {
        $colour = switch -Wildcard ($r.Action) {
            'PUSH*'  { 'Yellow';   break }
            'SKIP*'  { 'DarkGray'; break }
            'MISSING'{ 'Red';      break }
            'HAVE*'  { 'Green';    break }
            default  { 'White' }
        }
        $line = '   ' + ($r.Package.PadRight($w1)) + '  ' + ($r.InFeed.PadRight($w2)) + '  ' + ($r.Local.PadRight($w3)) + '  ' + ($r.Action.PadRight($w4))
        Write-Host $line -ForegroundColor $colour
    }
}

function Write-Spinner {
    param([scriptblock]$Action,[string]$Message)
    if (-not $Host.UI.RawUI -or $NonInteractive) { return & $Action }
    $frames = @('|','/','-',[string][char]92)
    $job = Start-Job -ScriptBlock $Action
    $i = 0
    while ($job.State -eq 'Running') {
        Write-Host ("`r   {0} {1}   " -f $frames[$i % 4], $Message) -NoNewline -ForegroundColor DarkGray
        Start-Sleep -Milliseconds 120
        $i++
    }
    Write-Host ("`r" + (' ' * ($Message.Length + 8)) + "`r") -NoNewline
    $result = Receive-Job $job -ErrorAction SilentlyContinue
    Remove-Job $job -Force
    return $result
}

function Write-Summary {
    param([int]$Pushed,[int]$Skipped,[int]$Failed,[string]$FeedUrl)
    $line = ('=' * $script:UiWidth)
    $colour = if ($Failed -gt 0) { 'Red' } elseif ($Pushed -gt 0) { 'Green' } else { 'DarkGreen' }
    $title  = if ($Failed -gt 0) { 'COMPLETED WITH ERRORS' } elseif ($Pushed -gt 0) { 'SUCCESS' } else { 'NOTHING TO DO' }
    Write-Host ''
    Write-Host $line -ForegroundColor $colour
    Write-Host ("   $title") -ForegroundColor $colour
    Write-Host $line -ForegroundColor $colour
    Write-Field 'Pushed'  $Pushed
    Write-Field 'Skipped' $Skipped
    Write-Field 'Failed'  $Failed
    if ($FeedUrl) { Write-Field 'Feed' $FeedUrl }
    Write-Host $line -ForegroundColor $colour
}

function Read-Required {
    param([string]$Prompt, [string]$Pattern, [string]$ErrorText)
    if ($NonInteractive) { throw "Missing required value: $Prompt (NonInteractive mode)" }
    do {
        $val = Read-Host -Prompt "  $Prompt"
        $bad = [string]::IsNullOrWhiteSpace($val) -or ($Pattern -and $val -notmatch $Pattern)
        if ($bad) {
            $msg = if ($ErrorText) { $ErrorText } else { 'Invalid value, try again.' }
            Write-Err $msg
        }
    } while ($bad)
    return $val
}

function Get-NuGetExe {
    if (Test-Path $script:NuGetExe) { return $script:NuGetExe }
    Write-Info 'Downloading nuget.exe (one-time, ~6 MB)...'
    if (-not (Test-Path $script:NuGetExeDir)) { New-Item -ItemType Directory -Path $script:NuGetExeDir -Force | Out-Null }
    Invoke-WebRequest -Uri 'https://dist.nuget.org/win-x86-commandline/latest/nuget.exe' -OutFile $script:NuGetExe -UseBasicParsing
    return $script:NuGetExe
}

function Get-PackageVersionFromNupkg {
    param([string]$Path)
    # NuGet package = ZIP. .nuspec inside has <version>.
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry = $zip.Entries | Where-Object { $_.FullName -like '*.nuspec' } | Select-Object -First 1
        if (-not $entry) { return $null }
        $reader = New-Object System.IO.StreamReader($entry.Open())
        try { $xml = [xml]$reader.ReadToEnd() } finally { $reader.Dispose() }
        return @{
            Id      = $xml.package.metadata.id
            Version = $xml.package.metadata.version
        }
    } finally { $zip.Dispose() }
}

function Get-FeedPackageVersions {
    param([string]$FeedUrl, [string]$Email, [string]$Pat, [string[]]$PackageIds)

    # Resolve flatcontainer base URL from v3 service index
    $auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${Email}:${Pat}"))
    $headers = @{ Authorization = "Basic $auth"; Accept = 'application/json' }

    try {
        $svc = Invoke-RestMethod -Uri $FeedUrl -Headers $headers -ErrorAction Stop
    } catch {
        throw "Cannot reach feed at $FeedUrl. Check URL/PAT. Inner: $($_.Exception.Message)"
    }
    $flat = $svc.resources | Where-Object { $_.'@type' -like 'PackageBaseAddress/3.0.0*' } | Select-Object -First 1
    if (-not $flat) { throw "Feed does not advertise PackageBaseAddress (flatcontainer). Not a valid v3 NuGet feed." }
    $base = $flat.'@id'.TrimEnd('/')

    $result = @{}
    foreach ($id in $PackageIds) {
        $idLower = $id.ToLowerInvariant()
        $url     = "$base/$idLower/index.json"
        try {
            $resp = Invoke-RestMethod -Uri $url -Headers $headers -ErrorAction Stop
            # Pick highest version using [version] sort
            $versions = $resp.versions | ForEach-Object {
                try { [pscustomobject]@{ Raw = $_; Parsed = [version]$_ } } catch { $null }
            } | Where-Object { $_ } | Sort-Object Parsed -Descending
            $result[$id] = if ($versions) { $versions[0].Raw } else { $null }
        } catch {
            # 404 = package not in feed yet
            $result[$id] = $null
        }
    }
    return $result
}

# =============================================================================
# Banner
# =============================================================================
Write-Banner
Test-ForUpdate

# =============================================================================
# STEP 0 — Configuration
# =============================================================================
Write-Step 'Configuration'

$saved = $null
if (Test-Path $script:ConfigFile) {
    try { $saved = Get-Content $script:ConfigFile -Raw | ConvertFrom-Json } catch { $saved = $null }
}

if (-not $FeedUrl)  { $FeedUrl  = $saved.FeedSource }
if (-not $FeedName) { $FeedName = $saved.FeedName }
if (-not $Email)    { $Email    = $saved.Email }

if ($saved -and $FeedUrl -eq $saved.FeedSource -and -not $NonInteractive) {
    Write-Info 'Saved configuration found:'
    Write-Field 'Feed URL'  $saved.FeedSource
    Write-Field 'Feed Name' $saved.FeedName
    Write-Field 'Email'     $saved.Email
    Write-Host ''
    $reuse = Read-Host -Prompt '   Use saved configuration? (Y/n)'
    if ($reuse -eq 'n' -or $reuse -eq 'N') { $FeedUrl = ''; $FeedName = ''; $Email = '' }
}

if (-not $FeedUrl) {
    Write-Info ''
    Write-Info 'FORMAT : https://pkgs.dev.azure.com/{ORG}/_packaging/{FEED}/nuget/v3/index.json'
    $FeedUrl = Read-Required -Prompt 'ADO Feed URL' -Pattern 'pkgs\.dev\.azure\.com' -ErrorText 'Must be an ADO Artifacts v3 feed URL.'
}
# Auto-derive FeedName from URL: .../_packaging/{FeedName}/nuget/v3/index.json
if (-not $FeedName -and $FeedUrl -match '_packaging/([^/]+)/nuget/v3') {
    $derived = $Matches[1]
    Write-Info "Feed name (auto-detected from URL): $derived"
    if (-not $NonInteractive) {
        $confirm = Read-Host -Prompt '   Use this feed name? (Y/n)'
        if ($confirm -eq 'n' -or $confirm -eq 'N') {
            $FeedName = Read-Required -Prompt 'Feed Name (short label)'
        } else {
            $FeedName = $derived
        }
    } else {
        $FeedName = $derived
    }
}
if (-not $FeedName) { $FeedName = Read-Required -Prompt 'Feed Name (short label)' }
if (-not $Email)    { $Email    = Read-Required -Prompt 'Your ADO email' -Pattern '@' -ErrorText 'Must be an email.' }

# Save (without PAT)
@{ FeedSource = $FeedUrl; FeedName = $FeedName; Email = $Email } |
    ConvertTo-Json | Out-File $script:ConfigFile -Force -Encoding UTF8

# PAT — never saved
if (-not $Pat) { $Pat = $env:ADO_PAT }
if (-not $Pat) {
    if ($NonInteractive) { throw 'PAT required: pass -Pat or set $env:ADO_PAT.' }
    Write-Info ''
    Write-Info 'PAT scope required: Packaging (Read & Write)'
    Write-Info "Generate at: https://dev.azure.com/_usersSettings/tokens"
    $secure = Read-Host -Prompt '  Enter your ADO PAT' -AsSecureString
    $Pat = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
}

Write-OK 'Configuration ready.'

# =============================================================================
# STEP 1 — Inspect ADO feed
# =============================================================================
Write-Step 'Inspecting ADO feed'
Write-Host ("   Querying $FeedName ...") -ForegroundColor DarkGray -NoNewline
$sw = [Diagnostics.Stopwatch]::StartNew()
try {
    $feedVersions = Get-FeedPackageVersions -FeedUrl $FeedUrl -Email $Email -Pat $Pat -PackageIds $script:KnownPackages
} catch {
    Write-Host ("`r" + (' ' * 60) + "`r") -NoNewline
    Write-Host ''
    Write-Host '   [ERR]  Cannot read ADO feed.' -ForegroundColor Red
    Write-Host ('          ' + $_.Exception.Message) -ForegroundColor DarkRed
    Write-Host ''
    Write-Host '   Common causes:' -ForegroundColor Yellow
    Write-Host '     - PAT scope must be Packaging (Read & Write) (not Read-only)' -ForegroundColor DarkGray
    Write-Host '     - PAT expired or generated for a different ADO organization' -ForegroundColor DarkGray
    Write-Host '     - Saved email does not match the PAT owner' -ForegroundColor DarkGray
    Write-Host '     - Corporate proxy / firewall blocking pkgs.dev.azure.com' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host ('   Feed URL: ' + $FeedUrl) -ForegroundColor DarkGray
    Write-Host ('   Email   : ' + $Email)   -ForegroundColor DarkGray
    if (-not $NonInteractive -and [Environment]::UserInteractive) {
        try {
            Write-Host ''
            Write-Host '   Press any key to exit . . .' -ForegroundColor DarkGray
            $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        } catch { }
    }
    exit 1
}
$sw.Stop()
Write-Host ("`r" + (' ' * 60) + "`r") -NoNewline
$present = ($feedVersions.Values | Where-Object { $_ }).Count
Write-OK ("$present of $($script:KnownPackages.Count) D365FO packages already in feed  ({0:0.0}s)" -f $sw.Elapsed.TotalSeconds)

# =============================================================================
# STEP 2 — Inspect local .nupkg files
# =============================================================================
Write-Step 'Scanning local .nupkg files'
Write-Info "Folder: $script:PkgFolder"
$localPkgs = @{}
$nupkgs = Get-ChildItem -Path $script:PkgFolder -Filter '*.nupkg' -File -ErrorAction SilentlyContinue
foreach ($f in $nupkgs) {
    try {
        $info = Get-PackageVersionFromNupkg -Path $f.FullName
        if ($info -and $script:KnownPackages -contains $info.Id) {
            $localPkgs[$info.Id] = [pscustomobject]@{
                Path    = $f.FullName
                Name    = $f.Name
                Version = $info.Version
            }
        }
    } catch {
        Write-Warn2 "Could not read $($f.Name): $($_.Exception.Message)"
    }
}
if ($localPkgs.Count -eq 0) { Write-Info 'No D365FO .nupkg files found locally yet.' } else { Write-OK "$($localPkgs.Count) local D365FO package(s) discovered." }

# =============================================================================
# STEP 3 — Decide actions
# =============================================================================
Write-Step 'Comparison'

$rows  = @()
$toPush = @()
$missing = @()

foreach ($id in $script:KnownPackages) {
    $inFeed = $feedVersions[$id]
    $local  = $localPkgs[$id]
    $action = ''
    if (-not $local) {
        $action = if ($inFeed) { 'HAVE-IN-FEED' } else { 'MISSING' }
        if (-not $inFeed) { $missing += $id }
    } else {
        $cmp = if ($inFeed) {
            try { ([version]$local.Version).CompareTo([version]$inFeed) } catch { -1 }
        } else { 1 }
        if ($cmp -gt 0)        { $action = 'PUSH (newer)';  $toPush += $local }
        elseif ($cmp -eq 0)    { $action = if ($Force) { 'PUSH (-Force)' } else { 'SKIP (same)' }; if ($Force) { $toPush += $local } }
        else                   { $action = 'SKIP (feed has newer)' }
    }

    $rows += [pscustomobject]@{
        Package = $id.Replace('Microsoft.Dynamics.AX.','')
        InFeed  = if ($inFeed) { $inFeed } else { '<empty>' }
        Local   = if ($local)  { $local.Version } else { '<not found>' }
        Action  = $action
    }
}

Write-Host ''
Write-CompareTable -Rows $rows

# =============================================================================
# STEP 4 — Handle missing (open LCS, wait)
# =============================================================================
if ($missing.Count -gt 0) {
    $script:TotalSteps = 6
    Write-Step 'Missing packages'
    Write-Warn2 "$($missing.Count) package(s) need to be downloaded from LCS."
    $missing | ForEach-Object { Write-Host "        - $_" -ForegroundColor Yellow }
    Write-Info ''
    Write-Info "Current package folder: $script:PkgFolder"
    if (-not $NonInteractive) {
        Write-Host ''
        Write-Info 'What do you want to do?'
        Write-Info '  [1] I already have the .nupkg files somewhere - let me point to the folder'
        Write-Info '  [2] Open LCS Shared Asset Library in browser so I can download them now'
        Write-Info '  [3] I have already dropped the files in the current folder - just rescan'
        $choice = Read-Host -Prompt '   Choice (1/2/3)'
        switch ($choice.Trim()) {
            '2' {
                Write-Info "Opening LCS: $script:LcsAssetLibraryUrl"
                Start-Process $script:LcsAssetLibraryUrl
                Write-Info ("Sign in with your LCS account, click on each package, and download all required .nupkg files (currently {0})." -f $script:KnownPackages.Count)
            }
            default { } # 1 or 3 or anything else - just go straight to the loop
        }
        # Loop until user confirms files are present (or aborts)
        while ($true) {
            Write-Host ''
            Write-Info "Current scan folder: $script:PkgFolder"
            Write-Info 'Enter one of:'
            Write-Info '  - press Enter           : scan the current folder'
            Write-Info '  - paste a folder path   : switch to that folder and scan'
            Write-Info '    (shorthand: "Downloads" = your user Downloads folder)'
            Write-Info '  - "q" to abort'
            $answer = Read-Host -Prompt '   >'
            $answer = $answer.Trim().Trim('"').Trim("'")
            if ($answer -eq 'q' -or $answer -eq 'Q') { Write-Warn2 'Aborted by user.'; return }
            if ($answer) {
                # Resolve shorthand: "Downloads" -> $env:USERPROFILE\Downloads
                $candidates = @($answer)
                if ($answer -notmatch '[\\/:]') { $candidates += (Join-Path $env:USERPROFILE $answer) }
                $resolved = $null
                foreach ($c in $candidates) { if (Test-Path $c) { $resolved = (Resolve-Path $c).Path; break } }
                if ($resolved) {
                    $script:PkgFolder = $resolved
                    Write-OK "Folder set to: $script:PkgFolder"
                } else {
                    Write-Warn2 "Folder not found: $answer (keeping $script:PkgFolder)"
                    continue
                }
            }

            # Re-scan
            Write-Info "Scanning: $script:PkgFolder"
            $newPkgs = Get-ChildItem -Path $script:PkgFolder -Filter '*.nupkg' -File -ErrorAction SilentlyContinue
            $found = @()
            foreach ($f in $newPkgs) {
                try {
                    $info = Get-PackageVersionFromNupkg -Path $f.FullName
                    if ($info -and ($missing -contains $info.Id)) {
                        $local = [pscustomobject]@{ Path = $f.FullName; Name = $f.Name; Version = $info.Version }
                        $found += $local
                        if (-not $localPkgs.ContainsKey($info.Id)) {
                            $toPush += $local
                            $localPkgs[$info.Id] = $local
                        }
                    }
                } catch { }
            }
            if ($found.Count -gt 0) {
                $found | ForEach-Object { Write-OK "Found: $($_.Name)" }
                # Recompute remaining
                $stillMissing = $missing | Where-Object { -not $localPkgs.ContainsKey($_) }
                if ($stillMissing.Count -eq 0) { break }
                Write-Warn2 "Still missing $($stillMissing.Count): $($stillMissing -join ', ')"
            } else {
                Write-Warn2 "No matching .nupkg files found in $script:PkgFolder"
            }
        }
    } else {
        throw 'Packages missing in NonInteractive mode. Aborting.'
    }
}

# =============================================================================
# STEP 5 — Push
# =============================================================================
$skipCount = ($rows | Where-Object { $_.Action -like 'SKIP*' -or $_.Action -eq 'HAVE-IN-FEED' }).Count

if ($toPush.Count -eq 0) {
    Write-Summary -Pushed 0 -Skipped $skipCount -Failed 0 -FeedUrl $FeedUrl
    return
}

Write-Step "Push to $FeedName"
Write-Info "$($toPush.Count) package(s) queued."
if (-not $NonInteractive) {
    $confirm = Read-Host -Prompt '   Continue with push? (Y/n)'
    if ($confirm -eq 'n' -or $confirm -eq 'N') { Write-Warn2 'Aborted by user.'; return }
}

$nuget = Get-NuGetExe
$tempConfig = Join-Path $script:NuGetExeDir 'NuGet.Push.Config'
$xml = @"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <add key="$FeedName" value="$FeedUrl" />
  </packageSources>
  <packageSourceCredentials>
    <$FeedName>
      <add key="Username" value="$Email" />
      <add key="ClearTextPassword" value="$Pat" />
    </$FeedName>
  </packageSourceCredentials>
</configuration>
"@
$xml | Out-File $tempConfig -Encoding UTF8 -Force

$succeeded = @(); $failed = @()
$idx = 0
try {
    # ---- Parallel push scheduler -------------------------------------------------
    $effectiveParallel = [Math]::Min($MaxParallel, $toPush.Count)
    if ($effectiveParallel -lt 1) { $effectiveParallel = 1 }
    Write-Info ("Concurrency: $effectiveParallel parallel upload(s) (use -MaxParallel <N> to change)")
    $frames = '|','/','-','\'

    # Build queue of remaining packages
    $queue = New-Object System.Collections.Generic.Queue[object]
    foreach ($p in $toPush) { $queue.Enqueue($p) }

    if ($NonInteractive) {
        # ---- Non-interactive simple scheduler: one line per package, no spinner ----
        $running = @{}  # slot index -> @{ Job; Pkg; Stopwatch }
        function Start-Next-NI {
            param($SlotIdx)
            if ($queue.Count -eq 0) { return $false }
            $pkg = $queue.Dequeue()
            $sizeMB = [math]::Round((Get-Item $pkg.Path).Length / 1MB, 1)
            Write-Host ("   [..]   $($pkg.Name) ($sizeMB MB)  pushing...") -ForegroundColor DarkGray
            $job = Start-Job -ScriptBlock {
                param($nuget,$path,$src,$cfg)
                $o = & $nuget push $path -Source $src -ApiKey az -ConfigFile $cfg -Timeout 1800 -NonInteractive 2>&1 | Out-String
                [pscustomobject]@{ Output = $o; ExitCode = $LASTEXITCODE }
            } -ArgumentList $nuget, $pkg.Path, $FeedName, $tempConfig
            $running[$SlotIdx] = @{ Job = $job; Pkg = $pkg; Stopwatch = [Diagnostics.Stopwatch]::StartNew() }
            return $true
        }
        # Prime
        for ($s = 0; $s -lt $effectiveParallel; $s++) { [void](Start-Next-NI -SlotIdx $s) }
        # Drive
        while ($running.Count -gt 0) {
            $doneKeys = @()
            foreach ($k in @($running.Keys)) {
                $r = $running[$k]
                if ($r.Job.State -ne 'Running') {
                    $r.Stopwatch.Stop()
                    $result = Receive-Job $r.Job -ErrorAction SilentlyContinue
                    Remove-Job $r.Job -Force
                    $elapsed = '{0:mm\:ss}' -f $r.Stopwatch.Elapsed
                    $ok = ($result -and $result.ExitCode -eq 0)
                    if ($ok) {
                        $succeeded += $r.Pkg
                        Write-Host ("   [OK]   $($r.Pkg.Name) pushed in $elapsed") -ForegroundColor Green
                    } else {
                        $failed += $r.Pkg
                        Write-Host ("   [FAIL] $($r.Pkg.Name) after $elapsed") -ForegroundColor Red
                        if ($result -and $result.Output) {
                            $errLine = ($result.Output -split "`r?`n" | Where-Object { $_ -match 'Conflict|409|error|Error|fail' } | Select-Object -First 1)
                            if (-not $errLine) { $errLine = ($result.Output.Trim() -split "`r?`n")[-1] }
                            if ($errLine) { Write-Host ("          " + $errLine.Trim()) -ForegroundColor DarkRed }
                        }
                    }
                    $doneKeys += $k
                }
            }
            foreach ($k in $doneKeys) { $running.Remove($k); [void](Start-Next-NI -SlotIdx $k) }
            if ($running.Count -gt 0) { Start-Sleep -Milliseconds 500 }
        }
    } else {

    # Slot table — one entry per parallel slot
    $slots = @()
    for ($s = 0; $s -lt $effectiveParallel; $s++) {
        $slots += [pscustomobject]@{ Slot=$s; Job=$null; Pkg=$null; Stopwatch=$null; Frame=0 }
    }

    # Reserve console lines for the slot status (one per slot)
    for ($s = 0; $s -lt $slots.Count; $s++) { Write-Host '' }
    $baseRow = [Math]::Max(0, $Host.UI.RawUI.CursorPosition.Y - $slots.Count)

    function Update-SlotLine {
        param($Slot, $BaseRow)
        $line = if ($Slot.Pkg) {
            $f = $frames[$Slot.Frame % $frames.Count]
            $elapsed = if ($Slot.Stopwatch) { '{0:mm\:ss}' -f $Slot.Stopwatch.Elapsed } else { '00:00' }
            $sizeMB  = [math]::Round((Get-Item $Slot.Pkg.Path).Length / 1MB, 1)
            "      [slot $($Slot.Slot+1)] $f  $($Slot.Pkg.Name) ($sizeMB MB)  elapsed $elapsed"
        } else { "      [slot $($Slot.Slot+1)] (done - waiting for others)" }
        # Truncate to console width
        $w = $Host.UI.RawUI.WindowSize.Width - 1
        if ($line.Length -gt $w) { $line = $line.Substring(0, $w) }
        $line = $line.PadRight($w)
        try {
            $Host.UI.RawUI.CursorPosition = [Management.Automation.Host.Coordinates]::new(0, $BaseRow + $Slot.Slot)
            Write-Host $line -ForegroundColor DarkGray -NoNewline
        } catch { }
    }

    function Start-NextInSlot {
        param($Slot, [ref]$Idx, $Total)
        if ($queue.Count -eq 0) { return }
        $pkg = $queue.Dequeue()
        $Idx.Value++
        $Slot.Pkg = $pkg
        $Slot.Stopwatch = [Diagnostics.Stopwatch]::StartNew()
        $Slot.Frame = 0
        $Slot.Job = Start-Job -ScriptBlock {
            param($nuget,$path,$src,$cfg)
            # -Timeout 1800 = 30 min (default 300s = 5 min often too short for 300+ MB packages on slow links)
            $o = & $nuget push $path -Source $src -ApiKey az -ConfigFile $cfg -Timeout 1800 -NonInteractive 2>&1 | Out-String
            [pscustomobject]@{ Output = $o; ExitCode = $LASTEXITCODE }
        } -ArgumentList $nuget, $pkg.Path, $FeedName, $tempConfig
    }

    # Prime all slots
    foreach ($slot in $slots) { Start-NextInSlot -Slot $slot -Idx ([ref]$idx) -Total $toPush.Count }

    # Drive loop
    while ($true) {
        $anyRunning = $false
        foreach ($slot in $slots) {
            if ($slot.Job) {
                $anyRunning = $true
                $slot.Frame++
                if ($slot.Job.State -ne 'Running') {
                    # Completed
                    $slot.Stopwatch.Stop()
                    $result = Receive-Job $slot.Job -ErrorAction SilentlyContinue
                    Remove-Job $slot.Job -Force
                    $elapsed = '{0:mm\:ss}' -f $slot.Stopwatch.Elapsed
                    # Snapshot details before reset
                    $finPkg = $slot.Pkg
                    $finOk  = ($result -and $result.ExitCode -eq 0)
                    $finOut = if ($result) { $result.Output.Trim() } else { '' }
                    if ($finOk) { $succeeded += $finPkg } else { $failed += $finPkg }
                    # Reset slot first
                    $slot.Job = $null; $slot.Pkg = $null; $slot.Stopwatch = $null
                    # Pull next from queue (so the slot keeps moving while we print)
                    Start-NextInSlot -Slot $slot -Idx ([ref]$idx) -Total $toPush.Count

                    # Move cursor BELOW the live slot block, write final line, slot block scrolls down
                    try { $Host.UI.RawUI.CursorPosition = [Management.Automation.Host.Coordinates]::new(0, $baseRow + $slots.Count) } catch { }
                    if ($finOk) {
                        Write-Host ("   [OK]   $($finPkg.Name) pushed in $elapsed") -ForegroundColor Green
                    } else {
                        Write-Host ("   [FAIL] $($finPkg.Name) after $elapsed") -ForegroundColor Red
                        if ($finOut) { Write-Host ("          " + $finOut) -ForegroundColor DarkRed }
                    }
                    # Re-reserve the slot lines below by writing blank lines and adjusting baseRow
                    for ($s2 = 0; $s2 -lt $slots.Count; $s2++) { Write-Host '' }
                    $baseRow = [Math]::Max(0, $Host.UI.RawUI.CursorPosition.Y - $slots.Count)
                    if ($slot.Job) { $anyRunning = $true }
                }
            }
        }
        # Refresh all slot status lines
        foreach ($slot in $slots) { Update-SlotLine -Slot $slot -BaseRow $baseRow }
        if (-not $anyRunning) { break }
        Start-Sleep -Milliseconds 200
    }

    # Move cursor below slot block, clear lines
    try { $Host.UI.RawUI.CursorPosition = [Management.Automation.Host.Coordinates]::new(0, $baseRow + $slots.Count) } catch { }
    Write-Host ''
    } # end else (interactive scheduler)
} finally {
    if (Test-Path $tempConfig) { Remove-Item $tempConfig -Force }
    $Pat = $null
}

Write-Summary -Pushed $succeeded.Count -Skipped $skipCount -Failed $failed.Count -FeedUrl $FeedUrl

# Pause before exit when running interactively (especially as compiled EXE which closes the window otherwise)
if (-not $NonInteractive -and [Environment]::UserInteractive) {
    try {
        Write-Host ''
        Write-Host '   Press any key to exit . . .' -ForegroundColor DarkGray
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    } catch {
        # Host doesn't support ReadKey (e.g. piped/redirected) - skip pause
    }
}
if ($failed.Count -gt 0) { exit 1 }
