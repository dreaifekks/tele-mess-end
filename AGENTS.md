# TeleMessEnd Agent Notes

This repository is the macOS client for `tele-mess-core`. Keep client behavior
aligned with the core API contract; do not duplicate archive state locally.

## Core API Confirmation

Before changing API-facing code, confirm which core the app is currently using.
The app stores profiles in macOS defaults under bundle
`com.dreaifekks.TeleMessEnd`:

```bash
defaults read com.dreaifekks.TeleMessEnd teleMessEnd.coreProfiles
defaults read com.dreaifekks.TeleMessEnd teleMessEnd.selectedProfileID
```

If the value is displayed as plist data, use `PlistBuddy` against
`~/Library/Preferences/com.dreaifekks.TeleMessEnd.plist` to inspect it. Do not
print or store Keychain tokens in logs, responses, commits, or memory.

For a remote core profile, use the selected profile's `baseURLString` as
`CORE_BASE_URL`. For the devNuc deployment this is commonly
`http://100.92.194.31:8765`, but verify the selected profile instead of assuming
it. Confirm the live API with the manifest and capability endpoints:

```bash
curl -sS -H "Authorization: Bearer $CORE_API_TOKEN" "$CORE_BASE_URL/manage/api-manifest"
curl -sS -H "Authorization: Bearer $CORE_API_TOKEN" "$CORE_BASE_URL/manage/capabilities"
CORE_BASE_URL="$CORE_BASE_URL" CORE_API_TOKEN="$CORE_API_TOKEN" script/smoke_core_api_live.sh
```

For a local core profile, the default base URL is `http://127.0.0.1:8765`.
Start the configured local core command from the app or run the configured
`tele-mess-core` server separately, then confirm the same endpoints:

```bash
CORE_BASE_URL="http://127.0.0.1:8765" CORE_API_TOKEN="$CORE_API_TOKEN" script/smoke_core_api_live.sh
```

When auth is disabled for a local test core, omit `CORE_API_TOKEN`. When auth is
enabled, pass the token through the environment only and avoid echoing it.

Use `script/test_core_api.sh` for typed client contract coverage without a live
server, and `swift build` / `swift test` for package-level validation.
