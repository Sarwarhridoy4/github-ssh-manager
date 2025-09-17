# ================================================
# Auto-SSH Build Script (PowerShell)
# Usage:
#   .\build.ps1 [version]
# Example:
#   .\build.ps1 1.0.0
#
# This script:
#   1. Sets app name + ID.
#   2. Installs Go, Fyne CLI, ImageMagick if missing.
#   3. Converts icon.png -> icon.ico (multi-size).
#   4. Embeds icon in Go binary via rsrc.
#   5. Builds Go binary.
#   6. Packages Windows installer with Fyne silently (--release).
#   7. Saves outputs in dist/windows/<version>/.
#   8. Cleans up previous builds automatically.
# ================================================

param(
    [string]$Version = "1.0.0"
)

# -------------------------------
# Step 0: App Info
# -------------------------------
$AppName = "auto-ssh"
$AppID   = "com.sarwar.autossh"
$PngIcon = "icon.png"
$IcoIcon = "icon.ico"
$BaseDistDir = "dist/windows"
$DistDir = "$BaseDistDir/$Version"   # versioned folder
$OutputFile = "$AppName.exe"

Write-Host "[INFO] Starting build for $AppName v$Version"

# -------------------------------
# Step 1: Cleanup old builds
# -------------------------------
if (Test-Path $BaseDistDir) {
    Write-Host "[INFO] Cleaning up previous builds in $BaseDistDir..."
    Remove-Item $BaseDistDir -Recurse -Force
}
# Recreate versioned folder
New-Item -ItemType Directory -Path $DistDir | Out-Null
Write-Host "[INFO] Created fresh distribution folder: $DistDir"

# -------------------------------
# Step 2: Ensure Go is installed
# -------------------------------
function Check-Command($cmd) { $null -ne (Get-Command $cmd -ErrorAction SilentlyContinue) }

if (-not (Check-Command go)) {
    Write-Host "[INFO] Go not found. Installing..."
    Invoke-WebRequest -Uri "https://go.dev/dl/go1.22.2.windows-amd64.msi" -OutFile "go.msi"
    Start-Process msiexec.exe -ArgumentList "/i go.msi /quiet /norestart" -Wait
    Remove-Item "go.msi"
    $Env:Path += ";C:\Program Files\Go\bin"
}

# -------------------------------
# Step 3: Ensure Fyne CLI is installed
# -------------------------------
if (-not (Check-Command fyne)) {
    Write-Host "[INFO] Installing Fyne CLI..."
    go install fyne.io/tools/cmd/fyne@latest
}

# -------------------------------
# Step 4: Ensure ImageMagick is installed
# -------------------------------
if (-not (Check-Command magick)) {
    Write-Host "[INFO] ImageMagick not found. Installing..."
    $imUrl = "https://imagemagick.org/archive/binaries/ImageMagick-7.1.1-29-Q16-HDRI-x64-dll.exe"
    Invoke-WebRequest -Uri $imUrl -OutFile "imagemagick-installer.exe"
    Start-Process "imagemagick-installer.exe" -ArgumentList "/silent" -Wait
    Remove-Item "imagemagick-installer.exe"
    $Env:Path += ";C:\Program Files\ImageMagick-7.1.1-Q16-HDRI"
}

# -------------------------------
# Step 5: Ensure icon.ico exists
# -------------------------------
if (-not (Test-Path $IcoIcon)) {
    if (-not (Test-Path $PngIcon)) {
        Write-Error "[ERROR] icon.png not found. Please place it in the project root."
        exit 1
    }

    Write-Host "[INFO] Converting icon.png -> icon.ico (multi-size)..."
    magick convert $PngIcon -define icon:auto-resize=256,128,64,48,32,16 $IcoIcon
} else {
    Write-Host "[INFO] Found existing icon.ico (skipping conversion)"
}

# -------------------------------
# Step 6: Embed icon in binary using rsrc
# -------------------------------
Write-Host "[INFO] Embedding icon into binary..."
if (-not (Check-Command rsrc)) {
    Write-Host "[INFO] rsrc not found. Installing..."
    go install github.com/akavel/rsrc@latest
}

# Create rsrc.syso from icon.ico
rsrc -ico $IcoIcon -o rsrc.syso

# -------------------------------
# Step 7: Build Go binary
# -------------------------------
Write-Host "[INFO] Building Go binary..."
go build -ldflags "-X 'main.AppID=$AppID'" -o $OutputFile

# Move binary to dist folder
Move-Item $OutputFile $DistDir

# Remove temporary rsrc.syso
Remove-Item "rsrc.syso"

# -------------------------------
# Step 8: Package Windows installer with Fyne silently (--release)
# -------------------------------
Write-Host "[INFO] Packaging Windows installer..."
Push-Location $DistDir

# Run fyne package directly in the current session (no extra terminal)
fyne package

# -------------------------------
# Step 9: Finish
# -------------------------------
Write-Host "[SUCCESS] Windows build & package complete!"
Write-Host "[INFO] All output files are in $DistDir"
