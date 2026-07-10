# V1 Completion Audit

Audit date: 2026-07-03; verification guidance revised 2026-07-10.

This audit checks the current macOS V1 implementation against
`docs/v1-scope.md`.

## Verification Commands

Run from the repository root unless noted.

```bash
./script/verify.sh
CORE_BASE_URL=http://127.0.0.1:18765 CORE_API_TOKEN=smoke-token ./script/smoke_core_api_live.sh
./script/build_and_run.sh --verify
```

The live smoke used a temporary `tele-mess-core` clone in `/private/tmp` running
`tele-mess-core serve-api --config config.smoke.yml` with a token-protected
empty archive. The smoke passed against schema version 8 and verified health,
state, capabilities, accounts, origins, recent messages, failed events,
participants, cursors, and media metadata through the typed Swift client.

## Must Have

| Area | Status | Evidence |
| --- | --- | --- |
| Native SwiftUI macOS app | Complete | `Sources/TeleMessEnd/App/TeleMessEndApp.swift` defines the SwiftUI app and a single shared-state `Window`. |
| Multi-file structure | Complete | App, CoreAPI, CoreRuntime, feature views, shared UI, support, scripts, and docs are split by responsibility. |
| Codex Run action | Complete | `script/build_and_run.sh` and `.codex/environments/environment.toml` are present; `./script/build_and_run.sh --verify` passed. |
| Main `NavigationSplitView` | Complete | `ContentView` composes sidebar-detail navigation. |
| Settings scene | Complete | `TeleMessEndApp` defines `Settings`; `SettingsView` manages core profiles and the local runner. |
| System-adaptive styling | Complete | Views use SwiftUI semantic styles/materials instead of fixed custom palettes. |
| Remote/local profiles | Complete | `CoreProfile`, `CoreProfileStore`, `SettingsView`, and `LocalCoreProcessController` cover remote and local profiles. |
| Keychain token storage | Complete | `KeychainStore` stores tokens per profile UUID. |
| Bearer and `X-Api-Token` auth | Complete | `CoreAPIClient` injects both modes; `script/test_core_api.sh` verifies both headers. |
| Profile validation | Complete | `AppModel.validateActiveProfile()` calls `/healthz`, `/sync/state`, and `/manage/capabilities`; contract and live smoke cover these paths. |
| Connection status and last error | Complete | `ContentView` status bar and toolbar badge show `statusMessage` or `lastError`. |
| Typed API client | Complete | `CoreAPIClient` uses `URLSession`, async/await, typed models, centralized auth, and HTTP error mapping. |
| Mocked transport tests | Complete | `Tests/CoreAPIContractTests/main.swift` and `script/test_core_api.sh` cover V1 endpoint families and HTTP errors without XCTest dependency. |
| Dashboard | Complete | `DashboardView` shows state cards, recent 100 messages, failed operation events, active profile, refresh, and console action. |
| Accounts | Complete | `AccountsView` lists accounts, selects accounts from the account picker, creates account metadata, masks phone display, runs status/request-code/submit-code with 2FA password, confirms deletion, and displays auth/session/last error. |
| Origins and policies | Complete | `OriginsView` lists origins, filters by account/search/type/backup/tag/archive, supports backup-first and column sorting, collapses topics by default, manages multi-select operations, discovers origins, archives/restores/deletes with confirmation, and edits policy/tag fields. |
| Messages and search | Complete | `MessagesView` and `MessageTable` load recent messages, search `/sync/search`, and display account/chat/sender/local-time/text/deleted/media/Telegram deeplink. |
| Diagnostics | Complete | `DiagnosticsView` covers operation events, participants, cursors, media files, participant refresh, filters, and raw payload detail panel. |
| Local core runner | Complete | `SettingsView` local runtime section starts/stops configured local command and displays status, output, and process errors. |

## Acceptance Criteria

| Criterion | Status | Evidence |
| --- | --- | --- |
| Add remote profile, store token, verify connection | Complete | `SettingsView` profile form + `KeychainStore` + validation flow; live smoke proves typed client can verify token-protected core. |
| Dashboard loads state, recent messages, failed events | Complete | `AppModel.loadDashboard()` and `DashboardView`; live smoke validates underlying endpoints. |
| Add account and run Telegram auth code/2FA flow | Complete | `AccountsView` and `CoreAPIClient` create/status/request-code/submit-code methods; contract test verifies request bodies. |
| Discover/filter/archive origins and edit policy/tags | Complete | `OriginsView`, `TagEditor`, and `AppModel` origin/policy methods; contract test verifies core payloads. |
| Diagnostics inspect participants/cursors/media/events safely | Complete | `DiagnosticsView` has empty states, typed tables, and raw detail panels; live smoke hit all diagnostics endpoints against empty data. |
| App builds and launches through run script | Complete | `./script/build_and_run.sh --verify` passed. |

## Notes

- `script/verify.sh` is the authoritative gate. The real endpoint and runtime
  assertions live in executable suites because the current CommandLineTools
  environment lacks usable XCTest and Swift Testing modules; the SwiftPM test
  target remains framework-free and buildable.
- V1 intentionally does not add local archive mirroring, media preview/download
  over HTTP, multi-user permissions, AI workflows, or remote core installation.
