#!/bin/bash
# =====================================================================
# GitHub SSH Manager Build & Package Script (Debian + AppImage)
# =====================================================================
APP_NAME="github-ssh-manager"
APP_ID="com.sarwar.githubsshmanager"

# --- Determine version from Git or argument ---
if git rev-parse --git-dir > /dev/null 2>&1; then
    VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "${1:-1.0.0}")
    GIT_HASH=$(git rev-parse --short HEAD)
else
    VERSION=${1:-"1.0.0"}
    GIT_HASH="unknown"
fi

# --- Map uname -m to Debian and AppImage architectures ---
ARCH_RAW=$(uname -m)
case "$ARCH_RAW" in
  x86_64) ARCH="amd64"; APPIMAGE_ARCH="x86_64" ;;
  aarch64) ARCH="arm64"; APPIMAGE_ARCH="arm64" ;;
  armv7l) ARCH="armhf"; APPIMAGE_ARCH="armhf" ;;
  i386) ARCH="i386"; APPIMAGE_ARCH="i386" ;;
  *) ARCH="$ARCH_RAW"; APPIMAGE_ARCH="$ARCH_RAW" ;;
esac

AUTHOR="Sarwar Hossain"
EMAIL="sarwarhridoy4@gmail.com"
DESCRIPTION_SHORT="GitHub SSH Manager"
DESCRIPTION_LONG="A cross-platform GUI tool built with Go and Fyne to manage multiple GitHub SSH keys. Generate keys, view public keys, upload to GitHub, test SSH connections, and manage your ~/.ssh/config."

echo "📦 Building ${APP_NAME} version ${VERSION} (commit ${GIT_HASH}) for ${ARCH}"

# =====================================================================
# Step 0: Install required tools
# =====================================================================
echo "🔧 Installing build dependencies..."
sudo apt-get update
sudo apt-get install -y imagemagick wget dpkg-dev golang-go
go mod tidy

# =====================================================================
# Step 1: Clean previous builds
# =====================================================================
rm -rf ${APP_NAME}-deb ${APP_NAME}_${VERSION}_${ARCH}.deb ${APP_NAME}.AppDir ${APP_NAME}_${VERSION}_${APPIMAGE_ARCH}.AppImage

# =====================================================================
# Step 2: Build Go binary with metadata
# =====================================================================
echo "⚙️  Building Go binary..."
go build -ldflags="-X 'main.AppID=${APP_ID}' -X 'main.GitCommit=${GIT_HASH}'" -o ${APP_NAME}

# =====================================================================
# Step 3: Create Debian package
# =====================================================================
echo "📦 Creating .deb package..."
mkdir -p ${APP_NAME}-deb/DEBIAN ${APP_NAME}-deb/usr/bin ${APP_NAME}-deb/usr/share/applications ${APP_NAME}-deb/usr/share/icons/hicolor ${APP_NAME}-deb/usr/share/${APP_NAME}/screenshots
cp ${APP_NAME} ${APP_NAME}-deb/usr/bin/

# Screenshots resizing
if [ -f "screenshot.png" ]; then
    for SIZE in 320 640 1280; do
        convert screenshot.png -resize ${SIZE}x ${APP_NAME}-deb/usr/share/${APP_NAME}/screenshots/screenshot_${SIZE}.png
    done
fi

# Icons resizing
for SIZE in 16 22 24 32 48 64 128 256 512; do
    ICON_DIR=${APP_NAME}-deb/usr/share/icons/hicolor/${SIZE}x${SIZE}/apps
    mkdir -p ${ICON_DIR}
    convert icon.png -resize ${SIZE}x${SIZE} ${ICON_DIR}/${APP_NAME}.png
done

# Control file
cat <<EOF > ${APP_NAME}-deb/DEBIAN/control
Package: ${APP_NAME}
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: ${ARCH}
Maintainer: ${AUTHOR} <${EMAIL}>
Homepage: https://github.com/Sarwarhridoy4/github-ssh-manager
Description: ${DESCRIPTION_SHORT}
 ${DESCRIPTION_LONG}
EOF

# postinst
cat <<'EOF' > ${APP_NAME}-deb/DEBIAN/postinst
#!/bin/bash
set -e
command -v update-desktop-database &>/dev/null && update-desktop-database -q
command -v gtk-update-icon-cache &>/dev/null && gtk-update-icon-cache -q /usr/share/icons/hicolor
exit 0
EOF
chmod 755 ${APP_NAME}-deb/DEBIAN/postinst

# prerm
cat <<'EOF' > ${APP_NAME}-deb/DEBIAN/prerm
#!/bin/bash
set -e
command -v update-desktop-database &>/dev/null && update-desktop-database -q
command -v gtk-update-icon-cache &>/dev/null && gtk-update-icon-cache -q /usr/share/icons/hicolor
exit 0
EOF
chmod 755 ${APP_NAME}-deb/DEBIAN/prerm

# Desktop entry
cat <<EOF > ${APP_NAME}-deb/usr/share/applications/${APP_NAME}.desktop
[Desktop Entry]
Name=GitHub SSH Manager
Exec=${APP_NAME}
Icon=${APP_NAME}
Type=Application
Categories=Utility;
Comment=${DESCRIPTION_LONG}
StartupNotify=true
X-GNOME-UsesNotifications=true
X-AppID=${APP_ID}
X-AppInstall-Screenshot=/usr/share/${APP_NAME}/screenshots/screenshot_640.png
EOF

# Build .deb
dpkg-deb --build ${APP_NAME}-deb
mv ${APP_NAME}-deb.deb ${APP_NAME}_${VERSION}_${ARCH}.deb
echo "✅ .deb package created: ${APP_NAME}_${VERSION}_${ARCH}.deb"

# =====================================================================
# Step 4: Create AppImage
# =====================================================================
echo "📦 Creating AppImage..."
mkdir -p ${APP_NAME}.AppDir/usr/bin ${APP_NAME}.AppDir/usr/share/icons/hicolor ${APP_NAME}.AppDir/usr/share/applications ${APP_NAME}.AppDir/usr/share/${APP_NAME}/screenshots

cp ${APP_NAME} ${APP_NAME}.AppDir/${APP_NAME}
chmod +x ${APP_NAME}.AppDir/${APP_NAME}
ln -sf ${APP_NAME} ${APP_NAME}.AppDir/AppRun

# Screenshots
if [ -f "screenshot.png" ]; then
    for SIZE in 320 640 1280; do
        convert screenshot.png -resize ${SIZE}x ${APP_NAME}.AppDir/usr/share/${APP_NAME}/screenshots/screenshot_${SIZE}.png
    done
fi

# Desktop entry
cat <<EOF > ${APP_NAME}.AppDir/${APP_NAME}.desktop
[Desktop Entry]
Name=GitHub SSH Manager
Exec=${APP_NAME}
Icon=${APP_NAME}
Type=Application
Categories=Utility;
Comment=${DESCRIPTION_LONG}
StartupNotify=true
X-GNOME-UsesNotifications=true
X-AppID=${APP_ID}
X-AppInstall-Screenshot=/usr/share/${APP_NAME}/screenshots/screenshot_640.png
EOF

# Icons
cp icon.png ${APP_NAME}.AppDir/${APP_NAME}.png
for SIZE in 16 22 24 32 48 64 128 256 512; do
    mkdir -p ${APP_NAME}.AppDir/usr/share/icons/hicolor/${SIZE}x${SIZE}/apps
    convert icon.png -resize ${SIZE}x${SIZE} ${APP_NAME}.AppDir/usr/share/icons/hicolor/${SIZE}x${SIZE}/apps/${APP_NAME}.png
done

# Download appimagetool if missing
if ! command -v appimagetool &> /dev/null; then
    echo "⬇️ Downloading appimagetool..."
    wget -q https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-${APPIMAGE_ARCH}.AppImage -O appimagetool
    chmod +x appimagetool
    sudo mv appimagetool /usr/local/bin/
fi

# Build AppImage
appimagetool ${APP_NAME}.AppDir
mv ${APP_NAME}-${APPIMAGE_ARCH}.AppImage ${APP_NAME}_${VERSION}_${APPIMAGE_ARCH}.AppImage
echo "✅ AppImage created: ${APP_NAME}_${VERSION}_${APPIMAGE_ARCH}.AppImage"

echo "🎉 Build complete! Packages created:"
echo "  • Debian package : ${APP_NAME}_${VERSION}_${ARCH}.deb"
echo "  • AppImage       : ${APP_NAME}_${VERSION}_${APPIMAGE_ARCH}.AppImage"
