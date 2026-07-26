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
- [~] **Verify Android** — emulator (Medium Phone API 36, `emulator-5554`) up; debug APK build in
      progress. First attempt died on **ENOSPC** (unrelated: the volume was full — a leftover
      DrawThings sandbox container at 6.5 GB plus my abandoned 1.3 GB Flutter download).
- [ ] Commit + push to `origin main`.

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

## Milestone B — Design system port

- [ ] `core/theme/` — light + dark ColorScheme from the web palette (tinted neutrals, never pure
      black/white), Figtree bundled as an asset (no network fetch at launch).
- [ ] Semantic colour as a named theme extension — emerald/amber/destructive/blue/orange per
      `CLAUDE.md`. No raw `Colors.*` at call sites.
- [ ] `core/money.dart` — currency formatting from `tenant_settings` (never hardcoded), plus a
      `moneyRange()` equivalent, tabular figures helper.
- [ ] `core/labels.dart` — enum → human label maps (`table_state`, `order_status`, `order_type`).
      Staff never see `bill_requested`.
- [ ] Tap-target defaults ≥44px (Material's are smaller — set them explicitly).
- [ ] Port `VegMark` — **circle vs triangle**, colour only reinforces. Nullable `is_veg`: unmarked
      renders nothing (the web column is nullable on purpose — `not null default false` would have
      labelled every existing dish non-vegetarian).
- [ ] Port `ChoiceChip`, `MenuTile` (photo-first, designed monogram placeholder, count badge),
      `TableGlyph`.
- [ ] **Verify:** greyscale screenshot of every state that uses colour is still unambiguous; text
      scaled to the OS maximum doesn't clip; light and dark both checked.

## Milestone C — Auth, tenant context, permissions (shell)

- [ ] `supabase_flutter` init + session persistence + auth state stream.
- [ ] Login screen (email + password, same as web). Map terse auth errors to plain language.
- [ ] Logout, and handle a session that expires or is revoked while the app is backgrounded.
- [ ] Tenant context — read `user_tenants` memberships; **pending memberships grant no access**.
- [ ] Tenant switcher, shown only when the user belongs to more than one restaurant.
- [ ] Join-by-code screen → `redeem_join_code` (creates a pending membership; an owner approves on
      the web `/team` page). Restaurant creation stays web-only.
- [ ] Permission gate — `get_my_permissions` → Riverpod provider → hides nav items and buttons the
      role can't use. Never gate on a role string held in the app.
- [ ] "No access yet" state for a user with no approved membership — teach the next step.
- [ ] Navigation skeleton (`go_router`) + app shell.
- [ ] **Verify:** login → tenant resolved → permissions loaded, on both platforms; a tenant-B user
      sees zero tenant-A rows; switching tenant re-scopes every screen.

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
