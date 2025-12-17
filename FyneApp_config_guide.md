# FyneApp.toml Configuration Guide

## Updated FyneApp.toml for GitHub SSH Manager

```toml
# Optional metadata for apps.fyne.io listing
Website = "https://github.com/Sarwarhridoy4/github-ssh-manager"

[Details]
# Application icon (relative path from FyneApp.toml location)
Icon = "Icon.png"

# Application display name
Name = "GitHub SSH Manager"

# Unique application identifier (reverse domain notation)
ID = "com.sarwarhridoy4.github-ssh-manager"

# Application version (semantic versioning recommended)
Version = "1.0.0"

# Build number (increment with each build)
Build = 1

[LinuxAndBSD]
# Generic name for the application category
GenericName = "SSH Key Manager"

# Desktop entry categories (must be valid freedesktop.org categories)
# See: https://specifications.freedesktop.org/menu-spec/latest/apa.html
Categories = ["Development", "Network", "Utility"]

# Short description of the application
Comment = "Manage SSH keys for GitHub accounts"

# Keywords for desktop search
Keywords = ["ssh", "github", "key", "manager", "git", "security"]

# Optional execution parameters
# ExecParams = ""
```

## How to Use FyneApp.toml While Building & Packaging

### 1. **Basic Build Command**

Without FyneApp.toml, you would need:
```bash
fyne package -os linux -icon Icon.png -name "GitHub SSH Manager" -appID com.sarwarhridoy4.github-ssh-manager
```

With FyneApp.toml in your project root:
```bash
# Simple build - all metadata read from FyneApp.toml
fyne package -os linux

# Build for different platforms
fyne package -os windows
fyne package -os darwin  # macOS
fyne package -os android
fyne package -os ios
```

### 2. **Cross-Platform Packaging**

```bash
# Package for current platform
fyne package

# Package for specific OS
fyne package -os linux
fyne package -os windows
fyne package -os darwin

# Package for mobile
fyne package -os android
fyne package -os ios
```

### 3. **Release Command**

```bash
# Create a release package
fyne release -os linux

# The version and build number come from FyneApp.toml
# Output will be: github-ssh-manager-1.0.0.tar.gz (Linux)
# or: GitHubSSHManager-1.0.0.exe (Windows)
```

### 4. **Override FyneApp.toml Values**

You can still override values via command line:
```bash
# Override version for a beta release
fyne package -os linux -appVersion "1.1.0-beta"

# Override app ID
fyne package -os linux -appID "com.example.custom-id"

# Override icon
fyne package -os linux -icon "CustomIcon.png"
```

### 5. **Building for Multiple Architectures**

```bash
# Build for specific architecture
GOARCH=amd64 fyne package -os linux
GOARCH=arm64 fyne package -os linux
GOARCH=arm fyne package -os linux

# Build for 32-bit Windows
GOARCH=386 fyne package -os windows

# Build for macOS (Intel)
GOARCH=amd64 fyne package -os darwin

# Build for macOS (Apple Silicon)
GOARCH=arm64 fyne package -os darwin
```

## Project Structure

```
github-ssh-manager/
├── FyneApp.toml          # Metadata file
├── Icon.png              # Application icon (512x512 recommended)
├── go.mod
├── go.sum
├── main.go
└── ...
```

## Icon Requirements

- **Format**: PNG with transparency
- **Size**: 512x512 pixels recommended
- **Location**: Relative to FyneApp.toml (usually project root)

## Complete Build Workflow

### Development Build
```bash
# Run without packaging
go run .

# Or use fyne for testing
fyne run
```

### Testing Packaging
```bash
# Quick package for current OS
fyne package

# Test the packaged app
./github-ssh-manager  # Linux
./GitHubSSHManager.app  # macOS
GitHubSSHManager.exe  # Windows
```

### Production Release
```bash
# Clean build
go clean

# Build for all platforms
fyne release -os linux
fyne release -os windows
fyne release -os darwin

# Build for mobile (requires additional setup)
fyne release -os android
fyne release -os ios
```

## Automated Multi-Platform Build Script

Create a `build.sh` script:

```bash
#!/bin/bash

# Build for Linux
echo "Building for Linux..."
fyne package -os linux

# Build for Windows
echo "Building for Windows..."
fyne package -os windows

# Build for macOS (Intel)
echo "Building for macOS (Intel)..."
GOARCH=amd64 fyne package -os darwin

# Build for macOS (Apple Silicon)
echo "Building for macOS (Apple Silicon)..."
GOARCH=arm64 fyne package -os darwin

echo "All builds completed!"
```

Make it executable:
```bash
chmod +x build.sh
./build.sh
```

## GitHub Actions CI/CD Example

Create `.github/workflows/build.yml`:

```yaml
name: Build Releases

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    strategy:
      matrix:
        os: [ubuntu-latest, windows-latest, macos-latest]
    runs-on: ${{ matrix.os }}
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Set up Go
      uses: actions/setup-go@v4
      with:
        go-version: '1.21'
    
    - name: Install Fyne CLI
      run: go install fyne.io/fyne/v2/cmd/fyne@latest
    
    - name: Install dependencies (Linux)
      if: runner.os == 'Linux'
      run: |
        sudo apt-get update
        sudo apt-get install -y gcc libgl1-mesa-dev xorg-dev
    
    - name: Build
      run: |
        fyne package -os ${{ runner.os == 'Linux' && 'linux' || runner.os == 'Windows' && 'windows' || 'darwin' }}
    
    - name: Upload artifacts
      uses: actions/upload-artifact@v3
      with:
        name: ${{ matrix.os }}-build
        path: |
          github-ssh-manager*
          GitHubSSHManager*
```

## Common Issues & Solutions

### Issue: Icon not found
**Solution**: Ensure Icon.png is in the same directory as FyneApp.toml

### Issue: Build fails on Linux
**Solution**: Install required dependencies:
```bash
sudo apt-get install gcc libgl1-mesa-dev xorg-dev
```

### Issue: Cross-compilation not working
**Solution**: Use `fyne-cross` for cross-compilation:
```bash
go install github.com/fyne-io/fyne-cross@latest
fyne-cross linux -arch=amd64,arm64
fyne-cross windows -arch=amd64
fyne-cross darwin -arch=amd64,arm64
```

## Validating FyneApp.toml

Test that your configuration is correct:
```bash
# Check if fyne can read the metadata
fyne package -os linux -dryrun

# Verify the application ID
fyne metadata
```

## Best Practices

1. **Version Management**: Use semantic versioning (MAJOR.MINOR.PATCH)
2. **Build Numbers**: Increment build number with each release
3. **Icon Quality**: Use high-resolution icons (512x512 minimum)
4. **App ID**: Use reverse domain notation (com.domain.app-name)
5. **Categories**: Choose appropriate freedesktop.org categories for Linux
6. **Git Tags**: Tag releases in Git to match version numbers

## Additional Resources

- [Fyne Packaging Documentation](https://docs.fyne.io/started/packaging/)
- [Fyne Metadata Documentation](https://docs.fyne.io/started/metadata/)
- [Desktop Entry Specification](https://specifications.freedesktop.org/desktop-entry/latest/)
- [Freedesktop.org Categories](https://specifications.freedesktop.org/menu-spec/latest/apa.html)