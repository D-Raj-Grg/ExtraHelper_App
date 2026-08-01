# Changelog

All notable changes to the **ExtraHelper mobile app** (iOS + Android).

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions are patch-level: each release is a milestone's worth of work that shipped together. Dates are ship dates taken from git history. Each release ends with a collapsed **Technical** note listing the commits and the substance behind them.

The app is not published to the App Store or Play Store yet; `pubspec.yaml` stays at `1.0.0+1` until the first store build. Business rules live in Postgres and are shared with the web app — see `../extrahelper/CHANGELOG.md` for the server-side half of any release noted below.

> **Branch note.** 1.0.0 and 1.0.1 are on `main`. 1.0.2 through 1.0.6 currently live on `milestone-f-offline` and are not merged to `main` yet.

---

## [Unreleased]

### Changed
- **Navigation moved to a drawer.** Dashboard, Store room, Manager log and Account were five icon buttons crowded into the top-right of the app bar; each now has a named row in a drawer, opened from the hamburger or an edge swipe. The restaurant — and switching between restaurants — sits at the top of it.
- The app bar now names the screen you are on ("POS", "Store room") instead of the restaurant.
- Tables and Orders now sit in the app bar rather than in a separate strip below it.

### Fixed
- The sync indicator used to disappear whenever everything was sent, so the app bar changed width mid-service. Connection and anything waiting to send are now one band under the bar, on every screen: `Offline`, `Offline · 2 waiting`, `2 waiting to send`, or a refused write, each tappable for detail.
- Screens no longer clip at larger text sizes: titles are one line with an ellipsis, and the dashboard's subtitle strip sizes itself to the text.
- Two restaurants with the same name were indistinguishable when switching; each now shows its unique @handle.
- **Opening the app with no coverage after it sat idle overnight.** The phone spent about thirteen seconds on a spinner before showing the floor it already had saved. It now opens in about four — the app asks whether there's coverage before it asks the server anything.

<details><summary>Technical</summary>

- New `app/app_scaffold.dart` (`AppScaffold`) owns the drawer, the `SyncStrip` and the one-line title, so chrome can't drift per screen. In `app/` rather than `core/` so `core` never imports `features`. Leaves (composer, stock count) pass `showDrawer: false` and keep the back arrow.
- New `features/tenant/app_drawer.dart`; `TenantSwitcher` became `TenantDrawerHeader`; `AccountScreen` extracted out of `home_shell.dart`.
- `SyncStatusAction` + `OfflineBanner` collapsed into `SyncStrip` — the only coloured band in the app frame, so colour in the chrome means "not on the server yet". Icon + word + count on every state (greyscale-safe).
- Destinations are real go_router routes (`/dashboard`, `/store-room`, `/manager-log`, `/account`) that replace each other, with a `PopScope` sending Back to the POS.
- The POS `TabController` moved to the shell and feeds `AppBar.bottom`; `PosScreen` takes it as a parameter.
- `test/shell_chrome_test.dart` — 10 widget tests covering drawer permission gating, destination navigation, the header's one-vs-many restaurant behaviour, and every `SyncStrip` state.
- New `data/local/cache_backed.dart` (`cacheBackedRead`) backs both identity providers: offline serves the cache without attempting the network, online caps the attempt at 6s before falling back, and the connectivity check itself is capped at 2s. Root cause: `supabase`'s `_getAccessToken` awaits a token refresh before every request once the session is expired, and gotrue retries that refresh until the next backoff would outrun its 10s tick — so each identity read paid ~10s offline before its `catch` reached the cache. Both providers now watch `isOnlineProvider`, so returning coverage refetches. 8 unit tests; 128 passing overall.

Verified on the Android emulator signed in as owner: drawer navigation and selected state, Back returning to the POS, the composer as a leaf with a back arrow, the strip under airplane mode, a greyscale crop of that band, and screenshots at text scale 1.0 and 1.5. Not run on iOS.
</details>

### Outstanding verification (tracked in `TASKS.md`)
- Offline path on a physical iPhone (only emulator/simulator verified).
- `menu.86` permission key.

---

## [1.0.6] — 2026-07-31 · Store room

### Added
- **Store room screen**: on-hand quantities, stock counts, adjustments and waste write-offs, and barcode scanning to find an item.
- A stock count taken in a walk-in with no signal is queued and lands exactly once when signal returns. Re-counting a shelf replaces the queued number instead of queuing a second write.

### Changed
- Adjustments stay online with an honest failure rather than queueing — an adjustment is a delta, so replaying it would move stock twice. A count is an absolute quantity, so replay is safe.
- Posting a count is blocked while anything is still owed to the server, so you can't post over a number the server never saw.

### Security
- The stock-write routine behind every adjustment and waste write-off had **no authorization at all** — no role check, no permission check — while the inventory tables were protected only by restaurant scope. Any member could move stock through the API, and nothing recorded who. Now permission-checked and audited, with a new routine replacing a direct table write anyone could have made against any count.

<details><summary>Technical</summary>

`00209dc`.

- `adjust_inventory` was SECURITY INVOKER with the only guard being `requireRole(...)` in the TypeScript action (whose comment claimed "RLS + role enforced inside" — it did not). Now gated on `inventory.edit` and audited; new `set_stock_count_actual` replaces the direct `stock_count_items` write. Migration lives in the web repo — see `../extrahelper/TASKS.md`.
- Counts go through the outbox (absolute quantity → replay-safe); adjustments do not (`adjust_inventory` takes no idempotency key).
- Count rows keyed on the count line's id: without a key Flutter matches by index, so filtering hands row 0's live controller — holding a number typed for another shelf — to whatever is now first, and blurring records it against the wrong stock.
- Verified on the Android emulator against the live project including airplane mode.
</details>

---

## [1.0.5] — 2026-07-31 · Owner dashboard

### Added
- **Dashboard** for owners: KPI tiles, a revenue trend and the day's open work — the same figures the web dashboard shows, from the same server call.

### Changed
- The dashboard is network-only on purpose. Every other read in the app is cache-first so a waiter keeps working on dead wifi; for an owner glancing at today's money, a silently stale figure is worse than an honest "couldn't load".

<details><summary>Technical</summary>

`dc2b4a7`.

- Reads `dashboard_summary`, the RPC the web dashboard was refactored onto in the same period. Aggregation lives in Postgres because `package:intl` carries no IANA timezone database — bucketing bills into tenant-local days in Dart would fork the definition of "which day is this". Timestamps come back pre-formatted in the tenant's zone for the same reason.
- Chart is hand-painted, not a charting dependency: one zero-filled series, no axes, no interaction (a gap would draw as a straight line between the days either side). Peak carries a dot and a printed figure, both ends print their dates, and there's a `Semantics` summary — nothing conveyed by the line alone.
</details>

---

## [1.0.4] — 2026-07-27 · Icon and splash

### Added
- App icon and splash screen on both platforms, rendered from the web app's own mark so the two clients look like one product on a home screen. Light and dark splash both first-class.

### Fixed
- The launcher name read `extrahelper` on Android and `Extrahelper` on iOS.

<details><summary>Technical</summary>

`69170c8`, `daf454f`.

- iOS: full-bleed square, no baked corners (iOS masks its own; a pre-rounded PNG shows its corners inside the mask) and no alpha channel, which the App Store rejects. Android: adaptive pair — near-black background layer, glyph inside the 66% safe zone so a circular mask doesn't clip the fork's tines. Android 12+ clips the splash icon to a 768px circle on a 1152px canvas, so that variant is sized to fill it.
- Re-rendered from `extrahelper/public/icon.svg` rather than re-drawn. Verified by screenshot on both platforms.
- `daf454f` moves the two outstanding verification items from prose into `TASKS.md`.
</details>

---

## [1.0.3] — 2026-07-27 · Manager ops (Milestone G)

### Added
- Long-press a dish to mark it **sold out**; long-press a table to set its **state**.
- **Manager log** listing voids, discounts, stock changes and table changes, with who did them and why.
- A dish that sold out while the app was open is still sold out after a cold start — 86 arrives over Realtime and is written through to the local cache.

### Fixed
- The shell flashed "No ordering access" at every launch — an empty permission set while the tenant was still resolving read as "loaded, and you may do nothing".

### Security
- 86'ing a dish and setting a table's state now go through server-side routines that hold the role check and write an audit row. Both used to be plain column updates whose role check lived in a web server action, so any member of the restaurant could do either straight through the API, unrecorded.
- Setting a table free now refuses while it still has a live order — that used to hide the order from the board while the kitchen was cooking it.

<details><summary>Technical</summary>

`c35360c`.

- New shared RPCs `set_item_86` and `set_table_state`, mirroring the previous role sets exactly (86 = owner/manager/kitchen; state = owner/manager/receptionist/waiter/cashier). Same change lands web-side in `1.0.12` there.
- Both queue through the outbox as new kinds — last-write-wins on a single row, so replay is safe.
- Discounts deliberately absent: `apply_item_discount` requires the item to be on a bill, and bills are created at checkout, which is web-only in v1.
- Cross-platform check: with the iOS simulator untouched, putting a dish back on from Android flipped iOS's cached flag — Realtime subscription and cache write-through both work there. 82 tests passing.
</details>

---

## [1.0.2] — 2026-07-27 · Offline (Milestone F)

### Added
- **The app works with no coverage.** Every order write goes through a durable outbox on the device and is attempted from there — online included — so a connection that drops mid-call has already recorded the write under a key that can't duplicate the order. Reads come from a local cache first, so the tables board and menu render offline.

### Fixed
- Voiding a line could crash the whole app.
- Five offline bugs, all the same shape — a read blocking a write: a cold start rendered "No ordering access" because memberships and permissions were network-only; tapping a table waited on a long network timeout; committing an order waited on a table refresh after the write was already durable; the menu was only fetched when the composer opened; and a fresh install could delete the permissions the shell had just written.

<details><summary>Technical</summary>

`9cc7bf9`.

- Replay engine is pure Dart over an `OutboxStore` + `OutboxTransport` — no widgets, no sqlite — which makes the five PLANNING.md rules testable without an emulator: the key is minted at enqueue and never regenerated, enqueue precedes the attempt, a server reject dies immediately while a transient failure retries under a cap of 5, `inflight` is persisted before the call, and replay is serial so an amend can never land before its create.
- Adds a fourth outbox kind beyond the three PLANNING.md names: `fire`. Sending to the kitchen is its own idempotent RPC, and an offline session is normally N adds then one fire; folding it into another entry's payload would fire too early or lose it.
- Reads are cache-first from a tenant-stamped Drift cache; `adoptTenant` no longer wipes the cache when `cache_meta` doesn't already name the tenant.
- Crash: `_askVoidReason` disposed its `TextEditingController` the line after `await showDialog(...)`, but that future resolves a frame before the field unmounts, so the field's own dispose hit a dead controller. The dialog owns its controller now.
- 68 unit tests; Android emulator in airplane mode (an order composed offline reaches the kitchen exactly once, confirmed in the database); iOS simulator for build, launch, schema and cache parity.
</details>

---

## [1.0.1] — 2026-07-27 · Waiter ordering (Milestone E)

### Added
- **Take an order from the phone.** Tables board with live states, photo-first dish grid, options sheet, send to kitchen, add to an order already with the kitchen, and void a fired line with a reason.
- Dishes with variants show a price **range**, so a dish never advertises a base price nobody can order.
- The options sheet forces a variant and offers only add-ons linked to that dish, because the server rejects anything else.
- Voiding names the real consequence instead of asking "are you sure?".

### Fixed
- Tapping an occupied table opened an empty "New order" — one tap away from a second order on a table that already had one.

<details><summary>Technical</summary>

`5628153`.

- One composer serves create and amend; everything below it reads a `CartController` and asks about capabilities (`canDelete`, `needsVoidReason`, `hasPendingCommit`), never a mode flag. `CreateCart` batches locally and commits in one `place_staff_order` call with a client-minted idempotency key reused across retries (a fresh key per attempt is how one tap becomes two orders; the outbox in 1.0.2 depends on the key being caller-owned). `AmendCart` sends each edit immediately, because a line already on a kitchen ticket needs a reasoned, audited void.
- Realtime uses `setAuth` with the user JWT, or RLS drops every event and the board merely looks "not live".
- Repositories map rows into plain Dart models and never leak `PostgrestException` past their boundary.
- Bug: `_openTable` read `activeOrdersProvider` synchronously, but the Tables tab never watches it, so on a fresh launch it was unbuilt and read as "no open order". Now awaits the future.
- Verified against the live project end to end (status `in_kitchen`, `waiter_id` set, `name_snapshot` "Buff Sekuwa (KG)", `unit_price` 168000, one KOT, table flipped to Occupied; amend produces a second KOT with only the new line). 38 tests passing.
</details>

---

## [1.0.0] — 2026-07-26 → 2026-07-27 · Shell, design system, sign-in (Milestones A–C)

First working build on both platforms: it signs a user in, resolves their restaurant and permissions from the server, and renders it in the web app's design language.

### Added
- **iOS and Android app shell** with the Supabase client wired natively and verified on both an iPhone simulator and an Android emulator.
- **Sign in**, restaurant resolution, restaurant switcher for people who belong to more than one, and permissions fetched from the server.
- A pending membership says "waiting for approval" rather than "no access" — different problems.
- The session survives a cold restart; being dropped from a restaurant doesn't look like being signed out.
- **Design system ported from the web app**: palette converted from its source rather than eyeballed, semantic colours only, money formatting with the restaurant's currency and locale, tabular figures, and staff-readable labels instead of raw status words. Veg mark, table glyph, dish thumbnails with initials fallback and menu tiles all ported, including the web's price-range fix.
- The app ships its own font, so it renders correctly on dead wifi. Tap targets forced to at least 44px.
- Debug-only design gallery — one screen showing every state, so the "never colour alone" rule can be checked in greyscale.

<details><summary>Technical</summary>

`3ee3a07`, `c310a91`, `ad615b0`.

- Bundle id `com.extrahelper.app` rewritten across Gradle namespace/applicationId, all pbxproj entries and the Kotlin package path. `lib/` layered per PLANNING.md: `core`, `data/{supabase,local,sync}`, `features/{auth,tenant,pos}`, `app`. Config via `--dart-define-from-file=env.json` (publishable key only; `env.json` gitignored); missing config throws at startup naming the command. Strict `analysis_options.yaml` — `unawaited_futures` is an error, because a dropped future here is a lost order.
- Dependency decisions worth not re-litigating: `flutter_riverpod` pinned to 2.x (riverpod 3 depends on `package:test`, whose Dart 3.10.7-compatible versions force `web_socket_channel <3` while `realtime_client` requires `^3`; unlocks with an SDK bump, not constraint juggling); `sqlite3_flutter_libs` deliberately absent (resolves to `0.6.0+eol`); `Supabase.initialize` uses `publishableKey` (`anonKey` deprecated in 2.16.0).
- `tokens.dart` converted from the web's oklch source in `app/globals.css` — re-convert if the web palette changes. Semantic colour is a `ThemeExtension` read as `context.semantic.good`, so no call site can reach a raw `Colors.green`. Figtree bundled as a variable font.
- Memberships filter to `status='active'`; a stored tenant choice that no longer matches a live membership falls back to the first; permissions default to false while loading; one redirect in the router decides where anyone lands, holding position while memberships load.
- Android notes captured in `TASKS.md`: the Gradle 8.14 distribution is a 224 MB download this network stalls on, `--target-platform android-arm64` keeps the build tree from reaching 1.7 GB, and a killed build leaves a stale lock in `android/.gradle`.
- `flutter analyze` clean, `dart format` clean, 22 tests passing at C.
</details>

---

[Unreleased]: #unreleased
