#!/bin/bash
# =====================================================================
# GitHub SSH Manager - Production Build & Package Script
# Supports: Debian (.deb) + AppImage with TOML configuration
# =====================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ ${NC}$1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

# =====================================================================
# Step 0: Parse FyneApp.toml configuration
# =====================================================================
log_info "Reading FyneApp.toml configuration..."

if [ ! -f "FyneApp.toml" ]; then
    log_error "FyneApp.toml not found!"
    exit 1
fi

# Parse TOML using grep/sed
APP_NAME=$(grep '^name = ' FyneApp.toml | sed 's/name = "\(.*\)"/\1/' | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
APP_ID=$(grep '^id = ' FyneApp.toml | sed 's/id = "\(.*\)"/\1/')
VERSION=$(grep '^version = ' FyneApp.toml | sed 's/version = "\(.*\)"/\1/')
DESCRIPTION=$(grep '^description = ' FyneApp.toml | sed 's/description = "\(.*\)"/\1/')
AUTHOR=$(grep '^author = ' FyneApp.toml | sed 's/author = "\(.*\)"/\1/')
LICENSE=$(grep '^license = ' FyneApp.toml | sed 's/license = "\(.*\)"/\1/')
ICON_PATH=$(grep '^icon = ' FyneApp.toml | sed 's/icon = "\(.*\)"/\1/')

# Fallback values
APP_NAME=${APP_NAME:-"github-ssh-manager"}
APP_ID=${APP_ID:-"com.sarwar.githubsshmanager"}
VERSION=${VERSION:-"1.0.0"}
DESCRIPTION=${DESCRIPTION:-"A simple SSH manager for GitHub repositories"}
AUTHOR=${AUTHOR:-"Sarwar Hossain"}
LICENSE=${LICENSE:-"MIT"}
ICON_PATH=${ICON_PATH:-"assets/icon.png"}
EMAIL="sarwarhridoy4@gmail.com"

# Get git information
if git rev-parse --git-dir > /dev/null 2>&1; then
    GIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo "1")
    GIT_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
    if [ -n "$GIT_TAG" ]; then
        VERSION="$GIT_TAG"
    fi
else
    GIT_HASH="unknown"
    BUILD_NUMBER=$(date +%Y%m%d%H%M)
fi

# Architecture detection
ARCH_RAW=$(uname -m)
case "$ARCH_RAW" in
  x86_64) ARCH="amd64"; APPIMAGE_ARCH="x86_64" ;;
  aarch64) ARCH="arm64"; APPIMAGE_ARCH="aarch64" ;;
  armv7l) ARCH="armhf"; APPIMAGE_ARCH="armhf" ;;
  i386|i686) ARCH="i386"; APPIMAGE_ARCH="i686" ;;
  *) ARCH="$ARCH_RAW"; APPIMAGE_ARCH="$ARCH_RAW" ;;
esac

log_success "Configuration loaded:"
echo "  • App Name    : $APP_NAME"
echo "  • App ID      : $APP_ID"
echo "  • Version     : $VERSION"
echo "  • Build       : $BUILD_NUMBER"
echo "  • Author      : $AUTHOR"
echo "  • License     : $LICENSE"
echo "  • Architecture: $ARCH ($APPIMAGE_ARCH)"
echo "  • Git Hash    : $GIT_HASH"

# =====================================================================
# Step 1: Check required tools
# =====================================================================
log_info "Checking required build tools..."

MISSING_TOOLS=()
REQUIRED_TOOLS=("go" "dpkg-deb" "convert" "wget" "fyne")

for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v $tool &> /dev/null; then
        MISSING_TOOLS+=($tool)
    else
        log_success "$tool found: $(command -v $tool)"
    fi
done

if [ ${#MISSING_TOOLS[@]} -ne 0 ]; then
    log_error "Missing required tools: ${MISSING_TOOLS[*]}"
    log_info "Installing missing dependencies..."
    
    sudo apt-get update
    
    for tool in "${MISSING_TOOLS[@]}"; do
        case $tool in
            go)
                sudo apt-get install -y golang-go
                ;;
            dpkg-deb)
                sudo apt-get install -y dpkg-dev
                ;;
            convert)
                sudo apt-get install -y imagemagick
                ;;
            wget)
                sudo apt-get install -y wget
                ;;
            fyne)
                log_info "Installing Fyne CLI..."
                go install fyne.io/tools/cmd/fyne@latest
                export PATH=$PATH:$(go env GOPATH)/bin
                ;;
        esac
    done
    
    log_success "All dependencies installed!"
else
    log_success "All required tools are available!"
fi

# Check for FUSE (needed for AppImage)
if ! command -v fusermount &> /dev/null; then
    log_warning "FUSE not found, installing for AppImage support..."
    sudo apt-get install -y fuse libfuse2
fi

# Verify icon exists
if [ ! -f "$ICON_PATH" ]; then
    log_error "Icon file not found: $ICON_PATH"
    log_info "Creating placeholder icon..."
    mkdir -p $(dirname "$ICON_PATH")
    convert -size 512x512 xc:blue -fill white -pointsize 72 -gravity center \
            -annotate +0+0 "SSH" "$ICON_PATH"
    log_success "Placeholder icon created"
fi

# Verify Go modules
log_info "Verifying Go modules..."
if [ -f "go.mod" ]; then
    go mod tidy
    go mod download
    log_success "Go modules verified"
else
    log_error "go.mod not found! Initialize with: go mod init"
    exit 1
fi

# =====================================================================
# Step 2: Clean previous builds
# =====================================================================
log_info "Cleaning previous builds..."
rm -rf build/ dist/ ${APP_NAME}-deb ${APP_NAME}.AppDir *.deb *.AppImage *.tar.xz
mkdir -p build dist
log_success "Build directories cleaned"

# =====================================================================
# Step 3: Build Go binary with Fyne
# =====================================================================
log_info "Building Go binary with Fyne..."

BUILD_FLAGS="-X 'main.AppVersion=${VERSION}' -X 'main.AppID=${APP_ID}' -X 'main.GitCommit=${GIT_HASH}'"

log_info "Build number: $BUILD_NUMBER (Git hash: $GIT_HASH)"

# Use fyne package with correct parameters (note: --app-version not -appVersion)
log_info "Building with fyne package command..."
if fyne package --os linux --icon "$ICON_PATH" --app-version "$VERSION" --app-build "$BUILD_NUMBER" --name "$APP_NAME" --release 2>/dev/null; then
    log_success "Fyne package build successful"
    
    # Extract binary from tar.xz if created
    if [ -f "${APP_NAME}.tar.xz" ]; then
        tar -xf "${APP_NAME}.tar.xz"
        # Find and move the binary
        if [ -f "usr/local/bin/${APP_NAME}" ]; then
            mv "usr/local/bin/${APP_NAME}" "build/${APP_NAME}"
        fi
        rm -rf usr "${APP_NAME}.tar.xz"
    fi
fi

# Fallback: Manual build if needed
if [ ! -f "build/${APP_NAME}" ]; then
    log_warning "Using manual go build as fallback..."
    go build -ldflags="$BUILD_FLAGS" -o "build/${APP_NAME}" .
fi

if [ ! -f "build/${APP_NAME}" ]; then
    log_error "Binary not found after build!"
    exit 1
fi

chmod +x "build/${APP_NAME}"
BINARY_SIZE=$(du -h "build/${APP_NAME}" | cut -f1)
log_success "Binary built: build/${APP_NAME} (${BINARY_SIZE})"

# =====================================================================
# Step 4: Create Debian package structure
# =====================================================================
log_info "Creating Debian package structure..."

DEB_DIR="${APP_NAME}-deb"
mkdir -p "${DEB_DIR}/DEBIAN"
mkdir -p "${DEB_DIR}/usr/bin"
mkdir -p "${DEB_DIR}/usr/share/applications"
mkdir -p "${DEB_DIR}/usr/share/pixmaps"
mkdir -p "${DEB_DIR}/usr/share/icons/hicolor"
mkdir -p "${DEB_DIR}/usr/share/doc/${APP_NAME}"
mkdir -p "${DEB_DIR}/usr/share/${APP_NAME}"

# Copy binary
cp "build/${APP_NAME}" "${DEB_DIR}/usr/bin/"
chmod 755 "${DEB_DIR}/usr/bin/${APP_NAME}"

# Generate icons
log_info "Generating icons for Debian package..."
for SIZE in 16 22 24 32 48 64 128 256 512; do
    ICON_DIR="${DEB_DIR}/usr/share/icons/hicolor/${SIZE}x${SIZE}/apps"
    mkdir -p "$ICON_DIR"
    convert "$ICON_PATH" -resize ${SIZE}x${SIZE} "$ICON_DIR/${APP_NAME}.png"
done
cp "$ICON_PATH" "${DEB_DIR}/usr/share/pixmaps/${APP_NAME}.png"

# Desktop entry
log_info "Creating desktop entry..."
cat > "${DEB_DIR}/usr/share/applications/${APP_NAME}.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=GitHub SSH Manager
GenericName=SSH Key Manager
Comment=${DESCRIPTION}
Exec=${APP_NAME}
Icon=${APP_NAME}
Terminal=false
Categories=Utility;Development;Network;
Keywords=github;ssh;git;key;manager;
StartupNotify=true
StartupWMClass=${APP_NAME}
X-GNOME-UsesNotifications=true
MimeType=x-scheme-handler/ssh;
EOF

# Control file
log_info "Creating Debian control file..."
INSTALLED_SIZE=$(du -sk "${DEB_DIR}/usr" | cut -f1)

cat > "${DEB_DIR}/DEBIAN/control" <<EOF
Package: ${APP_NAME}
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: ${ARCH}
Installed-Size: ${INSTALLED_SIZE}
Depends: libc6 (>= 2.31), libgl1, libx11-6, libxcursor1, libxrandr2, libxinerama1, libxi6, libxxf86vm1
Maintainer: ${AUTHOR} <${EMAIL}>
Homepage: https://github.com/Sarwarhridoy4/${APP_NAME}
Description: ${DESCRIPTION}
 GitHub SSH Manager is a cross-platform GUI tool built with Go and Fyne
 to manage multiple GitHub SSH keys. Features include:
 .
  - Generate ED25519 SSH key pairs
  - View and copy public keys
  - Upload keys to GitHub via API
  - Test SSH connections
  - Manage ~/.ssh/config
  - Activity logging with export
 .
 Perfect for developers managing multiple GitHub accounts.
EOF

# Copyright and changelog
cat > "${DEB_DIR}/usr/share/doc/${APP_NAME}/copyright" <<EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: ${APP_NAME}
Upstream-Contact: ${AUTHOR} <${EMAIL}>
Source: https://github.com/Sarwarhridoy4/${APP_NAME}

Files: *
Copyright: $(date +%Y) ${AUTHOR}
License: ${LICENSE}
EOF

cat > "${DEB_DIR}/usr/share/doc/${APP_NAME}/changelog" <<EOF
${APP_NAME} (${VERSION}) unstable; urgency=medium

  * Version ${VERSION} release
  * Built from commit ${GIT_HASH}

 -- ${AUTHOR} <${EMAIL}>  $(date -R)
EOF
gzip -9 -n "${DEB_DIR}/usr/share/doc/${APP_NAME}/changelog"

# Maintainer scripts
cat > "${DEB_DIR}/DEBIAN/postinst" <<'POSTINST'
#!/bin/bash
set -e
if [ "$1" = "configure" ]; then
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q /usr/share/applications || true
    command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -f /usr/share/icons/hicolor || true
fi
exit 0
POSTINST
chmod 755 "${DEB_DIR}/DEBIAN/postinst"

cat > "${DEB_DIR}/DEBIAN/postrm" <<'POSTRM'
#!/bin/bash
set -e
if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q /usr/share/applications || true
    command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -f /usr/share/icons/hicolor || true
fi
exit 0
POSTRM
chmod 755 "${DEB_DIR}/DEBIAN/postrm"

# Build .deb
log_info "Building Debian package..."
dpkg-deb --build --root-owner-group "${DEB_DIR}"
mv "${DEB_DIR}.deb" "dist/${APP_NAME}_${VERSION}_${ARCH}.deb"

log_info "Verifying Debian package..."
dpkg-deb --info "dist/${APP_NAME}_${VERSION}_${ARCH}.deb"
log_success "Debian package created: dist/${APP_NAME}_${VERSION}_${ARCH}.deb"

# =====================================================================
# Step 5: Create AppImage
# =====================================================================
log_info "Creating AppImage..."

APPDIR="${APP_NAME}.AppDir"
mkdir -p "${APPDIR}/usr/bin"
mkdir -p "${APPDIR}/usr/share/applications"
mkdir -p "${APPDIR}/usr/share/icons/hicolor"
mkdir -p "${APPDIR}/usr/lib"

# Copy binary
cp "build/${APP_NAME}" "${APPDIR}/usr/bin/"
chmod 755 "${APPDIR}/usr/bin/${APP_NAME}"

# AppRun script
cat > "${APPDIR}/AppRun" <<EOF
#!/bin/bash
SELF=\$(readlink -f "\$0")
HERE=\${SELF%/*}
export PATH="\${HERE}/usr/bin:\${PATH}"
export LD_LIBRARY_PATH="\${HERE}/usr/lib:\${LD_LIBRARY_PATH}"
exec "\${HERE}/usr/bin/${APP_NAME}" "\$@"
EOF
chmod 755 "${APPDIR}/AppRun"

# Icons
log_info "Generating icons for AppImage..."
for SIZE in 16 22 24 32 48 64 128 256 512; do
    ICON_DIR="${APPDIR}/usr/share/icons/hicolor/${SIZE}x${SIZE}/apps"
    mkdir -p "$ICON_DIR"
    convert "$ICON_PATH" -resize ${SIZE}x${SIZE} "$ICON_DIR/${APP_NAME}.png"
done

convert "$ICON_PATH" -resize 256x256 "${APPDIR}/${APP_NAME}.png"
cp "${APPDIR}/${APP_NAME}.png" "${APPDIR}/.DirIcon"

# Desktop entry
cat > "${APPDIR}/${APP_NAME}.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=GitHub SSH Manager
GenericName=SSH Key Manager
Comment=${DESCRIPTION}
Exec=${APP_NAME}
Icon=${APP_NAME}
Terminal=false
Categories=Utility;Development;Network;
Keywords=github;ssh;git;key;manager;
StartupNotify=true
X-AppImage-Version=${VERSION}
X-AppImage-BuildId=${GIT_HASH}
EOF

cp "${APPDIR}/${APP_NAME}.desktop" "${APPDIR}/usr/share/applications/"

# AppStream metadata
mkdir -p "${APPDIR}/usr/share/metainfo"
cat > "${APPDIR}/usr/share/metainfo/${APP_ID}.appdata.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>${APP_ID}</id>
  <metadata_license>CC0-1.0</metadata_license>
  <project_license>${LICENSE}</project_license>
  <name>GitHub SSH Manager</name>
  <summary>${DESCRIPTION}</summary>
  <description>
    <p>GitHub SSH Manager is a cross-platform GUI tool for managing multiple GitHub SSH keys.</p>
    <p>Features:</p>
    <ul>
      <li>Generate ED25519 SSH key pairs</li>
      <li>View and copy public keys</li>
      <li>Upload keys to GitHub via Personal Access Token</li>
      <li>Test SSH connections</li>
      <li>Manage ~/.ssh/config automatically</li>
      <li>Activity logging with export capability</li>
    </ul>
  </description>
  <categories>
    <category>Utility</category>
    <category>Development</category>
  </categories>
  <url type="homepage">https://github.com/Sarwarhridoy4/${APP_NAME}</url>
  <developer_name>${AUTHOR}</developer_name>
  <releases>
    <release version="${VERSION}" date="$(date +%Y-%m-%d)">
      <description>
        <p>Version ${VERSION} release</p>
      </description>
    </release>
  </releases>
</component>
EOF

# Download appimagetool if needed
APPIMAGETOOL_URL="https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-${APPIMAGE_ARCH}.AppImage"

if [ ! -f "/usr/local/bin/appimagetool" ]; then
    log_info "Downloading appimagetool..."
    wget -q --show-progress "$APPIMAGETOOL_URL" -O appimagetool
    chmod +x appimagetool
    sudo mv appimagetool /usr/local/bin/
    log_success "appimagetool installed"
fi

# Build AppImage
log_info "Building AppImage..."
ARCH=${APPIMAGE_ARCH} appimagetool --comp gzip "${APPDIR}" "dist/${APP_NAME}-${VERSION}-${APPIMAGE_ARCH}.AppImage"

if [ -f "dist/${APP_NAME}-${VERSION}-${APPIMAGE_ARCH}.AppImage" ]; then
    chmod +x "dist/${APP_NAME}-${VERSION}-${APPIMAGE_ARCH}.AppImage"
    log_success "AppImage created: dist/${APP_NAME}-${VERSION}-${APPIMAGE_ARCH}.AppImage"
else
    log_error "AppImage creation failed!"
    exit 1
fi

# =====================================================================
# Step 6: Generate checksums
# =====================================================================
log_info "Generating checksums..."
cd dist
sha256sum *.deb *.AppImage > SHA256SUMS
md5sum *.deb *.AppImage > MD5SUMS
cd ..
log_success "Checksums generated"

# =====================================================================
# Step 7: Summary
# =====================================================================
echo ""
log_success "🎉 Build complete! Packages created:"
echo ""
echo "📦 Packages:"
ls -lh dist/*.deb dist/*.AppImage
echo ""
echo "🔐 Checksums:"
cat dist/SHA256SUMS
echo ""
log_info "Install Debian package: sudo dpkg -i dist/${APP_NAME}_${VERSION}_${ARCH}.deb"
log_info "Run AppImage: ./dist/${APP_NAME}-${VERSION}-${APPIMAGE_ARCH}.AppImage"
log_info "Extract AppImage: ./dist/${APP_NAME}-${VERSION}-${APPIMAGE_ARCH}.AppImage --appimage-extract"
echo ""
log_success "All done! 🚀"