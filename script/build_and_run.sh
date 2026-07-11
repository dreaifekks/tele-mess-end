#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="TeleMessEnd"
BUNDLE_ID="com.dreaifekks.TeleMessEnd"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build --scratch-path "$ROOT_DIR/.build"
BUILD_BINARY="$(swift build --scratch-path "$ROOT_DIR/.build" --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
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

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign_args=(--force --sign "$CODESIGN_IDENTITY")
  if [[ "${CODESIGN_HARDENED_RUNTIME:-0}" == "1" ]]; then
    codesign_args+=(--options runtime)
  fi
  if [[ -n "${CODESIGN_ENTITLEMENTS:-}" ]]; then
    codesign_args+=(--entitlements "$CODESIGN_ENTITLEMENTS")
  fi
  if [[ -n "${CODESIGN_KEYCHAIN:-}" ]]; then
    codesign_args+=(--keychain "$CODESIGN_KEYCHAIN")
  fi
  /usr/bin/codesign "${codesign_args[@]}" "$APP_BUNDLE"
else
  echo "warning: using ad-hoc signing; Keychain credentials may require replacement after rebuilds" >&2
  /usr/bin/codesign --force --sign - "$APP_BUNDLE"
fi

verify_signature() {
  if command -v /usr/bin/xattr >/dev/null 2>&1; then
    /usr/bin/xattr -cr "$APP_BUNDLE"
  fi
  # The workspace can be FileProvider-backed, which may immediately attach
  # FinderInfo to a launched bundle. Verify the live local signature without
  # treating that external metadata as signed content. Packaging remains strict.
  /usr/bin/codesign --verify --verbose=4 "$APP_BUNDLE"
}

verify_signature

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    verify_signature
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
