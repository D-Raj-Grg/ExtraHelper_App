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
- [~] Cross-tenant isolation check (a tenant-B user sees zero tenant-A rows) — **partly closed in
      Milestone I**: an owner of tenant A calling `dashboard_summary` for tenant B gets `null`, and
      their own tenant's figures otherwise. That covers the RPC path. Still unchecked **through the
      app's own reads and its local cache** — the Drift rows are tenant-stamped and `adoptTenant`
      wipes on switch (unit-tested in `local_cache_test`), but nobody has driven a two-tenant switch
      on a device and confirmed the menu, board and dashboard all change. RLS covers it server-side.
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

**A crash found on the emulator after E was called done (fixed 2026-07-27):** dismissing the
void-reason dialog took the whole app down with
`'package:flutter/src/widgets/framework.dart': Failed assertion: line 6271 pos 12:
'_dependents.isEmpty': is not true.` — the full-screen red error, on *both* "Keep it" and "Void
line". `_askVoidReason` created the `TextEditingController` itself and disposed it the line after
`await showDialog(...)`. That future resolves a frame *before* the dialog's `TextField` is actually
unmounted, so the field's own `dispose()` ran against a dead controller
("A TextEditingController was used after being disposed"), its element never finished deactivating,
and the `InheritedElement`s above it hit the assert. Fixed by moving the field into
`void_reason_dialog.dart`, where a `State` owns the controller and disposes it — the same shape
`_ItemOptionsSheet` already had. Regression test: `void_reason_dialog_test`. Also added the missing
`mounted` guards in `pos_screen` where `ref` is touched after an `await …push()`.

**A bug caught during device verification:** tapping an *occupied* table opened "New order" with an
empty cart instead of amending. `_openTable` read `activeOrdersProvider` synchronously, but the
Tables tab never watches it, so on a fresh launch it was unbuilt and `.valueOrNull` returned null —
which read as "no open order" and would have started a **second order on an occupied table**. Fixed
by awaiting `activeOrdersProvider.future` so the answer is real rather than merely available.

## Milestone F — Offline ✅ (2026-07-27)

- [x] Drift schema — cache tables (items, variants, modifiers, `item_modifiers` links, categories,
      tables, floors) + `cache_meta(tenant_id, fetched_at)` + `outbox`. Schema v2 adds the identity
      cache; migrated in place, never by dropping the file — the outbox may be holding a real order.
- [x] Cache refresh on POS open, on foreground and on Realtime change. **Tenant-stamped**:
      `adoptTenant` wipes every other tenant's rows before a single row is read.
- [x] Outbox — `kind`, `payload_json`, `idempotency_key` (**unique**), `attempts`, `state`
      (`pending|inflight|done|dead`), `last_error`, `order_ref`.
- [x] **All** order writes go through the outbox, online included — `OrderQueue` enqueues, then
      drains. A mid-flight network throw is already durable under the same key.
- [x] Replay engine — serial in enqueue order, re-checks connectivity between entries, `inflight`
      persisted in a transaction before the call, retry cap 5. Pure Dart: no widgets, no sqlite.
- [x] Server-reject → `dead` at once with the reason kept; transient → `attempts++` and retry.
      Entries queued behind a create that died are failed with a reason rather than fired at the
      server one by one.
- [x] Offline-created orders — the composer holds `draft:<uuid>`; an amend against a not-yet-synced
      order **merges into that pending create's payload**. Once the create lands, `remapOrderRef`
      rewrites every entry behind it to the real order id, durably.
- [x] Connectivity watcher, offline banner, app-bar badge (owed vs failed, icon + count, never
      colour alone) and a dialog listing dead entries with their reason and a "Try now".
- [x] **Verify — unit tests, no emulator** (`outbox_test`, `local_cache_test`, 53 tests):
      double-enqueue → one row; kill mid-`inflight` → re-attempted under the same key, no duplicate;
      server-reject → `dead`, never retried; 6 transient failures → dead after 5 with the error
      preserved; amend merges into a pending create; replay is serial; tenant switch → cache wiped.
- [x] **Verified on the Android emulator in airplane mode**, end to end: cold start with no
      coverage renders the tenant, role, floor plan and menu **from cache alone** → compose an order
      → "Send to kitchen" returns immediately with *"Saved. It goes to the kitchen the moment you're
      back on coverage."* and the app bar shows a **1** → coverage restored → badge clears by itself
      and the order appears In kitchen. Database confirms **exactly once**: one order, one item, one
      KOT, `waiter_id` set, for both the dine-in and the takeaway run. All test rows deleted
      afterwards and A1 restored to `free`.

**A fourth outbox kind.** `PLANNING.md` §2 names three (`order`, `amend_add`, `amend_void`); this
adds `fire`. Sending to the kitchen is its own idempotent RPC, and an offline session is normally
*N* adds then one fire — folding it into another entry's payload would either fire too early or
lose the fire when there was nothing new to add. On an order that hasn't synced, `fire` instead
flips the pending create's `fire` flag, so the create and the fire land together.

**What "offline" turned out to mean, beyond the queue.** Four things broke on a real airplane-mode
run that no unit test would have caught, each because a *read* was allowed to block a *write*:

- Cold start showed **"No ordering access"** — memberships and permissions were network-only, so the
  shell had no tenant and no keys. Now cached (`IdentityCache`), cleared on sign-out.
- Tapping a table **hung**: `_openTable` awaited `activeOrdersProvider`, and with no network that
  sits on a long HTTP timeout. Now it asks connectivity first and caps the wait at 6s. Offline, a
  *free* table still opens; an *occupied* one says so rather than guessing "no open order" and
  starting a second order on a taken table.
- "Send to kitchen" **spun forever** — the commit awaited a table refresh after the write. The write
  was already durable; the refresh is now unawaited.
- **The offline error stuck after coverage returned.** An `AsyncError` is sticky: the order list
  kept saying "No coverage" over a live LTE bar, and the only way out was the waiter tapping "Try
  again". `SyncLoop` now watches for the offline→online edge and rebuilds what gave up — which also
  re-subscribes the Realtime channel the offline build skipped. Verified: go offline on Orders, get
  the error, restore coverage, and the list recovers on its own with no tap.
- The menu was fetched only when the composer opened, i.e. exactly too late. The POS now warms
  menu, categories and floors on open, and an empty cache with no coverage says so immediately
  instead of spinning.

**Verified on iOS (simulator, iPhone 17 Pro / iOS 26.2), 2026-07-27.** Builds, launches, Supabase
initialises, Drift opens `Documents/extrahelper.sqlite` with all 11 tables, and the POS renders in
dark theme with the live board. Cache warms identically to Android: 20 menu items, 4 categories,
1 floor, 4 tables, 2 memberships, 35 permissions, 0 outbox rows. No exceptions in the run log.

**A bug the iOS cache dump caught: `permissions` cached 0 rows.** `adoptTenant` wiped everything
whenever `cache_meta` did not already hold exactly this tenant — and on a *fresh install* the meta
is empty, while the shell has already cached this tenant's permissions by the time the POS mounts.
So the very first run deleted them, and the next cold start with no coverage would have rendered
"No ordering access" again. Android never showed it because by the time it was tested the app had
launched several times. Fixed by keying the delete on `tenant_id != current` instead of "wipe unless
the stamp matches", which is immune to who wrote first. Regression tests in `local_cache_test`.

**Also plugged:** `done` outbox rows were never removed — a phone on a service floor for a year
would carry every order it ever sent. `SyncLoop` now prunes `done` rows older than 7 days on each
drain. `dead` rows are never pruned; someone still has to see them.

**Not yet verified on iOS: the offline path.** A simulator has no airplane mode, and
`connectivity_plus` on the simulator reports the host's network rather than the device's, so an
offline test there would prove nothing. The physical iPhone is the right target — and is what
`CLAUDE.md` asks for — but the run failed with *"Almighty is not available because the Developer
Disk Image is not mounted"*: the device needs to be unlocked and trusted. Signing itself is fine
(`Apple Development: divyashwar@icloud.com`).

**Codegen note:** `dart run build_runner build` fails with *"Failed to compile build script"* —
sqlite3 3.x uses Dart build hooks, and `dart compile exe` refuses to AOT-compile a build script in
that graph. Use **`dart run build_runner build --force-jit`**.

## Milestone G — Manager ops ✅ (2026-07-27)

The floor's next real need after taking an order. Everything below sits on rules that live in
Postgres and are shared with the web — no business rule was invented on the client.

- [x] **Two shared RPCs, and a real security hole closed.** `set_item_86` and `set_table_state`
      (migration `20260727120000_manager_ops.sql`, `security definer`, `search_path = public`,
      `revoke from public, anon` + `grant to authenticated` naming the full signature; verified
      live: one function object each, ACL `authenticated` only). RLS on `menu_items` and
      `restaurant_tables` is **tenant-scoped only**, and the role checks lived inside TypeScript
      server actions — so any member of the restaurant could 86 a dish or restate a table through
      the API directly. The guard was in the client, which is not a guard. Both RPCs also write an
      `audit_logs` row, which the column updates never did.
- [x] **Role sets mirror the old web behaviour exactly**, so nothing regressed: 86 = owner, manager,
      **kitchen** (the kitchen is who knows the dish ran out, which is why it is not gated on
      `menu.edit` — owner/manager only); table state = owner, manager, receptionist, waiter,
      cashier. A cleaner long-term fix for the first is a dedicated `menu.86` key in the shared
      catalog; that is a catalog decision, not a mobile one.
- [x] **`set_table_state` refuses to free a table that still has a live order.** That was possible
      before and it hid an order from the board while the kitchen was still cooking it.
- [x] Web refactored onto both RPCs (`app/(app)/menu/actions.ts`, `app/(app)/tables/actions.ts`),
      types added to `database.types.ts`. `tsc` + `eslint` clean.
- [x] **86 toggle** — long-press a dish in the composer, behind `menu.edit`. Confirm sheet names the
      real consequence ("It disappears from every waiter's phone and the web POS"), never "are you
      sure?".
- [x] **Realtime `menu_items`** on the same authed socket as the board, with a write-through to the
      Drift cache, so a dish that sold out while the app was open is still sold out after a cold
      start.
- [x] **Table state** — long-press a table. Offered to anyone who can take orders, mirroring the
      RPC, rather than hidden behind `tables.edit` which only owners and managers hold.
- [x] **Manager log** — voids, discounts, stock and table changes with who and why, read from
      `audit_logs` (whose RLS is already owner/manager only, so a waiter reaching the screen would
      see an empty list rather than someone else's data). A void's audit row carries only the
      reason, so the dish name is looked up and merged in — "Void —" is a log entry nobody can act
      on. `full_name` is usually unset, so the username stands in.
- [x] **Offline stance, decided:** 86 and table state go **through the outbox** (new kinds `menu86`
      and `tableState`). They are things other staff need to see, and both are last-write-wins on a
      single row, so replay is safe. Voids stay queued as they already were. See `PLANNING.md` §2.
- [x] Tests: `outbox_test` (queued 86 and table state replay; a refused op keeps its reason; one
      refused manager op does not orphan an unrelated one), `local_cache_test` (an 86 from Realtime
      survives a cold start; one tenant's stock flag cannot touch another), `audit_log_test` (every
      row names a thing and a person; a discount describes itself; an unknown action degrades to a
      dash rather than crashing). **82 tests, all passing.**
- [x] **Verified on the Android emulator against the live project**, end to end: long-press a table →
      choose Free on a table with a live order → the server refuses with *"table A1 still has an
      open order"*, shown verbatim, and the app-bar badge counts one failed write with its reason →
      choose Cleaning instead → the board updates. Long-press a dish → "Mark sold out" → the tile
      shows a **Sold out** badge and the dish is unorderable. Database confirms `is_86 = true` and an
      `item_86` audit row; the manager log lists both actions with the actor and the time.
- [x] **Verified across platforms**: with the iOS simulator running and untouched, putting the dish
      back on from Android flipped iOS's cached `is86` to false — the Realtime subscription and the
      cache write-through both work on iOS. iOS also picked up the table state change. Test rows
      cleaned up afterwards and A1 restored.

**Discounts are deliberately not here.** `apply_item_discount` requires the item to be on a
**bill** (`orders.bill_id`), and bills are created at checkout — which is web-only in v1
(`PLANNING.md` §7 excludes tableside payment). A discount button on this app would fail with "item
is not on a bill yet" every time. It belongs to a payments milestone, and that answers the Open
Question about tableside payment for this milestone's purposes.

**A bug found during device verification:** the shell flashed **"No ordering access"** at every
launch. `permissionsProvider` answers with an empty set while the tenant is still resolving, and an
empty set reads as "loaded, and you may do nothing". Now the shell waits for the tenant too — a
surface must never appear and then vanish.

## Milestone H — App icon & splash ✅ (2026-07-27)

- [x] **The mark is the web app's own**, re-rendered rather than re-drawn: `extrahelper/public/icon.svg`
      (fork + knife) headless-Chrome-rendered from `assets/branding/*.svg` at the sizes each platform
      wants. The two clients now look like one product on a home screen, not two.
- [x] **iOS icon** — full-bleed 1024 square, no baked corners (iOS masks its own; a rounded PNG
      shows its corners *inside* the mask) and **no alpha channel**, which the App Store rejects.
- [x] **Android adaptive icon** — `#0A0A0A` background layer + glyph foreground inside the 66% safe
      zone, so a circular launcher mask doesn't clip the fork's tines. 5 densities + the v26 xml.
- [x] **Splash, light and dark both first-class** — purple `#8200DB` mark on white, white mark on the
      app's tinted near-black `#0C090C`. Never a white mark on white.
- [x] **Android 12+ splash** respects the platform's 768px circle on a 1152px canvas. First pass
      rendered the mark at 328px — technically correct, visually an afterthought — so it was scaled
      to 572px, filling the circle without risking the clip.
- [x] **App name fixed**: the launcher read `extrahelper` on Android and `Extrahelper` on iOS. Both
      now read **ExtraHelper**.
- [x] Regeneration is one command each, documented in `pubspec.yaml` beside the config:
      `dart run flutter_launcher_icons` and `dart run flutter_native_splash:create`.
- [x] **Verified on both platforms**: Android launcher shows the black adaptive circle with the white
      mark under "ExtraHelper"; light and dark splashes both confirmed by screenshot; iOS springboard
      shows the rounded black icon, and the dark splash renders. `flutter analyze` clean, 82 tests
      passing.

## Milestone I — Owner dashboard ✅ (2026-07-30)

Read-only. The owner's glance: what today made, what is still open, what is running out.

- [x] **The whole screen is one shared RPC** — `dashboard_summary(_tenant, _days)`, migration
      `20260730090000_dashboard_summary.sql` in `../extrahelper/supabase/migrations/`. The web
      dashboard ran six parallel PostgREST reads plus tz-aware day bucketing in TypeScript
      (`Intl.DateTimeFormat` per bill). Flutter cannot copy that: **`package:intl` carries no IANA
      timezone database**, so bucketing "today" in `Asia/Kathmandu` in Dart would have meant a new
      dependency *and* a second implementation of the day boundary — the drift rule 1 forbids.
      Postgres already owns `tenant_settings.timezone`, so the arithmetic moved there and both
      clients now render the same payload. Reservation and payment timestamps come back **already
      formatted** in the tenant's zone (`to_char`), for the same reason.
- [x] `security invoker` + an explicit tenant filter on every read inside it — RLS remains the
      boundary. Gated on `reports.view` exactly as `report_extras` is, and it **returns null rather
      than raising** when the caller lacks the key, so a kitchen role gets a state to render instead
      of a red box. `revoke from public, anon` + grant to `authenticated`; verified
      `{postgres=X, authenticated=X, service_role=X}`.
- [x] **Web refactored onto the same RPC** (`../extrahelper/app/(app)/page.tsx`) — ~90 lines of
      query + bucketing deleted. `database.types.ts` updated; `tsc`, `eslint` and `next build` clean.
      **Behaviour change worth knowing**: `/` used to show revenue to *every* member of a
      restaurant, because the page only called `requireTenant()`. It is now gated on `reports.view`
      like every other reporting surface, and roles without it see a "no access to reports" card.
- [x] Flutter — `data/supabase/dashboard_repository.dart` (typed envelope, tolerant of missing keys
      and of numerics arriving as strings), `features/dashboard/` (screen, providers, chart).
      Reached from the app-bar chart icon, shown only when the user holds `reports.view`.
- [x] **Revenue chart hand-painted** (`revenue_chart.dart`, `CustomPainter`) rather than adding a
      charting package: one zero-filled series, no axes, no interaction — and every charting
      dependency arrives with its own idea of colour and type. Zero-fill matters: a gap would draw
      as a straight line between the days either side. The peak carries a **dot and a printed
      figure**, both ends print their dates, and the whole thing has a `Semantics` summary, so
      nothing is conveyed by the line's colour alone.
- [x] **Network-only, deliberately.** Every other read in this app is cache-first because a waiter
      must keep taking orders on dead wifi. This one is an owner glancing at today's money, where a
      silently stale figure is worse than an honest "couldn't load" — the error state says so, and
      says the POS still works offline.
- [x] `reservationStatusLabel` added to `core/format/labels.dart` — `pending` reads "Not confirmed".
- [x] Tests: `dashboard_summary_test` (9 cases) — envelope parsing, numerics as strings
      (`"3.750"` → 3.75), a null `table_label` surviving as null, a missing key never throwing,
      `deltaPct` matching the web formula, **null when yesterday sold nothing** (not infinity, not
      100%), and `isEmpty` telling a quiet day apart from a restaurant that hasn't opened.
      `flutter analyze` clean, **91 tests passing**.
- [x] **Cent/figure parity verified against a direct tz-aware query** on the live dev project: today
      revenue, today bill count and the 30-day series sum all match to the cent, 30 buckets for a
      30-day window. **Isolation verified**: a non-platform-admin owner of tenant A gets `null` for
      tenant B and data for their own.
- [x] **Verified on the Android emulator** against the live project, light and dark: KPI tiles,
      window chips (7/14/30/90) re-querying, the chart redrawing, "Chicken Kima −6 / 1 kg ·
      Oversold" with an icon and the word, empty states for reservations, recent payments with
      tenant-zone timestamps and Table/Takeaway labels. **Greyscale screenshot passed** — selection
      carries a check, oversold carries an icon plus the word plus a minus sign.
- [x] **A second revenue leak closed while scoping this** (migration
      `20260730093000_report_sales_guard.sql`, mirrored in `../extrahelper/TASKS.md`): the
      2026-07-12 report-security pass added the `reports.view` guard to six report RPCs and missed
      **`report_sales`** — the one returning the headline revenue figure. Same shape as the `/`
      dashboard leak above: `bills` RLS is tenant-scoped only, so any member could read the takings
      through the API. Guard added (same arity, plain replace), and `public`/`anon` EXECUTE revoked —
      the original migration granted to `authenticated` and never revoked, so `public` held it by
      default. No caller regressed.
- [x] **Process note: two sessions built this milestone at once, and Postgres kept both RPCs.** A
      parallel session wrote `dashboard_summary(_tenant, _days, _tz)` while `(_tenant, _days)` was
      already live — the arity trap in `CLAUDE.md`, from the other direction: not a replace that
      silently overloads, but two authors landing two signatures. PostgREST naming `{_tenant, _days}`
      matches either, so `/` would have failed on an ambiguous function call. The 3-arg version was
      dropped ~14 minutes later; one `dashboard_summary(uuid, int)` exists now. **Check `pg_proc` for
      the name before adding an RPC** — the repo is not the whole truth about what is deployed.
- [ ] **iOS: the dashboard screen itself is not yet eyeballed.** `flutter build ios --simulator`
      succeeds and the app runs on the iPhone 17 Pro simulator (signed in, POS renders, the new
      app-bar icon is there) — but scripted taps into the Simulator's Metal view didn't register, so
      the screen was never opened there. No platform channels and no plugins are involved, so this
      is a look-check, not a risk. Do it by hand next time the simulator is open.

## Milestone J — Inventory / store room ✅ (2026-07-30)

The store keeper's surface: what is on hand, counting it, correcting it. Scoped with the owner as
**barcode scanning in, counts offline, adjustments online-only**.

- [x] **An unguarded stock write, closed** (migration `20260730214500_inventory_ops.sql`).
      `adjust_inventory` — behind every adjustment and every waste write-off — had **no
      authorization at all**: `security invoker`, no role check, no permission check, and RLS on
      `inventory_items` / `stock_movements` is tenant-scoped only. The single guard was
      `requireRole(...)` in the TypeScript action, whose comment claimed *"RLS + role enforced
      inside"*. It was not. Any member — waiter, cook — could move stock through the API. Nothing
      wrote an `audit_logs` row either, and `stock_movements` has no actor column, so **who** moved
      stock was recorded nowhere. Now `security definer`, gated on `inventory.edit` (whose holders
      are exactly the old role list, so nothing regressed) and audited as `stock_adjust` /
      `stock_waste` with the item, delta, reason and resulting quantity.
- [x] **The definer trap, and why the order of two statements matters.** The old body derived the
      tenant *from the update itself* (`update … returning tenant_id`). That was only safe because
      RLS fenced the update. Under `security definer` the same shape would write another
      restaurant's stock and *then* ask whether the caller was allowed. Now: select the tenant,
      guard, then update. **Verified live**: a non-platform-admin owner of Demo Diner reaching into
      a Sekuwa Station item is refused `42501` and the foreign row does not move.
- [x] **`set_stock_count_actual`** — new, `security definer`, gated on `inventory.edit`, refuses a
      posted count, returns the variance. The web wrote `stock_count_items.actual_qty` straight
      through PostgREST, where RLS is tenant-only, so any member could edit the numbers a manager
      then posts. It is also what makes a count line **one replayable call** for the outbox.
- [x] `post_stock_count` now writes an audit row — posting is what actually moves shrinkage into
      stock, and it left no trace of who did it.
- [x] **Barcode** — `inventory_items.barcode`, unique **per tenant and only where set** (partial
      index). **Verified live**: a duplicate inside one restaurant is refused, the same code in two
      restaurants is fine, and many nulls do not collide. The web `item-sheet` grew a Barcode field,
      because a scanner with nothing to match is a toy; the constraint error is rewritten into
      something a store keeper can act on.
- [x] Web onto the same rules — `setCountActual` calls the RPC, the false comment on `adjustStock`
      is corrected, `database.types.ts` updated. `tsc` + `next build` clean; the only lint errors in
      the repo are pre-existing and in untouched files.
- [x] **`mobile_scanner 7.4.0` resolves** on Flutter 3.38.7 / Dart 3.10.7 — checked before a line of
      UI was written, because the Riverpod-3 wall in Milestone A cost a day. Needs iOS 12 / minSdk
      23 against this project's iOS 13 / compileSdk 36, so nothing had to move. Camera permission
      strings on both platforms, and a **denied camera degrades to search** rather than a dead
      screen.
- [x] Flutter — `data/supabase/inventory_repository.dart`, `features/inventory/` (list, count,
      adjust sheet, scanner). Reached from the app-bar box icon, shown only on `inventory.view`;
      `inventory.edit` decides whether anything can be changed, so a viewer gets a read-only screen
      that says so.
- [x] **Counts queue, adjustments do not.** New outbox kind `stockCount` carrying an **absolute**
      quantity: replay writes the same number again, which is exactly why it is safe. An adjustment
      is a *delta* and `adjust_inventory` takes no idempotency key, so replaying one would move
      stock twice — it stays online-only with an honest failure. Re-counting a shelf **replaces** the
      queued value instead of queuing a second write.
- [x] Drift **schema v3** — `CachedInventoryItems`, tenant-stamped, wiped by the existing
      `adoptTenant` sweep, so the worklist renders in a walk-in with no signal.
- [x] Tests: `inventory_test` (quantity formatting, numerics arriving as strings, an uncounted line
      staying null rather than becoming zero, signed variance, enum wire values matching
      `stock_movement_type`), `outbox_test` (a count queued offline lands later; recounting replaces
      rather than queues; a replayed count converges; a refused count dies with its reason),
      `local_cache_test` (store room from cache alone, tenant wipe, no cross-tenant quantities).
      `flutter analyze` clean, **110 tests passing**.
- [x] **Verified on the Android emulator against the live project**: store room lists low stock
      first with `Low` carried by an icon *and* the word; an adjustment of +12 kg on an item at
      −8 kg previews "leaves 4 kg", applies, and writes an `audit_logs` row naming the actor; a
      count reads "System 5 kg" per line, a counted 3 shows **↓ Short −2 kg** (arrow, word and sign
      — greyscale-safe), posting reconciles on-hand and writes a `count` movement of −2. Every test
      row was removed afterwards and both items restored.

**Three things the device run caught that no unit test would have:**

1. **A count with no lines rendered as a blank page** under a live "Post the count" button. Resuming
   an old count opened before anything existed in the store room hit it. Now an empty state that
   says to start a fresh one, and no post button.
2. **"2 of 2 counted" before anyone had walked to a shelf.** `start_stock_count` seeds every line's
   `actual_qty` with the system's own on-hand figure, so *nothing is ever uncounted* and a progress
   bar off that is a lie. The summary now says what is actually true and actually useful — how many
   lines **differ** from the system, i.e. what posting would move. The confirm sheet lost its
   "lines nobody counted are left alone" sentence for the same reason: it promised a safety net
   that cannot happen from this app.
3. The below-zero warning in the adjust sheet fired **before any amount was typed** on an item
   already in the negative, reading as an objection to opening the sheet.

**A judgement call worth recording.** The honest fix for (2) is for `start_stock_count` to seed
`actual_qty` as **null**, which is also what makes `post_stock_count`'s own "skip uncounted lines"
branch meaningful — it is currently unreachable. It was **not** changed here: the web count page does
`Number(r.actual_qty)`, so a null would render there as a counted **0**, which is worse. It needs the
web page and `StockCountSheet` changed in the same breath. Left as a decision for the owner rather
than a half-change across two clients.

- [x] **Offline count verified on the device** (airplane mode, Android emulator): counting a shelf
      with no coverage answers *"Saved. It goes up the moment you're back on coverage."*, the row
      shows **Waiting for coverage**, the app-bar badge counts it, and posting is **blocked** with
      "1 count waiting for coverage". Restoring coverage drained the queue by itself — no tap — and
      the database shows the counted value landed **exactly once** (`actual_qty` 7, variance 2).

**Five defects found in a review pass after the milestone was first called done.** Four were mine;
the fifth was not:

1. **A count could be written against the wrong item.** `_CountRow` is a `StatefulWidget` in a
   `ListView` and had **no key**, so Flutter matched rows by index: filter the list and row 0's live
   controller — holding a number typed for another shelf — is handed to whatever item is now first.
   Blurring it would have recorded that number against the wrong stock. Now keyed on the line id.
   Verified on the device: with 3 typed for Flour, filtering to "chick" shows Chicken Kima's own
   −8 kg. This is the same trap `CLAUDE.md` records for the POS, reached from the other side — not
   a content key, but *no* key.
2. **Posting was allowed while counts were still queued.** `_pending` cleared as soon as the write
   was durable, so offline the Post button re-enabled and would have reconciled stock against
   numbers the server had never seen — and closed the count, so those queued writes would then be
   refused. Now tracked separately as `_owed`, and the button says what it is waiting for.
3. **The row's field never reacted to the model changing.** A refused count dropped the optimistic
   value everywhere except the text field, which kept showing a figure nobody had recorded. Added
   `didUpdateWidget`, which never rewrites a field that has focus.
4. **The search box did not show what the scanner read.** Both screens drove the filter through
   state while the `TextField` was uncontrolled, so the list changed under an unchanged box. Both
   now own a controller. Also fixed a **57px overflow** on the count row when a variance and a
   queued badge appeared together — `Wrap`, not `Row`, which also survives a larger text scale.
5. **Not mine, and worth knowing:** an **expired access token plus no coverage hangs the shell on a
   spinner**. `supabase_flutter` cannot refresh the token offline and retries forever, so every
   request aborts and `permissionsProvider` never resolves — the cached fallback is never reached.
   Confirmed **pre-existing** by stashing all of Milestone J, rebuilding, and reproducing it
   identically on the baseline. Milestone F's offline verification passed because its token was
   still fresh. Logged in the backlog.

- [x] **Cold start offline with an expired token sat on a spinner** (found 2026-07-30, fixed
      2026-07-31). See "Milestone L" below for the measurement and the fix — the original note said
      the refresh "retries forever", which the resolved gotrue 2.26.0 does not; it gives up after
      about ten seconds, per request.
- [ ] **Not verified: scanning with a real camera.** The permission strings, the sheet and the
      no-match path are in place, but no barcode has been read on a device — and no inventory item
      carries a code yet, which is a labelling job before it can be tested end to end.
- [ ] **iOS: not run this milestone at all.** Nothing here is platform-specific except the camera,
      which is exactly the part that wants a real device.

## Milestone K — Shell redesign: drawer, one status band (2026-07-31)

The root app bar had become the navigation. An owner in debug saw a two-line `TenantSwitcher`
title competing with **six 44px actions** — sync, dashboard, store room, manager log, account,
design gallery. 6 × 44 = 264px of actions on a 360dp phone, leaving about 90px for a restaurant
name, all of it in the top-right corner a waiter holding a tray can least reach. Below it sat the
`OfflineBanner`, and below that a `TabBar` with an icon *and* a label per tab: three stacked bands
before any content.

- [x] **Destinations moved to a navigation drawer** (`features/tenant/app_drawer.dart`). Same
      permission keys, same reasoning, but each door gets a row with its name spelled out instead
      of an icon someone has to decode mid-service. The restaurant moved to the drawer header
      (`TenantDrawerHeader`), where switching expands into a list rather than a `PopupMenuButton`
      hung off the title.
- [x] **The app bar names the surface** — "POS", "Store room", "Dashboard" — which is the web's own
      page-frame rule (`../extrahelper/CLAUDE.md`: *never `{tenant.name} · X` as the title*). The
      Flutter shell had been breaking it since Milestone C.
- [x] **One shared frame** (`app/app_scaffold.dart`). `AppScaffold` owns the drawer, the sync strip
      and the one-line title, so chrome cannot drift screen to screen. Every destination and both
      leaves (composer, stock count) render through it; leaves pass `showDrawer: false` and keep
      the back arrow, because leaving a half-entered count by jumping elsewhere is not a move
      anyone means to make. Lives in `app/` rather than `core/` so `core` never imports `features`.
- [x] **The badge that vanished is now a band that stays.** `SyncStatusAction` hid itself whenever
      the outbox was clean, so the app bar silently changed width mid-service; the offline banner
      said a second half of the same story one row down. Both are now `SyncStrip`: offline, owed,
      refused — one row, tappable to the existing dialog. It is the **only coloured band in the app
      frame**, so colour in the chrome means exactly one thing: *this work is not on the server
      yet.* Icon + word + count on every state, so it still reads in greyscale.
- [x] **POS tabs moved into `AppBar.bottom`**, text-only. The bar and the tabs now read as one band
      instead of two, and the stacked icon+label tab (two lines) is gone. The `TabController` is
      owned by the shell and passed to `PosScreen`.
- [x] **Destinations are real routes** (`/dashboard`, `/store-room`, `/manager-log`, `/account`)
      rather than imperative `MaterialPageRoute` pushes, so the drawer can say which one you are on
      without tracking it itself. They replace each other; `AppScaffold` puts a `PopScope` on them
      so Back always means "return to the POS" rather than "leave the app".
- [x] **Text-scale safety pass.** Bar titles are one line with an ellipsis; the composer's two-line
      title (`New order` / `Table C1`) became title + subtitle, and the dashboard's hardcoded
      `Size.fromHeight(30)` subtitle strip — which clips at the larger text steps — is now derived
      from `MediaQuery.textScalerOf`.
- [x] `AccountScreen` extracted from `home_shell.dart` to its own file now that it is a destination.
- [x] 10 widget tests (`test/shell_chrome_test.dart`): drawer gating (an owner is offered every
      surface; a waiter is offered no door the server would shut), tapping a destination navigates,
      the header offers no switch on one restaurant and expands on two, and every `SyncStrip` state
      including a refused write outranking the queue. `flutter analyze` clean, `dart format` clean,
      **120 tests passing** (was 110).

- [x] **Two same-named restaurants were indistinguishable in the switcher** — found while looking at
      the expanded list on the emulator, where the demo account holds two "The Sekuwa Station"
      memberships. Each row now carries `@slug · Role`, which is the fix the web shipped for the
      same bug (`../extrahelper` 1.0.8). Verified: `@d-raj-a859` and `@d-raj`.
- [x] **Verified on the Android emulator, signed in as owner.** Drawer opens from the hamburger;
      Dashboard, Store room and Account each land with the hamburger (not a back arrow), the app bar
      naming the surface, and the drawer row filled and bold; Back from a destination returns to the
      POS; the composer opens as a leaf with a back arrow, `New order` on one line and `Table C3`
      beneath it. Airplane mode raises the strip — *"Offline — orders are saved on this phone and
      sent when coverage is back"* — under the tabs, and it **stays put** at every state instead of
      resizing the bar. Greyscale crop of that band still reads (icon + sentence + chevron).
      Screenshots at text scale 1.0 and **1.5** on the POS, the drawer and the dashboard: no
      clipping, no overflow, and the dashboard subtitle that used to sit in a hardcoded 30px strip
      now grows with the text.
- [ ] **iOS not run for this milestone.** Nothing here is platform-specific, but "builds" is not
      "runs".

## Milestone L — The offline cold start, measured and capped (2026-07-31)

- [x] **Reproduced it properly, and the original diagnosis was wrong in one detail.** The 07-30 note
      said `supabase_flutter` "retries the token refresh forever". With the resolved **gotrue
      2.26.0** it does not: `_refreshAccessToken` stops retrying once the next backoff would outrun
      `Constants.autoRefreshTickDuration` (10s), then throws. So the wait is bounded — per request —
      at about ten seconds, not infinite. Repro without waiting an hour or rooting the emulator:
      `adb shell run-as com.extrahelper.app` to rewrite `expires_at` in
      `FlutterSharedPreferences.xml` to two hours ago, force-stop, airplane mode, cold start.
      Measured on the baseline build: splash at 2s, **shell with a spinner at 10s, the board at
      ~13–15s.**
- [x] **Root cause.** `supabase`'s `_getAccessToken` (`supabase_client.dart:255`) awaits a token
      refresh before *every* request when the session has expired. Offline that refresh can never
      succeed, so `membershipsProvider` and `permissionsProvider` each paid the full retry window
      before their `catch` reached the identity cache that exists for exactly this case. The cache
      was never the problem; nothing asked it in time.
- [x] **The fix: ask connectivity first, and cap the wait even when the answer is yes** —
      `data/local/cache_backed.dart`, `cacheBackedRead`. Offline with something cached: serve the
      cache, attempt nothing. Offline with an empty cache: attempt anyway, because an empty cache is
      not an answer and the failure is what explains itself. Online: attempt, capped at 6s, falling
      back to the cache on an overrun or a throw and only surfacing the error when there is nothing
      to fall back to. The connectivity check itself is capped at 2s and treated as "online" when it
      doesn't answer, so it can never become the new block.
- [x] Both identity providers moved onto it, and both now **watch** `isOnlineProvider`, so a shift
      that started with no coverage refetches the real answer when coverage returns rather than
      living on the cache until something else invalidates it. Connectivity is resolved before the
      first await so the dependency registers at build time, not across an async gap.
- [x] 8 unit tests (`test/cache_backed_test.dart`), pure Dart, no emulator: offline serves cache and
      **does not touch the network**, offline with an empty cache still attempts, online prefers
      fresh, an overrun and a throw both fall back, an empty cache lets the error through, and a
      hung or throwing connectivity check does not block. **128 tests passing.**
- [x] **Verified on the Android emulator**, same repro: **the board is up at ~4s** (splash at 2s) —
      down from ~13–15s, and the spinner state is gone. Back online, a cold start loads fresh from
      the server (table order matches the server's, not the cache's) and the strip stays away.

## Milestone M — Printing from the phone (2026-08-01)

Schema half is in `../extrahelper/TASKS.md` under "Printing from the phone — a third drainer".

**Why.** The shop printer (80mm POSiFLOW KP307, USB + LAN + WiFi + BT) does not do browser print.
It cannot: JavaScript has no raw socket. The web app already solved that with QZ Tray on a till and
a headless Node agent on a shop PC — but this app is a native process, so it can drive the printer
itself with nothing installed on any computer. `dart:io` opens a socket to port 9100; Android speaks
Bluetooth SPP.

The queue was already the right shape. This app just became a third consumer of it.

- [x] `lib/data/print/print_models.dart` — printers, jobs, claims, and the render response. Knows
      which connections this device can drive, which is what the claim filter is built from.
- [x] `lib/data/print/print_repository.dart` — `claim_print_jobs`, `complete_print_job`,
      `retry_print_job`, `enqueue_print_job` (test page), plus the `printers` and `print_jobs` reads.
      Same `PostgrestException → PosFailure` / anything-else → `PosTransientFailure` split every
      repository uses.
- [x] `lib/data/print/render_client.dart` — `POST {APP_URL}/api/print/render` with the user's own
      access token. **No ESC/POS is built on the device.** The document model, the receipt template
      and every tax line live in TypeScript; a second implementation would drift, and then the
      till's copy and the phone's copy would disagree. Rendering after the claim also means a ticket
      amended in between comes out amended.
- [x] `transports/network_transport.dart` — one socket per job, 250ms before the FIN (closing
      immediately truncates a ticket on a printer whose buffer has not caught up), and deliberately
      not a kept-open connection: an idle thermal printer accepts bytes on a stale socket and prints
      nothing.
- [x] `transports/bluetooth_transport.dart` — `print_bluetooth_thermal 1.2.1`. The link is kept
      while it works (reconnecting per job makes a three-station fire feel broken) and dropped the
      moment a write is refused.
- [x] `lib/data/print/print_service.dart` — the drain loop, shaped after `tools/print-agent`:
      single-flight, five rounds, claim → render → send × copies → complete. **Every exit path
      completes the job**; a claimed row nobody completes only unsticks after the 60s sweep, which
      in a kitchen is a minute of nobody cooking.
- [x] `PrintLoop` in `print_providers.dart`, mounted beside `SyncLoop` in `main.dart`: realtime
      INSERT on `print_jobs` (with `setAuth`, or RLS drops every event), a 20s safety poll, and a
      drain on resume. One drainer per app, not one per screen.
- [x] **Print from this device** is per device in SharedPreferences, off by default. A manager's
      phone and the counter tablet are the same account; only one of them is next to the printer.
- [x] `APP_URL` added to `core/env.dart` + `env.example.json`. Without it the switch is disabled and
      the screen says why, rather than queueing work it cannot render.
- [x] `features/settings/printing_screen.dart` + drawer entry: what this phone can drive (icon *and*
      a word, so it survives greyscale), the printer list with Test print, paired Bluetooth printers
      with their addresses copyable into the web form, and recent tickets with the failure message
      and Retry.
- [x] Android manifest: `BLUETOOTH_CONNECT` + `BLUETOOTH_SCAN` with
      `neverForLocation` — without that flag Play asks what a printing app wants with the user's
      whereabouts. iOS: Bluetooth and local-network usage strings.
- [x] `flutter analyze` clean, `dart format` applied, **153 tests passing** (9 new in
      `test/print_models_test.dart`), and the Android APK builds with both native plugins.
- [ ] On the real KP307: WiFi from Android and from an iPhone, Bluetooth from Android, and four
      drainers running at once producing exactly one slip. Needs the physical printer.

### Defects found by re-reading it afterwards (2026-08-01)

Seven, of which two would have made Bluetooth impossible and one would have killed printing on a
device permanently.

- [x] **`print_bluetooth_thermal` never asks for the permission.** Its request code is commented out
      in the plugin's own Kotlin. On Android 12+ `isPermissionBluetoothGranted` therefore answers
      "no" forever and nothing ever prints, with nothing in the app to fix it. `permission_handler`
      now asks — from a button on the Printing screen, never from the drain loop, because a dialog
      that appears by itself mid-service is worse than no Bluetooth.
- [x] **The same plugin can hang the app's printing for good.** When the permission is missing its
      method handler `return`s *without completing the result*, so the Dart future never resolves. A
      hung `available` would leave `_draining` true forever — printing dead on that device until a
      restart. Every plugin call now has a timeout, and the permission is checked before anything
      that can hang.
- [x] **A WiFi-only shop was going to be nagged for Bluetooth every 20 seconds.** The drain asked
      every transport whether it was available, and asking raises a permission prompt.
      `PrintService.configured` now comes from the registry: a transport for a printer nobody owns is
      never consulted. Three unit tests hold this down.
- [x] **A tap on the switch could undo itself.** `PrintEnabled` overwrote its state when
      SharedPreferences finished opening, so toggling during launch flicked back on its own.
- [x] **Realtime went deaf after a token refresh.** `setAuth` ran only at subscribe time; an
      hour-old socket carries a stale JWT and RLS drops every event silently. The channel now
      re-subscribes on auth change. (The 20s poll hid this, which is exactly why it was worth
      finding.)
- [x] **A stale registry.** `printersProvider` is cached for the app's lifetime, so a printer added
      on the web stayed invisible — including whether Bluetooth was worth consulting. Re-read on
      resume.
- [x] **Test print was offered to people the server refuses.** `enqueue_print_job` gates a test page
      on `settings.edit`; a waiter only ever got a 42501. The button is now gated and says who can.
- [x] Losing the `printed` acknowledgement re-queues the job after 60s and the kitchen gets the
      ticket twice. The paper is already out by then, so it is worth three attempts, not one.
- [x] Subscribing moved out of `build()` into a post-frame callback — it is a side effect on an
      external system.
- [x] `permission_handler` pinned to **12.x**: 14's `build.gradle.kts` does not compile against this
      project's Kotlin 2.2.20 / AGP 8.11.1, and bumping the Android toolchain for one permission is
      not a trade worth making. Reasoning is in `pubspec.yaml` next to the pin.

**Not built, on purpose.**

- **Devanagari.** Image mode is rasterised by a browser; this app declines those jobs with a
      sentence rather than printing question marks. Flutter is the better rasteriser (`dart:ui`
      Canvas → `GS v 0`, a port of the web's `components/print/raster.ts`) and doing it here would
      also unblock image mode on paths with no browser. Phase 2.
- **Offline printing.** Printing needs the network twice today: to claim, and to render. The common
      shop failure is *internet down, LAN up* — the printer is reachable and nothing prints. Fixing
      it means porting `lib/print/docs.ts` + `escpos*.ts` to Dart and rendering from the drift cache.
      Note for whoever takes it: the outbox is a **server-write** queue, and a local print is not an
      RPC, so this needs its own queue, not a new `OutboxKind`.
- **USB.** No desktop target and no OTG printer stack. That stays QZ Tray's job. Worth saying
      plainly because the KP307 has a USB port and it looks like an option: a phone cannot drive it
      on either platform. Mobile printing means WiFi or Ethernet.
- **Bluetooth on iPhone.** Not a gap to close — iOS refuses classic Bluetooth SPP, the profile these
      printers speak, unless the device carries an Apple MFi authentication chip and the app drives
      it through ExternalAccessory with a registered protocol string. The KP307 has no MFi chip and
      nor does any printer at this price. `print_bluetooth_thermal` falls back to BLE on iOS and
      reports *nearby* CoreBluetooth UUIDs rather than the MAC address a `printers` row holds, which
      is why `BluetoothPrintTransport.supportedPlatform` is `Platform.isAndroid` and `send()` refuses
      with a sentence naming the fix. A BLE transport was considered and dropped: the KP307's module
      is undocumented as to BLE, probing it needs the printer in hand, and even then today's
      single-shot `writeBytes` of a whole payload becomes chunked writes against an unknown MTU with
      no flow control. **iPhone prints over the network. That is the answer, not a workaround** — for
      a counter-mounted printer it is the better one anyway: every phone reaches it, no pairing, no
      10m range, no single device holding the link.

## Milestone N — Checkout on the phone (2026-08-13)

Answers `PLANNING.md` §7.3. The whole money layer was already in Postgres and client-agnostic —
around fifteen permission-gated RPCs with `recompute_bill` running inside each one — so this
milestone is **client-side only**: no migration, no RPC change, and no new printing code. Settling a
bill fires `trg_bills_enqueue_print`, and the print stack shipped in Milestone M claims the `bill`
job and prints it.

- [x] `lib/features/pos/bill_models.dart` + `bill_math.dart` — the models, and the five figures the
      client computes locally. The maths is pure and separate **because it is the parity surface**:
      `test/bill_math_test.dart` pins each one to the integer the web produces, so the phone and the
      counter can never quote a guest different numbers.
- [x] `lib/data/supabase/bill_repository.dart` — every checkout RPC, plus `PaymentUncertainFailure`.
      That type exists because "couldn't reach the server" is the wrong sentence for a payment:
      `record_payment` may have committed before the socket died, and telling a cashier money wasn't
      taken when it might have been is how a guest gets charged twice.
- [x] `bill_providers.dart` — `BillSnapshotNotifier` with a `mutate()` that every lever goes through
      (write, then re-read), a `bills`/`payments` realtime channel, and a settled-cascade that
      refreshes the board, the tables and the Bills tab. **Not cached**: everywhere else in this app
      stale beats absent; a total from ten minutes ago is a figure someone gets charged.
- [x] The checkout screen and its five sheets — payment, adjustments, per-line, split, guest.
- [x] **Three latent bugs closed on the way.** A billed order drops out of `activeOrders()`, so
      without the new **Bills** tab a part-paid bill was unreachable from the phone. Tapping a
      `bill_requested` table would have started a *second* order, because the lookup only ever saw
      orders still on the floor. And `PosOrder` carried no `bill_id`, so a button could not tell
      "Bill" from "Open bill".
- [x] Online-only, in exactly three places: the snapshot's build, the entry points, and the due bar.
      **`lib/data/sync/` is untouched.**

**Found on the emulator run, 2026-08-13, and fixed:**

- [x] **`_CachedList` never refreshed after the first save.** `build()` started `refresh()` while it
      was still on the stack, `refresh()` called `ref.read`, and riverpod's `_assertNotOutdated`
      threw — into an unawaited future, so it surfaced as an unhandled error and nothing else. The
      cache was therefore written once per install and never again. **This is a money bug, and it
      was caught in the act**: a bill on the device carried `Pork Seukwa 1 × NPR 0.00`, because the
      phone was showing a menu from before the dish moved to size variants, added it with no size
      forced, and `place_staff_order` snapshotted the real row — base 0, no variant. The background
      refresh now takes the repo, cache and tenant that `build` already resolved and touches no
      providers; `refresh()` is the outside-a-build entry point and delegates to the same body. A
      `_disposed` flag guards the late `state =`.
- [x] **Custom items on mobile** — new `amend_order_add_custom_item` RPC (see `../extrahelper`),
      `PosMenuItem.custom` whose id is derived from name+price so identical charges merge and
      different ones don't, `toRpcJson` emitting `custom_name` instead of `item_id`, and
      `custom_item_sheet.dart`. Offline replay is free: the outbox already persists the RPC payload,
      and `addItemJson` branches on `custom_name`.
- [x] **A billed order looked lost.** It leaves the Orders tab by design (`activeOrders` filters
      `billed`), so backing out of a bill dropped the waiter on a list their order had just
      vanished from. Returning from a bill that is still owed money now lands on the Bills tab, and
      the Orders empty state names where billed orders go.

**Deliberate gaps, both recorded rather than hidden:**

- [ ] **Card-online from the phone.** The web's `payByCard` runs a server-side gateway adapter
      (`lib/integrations`) with no RPC behind it. An app offering "Card (online)" would record a
      payment it never collected, so the method is omitted from the chips — a bill settled on the
      web that carries one still displays correctly. Needs an Edge Function wrapping `getGateway`,
      or a `charge_card` RPC.
- [ ] **A retry-safe refund.** `refund_payment` takes no idempotency key, so it is the one write on
      this screen a blind retry can double. The confirm dialog and the busy guard are the whole
      protection, and after a lost answer the UI says to check the payments rather than offering to
      try again. A key on the RPC is the real fix.
- [ ] **Offline payments.** Out of scope by decision. The seam is already there: `record_payment` is
      keyed and clamped, `PaymentUncertainFailure` carries the key it used, and the split scheme is
      deterministic per slot — so a future `OutboxKind` for payments is five files and no redesign.
      `apply_bill_discount` is **not** keyed and must never be queued.
- [ ] **Cash sessions / day-close.** Web-only. Not touched here.

## Receipt branding — logo + payment QR (2026-08-13, web-side change, no Dart change)

- [x] Receipts now carry the tenant's **logo** and an uploaded **payment QR** (FonePay/eSewa/bank),
      set in the web app under Settings → Receipt & branding. **This app needed no code change**,
      and that is the point of the design: images are rasterised to 1-bit `GS v 0` bitmaps **once,
      at upload, in the browser**, and stored in `tenant_settings.receipt_template.print_assets` —
      one bitmap per paper width, since the printer will not scale a raster image. `/api/print/render`
      already returns finished ESC/POS, so `RenderClient` → `NetworkTransport`/`BluetoothTransport`
      carry the QR to paper as ordinary bytes. Rasterising at print time instead would have made this
      a browser-only feature and left every phone-printed slip blank where the QR belongs.
- [x] **Bluetooth payload size checked, not assumed.** A receipt grows by roughly 30–40KB of raster.
      `PrintBluetoothThermal.writeBytes` already chunks at 16KB with a flush per chunk
      (`PrintBluetoothThermalPlugin.kt`), so no chunking is needed in `bluetooth_transport.dart`.
      Watch the 15s `_slow` write timeout on a real device — a slow SPP link plus head time is the
      one thing that could brush it.
- [ ] **Device test outstanding**: settle a bill from `checkout_screen.dart` with printing enabled and
      confirm the QR **scans off the paper**, over both network and Bluetooth, at 58mm and 80mm.
      Image-mode printers are still refused by `print_service.dart` as before — unchanged and correct.

## Milestone O — POS parity with the web (2026-08-14)

Six shippable steps, each a surface the phone lacked and the web already had. Every business rule
was already a Postgres RPC; one new migration was needed, for a timezone boundary Dart cannot
compute.

**O1 — Reprint infrastructure** (`lib/data/print/`)
- [x] `PrintRepository.enqueue()` + `orderKotIds()`, with routing ported from the web's
      `enqueuePrint`: the **station** decides KOT vs BOT (a bar station's ticket reprinted from the
      pass must not come out with a kitchen header), a station's own printer beats the
      `printer_documents` assignment, and a branch-scoped printer is skipped for another branch's
      document. Rules live in `print_routing.dart`, pure, so they are testable without a network.
- [x] `reprint_actions.dart` — `reprintBill` / `reprintOrderSlip` / `reprintKot` /
      `reprintOrderKots`, each returning the sentence to show.
- [x] **Not gated on `Env.canPrint`.** That flag says whether *this device drains the queue*; a
      waiter's phone with no printer is exactly the device that needs to ask the counter's printer
      for a receipt. Gating enqueue would have silently removed the feature from every phone.
- [x] Not queued through the outbox — a reprint asked for ten minutes ago is not one anyone wants.

**O3 — Orders tab** (`pos_screen.dart`, `order_composer.dart`)
- [x] **Cancel order** wired to `PosRepository.cancelOrder`, which existed with zero call sites.
      Gated on `isManagerProvider` — `cancel_order` checks `has_tenant_role(owner, manager)` and
      **not** a permission key, so gating on `order.void` would have shown a custom role a button
      that fails every time. Reason required, consequence named, audited. On the card and in the
      composer's overflow, as on the web.
- [x] Pin / unpin (`orders.pinned_at`, direct column write — a display preference, no money or
      access), `activeOrders()` now orders `pinned_at desc nulls last, created_at desc`.
- [x] Order-type chips, client-side over the list already in hand; a type that empties falls back
      to All.
- [x] Guests stepper, feeding the already-plumbed `CreateCart.guests` on create and `setGuests` on
      amend. Clamped 1..200 where the server clamps.

**O2 — Completed tab** (`completed_tab.dart`, new migration)
- [x] `tenant_day_start(uuid, timestamptz)` — the only new SQL in the sweep. `package:intl` has no
      IANA timezone database, so a boundary deciding which orders a waiter can see must not be a
      second implementation; the same argument `dashboard_summary` already made. Applied and
      verified against the tenant's zone (local midnight → 04:00Z).
- [x] Fourth tab, labelled **Done** so four labels still fit at a raised text size. `TabController`
      length is a fixed 4 — the old comment forbids a length that *changes with permissions*, not a
      length of four.
- [x] Today's `billed` / `closed` / `cancelled`, limit 300, status chips, and a takings line
      **summed from each order's own lines** — two orders merged onto one bill both carry the whole
      bill total, and adding those would report nearly double the money taken. Cancelled orders
      contribute nothing and render "—", not a zero.
- [x] Row actions: view bill, reprint receipt, reprint order slip, reprint kitchen tickets. No
      permission means no control, never a disabled one.
- [x] Live off the existing orders channel — an order billed at the till appears here without a pull.

**O4 — Bills tab**
- [x] `BillFilter` — Owed / Paid / Void / All today. **Owed is never day-bound**: a debt from last
      night is still a debt this morning. Settled bills are capped to today, the same boundary.
- [x] **`refunded` is not a `bill_status`.** The enum is open/partial/paid/void; it exists only as a
      label. Filtering on it would have been a runtime 22P02 — checked against the live enum before
      writing the filter, and there is a test that keeps it out.

**O5 — Kitchen board** (`kds_repository.dart`, `kds_providers.dart`, `ticket_card.dart`)
- [x] **Live defect fixed.** `KdsTicket.isCompleted` now means *the kitchen bumped it OR its order
      has been billed, closed or cancelled*. A `ready` ticket on an order paid at the till sat on
      the board forever, and a board with permanent residents is one cooks stop reading. The web
      settled this in `isKotCompleted`; mobile had only half of it.
- [x] Reprint on each ticket, gated `order.view`.
- [x] **No fifth POS tab.** `/kitchen` is already a superset of the web's KOT tab (per-station
      filter, per-line status, recall); a fifth tab on a bar that just gained a fourth is a worse
      trade than a drawer destination that already exists.

**O6 — Table operations** (`table_ops_sheets.dart`, `manager_ops.dart`)
- [x] Transfer / merge / split, hung off the existing table long-press, which becomes a table-actions
      sheet. All three RPCs already existed and were granted; mobile simply had no route to them.
- [x] `activeOrderIdForTable` deliberately does **not** reuse `activeOrders()`'s filter: that one
      hides `billed` orders, and a billed order can still be transferred — refusing to find it would
      strand a table whose guests moved after asking for the bill.
- [x] Merge is composed the way the web composes it (`create_bill_for_order` then
      `add_order_to_bill`), not a third function that does the same thing slightly differently.
- [x] All three online-only, no new `OutboxKind`: each writes a destination table's state, and
      `split_order_items` mints an order id the screen has to have.

**Deliberately not ported** — online/card-gateway payment (no RPC behind the charge, only the web's
server-side adapter), reports, cash sessions, the online-orders manager, table setup. Reasons in the
plan; none of them changed.

- [ ] **Device pass outstanding.** Verified by `flutter analyze`, 240 tests and a launch on the iOS
      simulator; the new controls need a live order on the floor to exercise, and a greyscale
      screenshot of the Completed tab and the four-tab bar at max text scale.

## Print the bill before taking payment (2026-08-14, both clients)

- [x] **The due bar now presents the bill, then takes the money — in that order.** Paper for a bill
      only ever came out *after* `record_payment` landed (the `enqueue_bill_print` trigger fires on
      `status → paid`), so the slip a guest reads and checks before paying did not exist on the
      phone. `_DueBar` gained a **Print bill** button beside the due figure, with payment full-width
      beneath it; `printBillEstimate` in `data/print/reprint_actions.dart` queues the same `bill`
      doc, which `buildBill` already heads "ESTIMATE" and prints without tender lines. No new doc
      type, no permission of its own — `enqueue_print_job` wants `checkout.view` for a bill, which is
      what opened the screen, so a waiter can hand a table its slip without holding the key to charge
      for it. A voided bill prints nothing; a settled one offers **Print receipt**.
- [x] **"The bill changed after it was printed."** Printing locks nothing — a table that orders
      another round after asking for the bill is ordinary — so `enqueue_print_job` stamps
      `bills.bill_printed_at` + `bill_printed_total_cents` as it queues (web migration
      `20260814140000`), `Bill.printedTotalIsStale` compares it, and the bar says so and flips the
      button to **Reprint bill**. A warning, not a gate: payment stays enabled.
- [x] **Layout trap, caught by the tests.** Stacking both buttons full-width made the bottom bar tall
      enough to cover the body controls it sits under — on a 600px test surface the adjustments sheet
      stopped opening at all, which is exactly what would happen on a small phone. Print moved up
      beside the due figure; top-to-bottom order (print, then pay) is preserved.
- [x] Six widget tests in `test/checkout_screen_test.dart` cover: print offered before payment and
      above it, offered on `checkout.view` alone, receipt-not-bill once settled, reprint label after
      a first print, the stale warning after another round, and dead-not-absent when offline. Full
      suite green, `flutter analyze` clean.
- [ ] **Device pass outstanding** for this one too: a real slip out of a real printer, before payment
      and after a change, plus a greyscale check on the amber stale warning.

## QR orders reach the kitchen (2026-08-14, both clients)

- [x] **A guest's QR order was invisible to the cooks.** `place_qr_order` wrote `orders` +
      `order_items` and never a `kot`, and both kitchen boards read `kots` — so a table's order sat
      at `placed` on the POS list and the kitchen never saw it. Server-side fix in the web repo
      (`20260814150000_qr_auto_fire`, remote `20260814074527`): `fire_order`'s ticket builder moved
      into `fire_order_kots(_order_id, _tenant)`, new per-tenant `tenant_settings.qr_auto_fire`
      (**default true**) makes `place_qr_order` build the tickets itself, and new `accept_qr_order`
      lets a waiter send one by hand when a tenant turns auto-fire off. No Dart business logic —
      rule 1 holds.
- [x] **`PosRepository.acceptQrOrder`** calls the RPC and returns the ticket count; zero is a no-op,
      not an error, because the RPC is idempotent. `PosOrder.awaitingQrAccept` (`orderType == 'qr'`
      and `status == 'placed'`) is what the card keys off — the lines are `placed`, never `draft`, so
      `canFire` is false for them and this is its own gate rather than the composer's.
- [x] **The card says who is waiting.** A band in the attention colour with a QR icon and a **Send to
      kitchen** button, same shape as "Ready to run" but a different icon so the two don't read alike
      in greyscale. Not queued offline: `accept_qr_order` is a kitchen action, and a ticket that
      syncs half an hour later is worse than one the waiter re-sends on coverage — offline says so
      and does nothing.
- [x] The toggle itself stays on the web (Settings → General → Operations); this app has no
      `tenant_settings` editor, the same way the printer registry is edited there.
- [x] Model test in `test/cart_test.dart` covers all three cases: a QR order at `placed` waits, one
      already `in_kitchen` (auto-fire) does not, and a staff order at `placed` is the composer's
      business. Full suite green (250), `flutter analyze` clean.
- [ ] **Device pass outstanding**: place a real QR order with auto-fire on and confirm the ticket
      prints unattended, then off and confirm the band appears and the button sends it.

- [x] **Two fixes on review** (2026-08-14). The **Send to kitchen** band is now gated on
      `hasPermissionProvider('order.fire')` — Kitchen reaches the POS board on `order.view` alone and
      the RPC would refuse it, and a control nobody can use is worse than no control. Server side,
      auto-fire inside `place_qr_order` is wrapped so a fire-time guard (`block_negative_stock`
      raising `23514`) can no longer roll back the guest's whole order; it lands at `placed` and this
      band is the recovery path, showing the real error when tapped.

## Backlog / Later phases

- [ ] **Offline on a physical iPhone, in airplane mode.** The one verification `CLAUDE.md` asks for
      that is still outstanding. A simulator has no airplane mode and `connectivity_plus` there
      reports the *host's* network, so it proves nothing. **Unblocked by 1.0.7** — TestFlight puts a
      signed build on the phone without needing developer services on the device. Run: cold launch,
      airplane mode on, full order with variants and modifiers, force-quit mid-queue, relaunch,
      airplane mode off — the order must reach the kitchen exactly once. Then a cold start with no
      coverage at all, which must render the shell from cache, not "No ordering access". Everything
      else in Milestone F is verified on the Android emulator.
- [ ] **Decide on a `menu.86` permission key.** The kitchen must be able to 86 a dish but must not
      hold `menu.edit` (which is full menu editing, prices included), so `set_item_86` checks the
      role directly today. A dedicated key is the clean fix; it is a shared-catalog change, so it
      lands in `../extrahelper/TASKS.md` too.
- [ ] Inventory — stock counts and adjustments in the store room; barcode/QR scan via camera.
- [x] **iOS signing + TestFlight internal.** `Apple Development` identity (the old `iPhone Developer`
      string makes an archive undistributable), `CODE_SIGN_STYLE = Automatic` pinned on the Runner
      target, `ITSAppUsesNonExemptEncryption = false`, version `1.0.7+1`. Build with
      `flutter build ipa --dart-define-from-file=env.json` — never archive from the Xcode GUI, which
      reads dart-defines from a stale `Generated.xcconfig` and ships a binary that crashes on launch.
      Internal testing skips App Review entirely.
- [ ] **App Review submission (public App Store).** Everything internal TestFlight let us skip:
      - [ ] A demo tenant with seeded data, plus review credentials + join code in the App Review
            notes. The app is login-gated behind a membership; without these it is an automatic
            rejection. Never a real tenant's data.
      - [ ] Privacy policy URL + support URL, both live and reachable.
      - [ ] App Store Connect privacy nutrition labels — email and user content at minimum.
      - [ ] Guideline 5.1.1(v) account deletion. There is no in-app signup (login + join code only),
            which is the exemption argument, but accounts are created on the web. Decide the answer
            before submitting rather than in a rejection reply.
      - [ ] Screenshots: iPhone and iPad, since the binary is universal.
      - [ ] External TestFlight testers need Beta App Review — same demo-account requirement.
- [ ] **Play internal testing track.** `android/app/build.gradle.kts` still signs release with the
      **debug** keystore (the untouched template TODO). Needs a real keystore, `key.properties`
      gitignored, and `flutter build appbundle` — Play takes an AAB, not the APK the README documents.
- [ ] **iPad layout pass.** The binary is universal (`TARGETED_DEVICE_FAMILY = "1,2"`) but only
      `kds_screen.dart:240` and `dashboard_screen.dart:222` have breakpoints; POS, composer, store
      room, manager log, auth and the drawer are fixed single-column and read as a stretched phone on
      a 12.9". No `SystemChrome.setPreferredOrientations` anywhere either, so every screen rotates
      freely with no layout that accounts for it. Fine for internal testing, not for review.
- [ ] Deep links (order links, QR) — needs universal links + app links and the associated-domain
      files, so it lands with a real bundle id and a hosted domain.
- [ ] Widget/integration tests for the composer beyond the unit-tested sync layer.
- [ ] Crash + error reporting.

- [x] **Discounts replace rather than stack, and can be cancelled** (2026-08-14). Checkout's adjust
      sheet and line sheet now show the discount already on the bill with a **Remove** control, and
      the apply button reads "Replace discount" when one is there. All of the rule lives in Postgres
      (`20260814093000` in `../extrahelper/`) — `BillRepository` only calls `remove_bill_discount` /
      `remove_item_discount`, per rule 1. `BillSnapshot.staffBillDiscount` mirrors the SQL predicate
      (bill-level, not a coupon) so the sheet never offers to remove a guest's coupon; it is unit
      tested against that exact case. Review also caught the manager log rendering the raw
      `discount_removed` string — the action switch in `manager_ops.dart` falls back to
      `entry.action`, so a new audit action reaches staff as an enum unless it is added there.
      Added, with `complimentary`, which had the same gap. Suite green (249), analyze clean.

- [x] **Appearance is a choice, and it defaults to light** (2026-08-14). `MaterialApp.router` set no
      `themeMode`, so the app silently followed the OS — a phone on scheduled dark mode repainted the
      till at dusk, mid-service. Now `themeModeProvider` (`core/theme/theme_mode_provider.dart`)
      holds Light / Dark / Follow system per device in SharedPreferences, defaulting to **light**
      rather than system, with the control under Account → Appearance. Palettes untouched; both were
      already first-class. **Two traps paid for:** the notifier starts at light *synchronously*
      because SharedPreferences resolves a frame or two after launch — starting at `system` would
      paint the first frame dark on a dark phone and then snap; and it carries the same `_settled`
      guard as `PrintEnabled`, or a choice made while storage is still opening is overwritten when it
      lands and the setting appears to change itself. An unrecognised stored value falls back to
      light rather than throwing, since this runs during startup. 5 unit tests cover exactly those
      cases. Note for anyone updating: existing installs follow the OS today, so a staff member on a
      dark phone sees the app turn light once, until they choose. Suite green (255), analyze clean.

## Open Questions

- [x] Confirm bundle id `com.extrahelper.app` before the first signed build. Confirmed and shipped in
      1.0.7 — it is now the App Store Connect record's identifier and cannot change.
- [ ] KDS on mobile — is a phone-sized kitchen display useful at all, or is it a wall-display-only
      surface? Decide before the manager-ops phase.
- [x] Cashier/payments on mobile — **answered 2026-08-13: yes, at full parity with the web.** Shipped
      as the Checkout milestone below.
- [ ] Push notifications (FCM/APNs) for new orders — needed, and on whose device?
- [ ] Pilot distribution — TestFlight + Play internal track, or a direct `.apk`?
