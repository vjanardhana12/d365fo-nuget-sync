<#
.SYNOPSIS
Installation & first-run setup helper for Sync-D365FONuGet tool

.DESCRIPTION
Guides users through:
1. Downloading the latest release
2. Verifying integrity
3. Setting up ADO configuration
4. Running first sync

.EXAMPLE
.\Setup-D365FONuGetSync.ps1

.NOTES
Requires: PowerShell 5.1+ on Windows, 7.0+ on Linux/macOS
#>

#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$VerbosePreference = 'Continue'

# Constants
$ToolRepo = 'vjanardhana12/d365fo-nuget-sync'
$ToolName = 'Sync-D365FONuGet'
$GitHubAPI = "https://api.github.com/repos/$ToolRepo/releases/latest"

function Write-Header {
    param([string]$Text)
    Write-Host "`n" -NoNewline
    Write-Host ('=' * 70) -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ('=' * 70) -ForegroundColor Cyan
    Write-Host ''
}

function Write-Step {
    param([string]$Text, [int]$Number)
    Write-Host "[$Number] " -NoNewline -ForegroundColor Yellow
    Write-Host $Text -ForegroundColor White
}

function Write-Info {
    param([string]$Text)
    Write-Host "    ℹ  $Text" -ForegroundColor DarkGray
}

function Write-Success {
    param([string]$Text)
    Write-Host "    ✓  $Text" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Text)
    Write-Host "    ⚠  $Text" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Text)
    Write-Host "    ✗  $Text" -ForegroundColor Red
}

function Get-LatestRelease {
    Write-Step "Checking for latest release..." 1
    
    try {
        $response = Invoke-RestMethod -Uri $GitHubAPI `
            -TimeoutSec 10 `
            -Headers @{ 'User-Agent' = 'PowerShell' } `
            -ErrorAction Stop
        
        $version = $response.tag_name
        $releaseUrl = $response.html_url
        $assets = $response.assets
        
        Write-Success "Found release: $version"
        Write-Info "Release URL: $releaseUrl"
        
        return @{
            Version = $version
            Url = $releaseUrl
            Assets = $assets
        }
    }
    catch {
        Write-Error "Failed to fetch latest release: $_"
        Write-Info "Visit https://github.com/$ToolRepo/releases manually"
        return $null
    }
}

function Show-DownloadOptions {
    param($Release)
    
    Write-Step "Available downloads:" 2
    
    Write-Host "`n  Choose your preferred option:`n" -ForegroundColor White
    Write-Host "  1. Compiled EXE (Recommended)" -ForegroundColor Cyan
    Write-Host "     • Auto-update support" -ForegroundColor DarkGray
    Write-Host "     • Double-click to run" -ForegroundColor DarkGray
    Write-Host "     • No PowerShell knowledge required" -ForegroundColor DarkGray
    
    Write-Host "`n  2. ZIP Distribution" -ForegroundColor Cyan
    Write-Host "     • Includes EXE + Script + License + README" -ForegroundColor DarkGray
    Write-Host "     • Easy to share with teams" -ForegroundColor DarkGray
    Write-Host "     • Portable (USB, network share)" -ForegroundColor DarkGray
    
    Write-Host "`n  3. PowerShell Script" -ForegroundColor Cyan
    Write-Host "     • Cross-platform (Linux/macOS with PS7+)" -ForegroundColor DarkGray
    Write-Host "     • Audit source code before running" -ForegroundColor DarkGray
    Write-Host "     • Manual update required" -ForegroundColor DarkGray
    
    Write-Host "`n  4. Open Release Page in Browser" -ForegroundColor Cyan
    Write-Host "     • Manual download and setup" -ForegroundColor DarkGray
    
    $choice = Read-Host "`n  Select option (1-4)"
    
    $exeAsset = $Release.Assets | Where-Object { $_.name -eq "$ToolName.exe" }
    $zipAsset = $Release.Assets | Where-Object { $_.name -match "\.zip$" } | Select-Object -First 1
    $psAsset = $Release.Assets | Where-Object { $_.name -eq "$ToolName.ps1" }
    
    switch ($choice) {
        "1" {
            if ($exeAsset) {
                return @{ Type = 'EXE'; Asset = $exeAsset }
            } else {
                Write-Error "EXE asset not found in release"
                return $null
            }
        }
        "2" {
            if ($zipAsset) {
                return @{ Type = 'ZIP'; Asset = $zipAsset }
            } else {
                Write-Error "ZIP asset not found in release"
                return $null
            }
        }
        "3" {
            if ($psAsset) {
                return @{ Type = 'PS1'; Asset = $psAsset }
            } else {
                Write-Error "PowerShell script asset not found in release"
                return $null
            }
        }
        "4" {
            Start-Process $Release.Url
            Write-Info "Opening browser... Please download manually and re-run setup."
            return 'MANUAL'
        }
        default {
            Write-Error "Invalid selection"
            return $null
        }
    }
}

function Get-InstallFolder {
    Write-Step "Choose installation folder:" 3
    
    $defaultFolder = if ($PSVersionTable.Platform -eq 'Unix') {
        "~/.local/bin"
    } else {
        [System.IO.Path]::Combine($env:USERPROFILE, "AppData", "Local", "d365fo-nuget-sync")
    }
    
    Write-Info "Default: $defaultFolder"
    $choice = Read-Host "  Use default? (Y/n)"
    
    if ($choice -eq 'n' -or $choice -eq 'N') {
        $folder = Read-Host "  Enter folder path"
        if (-not (Test-Path $folder)) {
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
            Write-Success "Created folder: $folder"
        }
        return $folder
    } else {
        if (-not (Test-Path $defaultFolder)) {
            New-Item -ItemType Directory -Path $defaultFolder -Force | Out-Null
        }
        Write-Success "Using: $defaultFolder"
        return $defaultFolder
    }
}

function Download-Asset {
    param([object]$Asset, [string]$DestinationFolder)
    
    Write-Step "Downloading $($Asset.name) ($([math]::Round($Asset.size / 1MB, 2))MB)..." 4
    
    $outputPath = Join-Path $DestinationFolder $Asset.name
    
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Asset.browser_download_url `
            -OutFile $outputPath `
            -TimeoutSec 300 `
            -ErrorAction Stop
        
        Write-Success "Downloaded to: $outputPath"
        return $outputPath
    }
    catch {
        Write-Error "Download failed: $_"
        return $null
    }
    finally {
        $ProgressPreference = 'Continue'
    }
}

function Verify-Download {
    param([string]$FilePath)
    
    if (-not (Test-Path $FilePath)) {
        Write-Error "File not found: $FilePath"
        return $false
    }
    
    $fileSize = (Get-Item $FilePath).Length
    if ($fileSize -lt 10KB) {
        Write-Error "File appears corrupted (too small: $fileSize bytes)"
        return $false
    }
    
    Write-Success "File verified ($([math]::Round($fileSize / 1KB, 2))KB)"
    return $true
}

function Add-ToPath {
    param([string]$Folder)
    
    $pathVar = [Environment]::GetEnvironmentVariable('Path', [EnvironmentVariableTarget]::User)
    
    if ($pathVar -notmatch [regex]::Escape($Folder)) {
        Write-Step "Add to PATH? (y/N):" 5
        $choice = Read-Host "  This allows running tool from anywhere"
        
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            [Environment]::SetEnvironmentVariable(
                'Path',
                "$pathVar;$Folder",
                [EnvironmentVariableTarget]::User
            )
            Write-Success "Added to PATH (restart terminal to take effect)"
        }
    }
}

function Show-FirstRunGuide {
    param([string]$ToolPath)
    
    Write-Header "First Run Configuration"
    
    Write-Host "When you run the tool, it will prompt for:" -ForegroundColor White
    Write-Host ""
    Write-Host "1. ADO Feed URL" -ForegroundColor Cyan
    Write-Host "   Example: https://pkgs.dev.azure.com/myorg/_packaging/MyFeed/nuget/v3/index.json" -ForegroundColor DarkGray
    Write-Host "   Find at: Azure DevOps → Artifacts → Feed Details → NuGet" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "2. Feed Name" -ForegroundColor Cyan
    Write-Host "   Example: MyFeed" -ForegroundColor DarkGray
    Write-Host "   Just a label for the tool" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "3. Email Address" -ForegroundColor Cyan
    Write-Host "   Your Azure DevOps login email" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "4. Personal Access Token (PAT)" -ForegroundColor Cyan
    Write-Host "   Create at: https://dev.azure.com/myorg/_usersSettings/tokens" -ForegroundColor DarkGray
    Write-Host "   Required Scope: ✓ Packaging (Read & Write)" -ForegroundColor DarkGray
    Write-Host ""
    
    Write-Step "Ready to run the tool:" 6
    
    if ($ToolPath -match '\.exe$') {
        Write-Host "  .\$([System.IO.Path]::GetFileName($ToolPath))" -ForegroundColor Green
    } else {
        Write-Host "  .\$([System.IO.Path]::GetFileName($ToolPath))" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Info "First run will guide you through the setup"
    Write-Info "Configuration is saved for future runs"
    Write-Info "Run with -NonInteractive flag for CI/CD pipelines"
}

function Start-Setup {
    try {
        Write-Header "D365 F&O NuGet Sync - Setup Wizard"
        
        Write-Host "This wizard will help you install and configure the tool.`n" -ForegroundColor White
        
        # Step 1: Get latest release
        $release = Get-LatestRelease
        if (-not $release) { return }
        
        # Step 2: Choose download option
        $download = Show-DownloadOptions -Release $release
        if (-not $download) { return }
        if ($download -eq 'MANUAL') { return }
        
        # Step 3: Choose folder
        $folder = Get-InstallFolder
        if (-not $folder) { return }
        
        # Step 4: Download
        $filePath = Download-Asset -Asset $download.Asset -DestinationFolder $folder
        if (-not $filePath) { return }
        
        # Step 5: Verify
        if (-not (Verify-Download -FilePath $filePath)) { return }
        
        # Step 6: Add to PATH
        Add-ToPath -Folder $folder
        
        # Step 7: Show first run guide
        Show-FirstRunGuide -ToolPath $filePath
        
        Write-Header "Setup Complete!"
        Write-Success "Ready to use!"
        Write-Host ""
    }
    catch {
        Write-Error "Setup failed: $_"
        Write-Host ""
        Write-Info "For manual installation, visit: https://github.com/$ToolRepo/releases"
    }
}

# Main
Start-Setup

# Pause for manual run
if ($PSVersionTable.Platform -eq 'Win32NT') {
    Write-Host "Press any key to exit..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
