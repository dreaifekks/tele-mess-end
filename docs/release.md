# Release Process

This document covers signing, notarization, and publishing TeleMessEnd
releases. Local build and verification steps live in
[development.md](development.md).

## Pre-release Checks

Run the verification gate and, ideally, a live smoke against the Core you
target:

```bash
./script/verify.sh
CORE_BASE_URL=http://127.0.0.1:8765 CORE_API_TOKEN=your-token ./script/smoke_core_api_live.sh
```

Pass tokens through the environment only. Do not write them into files, logs,
or release notes.

## Local Notarization

To notarize and staple a DMG locally, store notarization credentials once and
pass the profile name:

```bash
xcrun notarytool store-credentials tele-mess-end-notary \
  --key /path/to/AuthKey_KEYID.p8 --key-id KEYID --issuer ISSUER_UUID
NOTARIZE=1 NOTARYTOOL_KEYCHAIN_PROFILE=tele-mess-end-notary ./script/package_macos.sh
```

## Publishing a GitHub Release

Publish a GitHub Release DMG by pushing a version tag that matches `VERSION`:

```bash
git tag "v$(tr -d '[:space:]' < VERSION)"
git push origin "v$(tr -d '[:space:]' < VERSION)"
```

The release workflow (`.github/workflows/release-macos.yml`) runs on a
GitHub-hosted macOS runner, builds the DMG, and uploads it to the matching
GitHub Release. It reads these repository secrets:

| Secret | Purpose |
| --- | --- |
| `MACOS_SIGNING_P12` | Base64 of the Developer ID Application `.p12`, including the intermediate chain |
| `MACOS_SIGNING_PASSWORD` | Password of that `.p12` |
| `APPLE_API_KEY_P8_BASE64` | Base64 of the App Store Connect API key used for notarization |
| `APPLE_API_KEY_ID` | Key ID of that API key |
| `APPLE_API_ISSUER_ID` | Issuer ID of that API key |
| `SPARKLE_PRIVATE_KEY` | Contents of the exported Sparkle EdDSA private key; required for tag releases |

With the signing secrets the DMG is Developer ID signed, and with the API key
secrets it is also notarized and stapled. Without them the DMG is ad-hoc signed
and macOS Gatekeeper will warn on first open. The release notes state which of
the three applies.

The workflow currently builds one runner architecture, not an architecture
matrix. Release DMGs are named `TeleMessEnd-<version>-macos-<arch>.dmg`.

## Dry Run

To check signing and notarization without publishing, run the workflow
manually. A manual run stores the DMG as a workflow artifact and leaves Releases
alone:

```bash
gh workflow run release-macos.yml --ref master
```

## Sparkle Updates

The app checks for updates with Sparkle. Both bundle scripts write
`SUFeedURL`, `SUPublicEDKey`, and a daily automatic check interval into the
generated Info.plist. The feed URL points at the `appcast.xml` asset of the
latest GitHub Release.

First-time Sparkle setup:

1. Run `swift package resolve`.
2. Run `.build/artifacts/sparkle/Sparkle/bin/generate_keys --account com.dreaifekks.TeleMessEnd`.
3. Put the public key in `SUPublicEDKey` in the Info.plist template of both
   bundle scripts. The committed public key already matches the locally
   generated TeleMessEnd key.
4. Keep the exported private key outside the repository and add its contents as
   the `SPARKLE_PRIVATE_KEY` repository secret. Never commit the private key.

Tag releases generate `appcast.xml` from the signed and notarized DMG and
publish both assets to the same GitHub Release. Sparkle's generator records the
archive's hardware requirements. Users check, download, and install updates with
Sparkle's standard app-menu command and dialogs.
