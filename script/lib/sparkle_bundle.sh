# Sourced after the caller defines ROOT_DIR, APP_BUNDLE, APP_BINARY and the
# signing identity. Keep the SwiftPM framework's symlinks and helper signatures.

embed_sparkle() {
  local frameworks=("$ROOT_DIR"/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-*/Sparkle.framework)
  mkdir -p "$APP_BUNDLE/Contents/Frameworks"
  /usr/bin/ditto "${frameworks[0]}" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"

  if ! /usr/bin/otool -l "$APP_BINARY" \
    | /usr/bin/awk '/cmd LC_RPATH/ { getline; getline; print $2 }' \
    | /usr/bin/grep -Fx '@executable_path/../Frameworks' >/dev/null; then
    /usr/bin/install_name_tool -add_rpath '@executable_path/../Frameworks' "$APP_BINARY"
  fi
  /usr/bin/xattr -cr "$APP_BUNDLE"
}

sign_app_with_sparkle() {
  local framework="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
  local version="$framework/Versions/Current"
  local args=(--force --sign "${CODESIGN_IDENTITY:--}")
  if [[ -n "$CODESIGN_IDENTITY" ]]; then
    args+=(--timestamp)
  fi
  if [[ "$CODESIGN_HARDENED_RUNTIME" == "1" ]]; then
    args+=(--options runtime)
  fi
  if [[ -n "${CODESIGN_KEYCHAIN:-}" ]]; then
    args+=(--keychain "$CODESIGN_KEYCHAIN")
  fi

  /usr/bin/codesign "${args[@]}" "$version/XPCServices/Installer.xpc"
  /usr/bin/codesign "${args[@]}" --preserve-metadata=entitlements "$version/XPCServices/Downloader.xpc"
  /usr/bin/codesign "${args[@]}" "$version/Autoupdate"
  /usr/bin/codesign "${args[@]}" "$version/Updater.app"
  /usr/bin/codesign "${args[@]}" "$framework"

  if [[ -n "${CODESIGN_ENTITLEMENTS:-}" ]]; then
    args+=(--entitlements "$CODESIGN_ENTITLEMENTS")
  fi
  /usr/bin/codesign "${args[@]}" "$APP_BUNDLE"
}
