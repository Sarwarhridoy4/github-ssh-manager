# ================================================
# GitHub SSH Manager - Windows Build Script
# Usage:
#   .\build.ps1 [version]
# Example:
#   .\build.ps1 1.0.0
#
# This script:
#   1. Uses FyneApp.toml for metadata
#   2. Installs dependencies (Go, Fyne CLI, ImageMagick, rsrc)
#   3. Converts icon.png -> icon.ico (multi-size)
#   4. Embeds icon in Go binary via rsrc
#   5. Builds Go binary with proper flags
#   6. Packages Windows installer using Fyne + FyneApp.toml
#   7. Creates versioned distribution folder
#   8. Generates release notes and checksums
# ================================================

param(
    [string]$Version = "",
    [switch]$SkipClean = $false,
    [switch]$Release = $false
)

# -------------------------------
# Color Output Functions
# -------------------------------
function Write-Info($msg) {
    Write-Host "[INFO] $msg" -ForegroundColor Cyan
}

function Write-Success($msg) {
    Write-Host "[SUCCESS] $msg" -ForegroundColor Green
}

function Write-Error2($msg) {
    Write-Host "[ERROR] $msg" -ForegroundColor Red
}

function Write-Warning2($msg) {
    Write-Host "[WARNING] $msg" -ForegroundColor Yellow
}

# -------------------------------
# Step 0: Read FyneApp.toml
# -------------------------------
Write-Info "Reading configuration from FyneApp.toml..."

if (-not (Test-Path "FyneApp.toml")) {
    Write-Error2 "FyneApp.toml not found! Please create it in the project root."
    Write-Info "Example FyneApp.toml:"
    Write-Host @"
Website = "https://github.com/Sarwarhridoy4/github-ssh-manager"

[Details]
Icon = "Icon.png"
Name = "GitHub SSH Manager"
ID = "com.sarwarhridoy4.github-ssh-manager"
Version = "1.0.0"
Build = 1
"@
    exit 1
}

# Parse TOML (simple parsing for this use case)
$tomlContent = Get-Content "FyneApp.toml" -Raw
$AppName = if ($tomlContent -match 'Name\s*=\s*"([^"]+)"') { $Matches[1] } else { "github-ssh-manager" }
$AppID = if ($tomlContent -match 'ID\s*=\s*"([^"]+)"') { $Matches[1] } else { "com.sarwarhridoy4.github-ssh-manager" }
$TomlVersion = if ($tomlContent -match 'Version\s*=\s*"([^"]+)"') { $Matches[1] } else { "1.0.0" }
$BuildNum = if ($tomlContent -match 'Build\s*=\s*(\d+)') { $Matches[1] } else { "1" }
$IconFile = if ($tomlContent -match 'Icon\s*=\s*"([^"]+)"') { $Matches[1] } else { "Icon.png" }

# Use version from parameter or TOML
if ([string]::IsNullOrEmpty($Version)) {
    $Version = $TomlVersion
    Write-Info "Using version from FyneApp.toml: $Version"
}

# -------------------------------
# App Configuration
# -------------------------------
$PngIcon = $IconFile
$IcoIcon = "Icon.ico"
$BaseDistDir = "dist\windows"
$DistDir = "$BaseDistDir\$Version"
$OutputExe = "$AppName.exe"
$OutputExe = $OutputExe -replace '\s+', ''  # Remove spaces from filename

Write-Info "Building $AppName v$Version (Build $BuildNum)"
Write-Info "App ID: $AppID"

# -------------------------------
# Step 1: Cleanup old builds
# -------------------------------
if (-not $SkipClean) {
    if (Test-Path $DistDir) {
        Write-Info "Cleaning up previous build: $DistDir"
        Remove-Item $DistDir -Recurse -Force
    }
}

# Create fresh distribution folder
New-Item -ItemType Directory -Path $DistDir -Force | Out-Null
Write-Success "Created distribution folder: $DistDir"

# -------------------------------
# Helper Function: Check Command
# -------------------------------
function Test-Command($cmd) {
    $null -ne (Get-Command $cmd -ErrorAction SilentlyContinue)
}

# -------------------------------
# Step 2: Ensure Go is installed
# -------------------------------
Write-Info "Checking Go installation..."
if (-not (Test-Command go)) {
    Write-Warning2 "Go not found. Installing Go 1.25.5..."
    $goUrl = "https://go.dev/dl/go1.25.5.windows-amd64.msi"
    $goInstaller = "$env:TEMP\go-installer.msi"
    
    Invoke-WebRequest -Uri $goUrl -OutFile $goInstaller
    Start-Process msiexec.exe -ArgumentList "/i `"$goInstaller`" /quiet /norestart" -Wait
    Remove-Item $goInstaller
    
    # Add Go to PATH for current session
    $env:Path = "C:\Program Files\Go\bin;$env:Path"
    $env:GOPATH = "$env:USERPROFILE\go"
    $env:Path = "$env:GOPATH\bin;$env:Path"
    
    Write-Success "Go installed successfully"
} else {
    $goVersion = go version
    Write-Success "Go already installed: $goVersion"
}

# Ensure GOPATH is set
if ([string]::IsNullOrEmpty($env:GOPATH)) {
    $env:GOPATH = "$env:USERPROFILE\go"
    $env:Path = "$env:GOPATH\bin;$env:Path"
}

# -------------------------------
# Step 3: Ensure Fyne CLI is installed
# -------------------------------
Write-Info "Checking Fyne CLI installation..."
$fynePath = "$env:GOPATH\bin\fyne.exe"

if (-not (Test-Path $fynePath)) {
    Write-Warning2 "Fyne CLI not found. Installing..."
    go install fyne.io/fyne/v2/cmd/fyne@latest
    
    if (Test-Path $fynePath) {
        Write-Success "Fyne CLI installed successfully"
    } else {
        Write-Error2 "Failed to install Fyne CLI"
        exit 1
    }
} else {
    Write-Success "Fyne CLI already installed"
}

# -------------------------------
# Step 4: Ensure ImageMagick is installed
# -------------------------------
Write-Info "Checking ImageMagick installation..."
if (-not (Test-Command magick)) {
    Write-Warning2 "ImageMagick not found. Installing..."
    $imUrl = "https://imagemagick.org/archive/binaries/ImageMagick-7.1.2-11-Q16-HDRI-x64-dll.exe"
    $imInstaller = "$env:TEMP\imagemagick-installer.exe"
    
    Invoke-WebRequest -Uri $imUrl -OutFile $imInstaller
    Start-Process $imInstaller -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-" -Wait
    Remove-Item $imInstaller
    
    # Add ImageMagick to PATH
    $env:Path = "C:\Program Files\ImageMagick-7.1.1-Q16-HDRI;$env:Path"
    
    Write-Success "ImageMagick installed successfully"
} else {
    Write-Success "ImageMagick already installed"
}

# -------------------------------
# Step 5: Convert PNG to ICO
# -------------------------------
if (-not (Test-Path $PngIcon)) {
    Write-Error2 "$PngIcon not found! Please ensure the icon file exists."
    exit 1
}

Write-Info "Converting $PngIcon -> $IcoIcon..."
if (Test-Path $IcoIcon) {
    Remove-Item $IcoIcon -Force
}

magick convert $PngIcon -define icon:auto-resize=256,192,128,96,64,48,32,16 $IcoIcon

if (Test-Path $IcoIcon) {
    Write-Success "Icon converted successfully (multi-size ICO)"
} else {
    Write-Error2 "Failed to convert icon"
    exit 1
}

# -------------------------------
# Step 6: Ensure rsrc is installed
# -------------------------------
Write-Info "Checking rsrc tool installation..."
$rsrcPath = "$env:GOPATH\bin\rsrc.exe"

if (-not (Test-Path $rsrcPath)) {
    Write-Warning2 "rsrc not found. Installing..."
    go install github.com/akavel/rsrc@latest
    
    if (Test-Path $rsrcPath) {
        Write-Success "rsrc installed successfully"
    } else {
        Write-Error2 "Failed to install rsrc"
        exit 1
    }
} else {
    Write-Success "rsrc already installed"
}

# -------------------------------
# Step 7: Embed Icon in Binary
# -------------------------------
Write-Info "Embedding icon into binary resource..."
if (Test-Path "rsrc.syso") {
    Remove-Item "rsrc.syso" -Force
}

& $rsrcPath -ico $IcoIcon -o rsrc.syso

if (Test-Path "rsrc.syso") {
    Write-Success "Icon embedded successfully"
} else {
    Write-Error2 "Failed to embed icon"
    exit 1
}

# -------------------------------
# Step 8: Build Go Binary
# -------------------------------
Write-Info "Building Go binary..."

$buildFlags = @(
    "-ldflags"
    "-H windowsgui -X 'main.Version=$Version' -X 'main.BuildNumber=$BuildNum' -X 'main.AppID=$AppID'"
    "-o"
    $OutputExe
)

if ($Release) {
    $buildFlags = @(
        "-ldflags"
        "-H windowsgui -s -w -X 'main.Version=$Version' -X 'main.BuildNumber=$BuildNum' -X 'main.AppID=$AppID'"
        "-trimpath"
        "-o"
        $OutputExe
    )
}

go build @buildFlags

if (-not (Test-Path $OutputExe)) {
    Write-Error2 "Failed to build Go binary"
    Remove-Item "rsrc.syso" -Force -ErrorAction SilentlyContinue
    exit 1
}

$exeSize = (Get-Item $OutputExe).Length / 1MB
Write-Success "Binary built successfully (Size: $([math]::Round($exeSize, 2)) MB)"

# Move binary to dist folder
Move-Item $OutputExe $DistDir -Force
Write-Success "Binary moved to $DistDir"

# Clean up temporary files
Remove-Item "rsrc.syso" -Force -ErrorAction SilentlyContinue

# -------------------------------
# Step 9: Package with Fyne
# -------------------------------
Write-Info "Packaging Windows installer with Fyne..."

Push-Location $DistDir

# Temporarily copy FyneApp.toml and icon to dist folder
Copy-Item "..\..\FyneApp.toml" . -Force
Copy-Item "..\..\$IconFile" . -Force

# Run fyne package (uses FyneApp.toml automatically)
if ($Release) {
    & $fynePath package -os windows -release
} else {
    & $fynePath package -os windows
}

# Clean up copied files
Remove-Item "FyneApp.toml" -Force -ErrorAction SilentlyContinue
Remove-Item $IconFile -Force -ErrorAction SilentlyContinue

Pop-Location

# -------------------------------
# Step 10: Generate Checksums
# -------------------------------
Write-Info "Generating checksums..."

$files = Get-ChildItem -Path $DistDir -File
$checksumFile = Join-Path $DistDir "checksums.txt"

foreach ($file in $files) {
    $hash = Get-FileHash $file.FullName -Algorithm SHA256
    "$($hash.Hash)  $($file.Name)" | Add-Content $checksumFile
}

Write-Success "Checksums saved to checksums.txt"

# -------------------------------
# Step 11: Create Release Notes
# -------------------------------
Write-Info "Creating release notes..."

$releaseNotes = @"
# $AppName v$Version

**Build Number:** $BuildNum
**Build Date:** $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
**Platform:** Windows x64

## Files Included

"@

foreach ($file in $files) {
    $fileSize = [math]::Round($file.Length / 1MB, 2)
    $releaseNotes += "- ``$($file.Name)`` ($fileSize MB)`n"
}

$releaseNotes += @"

## Installation

1. Download the installer package
2. Run the installer
3. Follow the installation wizard
4. Launch $AppName from Start Menu or Desktop

## System Requirements

- Windows 10 or later (64-bit)
- .NET Framework 4.7.2 or later (usually pre-installed)

## Checksums (SHA-256)

See checksums.txt for file verification.

---
Built with ❤️ using Fyne Framework
"@

$releaseNotes | Out-File (Join-Path $DistDir "RELEASE_NOTES.md") -Encoding UTF8

Write-Success "Release notes saved to RELEASE_NOTES.md"

# -------------------------------
# Step 12: Summary
# -------------------------------
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Success "BUILD COMPLETE!"
Write-Host "========================================" -ForegroundColor Cyan
Write-Info "Version: $Version (Build $BuildNum)"
Write-Info "Output directory: $DistDir"
Write-Host ""
Write-Info "Generated files:"
Get-ChildItem -Path $DistDir | ForEach-Object {
    $size = if ($_.PSIsContainer) { "DIR" } else { "$([math]::Round($_.Length / 1MB, 2)) MB" }
    Write-Host "  - $($_.Name) ($size)" -ForegroundColor Yellow
}
Write-Host ""
Write-Success "You can now distribute the files in: $DistDir"
Write-Host "========================================" -ForegroundColor Cyan