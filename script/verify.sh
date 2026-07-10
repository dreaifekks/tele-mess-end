#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

swift build --scratch-path "$ROOT_DIR/.build"
swift test --scratch-path "$ROOT_DIR/.build"
"$ROOT_DIR/script/test_core_api.sh"
"$ROOT_DIR/script/test_summary_settings.sh"
"$ROOT_DIR/script/test_runtime_state.sh"
"$ROOT_DIR/script/test_markdown_parser.sh"
