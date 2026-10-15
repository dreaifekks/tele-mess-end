# Development Notes

This document collects the implementation details, design records, and
verification workflow for contributors. User-facing information lives in the
[README](../README.md). Release signing and publishing live in
[release.md](release.md).

The repository contains the SwiftPM macOS app, a typed Core API client,
profile-scoped session and runtime state, Core-owned summary and message-point
workflows, CI and release verification, and the project-local Codex Run action.

## Design Records

- [`adr/0001-macos-app-stack.md`](adr/0001-macos-app-stack.md): why the client
  is a native SwiftUI macOS app rather than an Electron, Tauri, or web-wrapper
  app.
- [`adr/0002-profile-session-and-state-ownership.md`](adr/0002-profile-session-and-state-ownership.md):
  profile sessions, state ownership, and verification decisions.
- [`core-api-surface.md`](core-api-surface.md): mapping between app features and
  the Tele Mess Core HTTP API.
- [`v1-scope.md`](v1-scope.md): the V1 implementation scope.
- [`v1-completion-audit.md`](v1-completion-audit.md): the V1 audit against that
  scope.

The app talks to the same HTTP API used by Core's built-in `/console` web UI and
does not mirror archive state locally.

## Core Connection Model

The app supports multiple saved Core profiles:

- **Remote Core:** base URL plus API token.
- **Managed local Core:** a pinned `tele-mess-core` PyPI version, workspace, API
  token, and process lifecycle owned by the Mac app.
- **Custom local Core:** an explicit shell command and optional working
  directory for development or nonstandard installations.

### Managed Runtime

The managed runtime uses `uv tool install` against an explicit public-PyPI
default index, with source-changing `UV_*`/`PIP_*` environment overrides
filtered and app-specific tool, bin, and cache directories under
`~/Library/Application Support/TeleMessEnd/CoreRuntime`. It does not depend on
an incidental `uvx` cache or the GUI app's shell startup files. The app looks
for `uv` through `TELE_MESS_END_UV_EXECUTABLE`, `UV_EXECUTABLE`, `PATH`,
`~/.local/bin`, `/opt/homebrew/bin`, and `/usr/local/bin`.

The default Core workspace is `~/Library/Application Support/tele-mess-core`. A
fresh workspace collects the Telegram API ID/hash, creates `config.yml` without
overwriting an existing file, and restricts it to the current user. The
generated Core API token is written to that Core-owned config and the profile
copy is stored in Keychain. Secrets never enter app preferences or runtime logs.

Managed Core `0.3.0` starts as the structured command
`tele-mess-core run-local --workspace <absolute-path> --web`. The app waits for
an authenticated `/healthz` response and the API manifest before marking the
process ready. Stop, profile switching, and app termination signal the process.
Normal Start/Stop actions wait for the previous process to exit before another
one can launch.

### Profile Switching

Selecting a different profile starts a new Core session. Core-derived data and
feature selections are cleared, in-flight results from the old profile are
discarded, and the visible section is reloaded against the newly selected Core.
Local profiles with authentication disabled can run background refreshes
without opening Keychain UI.

Sidebar sections are filtered by the live API manifest, so a section only
appears when the connected Core exposes its endpoint.

## Building and Running

Run locally:

```bash
./script/build_and_run.sh
```

The script also accepts `--debug`, `--logs`, `--telemetry`, and `--verify`.
`.codex/environments/environment.toml` wires the same script to the Codex app
Run action.

Build a local DMG for testing:

```bash
./script/package_macos.sh
```

### Local Code Signing

Both scripts sign with the first `Developer ID Application` identity found in
the keychain, so rebuilt apps keep one signing identity and stored Keychain
tokens stay readable. When no such identity exists they fall back to ad-hoc
signing, which is only intended for local testing. Override the choice with
`CODESIGN_IDENTITY`:

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./script/package_macos.sh
CODESIGN_IDENTITY=- ./script/build_and_run.sh   # force ad-hoc
```

## Verification

Run the complete local verification gate used by CI and releases:

```bash
./script/verify.sh
```

It builds the package and runs the mocked Core API contract suite, summary
settings/DTO tests, profile-session and local-Core lifecycle regressions,
Markdown parser tests, and the SwiftPM test build. Local runtime tests use
temporary workspaces and fake commands. They do not install from PyPI or touch
the user's Core workspace. The executable suites are intentionally independent
of XCTest because the supported CommandLineTools environment does not provide a
usable XCTest or Swift Testing module.

Run only the Core API contract tests:

```bash
./script/test_core_api.sh
```

These tests compile the typed Core API client with mocked transport fixtures and
real snake_case response payloads from the Core API surface.

Run a read-only live smoke against a running Core:

```bash
CORE_BASE_URL=http://127.0.0.1:8765 CORE_API_TOKEN=your-token ./script/smoke_core_api_live.sh
```

This compiles the same typed client and checks `/healthz`, `/sync/state`, the
API manifest/capabilities, accounts, origins, recent messages, operation events,
participants, cursors, media metadata, and read-only daily-summary and
message-point surfaces.
