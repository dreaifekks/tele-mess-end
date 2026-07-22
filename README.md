# Tele Mess End

Native macOS UI for Tele Mess Core.

This app is intended to manage and inspect a single-user Tele Mess Core service
that may run either locally on the Mac or remotely on another machine. The Mac
app talks to the same HTTP API used by the built-in `/console` web UI.

## Product Scope

V1 surfaces:

- Dashboard: service status, sync state, recent messages, operation errors, and
  web console shortcut.
- Accounts: account metadata plus Telegram auth status, code request, code
  submit, and 2FA password flow.
- Origins: table-first management for groups, channels, topics, archive state,
  discovery, filtering, and backup policy editing.
- Policies and tags: per-origin text/media/download toggles plus chip-style tag
  editing.
- Messages and search: recent messages and full-text search backed by the core.
- Daily analysis: Core-owned persisted summary artifacts and validated message
  points, package/summary job progress, soft-delete/restore, schedule scope, and
  Telegram delivery targets. Full per-origin analysis continues for the selected
  scope; Core delivers the independent important report when present, followed
  by a separate point digest with fixed `#point`.
- Diagnostics: operation events, capture cursors, participants, participant
  refresh, and media-file metadata.

## Core Connection Model

The app supports multiple saved core profiles:

- Remote core: base URL plus API token.
- Managed local core: a pinned `tele-mess-core` PyPI version, workspace, API
  token, and process lifecycle owned by the Mac app.
- Custom local core: an explicit shell command and optional working directory for
  development or nonstandard installations.

The managed runtime uses `uv tool install` against an explicit public-PyPI
default index, with source-changing `UV_*`/`PIP_*` environment overrides
filtered and app-specific tool, bin, and cache directories under
`~/Library/Application Support/TeleMessEnd/CoreRuntime`; it does not depend on
an incidental `uvx` cache or the GUI app's shell startup files. The default Core workspace is
`~/Library/Application Support/tele-mess-core`. A fresh workspace collects the
Telegram API ID/hash, creates `config.yml` without overwriting an existing file,
and restricts it to the current user. The generated Core API token is written to
that Core-owned config and the profile copy is stored in Keychain; secrets never
enter app preferences or runtime logs.

Managed Core `0.3.0` starts as the structured command
`tele-mess-core run-local --workspace <absolute-path> --web`. The app waits for
an authenticated `/healthz` response and the API manifest before marking the
process ready. Stop, profile switching, and app termination signal the process;
normal Start/Stop actions wait for the previous process to exit before another
one can launch.

Selecting a different profile starts a new Core session. Core-derived data and
feature selections are cleared, in-flight results from the old profile are
discarded, and the visible section is reloaded against the newly selected Core.
Local profiles with authentication disabled can run background refreshes without
opening Keychain UI.

## Technical Direction

The first implementation should be a native SwiftUI macOS app rather than an
Electron, Tauri, or web-wrapper app. The current decision record is in
[`docs/adr/0001-macos-app-stack.md`](docs/adr/0001-macos-app-stack.md).

Profile-session, state-ownership, and verification decisions are recorded in
[`docs/adr/0002-profile-session-and-state-ownership.md`](docs/adr/0002-profile-session-and-state-ownership.md).

Core API mapping is tracked in
[`docs/core-api-surface.md`](docs/core-api-surface.md).

V1 implementation scope is tracked in [`docs/v1-scope.md`](docs/v1-scope.md).

## Repository Status

This repository contains the SwiftPM macOS app, typed Core API client,
profile-scoped session/runtime state, Core-owned summary and message-point
workflows, CI/release verification, and the project-local Codex Run action.

Run locally:

```bash
./script/build_and_run.sh
```

Build a local DMG for testing:

```bash
./script/package_macos.sh
```

Without `CODESIGN_IDENTITY`, the package script uses ad-hoc signing and is only
intended for local install-flow testing. For Developer ID packaging, run it with
your signing identity:

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./script/package_macos.sh
```

Set `NOTARIZE=1` plus notarization credentials to submit and staple the DMG.

Publish a GitHub Release DMG by pushing a version tag that matches `VERSION`:

```bash
git tag "v$(tr -d '[:space:]' < VERSION)"
git push origin "v$(tr -d '[:space:]' < VERSION)"
```

The release workflow runs on a GitHub-hosted macOS runner, builds the DMG, and
uploads it to the matching GitHub Release. Until Developer ID signing is
configured, that DMG is ad-hoc signed and macOS Gatekeeper will warn on first
open.

Run the complete local verification gate used by CI and releases:

```bash
./script/verify.sh
```

It builds the package and runs the mocked Core API contract suite, summary
settings/DTO tests, profile-session and local-Core lifecycle regressions,
Markdown parser tests, and the SwiftPM test build. Local runtime tests use
temporary workspaces and fake commands; they do not install from PyPI or touch
the user's Core workspace. The executable suites are intentionally independent
of XCTest because the supported CommandLineTools environment does not provide a
usable XCTest or Swift Testing module.

Run only the Core API contract tests:

```bash
./script/test_core_api.sh
```

These tests compile the typed Core API client with mocked transport fixtures and
real snake_case response payloads from the core API surface.

Run a read-only live smoke against a running core:

```bash
CORE_BASE_URL=http://127.0.0.1:8765 CORE_API_TOKEN=your-token ./script/smoke_core_api_live.sh
```

This compiles the same typed client and checks `/healthz`, `/sync/state`, the API
manifest/capabilities, accounts, origins, recent messages, operation events,
participants, cursors, media metadata, and read-only daily-summary and
message-point surfaces.

## License

Apache License 2.0. See [`LICENSE`](LICENSE).
