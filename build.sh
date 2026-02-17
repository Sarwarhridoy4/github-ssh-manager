#!/usr/bin/env bash
# =====================================================================
# GitHub SSH Manager - Build and Packaging Script (Linux)
# Outputs: Debian (.deb) + AppImage
# =====================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

timestamp() { date +"%H:%M:%S"; }
log_info() { echo -e "${CYAN}[$(timestamp)] INFO ${NC}$1"; }
log_success() { echo -e "${GREEN}[$(timestamp)] OK   ${NC}$1"; }
log_warning() { echo -e "${YELLOW}[$(timestamp)] WARN ${NC}$1"; }
log_error() { echo -e "${RED}[$(timestamp)] ERR  ${NC}$1"; }
log_phase() { echo -e "\n${BOLD}${MAGENTA}==> $1${NC}"; }

print_banner() {
    echo -e "${BOLD}${BLUE}"
    echo "=============================================================="
    echo "  G I T H U B   S S H   M A N A G E R   B U I L D   S Y S T E M"
    echo "=============================================================="
    echo -e "${NC}"
}

die() {
    log_error "$1"
    exit 1
}

require_cmd() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 || die "Missing required command: $cmd"
}

usage() {
    cat <<EOF
Usage: ./build.sh [options] [version]

Options:
  -v, --version <version>  Override version from FyneApp.toml
  -b, --build <number>     Override build number from FyneApp.toml
  -h, --help               Show this help

Positional:
  version                  Backward-compatible version override
EOF
}

OVERRIDE_VERSION=""
OVERRIDE_BUILD_NUMBER=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        -v|--version)
            [ "${2:-}" ] || die "Missing value for $1"
            OVERRIDE_VERSION="$2"
            shift 2
            ;;
        -b|--build)
            [ "${2:-}" ] || die "Missing value for $1"
            OVERRIDE_BUILD_NUMBER="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            if [ -z "$OVERRIDE_VERSION" ]; then
                OVERRIDE_VERSION="$1"
                shift
            else
                die "Unknown argument: $1"
            fi
            ;;
    esac
done

# toml_get <section> <key>
# section "" means top-level keys.
toml_get() {
    local section="$1"
    local key="$2"

    awk -v target_section="$section" -v target_key="$key" '
        BEGIN {
            cur_section = ""
        }
        /^[[:space:]]*#/ || /^[[:space:]]*;/ || /^[[:space:]]*$/ { next }
        /^[[:space:]]*\[/ {
            sec = $0
            gsub(/^[[:space:]]*\[/, "", sec)
            gsub(/\][[:space:]]*$/, "", sec)
            gsub(/[[:space:]]+/, "", sec)
            cur_section = sec
            next
        }
        {
            line = $0
            split(line, kv, "=")
            k = kv[1]
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)

            if (tolower(k) == tolower(target_key) && tolower(cur_section) == tolower(target_section)) {
                sub(/^[^=]*=/, "", line)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
                if (line ~ /^".*"$/) {
                    sub(/^"/, "", line)
                    sub(/"$/, "", line)
                }
                print line
                exit
            }
        }
    ' FyneApp.toml
}

print_banner
log_phase "Loading metadata"
log_info "Reading FyneApp.toml..."
[ -f FyneApp.toml ] || die "FyneApp.toml not found"

APP_NAME_DISPLAY="$(toml_get "Details" "Name")"
APP_ID="$(toml_get "Details" "ID")"
VERSION="$(toml_get "Details" "Version")"
BUILD_NUMBER="$(toml_get "Details" "Build")"
ICON_PATH="$(toml_get "Details" "Icon")"
WEBSITE="$(toml_get "" "Website")"
DESCRIPTION="$(toml_get "LinuxAndBSD" "Comment")"
GENERIC_NAME="$(toml_get "LinuxAndBSD" "GenericName")"

APP_NAME_DISPLAY="${APP_NAME_DISPLAY:-GitHub SSH Manager}"
APP_ID="${APP_ID:-com.sarwarhridoy4.github-ssh-manager}"
VERSION="${VERSION:-0.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
DESCRIPTION="${DESCRIPTION:-Manage SSH keys for GitHub accounts}"
GENERIC_NAME="${GENERIC_NAME:-SSH Key Manager}"
WEBSITE="${WEBSITE:-https://github.com/Sarwarhridoy4/github-ssh-manager}"
ICON_PATH="${ICON_PATH:-icon.png}"
EMAIL="sarwarhridoy4@gmail.com"
AUTHOR="Sarwar Hossain"
LICENSE_NAME="MIT"

if [ -n "$OVERRIDE_VERSION" ]; then
    VERSION="$OVERRIDE_VERSION"
fi
if [ -n "$OVERRIDE_BUILD_NUMBER" ]; then
    BUILD_NUMBER="$OVERRIDE_BUILD_NUMBER"
fi
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || die "Build number must be numeric, got: $BUILD_NUMBER"

# Resolve icon path robustly
if [ ! -f "$ICON_PATH" ]; then
    if [ -f "assets/icon.png" ]; then
        ICON_PATH="assets/icon.png"
    elif [ -f "icon.png" ]; then
        ICON_PATH="icon.png"
    else
        die "Icon file not found (checked: $ICON_PATH, assets/icon.png, icon.png)"
    fi
fi

# Debian package/binary-safe slug
APP_SLUG="$(echo "$APP_NAME_DISPLAY" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9.+-')"
[ -n "$APP_SLUG" ] || APP_SLUG="github-ssh-manager"

if git rev-parse --git-dir >/dev/null 2>&1; then
    GIT_HASH="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
else
    GIT_HASH="unknown"
fi

ARCH_RAW="$(uname -m)"
case "$ARCH_RAW" in
    x86_64) DEB_ARCH="amd64"; APPIMAGE_ARCH="x86_64" ;;
    aarch64) DEB_ARCH="arm64"; APPIMAGE_ARCH="aarch64" ;;
    armv7l) DEB_ARCH="armhf"; APPIMAGE_ARCH="armhf" ;;
    i386|i686) DEB_ARCH="i386"; APPIMAGE_ARCH="i686" ;;
    *) DEB_ARCH="$ARCH_RAW"; APPIMAGE_ARCH="$ARCH_RAW" ;;
esac

log_success "Metadata loaded"
echo "  Name        : $APP_NAME_DISPLAY"
echo "  Slug        : $APP_SLUG"
echo "  ID          : $APP_ID"
echo "  Version     : $VERSION"
echo "  Build       : $BUILD_NUMBER"
echo "  Architecture: $DEB_ARCH / $APPIMAGE_ARCH"
echo "  Icon        : $ICON_PATH"

log_phase "Validating toolchain"
require_cmd go
require_cmd fyne
require_cmd dpkg-deb
require_cmd convert
require_cmd tar

mkdir -p build dist
rm -rf build/* dist/* "${APP_SLUG}-deb" "${APP_SLUG}.AppDir" "${APP_SLUG}.tar.gz" "${APP_SLUG}.tar.xz"

log_phase "Resolving dependencies"
go mod tidy
go mod download

log_phase "Packaging Linux binary"
fyne package -os linux -icon "$ICON_PATH" -name "$APP_SLUG" -app-version "$VERSION" -app-build "$BUILD_NUMBER" -release

# Fyne docs indicate .tar.gz for Linux packaging
if [ -f "${APP_SLUG}.tar.gz" ]; then
    tar -xzf "${APP_SLUG}.tar.gz"
elif [ -f "${APP_SLUG}.tar.xz" ]; then
    # Compatibility fallback for older/newer tool behavior
    tar -xf "${APP_SLUG}.tar.xz"
else
    die "Could not find packaged tar archive from fyne package"
fi

if [ -f "usr/local/bin/${APP_SLUG}" ]; then
    mv "usr/local/bin/${APP_SLUG}" "build/${APP_SLUG}"
    rm -rf usr "${APP_SLUG}.tar.gz" "${APP_SLUG}.tar.xz"
else
    die "Packaged binary not found at usr/local/bin/${APP_SLUG}"
fi

chmod +x "build/${APP_SLUG}"
log_success "Binary ready: build/${APP_SLUG}"

# ---------------------------------------------------------------------
# Debian package
# ---------------------------------------------------------------------
log_phase "Building Debian package"
DEB_DIR="${APP_SLUG}-deb"
mkdir -p "${DEB_DIR}/DEBIAN"
mkdir -p "${DEB_DIR}/usr/bin"
mkdir -p "${DEB_DIR}/usr/share/applications"
mkdir -p "${DEB_DIR}/usr/share/pixmaps"
mkdir -p "${DEB_DIR}/usr/share/icons/hicolor"
mkdir -p "${DEB_DIR}/usr/share/doc/${APP_SLUG}"

cp "build/${APP_SLUG}" "${DEB_DIR}/usr/bin/${APP_SLUG}"
chmod 755 "${DEB_DIR}/usr/bin/${APP_SLUG}"

for size in 16 22 24 32 48 64 128 256 512; do
    icon_dir="${DEB_DIR}/usr/share/icons/hicolor/${size}x${size}/apps"
    mkdir -p "$icon_dir"
    convert "$ICON_PATH" -resize "${size}x${size}" "$icon_dir/${APP_SLUG}.png"
done
cp "$ICON_PATH" "${DEB_DIR}/usr/share/pixmaps/${APP_SLUG}.png"

cat > "${DEB_DIR}/usr/share/applications/${APP_SLUG}.desktop" <<DESKTOP
[Desktop Entry]
Version=1.0
Type=Application
Name=${APP_NAME_DISPLAY}
GenericName=${GENERIC_NAME}
Comment=${DESCRIPTION}
Exec=${APP_SLUG}
Icon=${APP_SLUG}
Terminal=false
Categories=Development;Utility;
Keywords=github;ssh;git;key;manager;
StartupNotify=true
StartupWMClass=${APP_SLUG}
DESKTOP

installed_size="$(du -sk "${DEB_DIR}/usr" | cut -f1)"

cat > "${DEB_DIR}/DEBIAN/control" <<CONTROL
Package: ${APP_SLUG}
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: ${DEB_ARCH}
Installed-Size: ${installed_size}
Depends: libc6 (>= 2.31), libgl1, libx11-6, libxcursor1, libxrandr2, libxinerama1, libxi6, libxxf86vm1
Maintainer: ${AUTHOR} <${EMAIL}>
Homepage: ${WEBSITE}
Description: ${DESCRIPTION}
 GitHub SSH Manager is a cross-platform GUI tool built with Go and Fyne
 for managing multiple GitHub SSH identities.
CONTROL

cat > "${DEB_DIR}/usr/share/doc/${APP_SLUG}/copyright" <<COPYRIGHT
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: ${APP_SLUG}
Upstream-Contact: ${AUTHOR} <${EMAIL}>
Source: ${WEBSITE}

Files: *
Copyright: $(date +%Y) ${AUTHOR}
License: ${LICENSE_NAME}
COPYRIGHT

cat > "${DEB_DIR}/usr/share/doc/${APP_SLUG}/changelog" <<CHANGELOG
${APP_SLUG} (${VERSION}) unstable; urgency=medium

  * Version ${VERSION} release
  * Built from commit ${GIT_HASH}

 -- ${AUTHOR} <${EMAIL}>  $(date -R)
CHANGELOG

gzip -9 -n "${DEB_DIR}/usr/share/doc/${APP_SLUG}/changelog"

dpkg-deb --build --root-owner-group "${DEB_DIR}"
mv "${DEB_DIR}.deb" "dist/${APP_SLUG}_${VERSION}_${DEB_ARCH}.deb"
log_success "Debian package: dist/${APP_SLUG}_${VERSION}_${DEB_ARCH}.deb"

# ---------------------------------------------------------------------
# AppImage
# ---------------------------------------------------------------------
log_phase "Building AppImage"
APPDIR="${APP_SLUG}.AppDir"
mkdir -p "${APPDIR}/usr/bin"
mkdir -p "${APPDIR}/usr/share/applications"
mkdir -p "${APPDIR}/usr/share/icons/hicolor"
mkdir -p "${APPDIR}/usr/share/metainfo"

cp "build/${APP_SLUG}" "${APPDIR}/usr/bin/${APP_SLUG}"
chmod 755 "${APPDIR}/usr/bin/${APP_SLUG}"

cat > "${APPDIR}/AppRun" <<APPRUN
#!/usr/bin/env bash
SELF="\$(readlink -f "\$0")"
HERE="\${SELF%/*}"
exec "\${HERE}/usr/bin/${APP_SLUG}" "\$@"
APPRUN
chmod 755 "${APPDIR}/AppRun"

for size in 16 22 24 32 48 64 128 256 512; do
    icon_dir="${APPDIR}/usr/share/icons/hicolor/${size}x${size}/apps"
    mkdir -p "$icon_dir"
    convert "$ICON_PATH" -resize "${size}x${size}" "$icon_dir/${APP_SLUG}.png"
done
convert "$ICON_PATH" -resize 256x256 "${APPDIR}/${APP_SLUG}.png"
cp "${APPDIR}/${APP_SLUG}.png" "${APPDIR}/.DirIcon"

cat > "${APPDIR}/${APP_SLUG}.desktop" <<DESKTOP
[Desktop Entry]
Version=1.0
Type=Application
Name=${APP_NAME_DISPLAY}
GenericName=${GENERIC_NAME}
Comment=${DESCRIPTION}
Exec=${APP_SLUG}
Icon=${APP_SLUG}
Terminal=false
Categories=Development;Utility;
Keywords=github;ssh;git;key;manager;
StartupNotify=true
X-AppImage-Version=${VERSION}
X-AppImage-BuildId=${GIT_HASH}
DESKTOP

cp "${APPDIR}/${APP_SLUG}.desktop" "${APPDIR}/usr/share/applications/"

cat > "${APPDIR}/usr/share/metainfo/${APP_ID}.appdata.xml" <<APPDATA
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>${APP_ID}</id>
  <metadata_license>CC0-1.0</metadata_license>
  <project_license>${LICENSE_NAME}</project_license>
  <name>${APP_NAME_DISPLAY}</name>
  <summary>${DESCRIPTION}</summary>
  <description>
    <p>GitHub SSH Manager is a cross-platform GUI tool for managing multiple GitHub SSH keys.</p>
  </description>
  <categories>
    <category>Utility</category>
    <category>Development</category>
  </categories>
  <url type="homepage">${WEBSITE}</url>
  <developer_name>${AUTHOR}</developer_name>
</component>
APPDATA

APPIMAGETOOL_BIN=""
if command -v appimagetool >/dev/null 2>&1; then
    APPIMAGETOOL_BIN="$(command -v appimagetool)"
elif [ -x "build/tools/appimagetool" ]; then
    APPIMAGETOOL_BIN="build/tools/appimagetool"
else
    mkdir -p build/tools
    if command -v wget >/dev/null 2>&1; then
        log_warning "appimagetool not found; downloading local copy to build/tools/"
        wget -q --show-progress \
            "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-${APPIMAGE_ARCH}.AppImage" \
            -O build/tools/appimagetool
        chmod +x build/tools/appimagetool
        APPIMAGETOOL_BIN="build/tools/appimagetool"
    else
        die "appimagetool not found and wget is unavailable. Install appimagetool or wget."
    fi
fi

ARCH="${APPIMAGE_ARCH}" "$APPIMAGETOOL_BIN" --comp gzip "${APPDIR}" "dist/${APP_SLUG}-${VERSION}-${APPIMAGE_ARCH}.AppImage"
chmod +x "dist/${APP_SLUG}-${VERSION}-${APPIMAGE_ARCH}.AppImage"
log_success "AppImage: dist/${APP_SLUG}-${VERSION}-${APPIMAGE_ARCH}.AppImage"

log_phase "Generating checksums"
(
    cd dist
    sha256sum *.deb *.AppImage > SHA256SUMS
    md5sum *.deb *.AppImage > MD5SUMS
)

echo
log_phase "Done"
log_success "Build complete"
ls -lh dist/*.deb dist/*.AppImage
