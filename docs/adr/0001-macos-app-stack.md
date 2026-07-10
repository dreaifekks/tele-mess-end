# ADR 0001: macOS App Stack

## Status

Accepted for initial scaffold.

## Context

Tele Mess Core already exposes an HTTP API and a built-in web console at
`/console`. The Mac app needs to provide a native UI over that API while letting
the user choose between a remote core service and a local core service. The core
model is single-user with multiple Telegram accounts, protected by an API token
sent as either `Authorization: Bearer <token>` or `X-Api-Token: <token>`.

The UI must be good at repeated desktop workflows: scanning recent sync state,
triaging failed events, managing many origins/topics in a dense table, editing
backup policies and tags, inspecting participant/media/cursor diagnostics, and
running Telegram account auth flows.

## Decision

Build a native macOS app with SwiftUI and Swift Concurrency.

Primary framework choices:

- App shell: SwiftUI `Window` for the single shared-state main window plus a dedicated
  `Settings` scene for core profiles.
- Layout: `NavigationSplitView` for module navigation, SwiftUI `Table` for
  origins and other dense management views, and inspectors/sheets for editing.
- State: Swift Observation for app stores and feature state. Use view-local
  `@State` for transient controls, `@SceneStorage` for per-window selection
  where useful, and app-level stores for connection/session state.
- Networking: `URLSession`, `Codable`, async/await, and a typed `CoreAPIClient`.
  Add OpenAPI generation only if the core project publishes a stable OpenAPI
  document; until then, keep a small hand-written client with endpoint-specific
  request/response types.
- Auth: inject the token per request, supporting bearer auth first and
  `X-Api-Token` as a compatibility option.
- Secret storage: Keychain via the system Security framework. Avoid storing
  tokens in plain preferences or local files.
- Local core runner: a `Process`-backed service controller for launch, stop,
  logs, and health checks. Treat LaunchAgent installation as a later explicit
  feature, not part of the first scaffold.
- Persistence: app preferences for non-secret profile metadata. Do not mirror
  messages into a Mac-side database in the first version; the core remains the
  source of truth. If offline cache or large local indexing becomes necessary,
  add SQLite/GRDB later.
- Logging: `OSLog` with privacy-aware fields for connection, auth, and local
  process lifecycle events.
- Embedded console: optional WebKit surface or external browser action for
  `/console`; this is secondary to native UI.

Initial deployment target:

- macOS 14+ unless older Mac support becomes a hard requirement. This keeps the
  app in modern SwiftUI/Observation territory without requiring the newest OS.

## Non-Goals

- No Electron shell for the first version.
- No Tauri shell for the first version.
- No web-first React UI unless the Mac app is later re-scoped as a companion to
  the existing console instead of a native desktop client.
- No local duplicate message database in the initial build.
- No multi-user core assumptions in the Mac UI.

## Architecture Shape

Suggested module/folder layout for the first scaffold:

```text
TeleMessEnd/
  App/
    TeleMessEndApp.swift
  Features/
    Dashboard/
    Accounts/
    Origins/
    Policies/
    Messages/
    Diagnostics/
    Settings/
  CoreAPI/
    CoreAPIClient.swift
    CoreAPIModels.swift
    CoreAPIError.swift
    AuthTokenProvider.swift
  CoreRuntime/
    CoreProfile.swift
    CoreProfileStore.swift
    LocalCoreProcessController.swift
    CoreHealthMonitor.swift
  SharedUI/
    TagEditor.swift
    EmptyStateView.swift
    StatusBadge.swift
  Support/
    KeychainStore.swift
    Log.swift
```

The scaffold should also include the project-local run contract recommended for
Codex macOS workflows:

```text
script/
  build_and_run.sh
.codex/
  environments/
    environment.toml
```

`script/build_and_run.sh` should own the normal kill, build, and launch loop for
the Mac app. `.codex/environments/environment.toml` should point the Codex app
Run action at that script. Keep both files outside app source.

## UI Model

Use a desktop-first main window:

- Sidebar modules: Dashboard, Accounts, Origins, Messages, Diagnostics.
- Toolbar: active profile selector, connection status, refresh, and console
  shortcut.
- Settings: manage remote/local core profiles and auth token storage.
- Origins detail: table with filters, multi-select, archive/unarchive action,
  and an inspector for policy editing.
- Diagnostics detail: operation events, participants, capture cursors, and media
  metadata.

## API Client Contract

Every request should flow through one client boundary:

```swift
struct CoreAPIClient {
    var baseURL: URL
    var tokenProvider: AuthTokenProvider
    var authMode: CoreAuthMode
}
```

Feature views should not construct raw URLs or headers. They should call
feature-shaped methods such as `fetchSyncState()`, `listAccounts()`,
`listManagementAccounts()`, `discoverOrigins(accountID:)`, `archiveOrigin(_:)`,
`setBackupPolicy(_:)`, `listOperationEvents(...)`, and `searchMessages(query:)`.

## Consequences

Benefits:

- Best macOS fit for tables, sidebars, menus, settings, Keychain, local process
  control, and future packaging.
- Small dependency surface at the start.
- Clear path to native desktop behavior while still reusing the existing core
  API and `/console`.

Tradeoffs:

- Native SwiftUI implementation cannot directly reuse console UI components.
- Dense table editing and advanced inspectors may need careful SwiftUI/AppKit
  interop if SwiftUI `Table` proves insufficient.
- API types must be maintained by hand until the core publishes a stable
  OpenAPI schema.

The later profile-session and state-ownership decisions are recorded in
[`0002-profile-session-and-state-ownership.md`](0002-profile-session-and-state-ownership.md).
