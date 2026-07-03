# Tele Mess End

Native macOS UI for Tele Mess Core.

This app is intended to manage and inspect a single-user Tele Mess Core service
that may run either locally on the Mac or remotely on another machine. The Mac
app talks to the same HTTP API used by the built-in `/console` web UI.

## Product Scope

Initial surfaces:

- Dashboard: service status, sync state, recent messages, failed operation events.
- Accounts: account list and Telegram login flow, including code and 2FA password.
- Origins: table-first management for groups, channels, topics, archival state,
  batch selection, and backup policy editing.
- Policy Tags: chip/tag editor aligned with the existing console behavior.
- Members and Media: read-only lists first, then refresh/delete workflows.

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

## Repository Status

This repository currently contains the project direction and architecture
decision docs. The next implementation step is to scaffold the macOS app
targets and wire a typed HTTP client against the core API.

## License

Apache License 2.0. See [`LICENSE`](LICENSE).
