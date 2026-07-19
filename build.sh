#!/usr/bin/env bash
# =====================================================================
# GitHub SSH Manager - Build and Packaging Script (Linux)
# Outputs: .deb + AppImage + .tar.gz
# Uses official fyne package workflow with robust prefix detection.
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

# ---------------------------------------------------------------------
# Dependency auto-install
# ---------------------------------------------------------------------

detect_pkg_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "apt"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    elif command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    elif command -v zypper >/dev/null 2>&1; then
        echo "zypper"
    elif command -v apk >/dev/null 2>&1; then
        echo "apk"
    else
        echo ""
    fi
}

install_pkgs() {
    local manager="$1"
    shift
    case "$manager" in
        apt)
            sudo apt-get update -y
            sudo apt-get install -y "$@"
            ;;
        dnf)
            sudo dnf install -y "$@"
            ;;
        yum)
            sudo yum install -y "$@"
            ;;
        pacman)
            sudo pacman -Sy --noconfirm "$@"
            ;;
        zypper)
            sudo zypper --non-interactive install "$@"
            ;;
        apk)
            sudo apk add --no-cache "$@"
            ;;
        *)
            return 1
            ;;
    esac
}

ensure_cmd() {
    local cmd="$1"
    local pkg="${2:-}"
    if command -v "$cmd" >/dev/null 2>&1; then
        return 0
    fi

    local manager
    manager="$(detect_pkg_manager)"
    if [ -z "$manager" ]; then
        die "Missing required command: $cmd (no supported package manager found)"
    fi

    log_warning "Missing required command: $cmd. Attempting to install via ${manager}..."
    if [ -n "$pkg" ]; then
        install_pkgs "$manager" "$pkg" || die "Failed to install package: $pkg"
    else
        install_pkgs "$manager" "$cmd" || die "Failed to install command: $cmd"
    fi

    command -v "$cmd" >/dev/null 2>&1 || die "Missing required command after install: $cmd"
    log_success "Installed: $cmd"
}

try_install_cmd() {
    local cmd="$1"
    local pkg="${2:-}"
    if command -v "$cmd" >/dev/null 2>&1; then
        return 0
    fi

    local manager
    manager="$(detect_pkg_manager)"
    if [ -z "$manager" ]; then
        return 1
    fi

    log_warning "Attempting to install ${cmd} via ${manager}..."
    if [ -n "$pkg" ]; then
        install_pkgs "$manager" "$pkg" || return 1
    else
        install_pkgs "$manager" "$cmd" || return 1
    fi

    command -v "$cmd" >/dev/null 2>&1
}

ensure_fyne_cli() {
    if command -v fyne >/dev/null 2>&1; then
        return 0
    fi

    log_warning "Fyne CLI not found. Installing via 'go install'..."
    GOBIN="${GOBIN:-$(go env GOPATH)/bin}"
    go install fyne.io/tools/cmd/fyne@latest || die "Failed to install fyne CLI"
    export PATH="$GOBIN:$PATH"
    command -v fyne >/dev/null 2>&1 || die "fyne not found after install"
    log_success "Installed: fyne"
}

ensure_appimagetool() {
    local bin_path="$1"

    if "$bin_path" --version >/dev/null 2>&1; then
        return 0
    fi

    log_warning "appimagetool could not run (possibly missing FUSE). Trying --appimage-extract fallback..."
    local tool_dir
    local tool_base
    tool_dir="$(dirname "$bin_path")"
    tool_base="$(basename "$bin_path")"

    if (cd "$tool_dir" && "./$tool_base" --appimage-extract >/dev/null 2>&1); then
        if [ -x "${tool_dir}/squashfs-root/AppRun" ]; then
            APPIMAGETOOL_BIN="${tool_dir}/squashfs-root/AppRun"
            return 0
        fi
        if [ -x "${tool_dir}/squashfs-root/appimagetool" ]; then
            APPIMAGETOOL_BIN="${tool_dir}/squashfs-root/appimagetool"
            return 0
        fi
    fi

    return 1
}

download_appimagetool() {
    local arch="$1"
    mkdir -p build/tools

    if command -v wget >/dev/null 2>&1; then
        log_warning "Downloading appimagetool to build/tools/..."
        wget -q --show-progress \
            "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-${arch}.AppImage" \
            -O build/tools/appimagetool
    elif command -v curl >/dev/null 2>&1; then
        log_warning "Downloading appimagetool to build/tools/..."
        curl -fsSL \
            "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-${arch}.AppImage" \
            -o build/tools/appimagetool
    else
        log_warning "Neither wget nor curl found; attempting to install one..."
        if ! try_install_cmd wget wget; then
            try_install_cmd curl curl || die "Could not install wget or curl"
        fi
        if command -v wget >/dev/null 2>&1; then
            log_warning "Downloading appimagetool to build/tools/..."
            wget -q --show-progress \
                "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-${arch}.AppImage" \
                -O build/tools/appimagetool
        elif command -v curl >/dev/null 2>&1; then
            log_warning "Downloading appimagetool to build/tools/..."
            curl -fsSL \
                "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-${arch}.AppImage" \
                -o build/tools/appimagetool
        else
            die "appimagetool not found and neither wget nor curl is available."
        fi
    fi

    chmod +x build/tools/appimagetool
}

# ---------------------------------------------------------------------
# Metadata from FyneApp.toml
# ---------------------------------------------------------------------

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

print_banner
log_phase "Loading metadata"
[ -f FyneApp.toml ] || die "FyneApp.toml not found"

# Fallback: parse FyneApp.toml manually
toml_get() {
    local section="$1"
    local key="$2"

    awk -v target_section="$section" -v target_key="$key" '
        BEGIN { cur_section = "" }
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

# Resolve icon path
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

# ---------------------------------------------------------------------
# Auto-install build dependencies
# ---------------------------------------------------------------------

log_phase "Validating toolchain"
ensure_cmd go golang
ensure_cmd tar tar
ensure_cmd dpkg-deb dpkg
ensure_cmd convert imagemagick
ensure_fyne_cli

log_phase "Preparing workspace"
DIST_DIR="dist"
WORK_DIR="${DIST_DIR}/work"
FYNE_ROOT="${WORK_DIR}/fyne-root"
DEB_ROOT="${WORK_DIR}/deb-root"
APPDIR="${WORK_DIR}/${APP_SLUG}.AppDir"
TARBALL_ROOT="${WORK_DIR}/tarball-root"

mkdir -p "${DIST_DIR}" "${WORK_DIR}"
rm -rf "${FYNE_ROOT}" "${DEB_ROOT}" "${APPDIR}" "${TARBALL_ROOT}"
rm -f "${DIST_DIR}/${APP_SLUG}_${VERSION}_${DEB_ARCH}.deb" \
       "${DIST_DIR}/${APP_SLUG}-${VERSION}-${APPIMAGE_ARCH}.AppImage" \
       "${DIST_DIR}/${APP_SLUG}-${VERSION}-${DEB_ARCH}.tar.gz" \
       "${APP_SLUG}.tar.xz" "${APP_SLUG}.tar.gz"

log_phase "Resolving Go dependencies"
go mod tidy
go mod download

# ---------------------------------------------------------------------
# Fyne package (official approach)
# ---------------------------------------------------------------------

log_phase "Packaging with Fyne (official)"
fyne package -os linux \
    -icon "$ICON_PATH" \
    -name "$APP_SLUG" \
    -app-id "$APP_ID" \
    -app-version "$VERSION" \
    -app-build "$BUILD_NUMBER" \
    -release

# ---------------------------------------------------------------------
# Extract Fyne package into WORK_DIR with prefix detection
# ---------------------------------------------------------------------

log_phase "Extracting Fyne package"
mkdir -p "${FYNE_ROOT}"

if [ -f "${APP_SLUG}.tar.gz" ]; then
    tar -xzf "${APP_SLUG}.tar.gz" -C "${FYNE_ROOT}"
elif [ -f "${APP_SLUG}.tar.xz" ]; then
    tar -xf "${APP_SLUG}.tar.xz" -C "${FYNE_ROOT}"
else
    die "Could not find packaged tar archive from fyne package"
fi

# Detect prefix
if [ -d "${FYNE_ROOT}/usr/local" ]; then
    PREFIX_REL="usr/local"
elif [ -d "${FYNE_ROOT}/usr" ]; then
    PREFIX_REL="usr"
else
    NESTED_USR=$(find "${FYNE_ROOT}" -maxdepth 3 -type d -name "usr" | head -n 1 || true)
    if [ -z "${NESTED_USR}" ]; then
        die "No usr directory found after fyne package extraction"
    fi
    NESTED_DIR=$(dirname "${NESTED_USR}")
    PREFIX_REL="${NESTED_DIR#${FYNE_ROOT}/}/usr"
    if [ -d "${FYNE_ROOT}/${PREFIX_REL}/local" ]; then
        PREFIX_REL="${PREFIX_REL}/local"
    fi
fi

log_info "Detected Fyne prefix: ${PREFIX_REL}"

# Normalize directory structure
USR_NORMALIZED="${WORK_DIR}/usr-normalized"
mkdir -p "${USR_NORMALIZED}"
cp -a "${FYNE_ROOT}/${PREFIX_REL}/." "${USR_NORMALIZED}/"

BIN_DIR="${USR_NORMALIZED}/bin"
APPS_DIR="${USR_NORMALIZED}/share/applications"
PIXMAPS_DIR="${USR_NORMALIZED}/share/pixmaps"

# Normalize binary name
FOUND_BIN=$(find "${BIN_DIR}" -maxdepth 1 -type f -executable | head -n 1 || true)
if [ -z "${FOUND_BIN}" ]; then
    die "Packaged binary not found under ${BIN_DIR}"
fi
if [ "$(basename "${FOUND_BIN}")" != "${APP_SLUG}" ]; then
    mv "${FOUND_BIN}" "${BIN_DIR}/${APP_SLUG}"
fi
BIN_PATH="${BIN_DIR}/${APP_SLUG}"
chmod +x "${BIN_PATH}"
log_success "Binary ready: ${BIN_PATH}"

# Find desktop and icon files
DESKTOP_PATH=$(find "${APPS_DIR}" -name '*.desktop' | head -n 1 || true)
ICON_PATH=$(find "${PIXMAPS_DIR}" -type f | head -n 1 || true)

if [ -z "${DESKTOP_PATH}" ]; then
    die "Desktop file not found in Fyne package output"
fi
if [ -z "${ICON_PATH}" ]; then
    die "Icon file not found in Fyne package output"
fi

# Normalize desktop and icon filenames
DESKTOP_DIR="$(dirname "${DESKTOP_PATH}")"
DESKTOP_NORM="${DESKTOP_DIR}/${APP_ID}.desktop"
if [ "$(basename "${DESKTOP_PATH}")" != "${APP_ID}.desktop" ]; then
    mv "${DESKTOP_PATH}" "${DESKTOP_NORM}"
    DESKTOP_PATH="${DESKTOP_NORM}"
fi

ICON_DIR="$(dirname "${ICON_PATH}")"
ICON_EXT="${ICON_PATH##*.}"
ICON_NORM="${ICON_DIR}/${APP_ID}.${ICON_EXT}"
if [ "$(basename "${ICON_PATH}")" != "${APP_ID}.${ICON_EXT}" ]; then
    mv "${ICON_PATH}" "${ICON_NORM}"
    ICON_PATH="${ICON_NORM}"
fi

# Update desktop file
sed -i -E "s|^Exec=.*|Exec=${APP_SLUG}|" "${DESKTOP_PATH}"
sed -i -E "s|^Icon=.*|Icon=${APP_ID}|" "${DESKTOP_PATH}"
sed -i -E "s|^Name=.*|Name=${APP_NAME_DISPLAY}|" "${DESKTOP_PATH}"
grep -q '^StartupWMClass=' "${DESKTOP_PATH}" || echo "StartupWMClass=${APP_SLUG}" >> "${DESKTOP_PATH}"
grep -q '^Categories=' "${DESKTOP_PATH}" || echo "Categories=Development;Utility;" >> "${DESKTOP_PATH}"
grep -q '^Keywords=' "${DESKTOP_PATH}" || echo "Keywords=github;ssh;git;key;manager;" >> "${DESKTOP_PATH}"

# Install icon in hicolor at all standard sizes
HICOLOR_DIR="${USR_NORMALIZED}/share/icons/hicolor"
for size in 16 22 24 32 48 64 128 256 512; do
    icon_dir="${HICOLOR_DIR}/${size}x${size}/apps"
    mkdir -p "$icon_dir"
    convert "$ICON_PATH" -resize "${size}x${size}" "$icon_dir/${APP_SLUG}.png"
done
cp "$ICON_PATH" "${HICOLOR_DIR}/256x256/apps/${APP_SLUG}.png"

# ---------------------------------------------------------------------
# Tarball
# ---------------------------------------------------------------------

log_phase "Building tarball"
TARBALL_ROOT="${WORK_DIR}/tarball-root"
rm -rf "${TARBALL_ROOT}"
mkdir -p "${TARBALL_ROOT}/${APP_SLUG}-${VERSION}-linux-${DEB_ARCH}"

cp -a "${USR_NORMALIZED}/." "${TARBALL_ROOT}/${APP_SLUG}-${VERSION}-linux-${DEB_ARCH}/"

TARBALL="dist/${APP_SLUG}-${VERSION}-${DEB_ARCH}.tar.gz"
(
    cd "${TARBALL_ROOT}"
    tar -czf "../../${TARBALL}" "${APP_SLUG}-${VERSION}-linux-${DEB_ARCH}"
)
log_success "Tarball: ${TARBALL}"

# ---------------------------------------------------------------------
# Debian package
# ---------------------------------------------------------------------

log_phase "Building Debian package"
DEB_DIR="${WORK_DIR}/deb-root"
rm -rf "${DEB_DIR}"
mkdir -p "${DEB_DIR}/DEBIAN"
mkdir -p "${DEB_DIR}/usr/bin"
mkdir -p "${DEB_DIR}/usr/share/applications"
mkdir -p "${DEB_DIR}/usr/share/pixmaps"
mkdir -p "${DEB_DIR}/usr/share/icons/hicolor"
mkdir -p "${DEB_DIR}/usr/share/doc/${APP_SLUG}"

cp "${BIN_PATH}" "${DEB_DIR}/usr/bin/${APP_SLUG}"
chmod 755 "${DEB_DIR}/usr/bin/${APP_SLUG}"

for size in 16 22 24 32 48 64 128 256 512; do
    icon_dir="${DEB_DIR}/usr/share/icons/hicolor/${size}x${size}/apps"
    mkdir -p "$icon_dir"
    convert "$ICON_PATH" -resize "${size}x${size}" "$icon_dir/${APP_SLUG}.png"
done
cp "$ICON_PATH" "${DEB_DIR}/usr/share/pixmaps/${APP_SLUG}.png"

cat > "${DEB_DIR}/usr/share/applications/${APP_ID}.desktop" <<DESKTOP
[Desktop Entry]
Version=1.0
Type=Application
Name=${APP_NAME_DISPLAY}
GenericName=${GENERIC_NAME}
Comment=${DESCRIPTION}
Exec=${APP_SLUG}
Icon=${APP_ID}
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
mkdir -p "${APPDIR}/usr/bin"
mkdir -p "${APPDIR}/usr/share/applications"
mkdir -p "${APPDIR}/usr/share/icons/hicolor"
mkdir -p "${APPDIR}/usr/share/metainfo"

cp "${BIN_PATH}" "${APPDIR}/usr/bin/${APP_SLUG}"
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
    download_appimagetool "${APPIMAGE_ARCH}"
    APPIMAGETOOL_BIN="build/tools/appimagetool"
fi

if ! ensure_appimagetool "$APPIMAGETOOL_BIN"; then
    die "appimagetool is not runnable. Install FUSE (libfuse.so.2) or run build on a host with FUSE support."
fi

ARCH="${APPIMAGE_ARCH}" "$APPIMAGETOOL_BIN" --comp gzip "${APPDIR}" "dist/${APP_SLUG}-${VERSION}-${APPIMAGE_ARCH}.AppImage"
chmod +x "dist/${APP_SLUG}-${VERSION}-${APPIMAGE_ARCH}.AppImage"
log_success "AppImage: dist/${APP_SLUG}-${VERSION}-${APPIMAGE_ARCH}.AppImage"

# ---------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------

log_phase "Cleanup"
rm -rf "${WORK_DIR}" "${APP_SLUG}.tar.xz" "${APP_SLUG}.tar.gz"

# ---------------------------------------------------------------------
# Checksums
# ---------------------------------------------------------------------

log_phase "Generating checksums"
(
    cd dist
    sha256sum *.deb *.AppImage *.tar.gz > SHA256SUMS
    md5sum *.deb *.AppImage *.tar.gz > MD5SUMS
)

echo
log_phase "Done"
log_success "Build complete"
ls -lh dist/
