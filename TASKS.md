# TASKS — ExtraHelper Mobile (Flutter)

> Check this before starting work. Mark tasks done immediately (`[x]`). Add newly discovered tasks
> under the right milestone (or Backlog). Milestones map to `PLANNING.md` §6.
> Anything that also changes the web app or the schema gets an entry in `../extrahelper/TASKS.md` too.

**Legend:** `[ ]` todo · `[~]` in progress · `[x]` done · `[!]` blocked (see Open Questions)

**Scope decided 2026-07-26:** first build = Milestones 0–2 (shell + waiter ordering create/amend +
native offline queue). Amend goes through a **new shared RPC** with the web refactored onto it.
Material 3 with ported design tokens. Riverpod + Drift. Login + join-by-code only — restaurant
creation stays web-only.

---

## Milestone A — Toolchain & scaffold

- [x] Install CocoaPods — **1.17.0** via `brew install cocoapods`. Validated by a real `pod install`
      during the iOS build (47s), so the "no iOS plugins" trap is closed.
- [x] Install Android `cmdline-tools` + accept licenses — `cmdline-tools` 21.0 unpacked to
      `~/Library/Android/sdk/cmdline-tools/latest`, all licenses accepted. `ANDROID_HOME` +
      `cmdline-tools`/`platform-tools` on `PATH` appended to `~/.zshrc`. `sdkmanager` needs a JDK;
      Android Studio's bundled JBR serves (`/Applications/Android Studio.app/Contents/jbr/Contents/Home`).
- [x] `flutter doctor` clean — **"No issues found!"**: Flutter 3.38.7 ✓, Android toolchain (SDK
      36.1.0) ✓, Xcode 26.2 ✓.
- [x] `git init` + `.gitignore` — repo on `main`, remote `origin` =
      `https://github.com/D-Raj-Grg/ExtraHelper_App.git`. `env.json` gitignored.
- [x] `flutter create` — `--platforms=ios,android` only. Bundle id rewritten from the generated
      `com.extrahelper.extrahelper` to **`com.extrahelper.app`** in three places: Gradle
      `namespace` + `applicationId`, all 6 `PRODUCT_BUNDLE_IDENTIFIER` entries in `project.pbxproj`,
      and the Kotlin package (file moved to `kotlin/com/extrahelper/app/` — the package declaration
      and the Gradle namespace must agree).
- [x] Flutter version — **3.38.7 / Dart 3.10.7** (Homebrew cask). Recorded in `PLANNING.md` §3.
      Attempted an upgrade to cask 3.44.8 for Riverpod 3 (see below) and **abandoned it**: Google's
      mirror served ~65 KB/s, hours away, and the stack resolves fine on 3.38.7.
- [x] Dependency stack resolved — `supabase_flutter 2.16.0`, `flutter_riverpod 2.6.1`,
      `go_router 17.3.0`, `drift 2.34.2` + `drift_dev 2.34.0` (`analyzer 10.0.1`),
      `path_provider 2.1.6`, `path 1.9.1`, `connectivity_plus 7.3.1`, `uuid 4.6.0`,
      `build_runner 2.15.1`. Constraints and the reasoning behind them are commented in
      `pubspec.yaml`.
- [x] Supabase config — `--dart-define-from-file=env.json` (URL + **publishable** key only),
      `env.json` gitignored, `env.example.json` committed, `lib/core/env.dart` fails loudly at
      startup naming the exact command when unset. Run/build commands documented in `README.md`.
- [x] Folder skeleton — `lib/{core,core/theme,data/supabase,data/local,data/sync,features/{auth,tenant,pos},app}`.
- [x] Lints + checks — strict `analysis_options.yaml` (`strict-casts`, `strict-raw-types`,
      `unawaited_futures: error` — a dropped future here is a lost order), `flutter analyze` **No
      issues found**, `dart format` clean, `flutter test` **2 passing** (`test/env_test.dart`).
- [x] **Verify iOS** — built for simulator, installed and launched on iPhone 17 Pro (iOS 26):
      renders, Supabase client initialises, dark theme applied. Screenshot-verified.
- [x] **Verify Android** — debug APK (84 MB, arm64) built, installed and launched on a Medium Phone
      API 36 emulator (`arm64-v8a`, Android 16): renders, Supabase client initialises, light theme.
      Screenshot-verified, no crash in logcat.
- [x] Commit + push to `origin main`.

**Android build notes** (this took three attempts; none of it was the app code):
- The Flutter template's wrapper wants **`gradle-8.14-all.zip` (224 MB)**, and this network stalls
  silently on large transfers. Fetched it out-of-band with a resuming, stall-aborting transfer
  (`curl -C - --speed-time 20 --speed-limit 2000`), verified with `unzip -t`, and placed it at
  `~/.gradle/wrapper/dists/gradle-8.14-all/<hash>/gradle-8.14-all.zip`. Once unpacked, the actual
  build takes **33 s**.
- **Build one ABI.** The default builds `android-arm`, `android-arm64` and `android-x64`, and the
  tree hit **1.7 GB**. `--target-platform android-arm64` is all an Apple-silicon emulator or a
  modern phone needs. `build/app/intermediates` alone is ~970 MB and is safe to delete after.
- A killed build leaves a **stale Gradle lock** (`android/.gradle/8.14/fileHashes`) that fails the
  next run with "Cannot lock file hash cache". Fix: kill the daemons, `rm -rf android/.gradle`.
- Both failures during this milestone were **ENOSPC**, not code. A cold three-ABI Gradle build plus
  a booting emulator wants several GB, and this volume runs at ~99%.

**Three findings worth keeping** (all cost time to establish):

1. **Riverpod is pinned to 2.x, not 3.** `riverpod 3.3.2` depends on `package:test`, and the `test`
   versions compatible with Dart 3.10.7 force `web_socket_channel <3`, while `realtime_client`
   (inside `supabase_flutter`) requires `^3`. Riverpod 3 needs Dart ^3.11 — so it unlocks with a
   Flutter SDK bump, not with any constraint juggling. Nothing else in the stack was blocking:
   drift resolved to its current 2.34.2.
2. **`sqlite3_flutter_libs` must NOT be added.** It resolves to `0.6.0+eol`, whose own README says
   it "no longer does anything" — `sqlite3` 3.x loads SQLite through Dart build hooks instead.
   Adding it back would be a regression. Removed, and noted in `pubspec.yaml`.
3. **`Supabase.initialize(anonKey:)` is deprecated** in 2.16.0 → use `publishableKey:`. Caught by
   `flutter analyze`, exactly the class of drift `AGENTS.md` exists to catch.

## Milestone B — Design system port ✅ (2026-07-27)

- [x] `core/theme/tokens.dart` — light + dark palette **converted** from the web's oklch tokens in
      `app/globals.css` (an oklch→sRGB conversion, not an eyeballed match), so both clients render
      one palette. Tinted neutrals, never pure black. Re-convert if the web palette changes.
- [x] Semantic colour as a `ThemeExtension` (`SemanticColors`) — good/warning/danger/info/attention
      + neutral, read as `context.semantic.good`. Call sites cannot reach a raw `Colors.green`,
      which is the rule the web enforces with tokens-only Tailwind classes.
- [x] `core/format/money.dart` — `money()` + `moneyRange()`, locale pinned `en_US` to match the web,
      currency always from `tenant_settings`. `tabularFigures` + a `.tabular` TextStyle extension.
- [x] `core/format/labels.dart` — table state / order status / order type / bill status / role.
      Fallback humanizes an unknown enum rather than leaking snake_case.
- [x] Tap targets ≥44px — `Tokens.tapTarget` applied to every button theme and to `AppChoiceChip`.
- [x] `VegMark` — circle vs triangle, null renders nothing.
- [x] `AppChoiceChip`, `MenuTile`, `TableGlyph`, `DishThumb` + `monogram()` ported. `MenuTile` carries
      the web's price-**range** fix, so a variant dish never advertises an unbuyable base price.
- [x] Figtree bundled (`assets/fonts/Figtree.ttf`, variable font — weights via `FontVariation`, not
      four statics). Bundled, never fetched: a staff app must render its own type on dead wifi.
- [x] **Verify: greyscale screenshot passed.** Veg circle vs triangle distinguishable, every table
      state carries its word, selected chip carries a check, occupied seats read solid, count badge
      and monograms legible. Colour carries nothing on its own. Light (Android) and dark (iOS) both
      confirmed. Built `features/dev/design_gallery.dart` (debug-only route) specifically to make
      this checkable — reaching these states on real screens costs minutes of setup each.
- [x] Tests: `money_test`, `labels_test`, `monogram_test`.

## Milestone C — Auth, tenant context, permissions (shell) ✅ (2026-07-27)

- [x] `supabase_flutter` init + session persistence + auth state stream (`supabase_providers.dart`).
      The stream is seeded from the current session — waiting for the first `onAuthStateChange`
      event would flash the login screen at a signed-in user on every cold start.
- [x] Login screen — email + password, `AuthRepository` never leaks `AuthException`;
      `friendlyAuthError` mirrors the web's mapping so a failure reads the same on both clients.
- [x] Sign out, and a session that expires or is revoked while backgrounded — the router listens to
      the auth stream, so it resolves wherever the app happens to be.
- [x] Tenant context — `user_tenants` filtered to **`status = 'active'`**; a pending membership is a
      request, not access. A stored tenant choice that no longer matches a live membership falls
      back to the first rather than selecting nothing (being dropped from a restaurant must not look
      like being signed out).
- [x] Tenant switcher — hidden when the user belongs to one restaurant. Choice persisted via
      `shared_preferences` (the web uses a cookie), validated against live memberships before use.
- [x] Join-by-code → `redeem_join_code`, with the RPC's `22023` mapped to plain language. The screen
      teaches the next step and distinguishes *waiting for approval* from *no access*.
- [x] Permission gate — `get_my_permissions` → `permissionsProvider` / `hasPermissionProvider`.
      **Defaults to false while loading** so a screen never flashes an action the user then loses.
- [x] Navigation (`go_router`) — **one** redirect decides where anyone lands; screens never navigate
      on sign-in/out. Holds position while memberships load rather than bouncing a user to /join for
      the second it takes to answer. Design gallery routed debug-only.
- [x] **Verify — full chain driven on a real Android emulator (arm64, Android 16)**: sign in as
      `clixacom@gmail.com` → tenant **"The Sekuwa Station" (Owner)** → currency **NPR** rendering
      `NPR 1,234.56` through `money()` → timezone **Asia/Kathmandu** → **9 permission keys** from
      `get_my_permissions`. Tenant switcher listed both memberships with the active one checked and
      switched cleanly. **Session survived a cold restart** (force-stop → relaunch → straight to
      home, no login flash). Sign out returned to login. A wrong password produced
      "That email or password is wrong." with icon **and** colour — proving the Supabase round-trip
      and the error mapping end to end.
- [~] **iOS**: builds, launches, Supabase client initialises, theme renders, and the router
      correctly redirects an unauthenticated user to /login — all screenshot-verified. The
      *signed-in* chain was **not** driven on iOS: macOS blocks synthetic keystrokes into the
      Simulator without Accessibility permission for the terminal, so the credentials can't be
      typed. Nothing iOS-specific is untested by design — the chain is pure Dart over
      `supabase_flutter` + `shared_preferences`, both already proven to load on the device. To close
      it: grant Terminal Accessibility (System Settings → Privacy & Security → Accessibility), or
      sign in by hand once in the Simulator.
- [ ] Cross-tenant isolation check (a tenant-B user sees zero tenant-A rows) — deferred to
      Milestone E, when there are actual rows to read. RLS covers it server-side today.
- [x] Tests: `auth_error_test`, `membership_test` (incl. `tenant_settings` arriving as either an
      object or a single-element list — get that wrong and a Nepali restaurant silently renders USD).

## Milestone D — Shared amend RPC ✅ (2026-07-27)

- [x] Migration `20260727090000_amend_order_add_item.sql` — `security definer`,
      `search_path = public`, `revoke from anon, public` + `grant to authenticated` naming the full
      8-arg signature. Verified live: exactly one function object, no stale overload, ACL is
      `authenticated` only.
- [x] Pricing lifted verbatim from `place_staff_order`; gated on `has_tenant_role` **and**
      `has_permission`; rejects a non-editable order, an 86'd item, a foreign variant, and any
      modifier not linked to *this* item via `item_modifiers`; inserts the line and its
      `order_item_modifiers` **in one transaction**.
- [x] Web `addItem` refactored to a thin wrapper (~95 lines → ~15). Signature and `PosState` return
      unchanged, so every caller stayed put. `tsc` + `eslint` clean. RPC added to
      `database.types.ts`.
- [x] **Verified against the live dev project.** Cent parity: the same item + KG variant + two
      add-ons through **both** paths gives `188000` and `"Buff Sekuwa (KG)"` with 2 modifier rows
      totalling 20000 — matching the reference case (38000 + 130000 + 15000 + 5000). Seven negative
      cases each rejected for the *right* reason: unlinked modifier, variant from another item, item
      outside the tenant, unknown order, 86'd item, closed order, unauthenticated caller. All test
      rows removed afterwards (`item_modifiers` back to 0, no item left 86'd).
- [x] Mirrored into `../extrahelper/TASKS.md`; committed there as `36837ae`.

**One deliberate difference from the create path:** create *skips* an 86'd line so a queued offline
order isn't rejected wholesale; amend *raises*, because an amend is a live, deliberate tap and the
waiter must be told.

**A bug this caught before shipping:** `has_permission` is `(_tenant, _key)`, and the generated
types list args **alphabetically**, so they don't reveal the real order. The first version called it
backwards. plpgsql resolves inner calls at run time, so it created cleanly and would have failed on
**every amend** in production.

## Milestone E — Waiter ordering, online ✅ (2026-07-27)

- [x] Tables board — floors + tables, `TableGlyph`, state as colour **plus** label plus seat fill.
- [x] Realtime table states — `realtime.setAuth` with the user JWT on connect (without it RLS
      silently drops every event and the board merely looks "not live"); changed rows merged in
      place rather than refetching the world.
- [x] Order composer, one surface, capability-shaped `CartController` — `canDelete`,
      `needsVoidReason`, `hasPendingCommit`. `CreateCart` batches locally and commits in one
      `place_staff_order` call with a **client-minted idempotency key reused across retries**;
      `AmendCart` fires each edit at the server immediately.
- [x] Destination — dine-in seeded from the tapped table, or takeaway.
- [x] Dish step — category chips, search, photo-first grid, 86 blocked, **price range** on the tile
      and in the accessibility label.
- [x] Item options sheet — variant forced when any exist, add-ons (only those linked to the item),
      cooking note, 44px qty stepper.
- [x] Cart — variant folded into the line title, running total, tabular figures, stable-id keys.
- [x] Create → `place_staff_order`; fire → `fire_order`; amend → `amend_order_add_item`; void →
      `void_order_item` behind a reason dialog that names the real consequence.
- [x] Order list with live status, and an empty state that teaches the next step.
- [x] Errors surfaced honestly — RPC prose mapped to plain language, never swallowed.
- [x] **Verified on a real Android emulator against the live project**, end to end:
      tables board renders real floors (C1 free / A1–A3 bill-requested, correct colours and fills) →
      tap free table → composer opens as "New order · Table C1" → **Buff Sekuwa tile shows
      "NPR 1,080.00 – 1,68…", not the unbuyable NPR 380 base** → options sheet forces the variant →
      pick KG → cart reads NPR 1,680.00 → Send to kitchen. Database confirms: status `in_kitchen`,
      **`waiter_id` set**, `name_snapshot` "Buff Sekuwa (KG)", `unit_price_cents` 168000
      (38000 + 130000), **1 KOT**. Table flipped Free → Occupied on the board.
      Reopening the table opens **"Add to order"** with the fired line shown as "With the kitchen",
      no qty stepper, and a block icon instead of delete. Adding a dish went through
      `amend_order_add_item` (Sukuti Sadeko, 30000, status `draft`), and firing it produced a
      **second KOT with only the new line** — a KOT amendment, not a reprint. Voiding it required a
      reason, set `is_void`, and wrote an `audit_logs` row.
      All test rows deleted afterwards and C1 restored to `free`.
- [x] Tests: `cart_test` — price range excludes optional add-ons, cart line pricing matches the
      server to the cent, variant folded into the title, merge signature ignores add-on order and
      the local id, `toRpcJson` omits absent options, voided lines leave the total, `canFire` and
      `isClosed` transitions.

**A bug caught during device verification:** tapping an *occupied* table opened "New order" with an
empty cart instead of amending. `_openTable` read `activeOrdersProvider` synchronously, but the
Tables tab never watches it, so on a fresh launch it was unbuilt and `.valueOrNull` returned null —
which read as "no open order" and would have started a **second order on an occupied table**. Fixed
by awaiting `activeOrdersProvider.future` so the answer is real rather than merely available.

## Milestone F — Offline

- [ ] Drift schema — cache tables (items, variants, modifiers, `item_modifiers` links, categories,
      tables, floors) + `cache_meta(tenant_id, fetched_at)` + `outbox`.
- [ ] Cache refresh on foreground and on Realtime change. **Tenant-stamped**: switching tenant wipes
      and refetches, so one tenant's menu can never render under another.
- [ ] Outbox — `kind` (`order` | `amend_add` | `amend_void`), `payload_json`, `idempotency_key`,
      `attempts`, `state` (`pending|inflight|done|dead`), `last_error`.
- [ ] **All** order writes go through the outbox, online included — enqueue first, then attempt, so
      a mid-flight network throw is already durable under the same key.
- [ ] Replay engine — serial per order, re-checks connectivity between entries (an amend must never
      land before the create it belongs to), `inflight` persisted inside a transaction before the
      call, retry cap 5.
- [ ] Server-reject → `dead` immediately with the error kept; transient → retry without burning the
      cap toward a silent drop.
- [ ] Offline-created orders — composer holds a local `draft_id`; amends against a not-yet-synced
      order merge into that pending create's payload instead of enqueuing separate ops.
- [ ] Connectivity watcher + a pending-count badge and a dead-entry warning in the app bar.
- [ ] **Verify — unit tests, no emulator** (the sync layer is pure Dart): double-enqueue → one row;
      kill mid-`inflight` → restart re-attempts under the same key, no duplicate; server-reject →
      `dead`, not retried; 6 transient failures → dead after 5, error preserved; tenant switch →
      cache wiped.
- [ ] **Verify on a real device in airplane mode** (a simulator's network stubbing is not the same
      thing): take a full order offline → return to coverage → the order reaches the kitchen
      **exactly once**.

## Backlog / Later phases

- [ ] Owner dashboard — KPI tiles + revenue chart, read-only. Closes the `mobile (Flutter)` TODO on
      `../extrahelper/TASKS.md` line 77.
- [ ] Manager ops — 86 toggle, table state control, void/discount approval.
- [ ] Inventory — stock counts and adjustments in the store room; barcode/QR scan via camera.
- [ ] App icon + splash, both platforms.
- [ ] Store release — signing, TestFlight + Play internal testing track, then production. Closes the
      blocked `../extrahelper/TASKS.md` line 107.
- [ ] Deep links (order links, QR) — needs universal links + app links and the associated-domain
      files, so it lands with a real bundle id and a hosted domain.
- [ ] Widget/integration tests for the composer beyond the unit-tested sync layer.
- [ ] Crash + error reporting.

## Open Questions

- [ ] Confirm bundle id `com.extrahelper.app` before the first signed build.
- [ ] KDS on mobile — is a phone-sized kitchen display useful at all, or is it a wall-display-only
      surface? Decide before the manager-ops phase.
- [ ] Cashier/payments on mobile — excluded from v1. Does a waiter ever take payment tableside? That
      pulls in `record_payment`, splits, refunds and receipts.
- [ ] Push notifications (FCM/APNs) for new orders — needed, and on whose device?
- [ ] Pilot distribution — TestFlight + Play internal track, or a direct `.apk`?
