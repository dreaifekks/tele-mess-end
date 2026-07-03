# Core API Surface For macOS UI

This file maps the known Tele Mess Core endpoints to first-pass macOS UI modules.

## Auth

Supported request auth:

- `Authorization: Bearer <token>`
- `X-Api-Token: <token>`

The app should store tokens in Keychain and let each saved core profile choose
its auth mode when needed. Bearer auth should be the default.

## Dashboard

Endpoints:

- `GET /sync/state`
- `GET /sync/messages?latest=true&limit=100`
- `GET /manage/operation-events?status=failed&limit=100`

UI:

- service connection status
- schema and message count
- last event
- account, origin, and participant counts
- recent 100 messages with `chat_title`
- failed operation events

## Accounts

Endpoints:

- `GET /manage/accounts`
- `POST /manage/accounts`
- `DELETE /manage/accounts`
- `GET /manage/accounts/auth/status`
- `POST /manage/accounts/auth/request-code`
- `POST /manage/accounts/auth/submit-code`

UI:

- account list
- add/remove account
- login status
- Telegram code flow
- 2FA password step

## Origins

Endpoints:

- `GET /manage/origins?account_id=...&include_archived=true`
- `POST /manage/discover-origins`
- `PATCH /manage/origins/archive`

Domain notes:

- default discovery skips private chats
- origin identity is `(account_id, origin_id, topic_id)`
- main group uses `topic_id = 0`
- topic is not a parent object
- archiving a group hides or semantically archives its topics

UI:

- Notion-like management table
- account filter
- archived/include archived filter
- search/filter by title/type/tag/policy
- batch selection
- archive/unarchive
- discover origins
- policy inspector

## Backup Policies

Endpoints:

- `GET /manage/backup-policies?account_id=...`
- `POST /manage/backup-policies`
- `PATCH /manage/backup-policies`
- `DELETE /manage/backup-policies`

Fields:

- `enabled`
- `capture_text`
- `capture_media_metadata`
- `download_media`
- `tags`

UI:

- origin-attached policy editor
- tag/chip editor matching console behavior
- batch policy assignment if the core API supports it later

## Members

Endpoints:

- `GET /manage/participants`
- `POST /manage/participants/refresh`
- `DELETE /manage/participants`

Domain note:

- participant cache does not affect the main message backup chain.

UI:

- read-only participants list first
- refresh action
- delete cache entry action after the read-only view is stable

## Messages And Media

Endpoints:

- `GET /sync/events?after=...`
- `GET /sync/messages?after=...&limit=...`
- `GET /sync/search?q=...`
- `GET /sync/media-files?account_id=...&chat_id=...`
- `GET /manage/capture-cursors`

UI:

- recent messages in Dashboard
- search view after Dashboard is stable
- media list by account/chat
- capture cursor diagnostics

## First Implementation Order

1. Core profile model, Keychain token storage, health probe via `/sync/state`.
2. Dashboard read-only data.
3. Accounts list and login flow.
4. Origins table with filters, discovery, archive/unarchive.
5. Backup policy and tag editor.
6. Members and media read-only views.
7. Refresh/delete and deeper diagnostics.
