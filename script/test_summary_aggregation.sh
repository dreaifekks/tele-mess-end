#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/summary-aggregation-tests"
BINARY="$BUILD_DIR/SummaryAggregationTests"

mkdir -p "$BUILD_DIR" "$ROOT_DIR/.build/module-cache"

swiftc \
  -parse-as-library \
  -module-cache-path "$ROOT_DIR/.build/module-cache" \
  "$ROOT_DIR/Sources/TeleMessEnd/CoreAPI/CoreAPIModels.swift" \
  "$ROOT_DIR/Sources/TeleMessEnd/CoreRuntime/DailyGroupSummary.swift" \
  "$ROOT_DIR/Sources/TeleMessEnd/CoreRuntime/SummarySettings.swift" \
  "$ROOT_DIR/Sources/TeleMessEnd/Support/Formatters.swift" \
  "$ROOT_DIR/Tests/SummaryAggregationTests/main.swift" \
  -o "$BINARY"

"$BINARY"
