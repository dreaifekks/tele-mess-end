#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/markdown-parser-tests"
BINARY="$BUILD_DIR/MarkdownParserTests"

mkdir -p "$BUILD_DIR" "$ROOT_DIR/.build/module-cache"

swiftc \
  -parse-as-library \
  -module-cache-path "$ROOT_DIR/.build/module-cache" \
  "$ROOT_DIR/Sources/TeleMessEnd/Support/MarkdownBlockParser.swift" \
  "$ROOT_DIR/Tests/MarkdownParserTests/main.swift" \
  -o "$BINARY"

"$BINARY"
