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
- Diagnostics: operation events, capture cursors, participants, participant
  refresh, and media-file metadata.

## Core Connection Model

The app supports multiple saved core profiles:

- Remote core: base URL plus API token.
- Local core: executable/path configuration plus API token, with start/stop/status
  owned by the Mac app.

Tokens are treated as secrets and stored in Keychain. Non-secret profile metadata
can be stored in app preferences.

## Technical Direction

The first implementation should be a native SwiftUI macOS app rather than an
Electron, Tauri, or web-wrapper app. The current decision record is in
[`docs/adr/0001-macos-app-stack.md`](docs/adr/0001-macos-app-stack.md).

Core API mapping is tracked in
[`docs/core-api-surface.md`](docs/core-api-surface.md).

V1 implementation scope is tracked in [`docs/v1-scope.md`](docs/v1-scope.md).

## Repository Status

This repository currently contains the project direction and architecture
decision docs. The next implementation step is to scaffold the macOS app
targets and wire a typed HTTP client against the core API.

## License

Apache License 2.0. See [`LICENSE`](LICENSE).
