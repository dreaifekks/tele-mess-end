#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-TeleMessEnd}"
BUNDLE_ID="${BUNDLE_ID:-com.dreaifekks.TeleMessEnd}"
MIN_SYSTEM_VERSION="${MIN_SYSTEM_VERSION:-14.0}"
CONFIGURATION="${CONFIGURATION:-release}"
NOTARIZE="${NOTARIZE:-0}"
SIGN_DMG="${SIGN_DMG:-1}"
NOTARY_TIMEOUT="${NOTARY_TIMEOUT:-30m}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ARCH_NAME="${ARCH_NAME:-$(uname -m)}"
DMG_PATH="${DMG_PATH:-$DIST_DIR/$APP_NAME-$APP_VERSION-macos-$ARCH_NAME.dmg}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/module-cache}"

log() {
  printf '[package] %s\n' "$*"
}

fail() {
  printf '[package] error: %s\n' "$*" >&2
  exit 1
}

require_macos_tool() {
  local tool="$1"
  command -v "$tool" >/dev/null 2>&1 || fail "missing required macOS tool: $tool"
}

decode_base64() {
  if /usr/bin/base64 --help 2>&1 | /usr/bin/grep -q -- '--decode'; then
    /usr/bin/base64 --decode
  else
    /usr/bin/base64 -D
  fi
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  fail "macOS packaging must run on Darwin"
fi

require_macos_tool swift
require_macos_tool /usr/bin/codesign
require_macos_tool /usr/bin/hdiutil
require_macos_tool /usr/bin/ditto

if [[ "$NOTARIZE" == "1" && -z "${CODESIGN_IDENTITY:-}" ]]; then
  fail "NOTARIZE=1 requires CODESIGN_IDENTITY"
fi

log "building $APP_NAME $APP_VERSION ($CONFIGURATION)"
swift build -c "$CONFIGURATION" --scratch-path "$ROOT_DIR/.build"
BUILD_BINARY="$(swift build -c "$CONFIGURATION" --scratch-path "$ROOT_DIR/.build" --show-bin-path)/$APP_NAME"

[[ -x "$BUILD_BINARY" ]] || fail "built executable not found: $BUILD_BINARY"

log "assembling app bundle"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
/usr/bin/ditto "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_VERSION</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
  </dict>
</dict>
</plist>
PLIST

if command -v /usr/bin/xattr >/dev/null 2>&1; then
  /usr/bin/xattr -cr "$APP_BUNDLE"
fi

log "signing app bundle"
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign_args=(--force --sign "$CODESIGN_IDENTITY" --timestamp)
  if [[ "${CODESIGN_HARDENED_RUNTIME:-1}" == "1" ]]; then
    codesign_args+=(--options runtime)
  fi
  if [[ -n "${CODESIGN_ENTITLEMENTS:-}" ]]; then
    codesign_args+=(--entitlements "$CODESIGN_ENTITLEMENTS")
  fi
  /usr/bin/codesign "${codesign_args[@]}" "$APP_BUNDLE"
else
  log "CODESIGN_IDENTITY is not set; using ad-hoc signing for local testing"
  /usr/bin/codesign --force --sign - "$APP_BUNDLE"
fi

/usr/bin/codesign --verify --strict --verbose=4 "$APP_BUNDLE"

log "creating dmg"
mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"
DMG_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/tele-mess-end-dmg.XXXXXX")"
NOTARY_KEY_PATH=""

cleanup() {
  rm -rf "$DMG_STAGE"
  if [[ -n "$NOTARY_KEY_PATH" ]]; then
    rm -f "$NOTARY_KEY_PATH"
  fi
}
trap cleanup EXIT

/usr/bin/ditto "$APP_BUNDLE" "$DMG_STAGE/$APP_NAME.app"
ln -s /Applications "$DMG_STAGE/Applications"

/usr/bin/hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGE" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ -n "${CODESIGN_IDENTITY:-}" && "$SIGN_DMG" == "1" ]]; then
  log "signing dmg"
  /usr/bin/codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$DMG_PATH"
  /usr/bin/codesign --verify --verbose=4 "$DMG_PATH"
fi

if [[ "$NOTARIZE" == "1" ]]; then
  require_macos_tool xcrun
  notary_args=(submit "$DMG_PATH" --wait --timeout "$NOTARY_TIMEOUT")

  if [[ -n "${NOTARYTOOL_KEYCHAIN_PROFILE:-}" ]]; then
    notary_args+=(--keychain-profile "$NOTARYTOOL_KEYCHAIN_PROFILE")
  elif [[ -n "${APPLE_API_KEY_P8_BASE64:-}" ]]; then
    [[ -n "${APPLE_API_KEY_ID:-}" ]] || fail "APPLE_API_KEY_ID is required"
    [[ -n "${APPLE_API_ISSUER_ID:-}" ]] || fail "APPLE_API_ISSUER_ID is required"
    NOTARY_KEY_PATH="$(mktemp "${TMPDIR:-/tmp}/notary-key.XXXXXX.p8")"
    printf '%s' "$APPLE_API_KEY_P8_BASE64" | decode_base64 >"$NOTARY_KEY_PATH"
    chmod 600 "$NOTARY_KEY_PATH"
    notary_args+=(--key "$NOTARY_KEY_PATH" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER_ID")
  elif [[ -n "${APPLE_API_KEY_PATH:-}" ]]; then
    [[ -n "${APPLE_API_KEY_ID:-}" ]] || fail "APPLE_API_KEY_ID is required"
    [[ -n "${APPLE_API_ISSUER_ID:-}" ]] || fail "APPLE_API_ISSUER_ID is required"
    notary_args+=(--key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER_ID")
  elif [[ -n "${APPLE_ID:-}" ]]; then
    [[ -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]] || fail "APPLE_APP_SPECIFIC_PASSWORD is required"
    [[ -n "${APPLE_TEAM_ID:-}" ]] || fail "APPLE_TEAM_ID is required"
    notary_args+=(--apple-id "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --team-id "$APPLE_TEAM_ID")
  else
    fail "NOTARIZE=1 requires NOTARYTOOL_KEYCHAIN_PROFILE, App Store Connect API key variables, or Apple ID variables"
  fi

  log "submitting dmg for notarization"
  xcrun notarytool "${notary_args[@]}"
  log "stapling notarization ticket"
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
fi

log "created $DMG_PATH"
