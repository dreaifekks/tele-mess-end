#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/runtime-state-tests"
BINARY="$BUILD_DIR/RuntimeStateTests"

mkdir -p "$BUILD_DIR" "$ROOT_DIR/.build/module-cache"

swiftc \
  -parse-as-library \
  -module-cache-path "$ROOT_DIR/.build/module-cache" \
  "$ROOT_DIR/Sources/TeleMessEnd/CoreAPI/AuthTokenProvider.swift" \
  "$ROOT_DIR/Sources/TeleMessEnd/CoreAPI/CoreAPIClient.swift" \
  "$ROOT_DIR/Sources/TeleMessEnd/CoreAPI/CoreAPIError.swift" \
  "$ROOT_DIR/Sources/TeleMessEnd/CoreAPI/CoreAPIModels.swift" \
  "$ROOT_DIR/Sources/TeleMessEnd/CoreRuntime/AppModel.swift" \
  "$ROOT_DIR/Sources/TeleMessEnd/CoreRuntime/AppSection.swift" \
  "$ROOT_DIR/Sources/TeleMessEnd/CoreRuntime/CoreProfile.swift" \
  "$ROOT_DIR/Sources/TeleMessEnd/CoreRuntime/CoreProfileStore.swift" \
  "$ROOT_DIR/Sources/TeleMessEnd/CoreRuntime/LocalCoreRuntimeSupport.swift" \
  "$ROOT_DIR/Sources/TeleMessEnd/CoreRuntime/LocalCoreProcessController.swift" \
  "$ROOT_DIR/Sources/TeleMessEnd/CoreRuntime/OriginFilters.swift" \
  "$ROOT_DIR/Sources/TeleMessEnd/CoreRuntime/SummarySettings.swift" \
  "$ROOT_DIR/Sources/TeleMessEnd/CoreRuntime/SummarySettingsStore.swift" \
  "$ROOT_DIR/Sources/TeleMessEnd/Features/Settings/SummaryTargetOptions.swift" \
  "$ROOT_DIR/Sources/TeleMessEnd/Support/KeychainStore.swift" \
  "$ROOT_DIR/Sources/TeleMessEnd/Support/Log.swift" \
  "$ROOT_DIR/Tests/RuntimeStateTests/main.swift" \
  -o "$BINARY"

"$BINARY"
