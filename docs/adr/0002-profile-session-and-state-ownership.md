# ADR 0002: Profile Sessions and State Ownership

## Status

Accepted on 2026-07-10.

## Context

TeleMessEnd can switch between local and remote Core profiles while requests,
refresh loops, and edits are in flight. A shared array being non-empty does not
prove that it belongs to the selected profile. Without an explicit session
boundary, data loaded from Core A can remain visible after selecting Core B, and
late results from A can overwrite B's state.

The Core also owns archive state, origin importance, daily-package jobs, and
persisted summary records. Mirroring those records in app preferences creates a
second source of truth. The one exception is a small profile-scoped settings
fallback for UI continuity when an older schedule response omits its `delivery`
field.

## Decision

### One app-wide session and one main window

The app uses a single SwiftUI `Window` backed by one app-owned `AppModel`. It
does not advertise multiple main windows while selection, filters, refresh
loops, and the active Core session are shared. Supporting multiple independent
windows later requires explicit per-window feature state and a shared service
layer first.

### Profile changes are session transitions

Every profile change advances a session generation, clears Core-derived state
and profile-bound selections, resets validation and credential caches, then
reloads the visible feature without prompting for Keychain access.

The observable session revision and selected app section form the root content
load key. `ContentView` is the sole owner of feature loading; feature views use
session tasks only to clear local selections and drafts. The root loader waits
for an active operation, bootstraps the manifest/capabilities, redirects an
unsupported section to Dashboard, and then loads the resolved feature. This
avoids duplicate view/root requests racing through the same runtime.

Initial and session-transition loads use noninteractive Keychain access. Once a
session is observed, explicit sidebar navigation and manual refreshes may allow
Keychain authentication UI, so a protected token never degrades to an
unauthenticated request and the user still has a clear retry path.

Each logical operation captures one `CoreSessionContext` containing the profile
ID, generation, and typed client. Before committing a result, the model verifies
that the context is still current. Follow-up calls in the same operation use the
same captured client, so a mid-operation profile switch cannot redirect them to
another Core.

### Credentials are an injected boundary

`CredentialStore` abstracts Keychain access for the runtime and tests. User-
initiated validation may permit Keychain UI; refresh loops do not. An auth-
disabled local profile proceeds with no token, while an authenticated profile
without a noninteractive credential fails without opening a background prompt.
Tokens never enter logs or app preferences.

### Core remains the source of truth

Archive, importance, jobs, runs, and summary records are read from and mutated
through the Core API. Legacy local summary aggregation, hidden-summary state,
and importance overrides are removed.

`SummarySettingsStore` stores only profile-scoped UI/schedule preferences. When
the live schedule includes `delivery: null`, the local delivery draft is
cleared. When the field is absent, the draft may preserve the fallback for that
same profile because older live schemas omit the field entirely.

### Mutations expose success

User mutations return an explicit success value. Views clear selections,
dismiss creation state, or replace drafts only after success. Overlapping
operations are tracked independently so one operation finishing cannot clear
another operation's loading state.

Exclusive foreground operations serialize shared status/error ownership, while
replaceable message requests use a request revision so a late search cannot
overwrite a newer search. A successful mutation is committed locally before a
best-effort list refresh; a refresh failure is reported as pending instead of
turning the successful write into a false failure. Multi-origin operations
update each successful item immediately and report explicit partial completion
if a later item fails.

### Compatibility and verification are observable

The dashboard reads the API manifest opportunistically and shows its contract
version/hash. Sidebar features are limited to endpoints the manifest advertises;
if no manifest is available, the app keeps the full compatibility surface. A
new session performs this compatibility bootstrap even when the user was not on
Dashboard when switching profiles.

`script/verify.sh` is the local, CI, and release gate. The real regression suites
are small executable harnesses because the supported CommandLineTools runtime
lacks usable XCTest and Swift Testing modules.

The handwritten Core API files remain in the executable target for now. A
separate library target would require a deliberate public/package DTO surface
and would disrupt the script-based contract suites; that module boundary should
be designed as its own change instead of created through broad access-control
rewrites.

## Consequences

- Switching profiles cannot commit stale results or retain actionable data from
  the prior Core.
- Failed saves preserve the user's draft and selection context.
- The app keeps only true client preferences locally; Core-owned records remain
  authoritative.
- The shared model and refresh loops have an honest single-window lifecycle.
- Compatibility drift is visible without making the manifest a hard dependency.
- `AppModel` remains a broad application coordinator. Future feature-store
  extraction can proceed behind the tested session boundary instead of trying
  to solve state correctness and file layout simultaneously.
