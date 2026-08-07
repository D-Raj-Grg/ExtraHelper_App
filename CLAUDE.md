@AGENTS.md

# ExtraHelper Mobile — Flutter (iOS + Android)

Native staff app for the ExtraHelper restaurant SaaS. **One client of an existing system** — the
web app, the schema, the RLS policies, and every business rule already exist. Read these before
non-trivial work:

- `PLANNING.md` (this repo) — mobile architecture, roadmap, toolchain status
- `../extrahelper/CLAUDE.md` — the system's non-negotiable rules and design system
- `../extrahelper/PLANNING.md` — product vision and full architecture
- `../extrahelper/TASKS.md` — what already ships, and the traps already paid for
- PRD: `/Users/almighty/.claude/plans/1-help-me-to-wondrous-bird.md`

## Stack
- **Flutter** (stable, 3.38.7 / Dart 3.10.7 here) — Material 3, one widget tree for both platforms.
- **Supabase** via `supabase_flutter` — the **same project as the web app**. RLS is the gate.
- **Riverpod** state · **Drift/SQLite** local cache + outbox · **go_router** routing.
- ⚠️ These packages have breaking changes vs training data — read `@AGENTS.md` first.

## Non-negotiable rules

1. **No business logic in Dart.** Anything that decides money, stock, or access lives in Postgres
   and is called by both clients. If a mobile feature needs logic that only exists in a TypeScript
   server action, write a Postgres function and refactor the web action onto it — do not
   reimplement. Duplicated pricing drifts, and drift means the till total disagrees with the
   kitchen ticket.
2. **Tenant isolation is sacred.** RLS is the boundary, but every query still carries an explicit
   `.eq('tenant_id', activeTenantId)` as defense in depth — the same sweep the web app did. Local
   cache rows are **tenant-stamped**; switching tenant wipes and refetches. Never ship the service
   role key — the app carries the **publishable** key only, via `--dart-define`.
3. **Permissions come from the server.** Gate navigation and buttons on `get_my_permissions`, never
   on a role string held in the app. Mobile does not invent permission keys; a new capability means
   a new key in the shared catalog.
4. **Idempotency keys are minted at enqueue and never regenerated.** Every order/amend write goes
   through the outbox, online or offline. A retry reuses its key. See `PLANNING.md` §2 for all five
   offline rules — each one maps to a real bug the web queue was hardened against.
5. **Realtime is an optimization, not a source of truth.** Every screen must render correctly from
   cache alone. And the socket **must carry the user JWT** or RLS silently drops all events — set
   auth on connect and on every token refresh.
6. **Audit and approval rules are the server's, not the app's.** A void needs a reason and manager
   approval because `void_order_item` enforces it. Never build a UI path that tries to skip it.

## Order lifecycle (shared with web)

`draft → placed → in_kitchen → preparing → ready → served → billed → closed` (plus `cancelled`).
Firing routes items per kitchen station — each station gets its own KOT. A change after firing is a
**KOT amendment**: adding is `amend_order_add_item`, removing is `void_order_item` with a reason.
Enum values: `order_status`, `order_type` (`dine_in|delivery|pickup|qr`), `table_state`
(`free|occupied|reserved|bill_requested|cleaning`), `kot_status`.

## Design system

Read `../extrahelper/.impeccable.md` for the why — it applies here unchanged. Staff use this
mid-service, one-handed, standing, in glare or low light. **Bold, high-contrast, legible at arm's
length.** Emotional goal is *certainty*: never make someone wonder whether the tap registered.

**Port the tokens, don't re-invent them.** `core/theme/` holds the Dart equivalents of the web
system, so the two apps are recognisably one product:

- **Type**: Figtree (bundle the font — no network fetch at launch). Size and weight carry hierarchy.
- **Palette**: tinted neutrals, never pure black or white. Light and dark both first-class.
- **Semantic colour, app-wide** — emerald = good/balanced/free · amber = warning/low/occupied/over ·
  destructive = error/short/loss · blue = informational/reserved · orange = bill requested.
  Named theme extensions only, never a raw `Colors.green`.
- **Never colour alone.** Every state carries an icon, label, or sign (`+`/`−`) too. Red-vs-green is
  the worst offender — it is the most common colourblindness. `VegMark` is the pattern to copy:
  **circle vs triangle** carries the meaning, colour only reinforces. **If it fails a greyscale
  screenshot, it is wrong.**
- **Tap targets ≥44px.** Quantity steppers, chips, anything hit mid-rush. Material's defaults are
  smaller — set them explicitly.
- **Money and numbers**: tabular figures on every column figure (`fontFeatures: [FontFeature.tabularFigures()]`),
  numeric columns right-aligned. Format through `core/money.dart` — never a hand-rolled
  `toStringAsFixed`. Currency, timezone, tax and fees come from `tenant_settings`.
- **Quote a price someone can actually pay.** A dish with variants forces a choice, so its base
  price is unbuyable. Tiles show a **range** (min/max including variant deltas, add-ons excluded
  since they're optional) — in the accessibility label too. This was a live bug on the web: a dish
  advertised NPR 380 when the only orderable prices were 1,080 and 1,680.
- **Enum values never reach staff.** `bill_requested` → "Bill requested" via a label map, never a
  string replace.
- **States are not optional.** Loading, empty (teach the next step — not "No data."), error (say the
  recovery), success. Destructive actions confirm and **name the real consequence**.
- **Motion**: transform/opacity only, ease-out, 150–300ms, and honour
  `MediaQuery.disableAnimations` / reduce-motion. No bounce.
- **Respect the user's text scale.** The web app ships a per-user text-size preference; on mobile
  the OS provides one. Never hardcode a height that breaks when text grows.
- **Anti-references**: no glassmorphism, no gradient text, no cards nested in cards.

**Widgets to port from the web POS** (`../extrahelper/components/pos/`), so behaviour matches:
`ChoiceChip` (few options a waiter picks mid-service), `MenuTile` (photo-first: image leads, name +
price under, designed monogram placeholder when there's no photo, count badge when it's in the
order), `VegMark`, `TableGlyph`, `DishThumb`'s monogram derivation.

## Known traps

Mobile-specific ones, plus the shared ones that will bite again:

- **The Realtime socket needs the JWT.** Without `setAuth` (and a re-set on token refresh) RLS drops
  every event and the screen looks merely "not live". Cost real debugging time on the web.
- **`inflight` must be persisted, not a memory flag.** An app killed mid-call leaves the write in
  limbo otherwise. Persisted + same idempotency key makes restart-retry safe.
- **A transient failure must not burn the retry cap.** Separate server-reject (→ dead, surface the
  error) from network-transient (→ retry). Conflating them silently drops real orders.
- **A dialog owns its controllers.** Never create a `TextEditingController` beside a `showDialog`
  call and dispose it after the `await` — the future resolves a frame before the field unmounts, and
  the field's `dispose()` then hits a dead controller. The element never finishes deactivating and
  the app dies on `'_dependents.isEmpty': is not true`. Put the field in a `StatefulWidget` and
  dispose in its `State`.
- **A role check inside a server action is not a guard.** RLS on `menu_items` and
  `restaurant_tables` is tenant-scoped only, so `requireRole(...)` in a TypeScript action stopped
  nobody from doing the same update through the API. Anything a role should gate belongs in a
  `security definer` RPC that both clients call — which is also where the audit row gets written.
- **Never key a list row by its content.** A signature key that changes on every keystroke rebuilds
  the row and loses the caret mid-word. Key on a stable id; use the signature only to decide merges.
- **`create or replace function` cannot change a function's arity** — it silently creates an
  *overload* and leaves the old body live. Changing an RPC's args means `drop` + `create`, then
  re-issuing `revoke`/`grant` **naming the full new signature**: `public` holds EXECUTE by default.
- **Every new `security definer` function needs `revoke execute from public` + an explicit grant to
  `authenticated`.** `revoke from anon` alone does nothing.
- **Don't hand-edit generated code** (`*.g.dart`, drift output) — run the generator, and run it as
  **`dart run build_runner build --force-jit`**. Plain `build_runner build` dies with "Failed to
  compile build script": sqlite3 3.x uses Dart build hooks, and `dart compile exe` refuses to
  AOT-compile a build script in that package graph.
- **Never let a read block a write, and never `await` a network read on a tap.** Offline, an HTTP
  call sits on a long timeout, so an awaited refresh turns a durable queued order into a spinner
  that never resolves. Ask connectivity first, cap the wait, and leave post-write refreshes
  unawaited. Every offline bug found on the airplane-mode run was this one shape.
- **Cache the shell, not just the board.** Memberships and permissions are network reads; without
  them a cold start with no coverage renders "No ordering access" and the app is useless. They are
  cached for rendering only — the RPCs still enforce every key.
- **A missing key in `env.json` can disable a feature in silence.** `SUPABASE_*` throws at startup
  naming the command, but `APP_URL` only gates `Env.canPrint` — omit it and the app builds, runs,
  and simply has no printing: no toggle, no error, no tickets. The first signed iOS archive shipped
  that way and it was caught by reading, not by anything failing. Copy **all** the keys from
  `env.example.json`, and check what actually reached the binary rather than trusting the flag:
  decode `DART_DEFINES` out of `ios/Flutter/Generated.xcconfig`.
- **iPhone cannot print over Bluetooth, and no amount of code changes that.** iOS blocks classic
  Bluetooth SPP without an MFi chip in the printer. Network (port 9100) is the iOS path; classic BT
  stays Android-only. Don't re-open it — the reasoning is in `TASKS.md` under Milestone M.
- **iOS plugins need CocoaPods.** Without it `supabase_flutter` simply won't build on iOS, and the
  error doesn't say so plainly.
- **Test offline on a real device in airplane mode.** A simulator's network stubbing is not the
  same thing, and neither is Chrome devtools throttling.

## Verification

Evidence before claims. For anything here that means:

- `flutter analyze` clean and `dart format` applied.
- **Unit tests for the sync layer** — it's pure Dart, no widgets, no emulator: double-enqueue → one
  row; kill mid-`inflight` → restart re-attempts under the same key, no duplicate; server-reject →
  `dead`, not retried; 6 transient failures → dead after 5 with the error preserved; tenant switch →
  cache wiped.
- **Cent-parity against the web** for any pricing path — same item, variant and modifiers must
  produce the identical `unit_price_cents` and `name_snapshot` through both clients.
- **RLS isolation** — a user of tenant A cannot read tenant B rows through the app, and the local
  cache never serves the wrong tenant.
- **A real device, both platforms.** "Builds" is not "runs"; "runs on Android" is not "runs on iOS".
- **Greyscale screenshot check** on any state that uses colour.
- Never test against a real tenant's data.

## Working rules

- Read `PLANNING.md` at the start of every new conversation.
- Check `TASKS.md` before starting work. Mark tasks done immediately. Add newly discovered tasks.
- When a change spans both clients (a new RPC, a schema change), update
  `../extrahelper/TASKS.md` too — one system, two front ends.
