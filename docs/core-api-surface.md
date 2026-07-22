# Core API Surface For macOS UI

This file maps the current `dreaifekks/tele-mess-core` `master` API surface to
the macOS V1 client.

Reference checked: live `tele-mess-core` OpenAPI contract `2026-07-10.4`
(`bf0d29cf60733f79`) on 2026-07-11.

Local runtime reference checked: `tele-mess-core` PyPI/CLI `0.3.0` on
2026-07-22.

## Runtime Model

The core is a single-user, multi-Telegram-account archive and management
service. It owns Telegram ingestion, SQLite archive state, backup policies,
media capture, participant metadata, runtime operation events, daily analysis,
validated message points, persisted summary artifacts, and summary delivery.

The Mac app is a native control and inspection client. It should not duplicate
the archive database in V1. The core remains the source of truth.

The core also runs the daily package and AI-summary workflow. The client starts,
monitors, and inspects that workflow but does not reproduce extraction,
validation, persistence, or Telegram delivery locally. The service still does
not model multiple product users or tenants.

## Auth

If `server.token` is configured, sync and management APIs require one of:

- `Authorization: Bearer <token>`
- `X-Api-Token: <token>`

`GET /` and `GET /console` are allowed without a token header so a browser can
load the built-in console. Console API calls still require the token.

The Mac app should store tokens in Keychain and default to bearer auth.

## Health And Console

Endpoints:

- `GET /healthz`
- `GET /console`
- `GET /`

Capabilities:

- `/healthz` returns `{ ok: true }` plus sync state fields.
- `/console` serves the built-in web console over the same API surface.

Mac V1:

- Use `/healthz` or `/sync/state` for profile connection checks.
- Provide an "Open Console" action for the active profile.

## Managed Local Core CLI

The managed local profile is a lifecycle boundary around the public PyPI CLI,
not a second archive implementation:

- Install the pinned distribution with
  `uv tool install --no-config --default-index https://pypi.org/simple tele-mess-core==0.3.0`,
  filter inherited `UV_*`/`PIP_*` variables that can change package sources or
  constraints, and set app-specific `UV_TOOL_DIR`, `UV_TOOL_BIN_DIR`, and
  `UV_CACHE_DIR` paths under TeleMessEnd Application Support.
- Execute the installed console script directly. Do not point persistent state
  at an incidental `uvx` cache or depend on login-shell PATH initialization.
- Start HTTP-backed local mode with the exact argument structure
  `tele-mess-core run-local --workspace <absolute-path> --web`. In particular,
  `run-local` without `--web` does not expose the API used by this client.
- Default the Core-owned workspace to
  `~/Library/Application Support/tele-mess-core`. Relative storage, session, and
  log paths in `config.yml` resolve inside that workspace.
- A fresh workspace requires one Telegram account template with `api_id` and
  `api_hash`, plus a local server token. Bootstrap creates the configuration
  exclusively with user-only permissions and never overwrites an existing file;
  the matching client token is stored in Keychain.
- Process launch is only the Starting state. Poll authenticated `/healthz` until
  `ok` is not false, then fetch `/manage/api-manifest` before reporting Ready.
  Authentication failures are terminal; connection refusal is retryable until
  the bounded readiness timeout or process exit.
- Send SIGTERM for normal stop, wait for exit before relaunching, and stop the
  owned process when its profile is replaced or the app terminates.

The Custom Command mode remains available for development and unusual
installations. It intentionally preserves the prior shell-command behavior, but
does not participate in managed install or workspace bootstrap.

## Sync API

### State

Endpoint:

- `GET /sync/state`

Fields:

- `database_id`
- `schema_version`
- `last_event_seq`
- `message_count`
- `operation_error_count`
- `server_time`

Mac V1:

- Dashboard service cards.
- Detect whether a profile points at a valid core service.
- Show operation error count prominently.

### Events

Endpoint:

- `GET /sync/events?after=0&limit=500`

Response shape:

- `items`
- `next_cursor`
- `has_more`

Event item fields:

- `seq`
- `source`
- `account_id`
- `event_type`
- `chat_id`
- `message_id`
- `event_at`
- `payload_json`

Mac V1:

- Use for low-level diagnostics and future incremental sync.
- Not required for the first dashboard if `/sync/messages?latest=true` is enough.

### Messages

Endpoints:

- `GET /sync/messages?after=0&limit=500`
- `GET /sync/messages?latest=true&limit=100`
- `GET /sync/search?q=term&limit=50`

Cursor response shape:

- `items`
- `next_cursor`
- `has_more`

Message item fields include:

- `event_seq`
- `source`
- `account_id`
- `chat_id`
- `message_id`
- `topic_id`
- `chat_title`
- `sender_id`
- `sender_name`
- `sender_username`
- `sent_at`
- `edited_at`
- `ingested_at`
- `deleted_at`
- `text`
- `has_media`
- `media_kind`
- `grouped_id`
- `reply_to_message_id`
- `forward_from_id`
- `forward_from_name`
- `permalink`
- `reactions_json`
- `raw_json`
- `version`

Mac V1:

- Dashboard recent 100 messages from `latest=true`.
- Search view against `/sync/search`.
- Render deleted messages via `deleted_at`.
- Show `chat_title`, account, sender, time, text, and media indicators.

### Accounts And Chats Metadata

Endpoints:

- `GET /sync/accounts`
- `GET /sync/chats`

Capabilities:

- Lightweight archive metadata for accounts and chats.
- Management account state is richer and should come from `/manage/accounts`.

Mac V1:

- Use as supporting lookup data for message and search views.
- Prefer `/manage/accounts` for account setup/auth screens.

### Media Files

Endpoint:

- `GET /sync/media-files?account_id=main&chat_id=-1001&message_id=1&limit=500`

Filters are optional.

Fields:

- `source`
- `account_id`
- `chat_id`
- `message_id`
- `file_index`
- `file_path`
- `media_kind`
- `mime_type`
- `file_size`
- `downloaded_at`
- `raw_json`
- `chat_title`

Mac V1:

- Read-only media list.
- Treat paths as core-side paths; remote profiles may not be able to open them
  locally without a later file-serving or mount feature.

## Management API

### Capabilities

Endpoint:

- `GET /manage/capabilities`

Capabilities:

- Reports mode, supported sync objects, supported management objects, and auth
  flow status.

Mac V1:

- Call during profile validation.
- Use to gate optional UI if the core evolves.

### Accounts And Telegram Auth

Endpoints:

- `GET /manage/accounts`
- `POST /manage/accounts`
- `DELETE /manage/accounts`
- `POST` or `PATCH /manage/accounts/auth`
- `POST /manage/accounts/auth/status`
- `POST /manage/accounts/auth/request-code`
- `POST /manage/accounts/auth/submit-code`

Account fields include:

- `source`
- `account_id`
- `display_name`
- `kind`
- `updated_at`
- `raw_json`
- `auth_state`
- `phone`
- `session_name`
- `session_dir`
- `last_error`
- `auth_updated_at`
- `auth_raw_json`

Write payload basics:

- Account create: `account_id`, optional `display_name`, `phone`,
  `session_name`, `session_dir`.
- Auth status/request/submit: `account_id`; request also needs `phone`; submit
  needs `phone`, `code`, and optional `password` for Telegram 2FA.

Mac V1:

- Accounts list with auth/session state.
- Add account metadata.
- Run status, request-code, submit-code, and 2FA password flow.
- Delete account metadata only after a confirmation that stored messages remain.
- Surface auth errors from `last_error` and operation events.

Important boundary:

- Live auth uses core server config as the Telethon template. The Mac app should
  not assume it can fully provision API ID/hash unless the core contract grows.

### Origins

Endpoints:

- `GET /manage/origins?account_id=main&include_archived=true`
- `POST /manage/origins`
- `DELETE /manage/origins`
- `PATCH /manage/origins/archive`
- `POST /manage/discover-origins`

Origin fields include:

- `source`
- `account_id`
- `origin_id`
- `topic_id`
- `origin_type`
- `parent_origin_id`
- `title`
- `username`
- `is_forum`
- `archived_at`
- `last_message_at`
- `discovered_at`
- `updated_at`
- `raw_json`
- embedded `backup_policy` when one exists

Domain semantics:

- Identity is `(source, account_id, origin_id, topic_id)`.
- Main group/channel rows use `topic_id = 0`.
- Topics are rows under the same `origin_id`, not parent objects.
- When `include_archived=false`, archived groups and topics under archived groups
  are hidden.
- Archiving an origin also disables matching backup policies.
- `POST /manage/discover-origins` accepts `account_id`, `include_topics`,
  `include_private`, and `topic_limit`.

Mac V1:

- Origins table is the main management surface.
- Include filters for account, type, backup status, tags, archived state, and
  search text.
- Support discovery from Telegram sessions.
- Support archive/unarchive. The Mac V1 UI treats origin removal as
  archive-only and does not expose hard delete for origin metadata.
- Render topic rows under their group/channel row without treating topics as
  separate parents.

### Backup Policies

Endpoints:

- `GET /manage/backup-policies?account_id=main`
- `POST` or `PATCH /manage/backup-policies`
- `DELETE /manage/backup-policies`

Fields:

- `source`
- `account_id`
- `origin_id`
- `topic_id`
- `enabled`
- `capture_text`
- `capture_media_metadata`
- `download_media`
- `tags`
- `updated_at`

Mac V1:

- Inspector or inline editor from Origins table.
- Tag chip editor backed by the core `tags` field.
- Explicit toggles for text, media metadata, and media download.
- Batch policy editing can follow after single-row editing is stable.

### Participants

Endpoints:

- `GET /manage/participants?account_id=main&origin_id=-1001`
- `POST /manage/participants`
- `DELETE /manage/participants`
- `POST /manage/participants/refresh`

Fields:

- `source`
- `account_id`
- `origin_id`
- `user_id`
- `username`
- `display_name`
- `is_bot`
- `role`
- `last_seen_at`
- `updated_at`
- `raw_json`

Mac V1:

- Start as read-only participant list by account/origin.
- Add refresh action once account/origin selection is clear.
- Keep manual create/delete secondary.

### Capture Cursors

Endpoint:

- `GET /manage/capture-cursors?account_id=main`

Fields:

- `source`
- `account_id`
- `origin_id`
- `topic_id`
- `last_message_id`
- `last_message_at`
- `last_backfill_at`
- `updated_at`
- `raw_json`
- `origin_title`

Mac V1:

- Diagnostics list for backfill/catch-up progress.

### Operation Events

Endpoint:

- `GET /manage/operation-events?account_id=main&status=failed&limit=100`
- `DELETE /manage/operation-events` with body `{"id": 1}`

Fields:

- `id`
- `source`
- `account_id`
- `operation`
- `status`
- `subject_type`
- `subject_id`
- `error_code`
- `message`
- `retry_after`
- `occurred_at`
- `raw_json`

Mac V1:

- Dashboard failed/partial/rate-limited summary.
- Dedicated diagnostics table with account/status filters and per-event delete.

### Daily Analysis, Summary Records, And Message Points

Endpoints:

- `GET` and `PATCH /manage/daily-package-schedule`
- `GET` and `PATCH /manage/daily-summary-delivery`
- `POST /manage/daily-packages`
- `GET /manage/daily-package-runs`
- `GET /manage/daily-package-runs/content`
- `POST /manage/daily-summaries`
- `POST` and `GET /manage/daily-summary-jobs`
- `PATCH /manage/daily-summary-jobs/cancel`
- `GET /manage/daily-summary-runs`
- `GET /manage/daily-summary-runs/content`
- `GET`, `PATCH`, and `DELETE /manage/daily-summary-records`
- `GET /manage/daily-summary-records/item`
- `GET /manage/daily-message-points`
- `GET /manage/daily-message-points/item`

Workflow semantics:

- A scheduled or manual run continues the existing full analysis for the
  selected account/origin/topic/tag scope. Important origins are not an input
  restriction.
- Core persists an independent `important_daily` summary artifact for important
  origins alongside the full analysis.
- Every origin, including important origins, participates in structured message
  point extraction. Core validates and persists those points before generating
  the `point_daily` summary.
- Telegram delivers the independent important report when one is present, then
  sends the point summary separately with the fixed `#point` tag. It does not
  deliver the full per-origin analysis. Extraction, validation, persistence,
  summary generation, and delivery remain Core-owned behavior.

Summary record fields include:

- `summary_id`, `run_id`, `package_run_id`
- `record_type` (including `important_daily` and `point_daily`)
- `date`, `timezone`, `scope`, `tags`, `important`, `provider`, `title`
- `content_preview`, optional full `content_md`, and `content_json`
- origin/group/image/content counts, deletion state, and timestamps

`GET /manage/daily-message-points` returns an `items` array and supports filters
for point/run/package IDs, date range, source, account/origin/topic/message IDs,
tags, importance score range, important-origin state, text query, incomplete-run
inclusion, and limit. `GET /manage/daily-message-points/item` requires
`point_id`.

Message point fields include:

- identity and run context: `point_id`, `run_id`, `package_run_id`, `date`,
  `timezone`
- source identity: `source`, `account_id`, `origin_id`, `topic_id`, optional
  `origin_title`, and optional `message_id`
- content: `occurred_at`, `tags`, `tags_csv`, `content`, Telegram deeplink or
  permalink, and heterogeneous `source_refs`
- importance: `importance_score` from 1 through 5, optional
  `importance_reason`, and `origin_important`
- provider/run/job status and created/updated timestamps

Mac V1:

- Treat summary records and message points as read-only Core-owned analytical
  state, except for the existing summary soft-delete/restore API.
- Show summary `record_type` so full, important, and point-derived artifacts stay
  distinguishable when one run produces multiple records.
- Provide a dedicated Message Points table with filters, importance context,
  source metadata, and persisted Telegram links; fetch item detail from Core
  rather than caching a parallel archive.

## V1 API Client Boundary

The app should expose feature-shaped methods, not raw URL construction in views:

```swift
struct CoreAPIClient {
    var baseURL: URL
    var tokenProvider: AuthTokenProvider
    var authMode: CoreAuthMode
}
```

Initial methods:

- `health()`
- `fetchSyncState()`
- `fetchCapabilities()`
- `fetchRecentMessages(limit:)`
- `searchMessages(query:limit:)`
- `listManagementAccounts()`
- `createAccount(...)`
- `deleteAccount(...)`
- `authStatus(accountID:)`
- `requestCode(accountID:phone:)`
- `submitCode(accountID:phone:code:password:)`
- `listOrigins(accountID:includeArchived:)`
- `discoverOrigins(accountID:includeTopics:includePrivate:topicLimit:)`
- `archiveOrigin(...)`
- `deleteOrigin(...)` exists in the client for API coverage, but Mac V1 origin
  removal uses archive semantics in the UI.
- `listBackupPolicies(accountID:)`
- `setBackupPolicy(...)`
- `deleteBackupPolicy(...)`
- `listParticipants(accountID:originID:)`
- `refreshParticipants(accountID:originID:limit:)`
- `listCaptureCursors(accountID:)`
- `listOperationEvents(accountID:status:limit:)`
- `listMediaFiles(accountID:chatID:messageID:limit:)`
- `fetchDailyPackageSchedule()`
- `updateDailyPackageSchedule(...)`
- `runDailySummaryJob(...)`
- `listDailySummaryJobs(...)`
- `listDailySummaryRuns(...)`
- `listDailySummaryRecords(...)`
- `fetchDailySummaryRecord(...)`
- `listDailyMessagePoints(...)`
- `fetchDailyMessagePoint(pointID:)`

## V1 Implementation Order

1. Profile and auth foundation: remote/local profiles, Keychain token storage,
   bearer header injection, `/healthz`, `/sync/state`, `/manage/capabilities`.
2. Dashboard: state, recent 100 messages, failed operation events, console link.
3. Accounts: list, create metadata, delete metadata, auth status, request code,
   submit code, 2FA password handling.
4. Origins and policies: discover origins, table filters/sorting, archive and
   restore, single-origin policy editor, tag chip editor.
5. Messages and search: recent messages view, search view, deleted/media/reaction
   display states.
6. Diagnostics: participants, participant refresh, capture cursors, media files,
   operation events.
7. Daily analysis: schedule/run progress, typed persisted summary records,
   validated message points, record/item inspection, and Telegram delivery
   configuration.
8. Local core runner: pinned PyPI install, secure workspace bootstrap,
   `run-local --web`, authenticated readiness, graceful lifecycle ownership, and
   an explicit custom-command escape hatch.
