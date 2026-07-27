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

## Milestone D — Shared amend RPC (touches the web app)

- [ ] Migration `amend_order_add_item(_order_id, _item_id, _qty, _variant_id, _modifier_ids,
      _notes, _course, _seat) returns uuid` — `security definer`, `search_path = public`,
      `revoke execute from public` + `grant to authenticated` **naming the full signature**.
- [ ] Body lifts `addItem`'s logic so pricing stays cent-identical: resolve order → tenant; gate on
      `has_permission`; reject a non-editable order state; reject an 86'd item; fold the variant
      delta and append `(variant)` to `name_snapshot`; **require every modifier be linked to *this*
      item via `item_modifiers`** and reject the whole line otherwise; insert `order_items` +
      `order_item_modifiers` **in one transaction**.
- [ ] Refactor web `addItem` (`../extrahelper/app/(app)/pos/actions.ts:34`) to a thin wrapper over
      the RPC. Keep its signature and `PosState` return identical so `use-amend-cart.ts` and every
      caller are untouched. ~95 lines → ~15.
- [ ] **Verify (this is shipped money-handling code):** cent-parity on the reference case — Buff
      Sekuwa KG, 38000 base + 130000 variant + 15000 + 5000 mods = 188000, both modifier rows
      snapshotted, `name_snapshot` = "Buff Sekuwa (KG)". Negative cases: unlinked modifier rejected,
      86'd item rejected, cross-tenant order rejected, variant-from-another-item rejected,
      non-editable order rejected. Then `tsc` + `lint` + `build` clean and a real browser amend on
      `/pos`. Grants checked for a stale overload.
- [ ] Mirror this entry into `../extrahelper/TASKS.md`.

**Three bugs this also fixes on the web** (worth stating so they don't get re-found later):
`addItem` currently inserts the line and its modifiers in two round-trips, so a failure between them
leaves a line priced for modifiers that have no `order_item_modifiers` rows — the till charges for
cheese the kitchen ticket never mentions. It also never checks that the order belongs to the active
tenant (leaning entirely on RLS, unlike every other query after the defense-in-depth sweep). And
modifier-link validation stops existing in two places that must agree to the cent.

## Milestone E — Waiter ordering, online

- [ ] Tables board — floors + tables, live `table_state`, `TableGlyph`, state colour **plus** icon
      and label.
- [ ] Realtime table states — `setAuth` on connect **and** on token refresh, or RLS drops every
      event. Merge the changed row in place; don't refetch the world.
- [ ] Order composer, one surface, capability-shaped `CartController` (`canDelete`, `setHold` —
      never a mode flag), mirroring `../extrahelper/components/pos/cart-types.ts`.
- [ ] Destination step — dine-in table or takeaway; guests count.
- [ ] Dish step — category chips + photo-first grid; 86'd items blocked; **price range** on tiles
      and in the accessibility label (a variant-forced dish's base price is unbuyable).
- [ ] Item options sheet — variant select, modifiers, cooking notes, qty stepper (≥44px).
- [ ] Cart rail — line title folds in the variant name (two lines both reading "Buff Sekuwa" and
      differing only by price is a real bug the web hit), running total, tabular figures.
- [ ] Create → one `place_staff_order` call with a client-minted idempotency key.
- [ ] Fire → `fire_order`; show the resulting per-station KOTs.
- [ ] Amend a fired order — add via `amend_order_add_item`, void via `void_order_item` (reason
      required; the server enforces approval, the app must not try to skip it).
- [ ] Custom/off-menu line — price clamped, and it writes an `audit_logs` `custom_price` row.
- [ ] Order list / detail — active orders, statuses, KOT state per line.
- [ ] Optimistic UI on add/remove/qty with honest rollback + an error surface on failure.
- [ ] **Verify on a real device, both platforms:** order with variant + modifiers → fire → correct
      per-station KOTs → amend adds a line → void with reason recomputes → matches what the web
      `/pos` shows for the same order.

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
