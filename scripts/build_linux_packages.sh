#!/usr/bin/env bash
# Packs the Linux release bundle (flutter build linux --release) into a
# tarball and an AppImage – used by the release workflow
# (specs/RELEASE.md).
#
#   scripts/build_linux_packages.sh <label> <arch>
#
# <label>: the tag, e.g. v8.0.0-beta.1; <arch>: x64 or arm64.
# Results in build/dist/:
#   TrytonFlutterClient-<label>-linux-<arch>.tar.gz   bundle, LICENSE, COPYRIGHT
#   TrytonFlutterClient-<label>-linux-<arch>.AppImage AppDir with the bundle
set -euo pipefail

LABEL="${1:?usage: $0 <label> <x64|arm64>}"
ARCH="${2:?usage: $0 <label> <x64|arm64>}"
cd "$(dirname "$0")/.."

APP_NAME="Tryton Flutter Client"
BINARY="tryton_flutter_client"
APP_ID="de.jankstar.tryton-flutter-client"
BUNDLE="build/linux/${ARCH}/release/bundle"
DIST="build/dist"
BASE="TrytonFlutterClient-${LABEL}-linux-${ARCH}"
# 256 px of assets/app_icon.png (flutter_launcher_icons)
ICON="macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png"

# appimagetool of the official release, checked by its SHA-256
APPIMAGETOOL_VERSION="1.9.1"
case "$ARCH" in
  x64)
    TOOL_ARCH="x86_64"
    TOOL_SHA256="ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0"
    ;;
  arm64)
    TOOL_ARCH="aarch64"
    TOOL_SHA256="f0837e7448a0c1e4e650a93bb3e85802546e60654ef287576f46c71c126a9158"
    ;;
  *) echo "error: unknown arch $ARCH" >&2; exit 1 ;;
esac

[[ -x "$BUNDLE/$BINARY" ]] || { echo "error: $BUNDLE/$BINARY not found" >&2; exit 1; }
mkdir -p "$DIST"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ── tarball ───────────────────────────────────────────────────────────────
mkdir -p "$WORK/$BASE"
cp -a "$BUNDLE/." "$WORK/$BASE/"
cp LICENSE COPYRIGHT "$WORK/$BASE/"
chmod 644 "$WORK/$BASE/LICENSE" "$WORK/$BASE/COPYRIGHT"
tar -C "$WORK" -czf "$DIST/$BASE.tar.gz" "$BASE"
echo "tarball: $DIST/$BASE.tar.gz"

# ── AppImage ──────────────────────────────────────────────────────────────
APPDIR="$WORK/AppDir"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share/applications" \
  "$APPDIR/usr/share/icons/hicolor/256x256/apps"
cp -a "$BUNDLE/." "$APPDIR/usr/bin/"
cp LICENSE COPYRIGHT "$APPDIR/usr/bin/"

cat > "$APPDIR/$APP_ID.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=$APP_NAME
Comment=Client for the Tryton ERP system
Exec=$BINARY %u
Icon=$APP_ID
Categories=Office;
Terminal=false
StartupWMClass=$BINARY
DESKTOP
cp "$APPDIR/$APP_ID.desktop" "$APPDIR/usr/share/applications/"
cp "$ICON" "$APPDIR/$APP_ID.png"
cp "$ICON" "$APPDIR/usr/share/icons/hicolor/256x256/apps/$APP_ID.png"

cat > "$APPDIR/AppRun" <<'APPRUN'
#!/bin/sh
# the bundle keeps its lib/ and data/ next to the executable
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/bin/tryton_flutter_client" "$@"
APPRUN
chmod 755 "$APPDIR/AppRun"

TOOL="$WORK/appimagetool-${TOOL_ARCH}.AppImage"
curl -fsSL -o "$TOOL" \
  "https://github.com/AppImage/appimagetool/releases/download/${APPIMAGETOOL_VERSION}/appimagetool-${TOOL_ARCH}.AppImage"
echo "${TOOL_SHA256}  ${TOOL}" | sha256sum -c -
chmod 755 "$TOOL"

# runners have no FUSE: appimagetool extracts and runs itself
ARCH="$TOOL_ARCH" APPIMAGE_EXTRACT_AND_RUN=1 \
  "$TOOL" --no-appstream "$APPDIR" "$DIST/$BASE.AppImage"
echo "AppImage: $DIST/$BASE.AppImage"
