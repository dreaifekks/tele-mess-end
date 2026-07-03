#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/core-api-contract-tests"
BINARY="$BUILD_DIR/CoreAPIContractTests"

mkdir -p "$BUILD_DIR" "$ROOT_DIR/.build/module-cache"

swiftc \
  -parse-as-library \
  -module-cache-path "$ROOT_DIR/.build/module-cache" \
  "$ROOT_DIR/Sources/TeleMessEnd/CoreAPI/AuthTokenProvider.swift" \
  "$ROOT_DIR/Sources/TeleMessEnd/CoreAPI/CoreAPIClient.swift" \
  "$ROOT_DIR/Sources/TeleMessEnd/CoreAPI/CoreAPIError.swift" \
  "$ROOT_DIR/Sources/TeleMessEnd/CoreAPI/CoreAPIModels.swift" \
  "$ROOT_DIR/Sources/TeleMessEnd/Support/KeychainStore.swift" \
  "$ROOT_DIR/Tests/CoreAPIContractTests/main.swift" \
  -o "$BINARY"

"$BINARY"
