# PLANNING — ExtraHelper Mobile (Flutter)

> Read this at the start of every session. Working rules: `CLAUDE.md`. Task list: `TASKS.md`.
> **This app is one client of an existing system.** The product spec, data model, and business
> rules live with the web app: `../extrahelper/PLANNING.md`, `../extrahelper/CLAUDE.md`,
> `../extrahelper/TASKS.md`, and the PRD at `/Users/almighty/.claude/plans/1-help-me-to-wondrous-bird.md`.
> Read those before designing anything here. This file covers only what is mobile-specific.

---

## 1. Why this app exists

The web app already runs a restaurant end to end — POS, KOT, KDS, billing, inventory, reports,
customer channels. It works on a phone browser, but a waiter working a floor mid-service needs
things a browser tab cannot give:

- **Survives a dead spot.** A native local queue keeps taking orders when the wifi drops at the
  back tables, and replays them on reconnect. The web PWA queue only survives a *warm* tab.
- **Always on hand.** App icon, no URL, no session lost to a browser tab being reclaimed.
- **Device hardware.** Camera for QR/barcode later; native print/share paths.

**Who it serves:** the staff who move — waiters first, then managers on the floor, inventory
counting in the store room, and the owner who wants live revenue on their phone.

**What it is not:** it is not a second product, and it is not a place for new business logic.
Anything that decides money, stock, or access belongs in Postgres where both clients share it.

**Success signal for v1:** a waiter installs the app, logs in, walks to a table with no signal,
takes a full order with variants and modifiers, walks back into coverage, and the order appears
in the kitchen exactly once.

---

## 2. Architecture

### The contract is Postgres, not the web app

Flutter talks to Supabase directly with `supabase_flutter`, authenticated as the user. **RLS is
the same gate here that it is on the web.** There is no Next.js hop — mobile must keep working
when the web app is down, which is the whole point of the offline queue.

Trusted logic stays in SQL and is called by both clients:

| Operation | Called via |
|---|---|
| Create order (batched, one shot) | `place_staff_order` (10 args) |
| Add a line to a fired order | `amend_order_add_item` — **new**, web `addItem` refactored onto it |
| Void a line (reason + audit) | `void_order_item` |
| Fire order → KOTs per station | `fire_order` |
| Cancel order | `cancel_order` |
| Waiter picker names | `list_order_staff` |
| Granular permissions | `get_my_permissions` |
| Join a restaurant by code | `redeem_join_code` |
| Tables / menu / order reads | direct `.from()` under RLS **+ explicit `.eq('tenant_id', …)`** |

If a mobile feature needs logic that only exists in a TypeScript server action, the answer is a
Postgres function both clients call — not a Dart reimplementation. Duplicated pricing logic
drifts, and drift here means the till total disagrees with the kitchen ticket.

### Layers

```
lib/
  core/        theme + design tokens, money/format, failures, result types
  data/
    supabase/  client, auth repo, tenant repo, menu repo, order repo
    local/     drift db — menu/table cache, outbox
    sync/      outbox replay engine, connectivity watcher
  features/
    auth/      login, join-by-code
    tenant/    tenant context + switcher, permission gate
    pos/       tables board, order composer, cart, amend
  app/         router, shell, providers
```

Rules that keep these independently testable:

- Repositories return Dart models and **never leak `PostgrestResponse`/`PostgrestException`** past
  their own boundary. Callers see a typed failure.
- The sync engine depends on the outbox and repositories, **never on widgets**. It is unit-testable
  with a stubbed transport and no emulator.
- Feature code reads a `CartController`-shaped abstraction — capabilities (`canDelete`, `setHold`),
  not a mode flag — so the create and amend flows share one composer. This mirrors
  `../extrahelper/components/pos/cart-types.ts`, which is the reference for the pattern.

### Offline: two separate concerns

**Cache (read path).** Drift tables mirroring the menu and floor: items, variants, modifiers,
`item_modifiers` links, categories, tables, floors, plus a `cache_meta` row holding `tenant_id`
and `fetched_at`. Refreshed on foreground and on Realtime change. **The cache is tenant-stamped**
— switching tenant wipes and refetches, so one tenant's menu can never render under another.

**Outbox (write path).** One Drift table:

```
outbox(id, kind, payload_json, idempotency_key, attempts, created_at,
       state /* pending | inflight | done | dead */, last_error)
```

Five rules, each mirroring a bug the web queue had to be hardened against
(`../extrahelper/TASKS.md`, Milestone 7, offline entry):

1. **The idempotency key is minted client-side at enqueue and never regenerated.** A retry reuses
   it. `place_staff_order` has a replay fast-path that returns before any write, so a resend
   cannot mutate a committed order or orphan a customer.
2. **Online writes go through the outbox too** — enqueue first, attempt immediately. A network
   throw mid-flight is then already durable under the same key. Writing directly and only queueing
   on a *detected* offline state loses the order when the socket throws.
3. **Server-reject and transient failure are different.** A constraint/permission error → `dead`
   immediately, with `last_error` surfaced to the waiter. A timeout/socket error → `attempts++`,
   retry, cap at 5. A transient failure must never burn toward the cap in a way that silently
   drops a real order.
4. **`inflight` is a persisted state, not a memory flag.** Set inside a transaction before the
   call. App killed mid-call → on restart the row is re-attempted under the same key, which is
   safe precisely because of rule 1.
5. **Replay is serial per order and re-checks connectivity between entries.** An amend must not
   land before the create it belongs to.

**Built with a fourth kind, `fire`** (2026-07-27). Sending to the kitchen is its own idempotent
RPC, and an offline session is normally *N* adds then one fire; folding it into another entry's
payload would either fire too early or lose the fire when nothing new was added. On an order that
has not synced yet, `fire` flips the pending create's `fire` flag so both land together.

**Manager ops queue too** (Milestone G, 2026-07-27). `menu86` and `tableState` are outbox kinds for
the same reason orders are: an 86 is something *other* staff need to see, and a table freed is too.
Both are last-write-wins on a single row, so replay is safe. Voids stay queued as before. Discounts
are not on mobile at all — `apply_item_discount` requires a bill, and bills come from checkout,
which is web-only in v1.

**Offline-created orders have no server id yet.** The composer holds a local `draft_id`; amends
against a not-yet-synced order are merged into that pending create's payload rather than enqueued
as separate ops. This matches how create mode already batches locally on the web, and avoids
mapping placeholder uuids after the fact.

### Realtime

Supabase Realtime for table states and order/KOT status. **The socket must carry the user JWT or
RLS drops every event** — this cost real debugging time on the web (`realtime.setAuth`, see
`../extrahelper/TASKS.md` Milestone 1 realtime entry). Set auth on connect *and* on token refresh.
Realtime is a freshness optimization layered on the cache, never the source of truth: a screen
must render correctly from cache alone.

---

## 3. Technology Stack

| Layer | Choice | Notes |
|---|---|---|
| Framework | **Flutter 3.38.7 / Dart 3.10.7** | Homebrew cask. Bumping the SDK unlocks Riverpod 3 — see the note below. |
| Platforms | **iOS + Android** | One widget tree, Material 3 both. No Cupertino fork — see `CLAUDE.md`. |
| Backend | **Supabase** (shared with web) | Project `ixrcdtwdcpsmlbocvejv` (dev). RLS is the isolation boundary. |
| Supabase client | `supabase_flutter` **2.16.0** | ⚠️ Breaking changes vs training data — see `AGENTS.md`. `initialize(anonKey:)` is deprecated; use `publishableKey:`. |
| State | **Riverpod 2.6.1** | Pinned to 2.x deliberately — see below. |
| Local DB | **Drift 2.34.2** over SQLite | Real transactions + typed queries. The outbox needs atomic state transitions. `sqlite3` 3.x loads SQLite via build hooks, so **no `sqlite3_flutter_libs`** (that package is end-of-life and does nothing). |
| Routing | `go_router` **17.3.0** | Declarative, deep-link ready for later (QR, order links). |
| Config | `--dart-define-from-file=env.json` | Supabase URL + **publishable** key only. Gitignored; `env.example.json` is committed. Never the service role key. |
| Package manager | `pub` (`flutter pub`) | |

**Why Riverpod 2 and not 3.** `riverpod 3.3.2` depends on `package:test`, and the `test` versions
compatible with Dart 3.10.7 force `web_socket_channel <3` — but `realtime_client`, inside
`supabase_flutter`, requires `^3`. Riverpod 3 needs Dart ^3.11, so this unlocks with an SDK bump and
not with any constraint juggling. Nothing else in the stack was blocking. Revisit when the Flutter
SDK moves; migrating is a contained change while the provider count is still low.

**Do not trust remembered version numbers or APIs** — read the resolved package's own docs
(`AGENTS.md`). `pubspec.yaml` carries the reasoning for each constraint.

---

## 4. Required Tools & Accounts

### Local dev — status on this machine (all resolved 2026-07-26, `flutter doctor` clean)

- **Flutter SDK 3.38.7 / Dart 3.10.7** ✓ (Homebrew cask)
- **Xcode 26.2** ✓ · **CocoaPods 1.17.0** ✓ — CocoaPods is not optional: without it
  `supabase_flutter` cannot build for iOS, and the failure doesn't say so plainly.
- **Android SDK 36.1.0** ✓ · **cmdline-tools 21.0** ✓ · **licenses accepted** ✓ —
  `ANDROID_HOME` and the tool paths are exported from `~/.zshrc`. `sdkmanager` needs a JDK; Android
  Studio's bundled JBR is used (`/Applications/Android Studio.app/Contents/jbr/Contents/Home`).
- **Git** ✓ — own repo, `main`, remote `D-Raj-Grg/ExtraHelper_App`. Separate from `../extrahelper/.git`.
- **Devices** — iPhone 17 Pro simulator (iOS 26) and a Medium Phone API 36 emulator both work. No
  physical device attached yet. Offline behaviour must be tested on a **real device in airplane
  mode** — a simulator's network stubbing is not the same thing.
- **Disk** — a cold iOS build plus a cold Gradle build want several GB free. A full volume surfaces
  as `ENOSPC` mid-build, not as a clear message.

### Accounts / services

- **Supabase** project — already live, shared with web. Nothing new to provision.
- **Apple Developer** ($99/yr) — required for a physical-device build beyond 7-day free
  provisioning, and for TestFlight/App Store.
- **Google Play Console** ($25 one-off) — for internal testing tracks and release.

### Identifiers

- Bundle / application id: `com.extrahelper.app` (proposed — fix before the first signed build;
  changing it later means a new Play listing and a new iOS app record).

---

## 5. Roles on mobile

Same per-tenant RBAC as the web: Owner/Admin · Manager · Receptionist/Host · Cashier · Waiter ·
Kitchen/KDS · Inventory/Store Keeper. Enforced identically — `app_role` bounds DB access via RLS,
and the 35-key granular permission matrix refines at the app layer. Mobile calls
`get_my_permissions` and gates navigation and buttons on the result, exactly as the web
`PermissionProvider` does.

**Mobile does not define its own roles or permission keys.** A new capability means a new
permission key in the shared catalog, added on the web side, and honoured by both.

v1 targets **waiters** (`order.create`, `order.fire`, `order.view`, `tables.view`). Later phases
add manager ops, inventory, and the owner dashboard.

---

## 6. Phased Roadmap

0. **Shell** — project scaffold, theme from ported design tokens, `supabase_flutter` wired, login,
   join-by-code, tenant context + switcher, permission gate, navigation skeleton, runs on a real
   iOS **and** Android device.
1. **Waiter ordering (online)** — tables board with live states, order composer (destination →
   dishes → variants/modifiers/notes → cart → fire), amend a fired order, void with reason.
2. **Offline** — menu/table cache, outbox, replay engine, pending badge, dead-entry surfacing.
3. **Owner dashboard** — KPI tiles + revenue chart, read-only (`../extrahelper/TASKS.md` line 77
   wants this).
4. **Manager ops** — 86 toggle, table state control, void/discount approval.
5. **Inventory** — stock counts and adjustments in the store room; barcode scan via camera.
6. **Store release** — signing, icons/splash, TestFlight + Play internal track, then production.

Phases 0–2 are the scoped first build. Track granular work in `TASKS.md`.

---

## 7. Open Questions

1. **Bundle id** — confirm `com.extrahelper.app` before the first signed build.
2. **KDS on mobile?** The web KDS is a full-screen wall display; a phone-sized KDS may be
   pointless. Decide before phase 4.
3. **Cashier/payments on mobile** — deliberately excluded from v1. Does a waiter ever need to take
   payment tableside? That pulls in the whole `record_payment` + split + receipt surface.
4. **Push notifications** — the web uses an in-app bell polling Realtime. Does mobile need real
   push (FCM/APNs) for new-order alerts, and if so, whose device gets them?
5. **App distribution before store approval** — TestFlight and Play internal testing, or a direct
   `.apk` for the pilot restaurant?
