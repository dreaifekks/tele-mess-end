#!/usr/bin/env bash
# Launch an isolated app with fictional data, then quit it normally to clean up.
# Requires Xcode, Python 3, and a logged-in macOS desktop. No production app kill,
# real Core request, token creation, or existing profile modification.
# Capture its window with: screencapture -x -o -l <window-id> docs/images/<name>.png
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"
swift build --package-path "$ROOT_DIR" --scratch-path "$ROOT_DIR/.build" -j 4
BUILD_DIR="$(swift build --package-path "$ROOT_DIR" --scratch-path "$ROOT_DIR/.build" --show-bin-path)"
STAGING="$(mktemp -d /private/tmp/telemess-screenshots.XXXXXX)"
BUNDLE_ID="com.dreaifekks.TeleMessEnd.screenshots.$(uuidgen)"
APP_BUNDLE="$STAGING/TeleMessEnd-Screenshots.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/TeleMessEnd-Screenshots"

cleanup() {
  pkill -f "^$APP_BINARY$" 2>/dev/null || true
  kill "$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
  defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
  rm -f "$HOME/Library/Preferences/$BUNDLE_ID.plist"
  rm -rf "$HOME/Library/Caches/$BUNDLE_ID" \
    "$HOME/Library/HTTPStorages/$BUNDLE_ID" \
    "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState"
  rm -rf "$STAGING"
}
python3 "$ROOT_DIR/script/screenshot_core.py" "$STAGING/port" >"$STAGING/core.log" 2>&1 &
SERVER_PID=$!
trap cleanup EXIT
trap 'exit 130' INT TERM
while [[ ! -s "$STAGING/port" ]]; do sleep 0.1; done
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp "$BUILD_DIR/TeleMessEnd" "$APP_BINARY"

python3 - "$STAGING" "$BUNDLE_ID" "$APP_BUNDLE" <<'PY'
import json, pathlib, plistlib, sys, uuid
root, bundle_id, app = pathlib.Path(sys.argv[1]), sys.argv[2], pathlib.Path(sys.argv[3])
profile_id = str(uuid.uuid4()).upper()
profile = dict(id=profile_id, name="Community Archive", kind="local",
               baseURLString="http://127.0.0.1:" + (root / "port").read_text(),
               authMode="bearer", localCommand="", localWorkingDirectory=str(root),
               localRuntimeMode="customCommand", localWorkspaceDirectory=str(root / "workspace"),
               createdAt=0, updatedAt=0)
preferences = {
    "teleMessEnd.coreProfiles": json.dumps([profile]).encode(),
    "teleMessEnd.selectedProfileID": profile_id,
    "AppleInterfaceStyle": "Light", "AppleLanguages": ["en"],
    "SUEnableAutomaticChecks": False, "SUHasLaunchedBefore": True,
}
(root / "preferences.plist").write_bytes(plistlib.dumps(preferences))
info = dict(CFBundleExecutable="TeleMessEnd-Screenshots", CFBundleIdentifier=bundle_id,
            CFBundleName="Tele Mess End", CFBundlePackageType="APPL",
            CFBundleShortVersionString="1.0", CFBundleVersion="1",
            LSMinimumSystemVersion="14.0", NSPrincipalClass="NSApplication",
            NSHighResolutionCapable=True, NSRequiresAquaSystemAppearance=True,
            SUEnableAutomaticChecks=False,
            NSAppTransportSecurity={"NSAllowsArbitraryLoads": True})
(app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
PY

source "$ROOT_DIR/script/lib/sparkle_bundle.sh"
CODESIGN_IDENTITY=""
CODESIGN_HARDENED_RUNTIME=0
embed_sparkle
sign_app_with_sparkle
codesign --verify --deep --strict "$APP_BUNDLE"
defaults import "$BUNDLE_ID" "$STAGING/preferences.plist"
echo "Screenshot app: $APP_BUNDLE"
echo "Isolated defaults: $BUNDLE_ID"
echo "Quit the screenshot app to remove the temporary profile, server, and bundle."
open -n -W "$APP_BUNDLE"
