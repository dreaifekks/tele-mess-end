# Tele Mess End

[![CI](https://github.com/dreaifekks/tele-mess-end/actions/workflows/ci.yml/badge.svg)](https://github.com/dreaifekks/tele-mess-end/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/dreaifekks/tele-mess-end.svg)](https://github.com/dreaifekks/tele-mess-end/releases/latest)
[![License](https://img.shields.io/github/license/dreaifekks/tele-mess-end.svg)](LICENSE)

**A native macOS app for running and managing your
[tele-mess-core](https://github.com/dreaifekks/tele-mess-core) Telegram
archive.**

Tele Mess End gives you a desktop view of a Tele Mess Core instance: capture
health, Telegram account login, which chats and topics get archived, archived
messages and media, and Core's daily analysis reports. It can connect to a Core
running on another machine, or install and run one on your Mac for you.

> [!NOTE]
> This is an early-stage project for a single operator. It is not affiliated
> with Telegram or OpenAI.

## How it fits with tele-mess-core

[tele-mess-core](https://github.com/dreaifekks/tele-mess-core) does the actual
work. It connects to Telegram, stores messages in a SQLite archive, runs daily
analysis jobs, and exposes a token-protected HTTP API.

Tele Mess End is a client for that API, the same one used by Core's built-in
`/console` web UI. The app keeps no copy of your archive. Everything you see is
read from the Core you are connected to, and every change is made through it.

## Features

- **Dashboard.** Archive and sync state, the live API contract version, the
  latest 100 messages, and failed or rate-limited operations, with a shortcut
  to Core's web console.
- **Accounts.** Add Telegram accounts and sign in with a login code and an
  optional two-step verification password.
- **Origins.** Discover the groups, channels, and forum topics your accounts can
  see. Filter, sort, archive, or restore them, and set per-origin backup
  policies and tags.
- **Messages.** Browse recent messages, run full-text search, and jump to the
  original message in Telegram.
- **Media.** Filter archived media by type, preview it inside the app, and open
  or copy the download link.
- **Daily Summary.** Start or cancel Core's daily analysis, follow job progress,
  read the generated reports, and soft-delete or restore them.
- **Message Points.** Browse the validated key points Core extracted from each
  day, filter them by importance score, and follow links back to the source
  messages.
- **Diagnostics.** Inspect operation events, capture cursors, and chat
  participants, and view the raw payload behind any row.
- **Settings.** Save several Core profiles and switch between them. Configure the
  daily analysis schedule, its scope, and delivery to a Telegram chat.
- **Updates.** The app checks for new releases once a day and installs them
  through the standard **Check for Updates…** menu command.

Sections appear only when the connected Core supports them, so an older Core
shows fewer sections.

## Requirements

- macOS 14 Sonoma or later.
- A Mac with Apple silicon for the prebuilt download. On an Intel Mac, build from
  source.
- A Tele Mess Core instance to connect to, or the ability to run one locally.
- For a local Core managed by the app: [uv](https://docs.astral.sh/uv/getting-started/installation/)
  and a Telegram API ID and hash from [my.telegram.org](https://my.telegram.org/apps).

Daily analysis is configured on the Core side. See the tele-mess-core
[daily-packaging guide](https://github.com/dreaifekks/tele-mess-core/blob/master/docs/daily-packaging.md)
before enabling it.

## Installation

1. Download the latest `TeleMessEnd-<version>-macos-arm64.dmg` from
   [GitHub Releases](https://github.com/dreaifekks/tele-mess-end/releases/latest).
2. Open the DMG and drag **TeleMessEnd** into **Applications**.
3. Launch it from Applications.

Release builds are signed with a Developer ID certificate and notarized by
Apple. Each release's notes state how that build was signed.

## Getting started

Open **Settings** with ⌘, and choose the **Core** tab. On first launch the app
already contains a **Local Core** profile. Pick the connection mode that matches
your setup:

| Mode | Choose it when |
| --- | --- |
| Remote | Core already runs on a server, NAS, or another Mac. |
| Managed local | You want the app to install and run Core on this Mac. This is the easiest start. |
| Custom local | You run Core from your own command, such as a source checkout. |

### Remote Core

1. Choose **Add Remote Core**.
2. Enter the **Base URL**, for example `http://192.168.1.20:8765`.
3. Leave **Auth** on **Bearer** unless your Core expects the `X-Api-Token`
   header.
4. Paste the Core's `server.token` into **New API token**.
5. Choose **Save**, then **Test Connection**.

### Managed local Core

Use the **Local Core** profile, or choose **Add Local Core**, and keep
**Runtime** set to **Managed PyPI**. The **Initial Setup** checklist then walks
you through three steps:

1. **Install Core.** The app uses uv to install a pinned version of
   `tele-mess-core` into a folder of its own, separate from your other uv
   tools.
2. **Configure Workspace.** Enter an account ID, your Telegram API ID and hash,
   a session name, and a timezone. The app then creates `config.yml` in
   `~/Library/Application Support/tele-mess-core`. It never overwrites an
   existing file. If you reuse an existing `config.yml`, enter its
   `server.token` in the **Connection** section and save.
3. **Start & Connect.** The app starts Core, waits until it answers, and
   connects.

After setup, **Start & Connect** is all you need. Quitting the app stops the
Core it started. The Core version and workspace path can be changed under
**Advanced runtime settings**.

### Custom local Core

Choose **Add Local Core** and set **Runtime** to **Custom Command**. Enter the
command that starts your Core and, optionally, a working directory. Then set the
base URL and token as you would for a remote Core. The command runs through your
login shell.

### First steps after connecting

1. In **Accounts**, add or select a Telegram account and sign in with the code
   Telegram sends you.
2. In **Origins**, choose **Discover** to list the chats your account can see,
   then enable backup on the ones you want to archive.
3. Watch new messages arrive in **Dashboard** and **Messages**.
4. Optionally, set up daily analysis under **Settings → Summary**.

## Privacy and security

- **Tokens stay in Keychain.** Each profile's API token is stored in the macOS
  Keychain. It is not written to app preferences or to the app's logs.
- **No local archive.** Messages, media, and reports stay in Core. The app only
  displays what it reads from the API.
- **Your credentials stay in your workspace.** For a managed Core, the Telegram
  API hash and the generated API token live in `config.yml`. The app makes that
  file readable only by your user account.
- **A Core configured by the app is local only.** The `config.yml` it creates
  binds Core to `127.0.0.1` and requires the API token for every request.
- **Protect remote connections.** The app accepts plain `http://` URLs, so the
  token travels unencrypted on such connections. Use HTTPS or a private network
  such as Tailscale for a remote Core.
- **Deleting a profile keeps your data.** It removes the profile and its saved
  token. The Core workspace and archive are left in place.
- **Update checks contact GitHub.** The app fetches the release feed from GitHub
  once a day.

## Building from source

You need macOS 14 or later and a Swift 5.9 or newer toolchain, from Xcode or
the Command Line Tools.

```bash
git clone https://github.com/dreaifekks/tele-mess-end.git
cd tele-mess-end
./script/build_and_run.sh      # build, bundle, and launch the app
./script/package_macos.sh      # build a DMG into dist/
./script/verify.sh             # run the full test suite
```

Without a Developer ID certificate, local builds are ad-hoc signed and are meant
for testing only.

## Documentation

| Document | Contents |
| --- | --- |
| [Development notes](docs/development.md) | Architecture, managed runtime internals, code signing, and tests |
| [Release process](docs/release.md) | Notarization, GitHub Releases, repository secrets, and Sparkle updates |
| [Core API surface](docs/core-api-surface.md) | How app features map to the Tele Mess Core API |
| [Design records](docs/adr/) | Architecture decision records |
| [tele-mess-core](https://github.com/dreaifekks/tele-mess-core) | The archive engine this app connects to |

## License

Apache License 2.0. See [`LICENSE`](LICENSE).
