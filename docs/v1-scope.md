# V1 Scope

V1 is a native macOS management client for the current Tele Mess Core API.

The core already provides sync, account auth, origin discovery, backup policy,
participant, cursor, media, operation-event, daily-analysis, persisted
message-point, and web-console endpoints. The app should make those workflows
usable from a desktop UI while supporting both remote and local core profiles.

## Product Goal

Give one operator a reliable Mac app to:

- connect to a remote or local `tele-mess-core`
- see whether capture is healthy
- authenticate Telegram accounts
- discover and select origins/topics to back up
- edit backup policies and tags
- inspect recent messages, failed operations, participants, cursors, and media
- run and inspect Core-owned daily analysis, independent important reports, and
  validated persisted message points

## Must Have

### App Foundation

- Native SwiftUI macOS app.
- Multi-file structure: app entrypoint, feature views, models, stores, services,
  and support helpers.
- `script/build_and_run.sh` and `.codex/environments/environment.toml` wired for
  the Codex app Run action.
- Main `WindowGroup` with `NavigationSplitView`.
- Settings scene for core profiles.
- System-adaptive macOS styling.

### Core Profiles

- Saved profiles for:
  - remote core: base URL plus token
  - local core: executable/config command plus token
- Keychain token storage.
- Bearer auth by default, `X-Api-Token` compatibility in the client layer.
- Profile validation through `/healthz`, `/sync/state`, and
  `/manage/capabilities`.
- Visible connection status and last error.

### Typed Core API Client

- `URLSession` + async/await.
- Codable request/response models for V1 endpoints.
- Centralized auth header injection and HTTP error mapping.
- No raw endpoint strings inside feature views.
- Fixture or mocked transport tests for client decoding and error paths.

### Dashboard

- Service state cards:
  - database ID
  - schema version
  - last event sequence
  - message count
  - operation error count
  - server time
- Recent 100 messages from `/sync/messages?latest=true&limit=100`.
- Failed/partial/rate-limited events from `/manage/operation-events`.
- Active profile selector.
- Refresh action.
- Open web console action.

### Accounts

- Account table from `/manage/accounts`.
- Account create form for account ID, display name, phone, session name, and
  optional session directory.
- Telegram auth controls:
  - status
  - request code
  - submit code
  - optional 2FA password
- Delete account metadata with confirmation.
- Clear display for `auth_state`, session name, phone, and `last_error`.

### Origins And Policies

- Origins table from `/manage/origins`.
- Account filter.
- Search by title, username, ID, and tags.
- Type filter.
- Backup on/off filter.
- Include archived toggle.
- Include archived toggle refreshes the loaded origin list immediately.
- Sort by title, type, last message, account, and backup state, with Backup
  First available as a pinned priority.
- Group/topic presentation where `topic_id = 0` is the group row and topics are
  child rows under the same `origin_id`; topic rows are collapsed by default.
- Manage mode for multi-select archive/restore operations.
- Discover origins action using `POST /manage/discover-origins`.
- Archive/unarchive action using `PATCH /manage/origins/archive`.
- Origin removal in the Mac UI is archive-only; do not expose hard delete for
  origin metadata in V1.
- Single-origin backup policy editor:
  - enabled
  - capture text
  - capture media metadata
  - download media
  - tags
- Tag chip editor backed by the core `tags` field.

### Messages And Search

- Recent messages list in Dashboard.
- Search page backed by `/sync/search`.
- Display account, chat title, sender, sent time, text, deleted state, media
  marker, and Telegram app deeplink when possible.
- Display core timestamps in the Mac user's current time zone.
- No local message database in V1.

### Daily Analysis And Message Points

- Schedule or manually start the Core-owned daily package and summary workflow.
- Keep the existing full per-origin analysis active for the selected scope;
  there is no client-side "important origins only" restriction.
- Display persisted summary records by `record_type`, including independent
  important reports and message-point digests.
- Inspect structured message points from `GET /manage/daily-message-points` and
  load individual records from `GET /manage/daily-message-points/item`.
- Display point time, tags, content, Telegram address, importance score and
  reason, origin context, and source references.
- Treat only validated, persisted Core points as inputs to the message-point
  digest. The client does not aggregate or validate points locally.
- Configure one Telegram target. Core sends the independent important report
  when present, then sends the message-point digest separately with fixed
  `#point`; it does not deliver the full per-origin analysis.

### Diagnostics

- Operation events table with account/status filters.
- Capture cursors table.
- Participants table with account/origin filters.
- Participant refresh action.
- Media files table.
- Raw payload detail panel for debugging selected rows.

### Local Core Runner

- Local profile can run a configured `tele-mess-core run-server --config ...`
  command.
- Start, stop, and status actions.
- Show process/log errors in the app.
- Remote profile support comes first; local runner can land after the core UI
  client is usable.

## Should Have

- Keyboard shortcuts for refresh, search, open console, and settings.
- Context menus for origins and messages.
- Batch archive/unarchive origins.
- Batch policy clear or enable after single policy editing is stable.
- Remember table filters per window or app session.
- Status badges for auth state, backup state, and operation status.

## Not V1

- Multi-user or team permissions.
- Client-side AI extraction, message-point validation, or summary generation.
- Client-side Telegram delivery that bypasses the Core workflow.
- Full local mirror of the archive database.
- Remote installation or upgrade of `tele-mess-core`.
- Changing Telegram API ID/hash from the Mac app unless the core API makes that
  explicit.

## Milestones

1. Scaffold app, run script, environment config, profile store, Keychain store,
   and a minimal dashboard that reads `/sync/state`.
2. Build the typed `CoreAPIClient`, fixture transport, and model tests for every
   V1 endpoint family.
3. Finish Dashboard, profile validation, recent messages, operation-event
   summary, and web console link.
4. Build Accounts and Telegram auth workflow.
5. Build Origins table, discovery, archive/unarchive, and policy/tag editor.
6. Add Search, Participants, Cursors, Media, and Operation Events diagnostics.
7. Add daily analysis progress, persisted summary records, message-point
   inspection, and delivery configuration.
8. Add local core runner and log/status handling.

## Acceptance Criteria

- A user can add a remote core profile, store its token in Keychain, and verify
  connection state.
- Dashboard loads state, recent messages, and failed operation events.
- A user can add an account, request a Telegram code, submit code/2FA, and see
  auth state changes.
- A user can discover origins, filter the origins table, archive/unarchive rows,
  and edit backup policy fields and tags.
- Diagnostics pages can inspect participants, cursors, media files, and
  operation events without crashing on empty data.
- Daily Summary distinguishes full, important, and point-derived artifacts, and
  Message Points can query and inspect validated persisted point records.
- The app builds and launches through `./script/build_and_run.sh`.
