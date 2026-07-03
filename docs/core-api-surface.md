# Core API Surface For macOS UI

This file maps the current `dreaifekks/tele-mess-core` `master` API surface to
the macOS V1 client.

Reference checked: `tele-mess-core` default branch `master` at `c4692c1`,
pushed `2026-07-03T10:12:28Z`.

## Runtime Model

The core is a single-user, multi-Telegram-account archive and management
service. It owns Telegram ingestion, SQLite archive state, backup policies,
media capture, participant metadata, and runtime operation events.

The Mac app is a native control and inspection client. It should not duplicate
the archive database in V1. The core remains the source of truth.

The core intentionally does not:

- forward messages to backup Telegram groups
- generate summaries
- run AI workflows
- model multiple product users or tenants

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
7. Local core runner: start/stop/status for a configured local `tele-mess-core`
   command after remote profile support is stable.
