#!/usr/bin/env bash
# Builds the macOS app and packs it into a DMG (app, link to
# /Applications, LICENSE, COPYRIGHT) – used by the release workflow and
# locally (specs/RELEASE.md).
#
#   scripts/build_macos_dmg.sh <label>
#
# <label>: the tag, e.g. v8.0.0-beta.1 → build/dist/TrytonFlutterClient-
# v8.0.0-beta.1-macos.dmg. Optional environment:
#   BUILD_NAME, BUILD_NUMBER   version of the build (default: pubspec.yaml)
#   TRYTON_SERIES              server series, --dart-define (default: code)
#   APP_LABEL                  release label for About (e.g. 8.0.0-beta.1)
#   SKIP_BUILD=1               package an existing release build
#   MACOS_SIGN_IDENTITY        signing identity: the SHA-1 hash of the
#                              certificate (release workflow, keeps the
#                              owner's name out of the log) or its name
#                              "Developer ID Application: …" – signs app and DMG
#   APPLE_ID, APPLE_APP_PASSWORD, APPLE_TEAM_ID
#                              with the identity: notarize and staple the DMG
set -euo pipefail

LABEL="${1:?usage: $0 <label, e.g. v8.0.0-beta.1>}"
cd "$(dirname "$0")/.."

APP_NAME="Tryton Flutter Client"
APP="build/macos/Build/Products/Release/${APP_NAME}.app"
DIST="build/dist"
DMG="${DIST}/TrytonFlutterClient-${LABEL}-macos.dmg"
ENTITLEMENTS="macos/Runner/Release.entitlements"

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  args=(build macos --release)
  # the version also as dart-define: shown in the About dialog
  [[ -n "${BUILD_NAME:-}" ]] && args+=(--build-name "$BUILD_NAME" "--dart-define=APP_VERSION=${BUILD_NAME}")
  [[ -n "${BUILD_NUMBER:-}" ]] && args+=(--build-number "$BUILD_NUMBER" "--dart-define=APP_BUILD=${BUILD_NUMBER}")
  [[ -n "${TRYTON_SERIES:-}" ]] && args+=("--dart-define=TRYTON_SERIES=${TRYTON_SERIES}")
  # the release label shown in About (8.0.0-beta.1)
  [[ -n "${APP_LABEL:-}" ]] && args+=("--dart-define=APP_LABEL=${APP_LABEL}")
  flutter "${args[@]}"
fi
[[ -d "$APP" ]] || { echo "error: $APP not found" >&2; exit 1; }

IDENTITY="${MACOS_SIGN_IDENTITY:-}"
if [[ -n "$IDENTITY" ]]; then
  # (the identity is not printed: its name is the owner's name)
  echo "Signing the app"
  codesign --force --deep --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
else
  echo "::warning::MACOS_SIGN_IDENTITY not set – the DMG is NOT signed and NOT notarized (Gatekeeper will warn)."
fi

# the content of the DMG
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
cp LICENSE COPYRIGHT "$STAGING/"
# readable for everyone (mktemp gives 700, the files keep their modes)
chmod 755 "$STAGING"
chmod 644 "$STAGING/LICENSE" "$STAGING/COPYRIGHT"

mkdir -p "$DIST"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov \
  -format UDZO "$DMG"

if [[ -n "$IDENTITY" ]]; then
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"
  if [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
    echo "Notarizing $DMG"
    result="$(xcrun notarytool submit "$DMG" --apple-id "$APPLE_ID" \
      --password "$APPLE_APP_PASSWORD" --team-id "$APPLE_TEAM_ID" \
      --wait --output-format json)"
    echo "$result"
    # --wait also ends with status Invalid: only Accepted is stapled
    if ! grep -q '"status" *: *"Accepted"' <<<"$result"; then
      echo "error: notarization not accepted (xcrun notarytool log <id> …)" >&2
      exit 1
    fi
    xcrun stapler staple "$DMG"
  else
    echo "::warning::APPLE_ID/APPLE_APP_PASSWORD/APPLE_TEAM_ID not set – the DMG is signed but NOT notarized."
  fi
fi

echo "DMG: $DMG"
