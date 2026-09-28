# Changelog

All notable changes to the **ExtraHelper mobile app** (iOS + Android).

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions are patch-level: each release is a milestone's worth of work that shipped together. Dates are ship dates taken from git history. Each release ends with a collapsed **Technical** note listing the commits and the substance behind them.

The app is not on the public App Store or Play Store. 1.0.7 is the first build to leave a simulator: iOS, signed, distributed through **TestFlight internal testing** (which skips App Review). `pubspec.yaml` now tracks the store version — the build number after the `+` increases on every upload. Business rules live in Postgres and are shared with the web app — see `../extrahelper/CHANGELOG.md` for the server-side half of any release noted below.

> **Branch note.** 1.0.0 and 1.0.1 are on `main`. 1.0.2 through 1.0.6 currently live on `milestone-f-offline` and are not merged to `main` yet.

---

## [Unreleased]

### Changed
- **Bills tab opens on All today.** The chips now run **All today · Paid · Void · Credit**, and the tab starts on All today instead of the old first chip. What used to be called **Owed** is now **Credit** — same list, every bill with money outstanding however old, sitting at the end where it is looked for rather than lived in.

### Added
- **Set a staff password from the phone.** On Team, an owner's row menu now has **Set password** (and **Create login** on an invite that never signed up), like the web. Type one or **Generate one** (`abcd-2345-wxyz`, no look-alike letters), show or copy it, and tell them in person — nothing is emailed, and their old password stops working right away. Only an owner sees it, never on an owner's row or your own; a person who also works at another restaurant is refused with the reason, same as the web.
- **Coupons on the phone.** A new **Coupons** entry in the drawer (Owner/Manager by default, via *See coupons*) brings the web's Insights → Coupons over. Every campaign code with its badge — **Active**, **Paused**, **Scheduled**, **Expired** or **Used up** — what it takes off, when it runs, how many times it was used and how much it has given away. Tap one for **Show QR**: the flyer square on screen for a guest to scan, **Copy link**, or **Share** it as a picture to whoever prints the flyers. With *Manage coupons* the same menu offers **Pause / Resume**, **Edit** and **Delete**, and **New coupon** at the bottom: code (blank makes one, `SAVE10-7KQ2`), campaign name, percent or amount off, valid from / through, usage limit, minimum order, dine in / takeaway / delivery, once per customer. A coupon already on a bill cannot be deleted — the phone says so and offers Pause instead, same as the web. Printing the flyer itself stays on the web.

### Fixed
- **The coupon test that was never run.** The checkout's "a coupon on the bill is named" test tapped a button that sat below the fold on the test screen and silently missed; it now scrolls first. The checkout coupon box and Scan button themselves were already right.

<details><summary>Technical — staff passwords</summary>

- The password write needs the service-role key, which no client may hold (rule 2), and there was no RPC or Edge Function for it — the web did it inside a Next.js server action. New Supabase Edge Function **`set-member-password`** (`../extrahelper/supabase/functions/set-member-password/index.ts`, deployed 2026-09-28, `verify_jwt: true`): takes `{tenant_id, password, user_id}` or `{tenant_id, password, email}`, re-checks the password rule, runs `assert_can_set_member_password` / `assert_can_create_invite_login` **under the caller's JWT** (the owner-only SQL the web already relied on), then `auth.admin.updateUserById` / `createUser` + `user_tenants` upsert + `staff_invites` delete, and writes the `password_reset` audit row (`set_password` / `create_login`, email only, never the password). Errors come back as `4xx {error}`; 401 for no or anon token.
- `TeamRepository.setMemberPassword` / `createInviteLogin` → `_client.functions.invoke('set-member-password')`. A `FunctionException` body's `error` goes through `friendlyTeamError`; anything else is transient. `passwordProblem()` mirrors the web's (8–72, letters + digits) so the dialog refuses what the server would.
- `canManagePasswordsProvider` = membership base role `owner` (the assert RPC checks `has_tenant_role`, not a permission key — the web gates on `tenant.role === "owner"` for the same reason). `staff_tab.dart`: `MemberAction.setPassword` on an active non-owner row that is not yours, `MemberAction.createLogin` on a non-owner invite. `password_dialog.dart` owns its controller; `generatePassword` is `Random.secure()` over `[a-hj-km-np-z]` and `[2-9]`.
- Tests: `test/password_dialog_test.dart` (validator, generator shape, button gating, refused-without-digit, generate → visible), `test/team_permissions_test.dart` (+2: owner sees the items on the right rows only; manager with `staff.edit` sees none).
- Not verified: a real set-password on device against a throwaway staff account (would touch the live tenant's logins).

</details>

<details><summary>Technical — coupons</summary>

- No new SQL. `CouponsRepository` (`lib/data/supabase/coupons_repository.dart`) calls the three RPCs the web already uses: `list_coupons(_tenant)` under `coupons.view`; `upsert_coupon(...)` and `delete_coupon(_id)` under `coupons.manage`. Pause/resume is `upsert_coupon` with every field re-sent and only `_is_active` flipped (`Coupon.toDraft().copyWith(isActive:)`) — there is no pause RPC. `Coupon.fromRow` coerces `numeric`/`bigint` strings; `CouponDraft.validate()` mirrors the web's `saveCoupon` checks (code `^[A-Z0-9-]{4,24}$` or blank, value > 0, percent ≤ 100, limit ≥ 1 or null, end after start); `effectiveOrderTypes` sends null for none-or-all.
- `lib/features/coupons/`: `coupon_status.dart` ports `lib/coupon-constants.ts` (`couponStatus`, `couponValueLabel`, `couponSummary`, `couponUrl`, `couponQrPayload`); `coupons_providers.dart` (`couponsProvider`, autoDispose, keyed on tenant id); `coupons_screen.dart` (list + action sheet + delete dialog); `coupon_sheet.dart` (form, owns its controllers); `coupon_qr_sheet.dart`; `no_coupon_access.dart`. Route `Routes.coupons = '/coupons'`; drawer entry after Customers on `coupons.view`.
- **QR** is drawn from `zxing2`'s `Encoder` (already a dependency, used by the print pipeline's tests) through a 40-line `CustomPainter` — no new package, no network. Payload is `${APP_URL}/s/{slug}?coupon=CODE`, the bare code when either is missing, so it scans on the web storefront and at the phone's checkout alike. Share photographs the card through `exportFrame` / `capturePng` from `bill_export.dart` and hands the PNG to `fileSharerProvider`, the receipt's path.
- **Dates**: the phone has no tz database. `showDatePicker` days become `DateTime(y,m,d)` in the device zone; "valid through" stores the exclusive start of the next day (`exclusiveEndOf` / `lastDayOf`, calendar arithmetic so a DST night cannot land a day out), as the web does in the tenant zone. An **edit that never touched a date sends the stored instant back unchanged** (`_fromTouched` / `_throughTouched`) — otherwise a phone in another zone would quietly move the end by its offset. The picker's range widens to include an old campaign's start, which `showDatePicker` would otherwise assert on. Staff phones are on the restaurant's clock; a *newly picked* day on a phone in another timezone is still off by that offset.
- Review pass (same day): `CouponDraft.toRpcParams` is a pure map and tested key-for-key; the form is tested through `showCouponSheet` (defaults, untouched dates round-trip, clear → null); both sheets `useSafeArea`; the date clear is a 44px `IconButton` with a tooltip; badge hues come from `context.semantic` (icon + word carry the state); the QR grid is encoded once per sheet, not per rebuild.
- Tests: `test/coupons_repository_test.dart` (row parsing, draft validation, pause keeps fields, RPC params), `test/coupon_status_test.dart` (badge matrix, labels, URL, QR grid, day bounds), `test/coupon_sheet_test.dart` (form round-trip), `test/coupons_screen_test.dart` (list, viewer vs manager levers, used-coupon delete → Pause instead, empty state, locked door), drawer cases in `test/shell_chrome_test.dart`.

</details>

## [1.0.16] — 2026-09-28 · Costs, coupons and customers

### Added
- **Scan the coupon.** The coupon box on the checkout's adjustments sheet has a **Scan** button beside it: point the camera at the flyer's QR and the code applies itself. Typing still works. A coupon already on the bill shows as "Now: SAVE10-7KQ2 · 10%" with **Remove**, and the totals card names it ("Discount · SAVE10-7KQ2"). Needs the web migration `20260928120000_coupons` on the server — which also makes the typed coupon box work for the first time (it had been failing on a database error since it shipped).
- **Cost price on the dish editor.** Under the price there is now a **Cost price** field — what the dish costs you to make. It is shown only to people with the new **See dish costs & profit** permission (owners by default); everyone else sees the form as before, and saving without the field never touches a cost already on file. Leave it blank to clear it.
- **Where costs are entered.** On the phone you can set a dish's own cost only. Per-size costs (Full / Half / 90 ml), add-on costs, the costing table for the whole menu and the “Apply costs to past sales” button are on the web, Inventory → Costing. The figures the phone shows come from the same server numbers as the web: refunds are deducted, add-ons are counted, and a bill discount is shared across that bill's lines.
- **Gross profit and Margin on Day close, profit per top item.** With the same permission, the KPI tiles gain **Gross profit** and **Margin**, and each dish under **Top items** shows its profit beside the quantity. A dish sold with no cost on file shows no profit rather than a wrong one, and a caption counts how many lines had no cost so you know the day's figure is low by that much (costs are entered on the web Inventory → Costing tab, or per dish here).

<details><summary>Technical — costs & profit</summary>

- Costs no longer live on `menu_items` / `item_variants` (those `cost_cents` columns are gone). They sit in RLS-gated one-to-one tables readable only with `profit.view`: `menu_item_costs(item_id pk, tenant_id, cost_cents)` and `item_variant_costs(variant_id pk, tenant_id, cost_cents)`. Without the permission PostgREST returns the embed as null — no error, no 0.
- `MenuRepository._columns` embeds `menu_item_costs(cost_cents)` on `menu_items` and `item_variant_costs(cost_cents)` inside `item_variants(...)`. `MenuEditItem.costCents` / `MenuEditVariant.costCents` parse through `_embeddedCost`: `{cost_cents: n}` → n; null, absent or malformed embed → null.
- `MenuItemDraft` gains `costCents` + `costSet` (default false). `createItem` / `updateItem` call `MenuItemWrites.setItemCost(id, cents)` — the `set_item_cost(_item_id, _cost_cents)` RPC, which carries the `profit.view` check — only when `costSet`; null clears. Both validate the cost (`0..100000000` cents, `MenuItemWrites.maxCostCents`) **before** any table write and throw a `PosFailure` ("Enter a cost price between 0 and 1,000,000, or leave it blank.") so a bad value never leaves a half-made dish.
- `createItem` now returns `CreatedMenuItem` (`({String id, String? costWarning})`). If `set_item_cost` fails after the `menu_items` row exists, the failure is caught and returned as `costWarning` ("Dish saved, but the cost was not. …") instead of thrown, so the person is not told the dish failed when it is on the menu. `item_edit_screen.dart` handles it like the post-save photo failure: shows the warning with "Tap Save to try again." and stays on the screen; `_id` is set by then, so the retry runs `updateItem`, which re-issues the cost RPC against the existing row.
- `item_edit_screen.dart`: `_cost` controller seeded from `item.costCents`; the field renders only under `hasPermissionProvider('profit.view')`, and `_save` sets `costSet: canSeeProfit`, so a form that never showed the field cannot clear a cost.
- `DaySales` gains nullable `netSalesCents`, `cogsCents`, `grossProfitCents`, `marginPct` (double), `uncostedLines`; `DayTopItem` gains nullable `costCents`, `profitCents`. Null-preserving `_maybeInt` / `_maybeDouble` helpers — absent, null **or unparsable** values parse to null, never 0 (`_maybeInt` no longer falls through to `_int`'s 0 default).
- `day_close_screen.dart`: Gross profit + Margin `_Kpi`s only when `grossProfitCents != null`; Margin renders `—` when `marginPct` is null (profit with no net sales to divide by) rather than `0.0%`; top-item note extends with ` · profit …`; muted caption when `uncostedLines > 0`. No new colours.
- Tests: `test/day_report_test.dart` (+3: keys present / absent / unparsable), `test/menu_edit_item_test.dart` (+4: embed present, embed null via RLS, embed absent, draft `costSet`).

</details>

### Added
- **Customers on the phone.** A new **Customers** entry in the drawer (Owner/Manager by default, via *View loyalty*) brings the web's Loyalty & CRM over: search by name, phone or email; **Outstanding credit** total at the top; every customer with their points, tier, and — in red — what they **owe** and on how many bills, debtors first. Tap a customer for their page: credit box, **Earn / Redeem** points, every **unpaid bill** with a **Collect** button that opens the checkout (for anyone who can take payments), and their **past orders**. With *Manage customers*, the ⋮ menu offers **Edit** (name, phone, email), **Merge into another customer** and **Delete**, with the same warnings as the web. Recent guest **feedback** sits under the list.

### Changed
- **Log an expense: category is a dropdown, and it starts on "Other".** The row of category chips is now a single dropdown, so a long list no longer pushes the note and Paid-from fields off the screen. It opens on **Other** (the first category if the restaurant has no "Other"), so a quick back-door payment needs no category tap at all. Editing an expense keeps its own category, archived or not. There is also a **✕** in the top-right corner to close the sheet without saving.

### Added
- **Checkout shows what the guest already owes.** When the attached guest has unpaid credit on *other* bills, the Guest card on the checkout shows a red **Owes Rs X · N unpaid bills** line under their name, so the cashier sees it before tapping **Unpaid (credit)** again. The bill being settled isn't counted against itself. A warning only — leaving another bill unpaid still works. Same numbers as the web's Loyalty & CRM page.

### Fixed
- **Customers, review pass before release.** A customer's page now loads that customer by id, so searching the list no longer blanks the page behind it, and a deep link to a customer shows the same locked door as the list for someone without *View loyalty*. **Merge into another customer** searches the whole book, not just the page you came from. **Outstanding credit … across N customers** counts only guests who still owe something. **Unpaid bills** lists every open or part-paid bill — one with nothing left on it says *nothing left to collect* rather than *owes Rs 0* — and **Past orders** is the paid ones; void bills stay hidden. Pull-to-refresh holds until the new figures land. **Edit** needs a name or a phone (an email alone is not enough to find someone at the counter) and says so. A points change refused by the server for lack of role reads "You don't have permission to do that."

### Known gaps
- The phone gates Customers on the `loyalty.view` permission only; the web additionally hides the page when the restaurant's plan lacks the loyalty feature. A plan without loyalty still sees the credit book here.

<details><summary>Technical</summary>

- Customers: `lib/data/supabase/customers_repository.dart` (`CrmCustomer`, `CustomerBillRow`, `CustomerFeedback`, `CrmOverview`, `CustomersRepository` over `customers`/`feedback` selects plus the shared RPCs `customer_credit_summary`, `customer_bill_history`, `loyalty_adjust`, `update_customer`, `merge_customers`, `delete_customer` — every rule stays in Postgres, the app maps errors to `PosFailure`). Debtors missing from the newest-50 page are fetched by id so every debt has a row. `lib/features/loyalty/`: `loyalty_providers.dart` (search notifier, overview, per-customer history), `loyalty_screen.dart`, `customer_detail_screen.dart`, `customer_dialogs.dart` (`RadioGroup` merge picker). Routes `/customers`, `/customers/:id` (`Routes.customerPath`); drawer item on `loyalty.view`; levers on `loyalty.edit`; Collect on `payment.take`. Tests: `test/customers_repository_test.dart` (14), `test/loyalty_screen_test.dart` (4).
- `BillRepository.snapshot` pass two calls `customer_credit_summary(_tenant)` (shared with the web, `checkout.view`-gated, `security invoker`) only when a guest is attached and the bill is still settleable. Failure is caught on that future alone (it shares a `Future.wait` with the modifiers), so a missing warning never costs the add-on names; the line is simply absent.
- `BillCustomer` gains `owesCents` / `unpaidBills` / `owes`; `BillCustomer.fromCreditRows` subtracts this bill's own due amount and count from the roll-up, mirroring `app/(app)/bill/[billId]/page.tsx` on the web. Unit tests in `test/bill_models_test.dart`; widget tests for the card in `test/checkout_screen_test.dart`.
- `expense_sheet.dart`: `DropdownButtonFormField` replaces the `AppChoiceChip` wrap for categories; `_defaultCategory` matches `other`/`others` case-insensitively and falls back to the first category. Header is a `Row` with an `IconButton(Icons.close)`. Widget tests in `test/expense_sheet_test.dart`.
- `_CustomerCard` in `checkout_screen.dart` renders the line in `colorScheme.error`. Not built or uploaded; ships with the next TestFlight build on request.
- Customers review fixes: `CustomersRepository.customer(id)` (`_select` by id + tenant, `maybeSingle`, joined with `customer_credit_summary`; null when no row) behind `customerProvider(id)`; `customer_detail_screen.dart` reads it, gates on `identityStatusProvider` like the list, and its `RefreshIndicator` awaits `Future.wait` of the customer and history refreshes (the list awaits `crmOverviewProvider.future`). `CrmCustomer.fromRow` accepts `loyalty_accounts` as a List, a Map or null; every `fromRow` in `overview()`/`customer()` runs inside the try so a bad row is a `PosTransientFailure`. `CrmOverview.countDebtors(rows)` counts `outstanding_cents > 0` only and the debtor back-fill uses the same filter. Providers select `activeTenantProvider.select((m) => m?.tenantId)` (`Membership` has no `==`). `showMergeCustomerDialog(context, customer, search:)` debounces 300 ms and calls `search(q)` (the detail passes `repo.overview(query:)`), excluding the customer itself. `_friendly` maps "require(s) a manager" to the permission message. Shared `NoCustomerAccess` widget in `lib/features/loyalty/no_customer_access.dart`. Tests: `customers_repository_test.dart` (+2), `loyalty_screen_test.dart` (+3, detail now overrides `customerProvider`).

</details>

---

## [1.0.15] — 2026-09-26 · The menu on the phone

TestFlight build **1.0.15+1**, submitted to App Store review on 2026-09-26 (releases automatically once approved). This is the first App Store release since 1.0.13, so it also carries everything in 1.0.14.

### Added
- **Manage the menu from the phone.** The Menu screen could only fix a dish's sizes. Now it can:
  - **Add a dish:** name, price, category, kitchen station, veg / non-veg / not marked, a description, and a photo.
  - **Change one** the same way, or **delete** it. Past orders and bills keep a deleted dish.
- **Dish photos.** Take one with the camera or pick one from the gallery, change it or remove it. It shows on the POS, the QR menu and the web, because it is the same photo the web editor uploads. Each dish in the menu list now shows its photo, or its initials when it has none.
- **In stock / Sold out, one tap.** Every dish in the menu list has a switch, with the word beside it. Turning it off marks the dish sold out everywhere, so nobody can order it until it's turned back on. The screen counts how many dishes are sold out. It works with no signal too: the change is saved on the phone and sent when coverage returns. Owners, managers and the kitchen can change stock; the switch is disabled for everyone else.
- **Categories.** Filter the menu by category with the chips at the top. From the new Categories screen, add, rename, and hide or show a whole section on ordering screens. You can also create a category while adding a dish.
- **Add-ons.** From a dish, tick which add-ons it offers (extra cheese, no onion, a side of rice) and set the most a guest can have of each. You can create a new add-on right there. **Manage menu → Add-ons** renames, reprices or deletes an add-on across every dish, and shows how many dishes use each one.
- **When it's sold.** Give a dish time windows — every day, or a single day, from one time until another (breakfast 07:00–11:00, a Saturday special). With no windows it's sold any time.
- **Combos.** **Manage menu → Combos** builds a bundle: a name, a price, and the dishes in it with quantities. It shows what they would cost bought separately. Switch a combo on or off, edit it, or delete it; the dishes in it stay on the menu.
- **Several kitchen stations per dish.** Pick every station a dish's ticket should go to.

### Known gaps
- **Time windows and combos are stored but not yet used when ordering, on the phone or the web.** A dish outside its window can still be ordered, and a combo can't be rung up as one line yet. Both need a server-side rule, which is the next step. Add-ons, stock and stations do take effect immediately.

<details><summary>Technical — menu editing</summary>

- No server change. `menu_items`, `menu_categories` and `item_station_routes` writes are plain table writes, gated on `menu.edit` by RLS, the same ones the web editor makes. Every write reads back its row, and zero rows is reported as a refusal. Stock goes through the existing `set_item_86` RPC via the outbox (`OutboxKind.menu86`). The switch keeps an optimistic value until the refreshed list arrives.
- Photos use the web's path `menu-images/{tenant}/{item}.{ext}` (upsert, cache-busted URL), so the two clients replace each other's photo.
- Stations are saved as a set difference (add the missing ones, delete the extras, leave matching ones alone), so a dish routed to several stations is never collapsed to one. Add-on links upsert on `(item_id, modifier_id)` like the web, and changing the maximum keeps `is_default`. Time windows go to `item_availability` (null day = every day; `HH:MM` local). Combos are `combos.items = [{item_id, qty}]`.
- `lib/features/menu/`: `item_edit_screen.dart`, `item_addons_screen.dart` (per-dish links + library), `item_availability_screen.dart`, `combos_screen.dart`, `menu_categories_screen.dart`, `stock_toggle.dart`, reworked `menu_screen.dart`. The photo picker moved to `lib/core/widgets/photo_picker.dart` and is shared with expense receipts. Test: `test/menu_edit_item_test.dart`.

</details>

---

## [1.0.14] — 2026-09-26 · Expenses and order alerts

TestFlight build **1.0.14+1**.

### Added
- **Expenses on the phone.** A new **Expenses** entry in the menu for everyone on staff. Tap **Add expense**, type the amount, tap a category, write a few words, and choose where the money came from (Cash, Online / eSewa, Owner's pocket). You can add a receipt photo from the camera or gallery. **It works with no signal**: the expense is saved on the phone, shown greyed out as "Waiting to send", and sent once when the connection is back, never twice. Page back through earlier days; managers can add to them. Edit, void with a reason, and attach, view or remove a receipt photo from each entry's menu.
- **Last 7 days and last 30 days.** Managers see rolling expense totals at the top of Expenses, with the category that cost the most, matching the web Reports page.
- **Count cash & close the day.** Day close now has a **Cash book** card: what should be in hand (sales minus refunds minus cash expenses), the same for online, and a **Count cash & close the day** sheet for what you actually counted. It shows Balanced, Short or Over, and you can recount. Day close also lists the day's expenses. The shift-drawer section only appears for restaurants that use a drawer.
- Owners and managers can manage expense categories from the tag icon on Expenses.
- **Order alerts on the phone.** The app now tells staff about every step of an order — **new order, preparing, ready to serve, served, billed, paid**, and cancelled — as a real phone notification with a banner and sound. A waiter hears that a table's food is up without watching the pass. Alerts come from other people's actions: tapping "Served" yourself doesn't buzz your own phone. The amount is shown in the restaurant's currency when there is one.
- **Asked once, like other apps.** Shortly after you sign in, the app explains what the alerts are for and then shows the phone's own permission prompt. It asks once per device. After that, **Settings → Notifications** shows whether alerts are on, turns them on (or opens the phone's settings if they were blocked), and has a **Mute on this phone** switch for a shared counter tablet that shouldn't buzz.
- **A bell in every screen's header** with an unread count, opening a **Notifications** screen: every update with an icon for each step, unread ones in bold, pull to refresh, and **Mark all read**. Tapping a phone notification opens this screen, including when the tap is what starts the app. Billed and paid updates open the bill for staff who can take payments.
- Unread works the same as on the web: only the last 24 hours count, and your own actions never do, so the phone and the browser show the same number.
- Kitchen and store-room roles get no bell, no alerts and no prompt.
- **The receipt on the phone looks like the real one, and can be sent.** The bill screen now carries the restaurant's logo, closing words, terms and the **payment QR** a guest scans, the same as the web receipt and the thermal slip. **Share** sends it as a picture, so a guest can get it on Viber or WhatsApp without a printer. Nothing extra shows for a restaurant that hasn't uploaded a logo or QR.

### Fixed
- **Day close: stepping back a day and then forward again now lands on today properly.** Going forward to today used to pin the screen to that date instead of following "today", so if the trading day rolled over while the app was open, the sheet stayed on the previous day. It could also briefly treat the day you'd just left as today and disable the forward arrow.
- **Day close could step back a day but never forward again.** The forward arrow stayed disabled once you left today; it now pages forward up to today.

### Known gaps
- **Alerts need the app to be running.** They arrive while ExtraHelper is open. On Android that includes the background for as long as the phone keeps the app running; iOS pauses a backgrounded app soon after, and whatever came in meanwhile shows in the list when you come back, without a banner. With the app fully closed nothing arrives. That needs push notifications through Firebase/APNs, which is the next step.
- Not yet checked on a real phone: the permission prompt, a banner while backgrounded, and tapping a notification to open the app.
- Expenses not yet checked on a real phone either: logging in airplane mode and seeing it arrive once, and attaching a receipt photo from the camera.

<details><summary>Technical — order alerts and day close</summary>

Server half: `../extrahelper/supabase/migrations/20260926120000_order_notifications.sql` and `20260926130000_order_notifications_hardening.sql` (see the web changelog).

- **Dependency.** `flutter_local_notifications` ^22.3.1 (needs Flutter 3.38.1+ / Dart 3.10, compileSdk 35+, AGP 8.11.1+, minSdk 24). Android: core library desugaring on with `desugar_jdk_libs:2.1.4`, `POST_NOTIFICATIONS` in the manifest, monochrome `ic_stat_notify` vector kept from R8 by `res/raw/keep.xml`, high-importance `orders` channel, category `event`. iOS: `UNUserNotificationCenter` delegate set in `AppDelegate.swift` so banners show while the app is open.
- **Code.** `lib/data/notifications/` (`AppNotification`, `LocalNotifier`), `lib/data/supabase/notifications_repository.dart` (latest 50, cursor, `mark_notifications_read`, realtime INSERT stream on a fresh topic per listen with an `onRejoin` catch-up), `lib/features/notifications/` (feed notifier, bell, screen, `NotifyLoop`), `lib/features/settings/notification_settings_screen.dart`.
- **Feed notifier.** Rebuilds only when the tenant id, user id or `notifications.view` changes, watched via `select`. `Membership` has no `==` and is rebuilt on every token refresh and connectivity flip, and rebuilding on those tore the channel down mid-service. Every async write carries a build generation, so a slow response from a previous tenant is dropped. `refresh()` merges rather than replaces and keeps the later cursor. It also recovers a feed whose first load failed; before, live rows went into a buffer that was never merged. A failed mark-read restores only the cursor. The screen keeps the list on reload/error (`skipLoadingOnReload`, `skipError`). A tray tap before go_router has its first route retries instead of throwing.
- **Unread.** `isUnread(n, cursor, userId:, now:)` = `created_at > max(cursor, now − 24h)` and not self-authored. Mirrors the web's rule.
- **Day close.** `DayCursor.next()` clears the selection (back to "today") when it reaches the known today, instead of naming the date; the screen's listener ignores loading states, whose `valueOrNull` is still the previous day's report.
- Tests: `test/notifications_test.dart` (alert filtering, unread window, cursor merge, arrival merge, bell) and `test/day_cursor_test.dart` (back → forward → back).

</details>


<details><summary>Technical — expenses</summary>

Server side: see `../extrahelper/CHANGELOG.md` → "daily expenses, receipts, night count".

- `data/supabase/expenses_repository.dart`: `PaidFrom`, `Expense`, `ExpenseDay` (`expenses_day`), `ExpenseRange` (`report_expenses`, rolling 7/30 days), record/update/void/categories/`close_day`, and receipts (upload to the private bucket, then `set_expense_receipt`, then clean up the old object; signed URL for 10 minutes).
- New `OutboxKind.expense`. The outbox idempotency key is the RPC's `_client_key`; it appends rather than last-write-wins. `OrderQueue.recordExpense` / `pendingExpenses`. Tests: `test/outbox_test.dart` → `expenses`.
- A photo picked while adding is attached after the write syncs (the id is looked up by client key). If the expense was queued offline, the user is told to attach it from the menu later.
- `features/expenses/` (screen, sheet, categories screen, `receipt_photo.dart`), `features/reports/day_count_sheet.dart`. `DayReport` parses `expenses`, `cash_book` and `cash_drawer_enabled`.
- iOS `NSPhotoLibraryUsageDescription` added; the camera usage string now mentions receipts.

</details>

---

## [1.0.8 – 1.0.13] — 2026-08-13 → 2026-08-24 · TestFlight builds

Six TestFlight builds went out between 1.0.7 and 1.0.14 without their own entries here. They are gathered into one entry; the per-build notes are in `TASKS.md` under "TestFlight 1.0.11+1", "1.0.12+1" and "1.0.13+1".

### Added
- **Checkout on the phone.** A waiter or cashier can now settle a bill at the table instead of walking to the till. Tap **Bill** on an order (or a table that has asked for one) and the bill opens: the items, what they come to, and what is still owed. From there you can take cash, card or wallet in full or in part; split the check equally, by item, or across several tenders; discount the bill or a single line; add an extra charge; apply a coupon; add a tip or round the total off; attach a guest and spend their loyalty points; put another round onto the same tab; leave the bill unpaid on a guest's tab; and refund a settled one. A third **Bills** tab lists everything still owed, because opening a bill takes its order off the Orders board.
- **The receipt prints itself.** Settling a bill on the phone queues the receipt exactly as settling one on the till does, and the phone's own printer picks it up. No new printing code was needed.
- **Something off the menu.** A new button in the order screen adds a hand-typed line — a plating charge, today's special — with a name, a price, a quantity and a kitchen note. It matches the web: no `item_id`, so it can never stand in for a menu item's price; no stock comes off it; it prints on the expo ticket; and the typed price is clamped and recorded in the manager log. Works when composing a new order and when adding to one already with the kitchen.
- **Day close on the phone.** The same Z-report as the web: sales, payments, cash drawer, top items and every order of the day, with back and forward through days. (1.0.10)
- **Sign up, Settings and Team on the phone.** Create a restaurant or join one from the app; change general, charges, branches, printers and appearance settings; approve staff and edit roles. (1.0.11)
- **A welcome screen before the login form,** and being offline no longer looks like being locked out. The app says it's offline and keeps working from what it has saved. (1.0.12)

### Fixed
- **The menu on the phone could go stale and never recover — and it cost money.** The cached-list loader kicked off its background refresh while it was still building, which Riverpod refuses; the refresh died as an unhandled error every time, so whatever was saved on the first run was what the phone showed forever. On a real order this charged nothing: a dish whose price had moved onto size variants still showed the old flat price, was added without asking for a size, and the server snapshotted it at zero. The refresh now runs on the values the build already resolved and touches no providers, so it completes. Pull-to-refresh was never affected — this only ever hit the automatic one.
- **Variants and add-ons appear again.** Same cause: the stale cache predated them, so dishes that should ask "which size?" were added straight to the order. A dish with options now shows its badge and price range and forces the choice, as it always should have.
- **Phone preferences reset on every launch** (theme, text size and similar). This regression shipped in 1.0.12 and was fixed in 1.0.13.

### Changed
- **Coming back from an unpaid bill lands on the Bills tab.** Billing an order moves it off the Orders list by design, so backing out of a half-finished bill used to drop you on a list your order had just vanished from. The Orders empty state now says where billed orders go, too.
- **Tapping a table that has asked for its bill opens the bill**, not a second order. Previously the app looked only at orders still on the floor, and a billed order is not one of them — so the tap would have started a fresh order on a table that was mid-payment.
- **Taking an order sends it to the kitchen.** The order screen had a **Save draft** button beside **Send to kitchen**, and a saved draft never reached a kitchen screen or a printer. There is now one button. Orders taken with no coverage still queue and go to the kitchen by themselves the moment the phone is back on signal. Matches the same change on the web app.

### Known gaps
- **Checkout needs a connection.** Nothing is queued: an order taken with no coverage is safe and still syncs, but it cannot be billed until the phone is back on signal. Every entry point says so rather than hanging.
- **Card (online) is web-only.** Charging a card through a payment gateway runs server-side on the web and has no RPC behind it, so the phone would record money it never collected. It offers cash, card (on a terminal), wallet and loyalty points. A settled bill that carries an online payment still shows it correctly.
- **A refund cannot be retried safely.** `refund_payment` takes no idempotency key, so after a lost connection the app asks you to check the bill's payments rather than offering to try again.
---

## [1.0.7] — 2026-08-07 · First build on a real phone

The first signed iOS build, distributed to internal testers through TestFlight. Nothing in the app changed to make that possible — the work was signing, versioning and one plist key. It matters because the offline queue, the whole reason this app exists over the mobile web, has until now only ever been exercised against an emulator that cannot go into airplane mode.

### Added
- iOS release signing. The project shipped with the pre-2019 `iPhone Developer` identity, which pins an archive to a development certificate and makes it undistributable; it is now `Apple Development`, with `CODE_SIGN_STYLE = Automatic` pinned on the Runner target so Xcode substitutes the distribution identity at export.
- `ITSAppUsesNonExemptEncryption = false` in `Info.plist`. The app reaches Supabase over HTTPS and nothing else, which is the standard exemption. Without the key, every upload stops in App Store Connect waiting for the question to be answered by hand before testers can install it.
- Store versioning starts here: `1.0.7+1`. Build numbers are burned on acceptance and never reused.

### Fixed
- **Printing was absent from the first archive.** `env.json` was missing `APP_URL`, which is what `Env.canPrint` gates on — so the build came out with the printing toggle disabled and no error anywhere to say why. A missing Supabase key throws at startup and names the command; this one is silent. Copy every key from `env.example.json`, and verify what reached the binary by decoding `DART_DEFINES` out of `ios/Flutter/Generated.xcconfig` rather than trusting the flag.

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

- The release build must be produced with `flutter build ipa --dart-define-from-file=env.json`. `Env` has no fallback and `Env.assertConfigured()` is a real `StateError`, not a stripped `assert`, so a build made without it installs and then dies before the first frame. Archiving from the Xcode GUI reads the dart-defines from a base64 blob in `ios/Flutter/Generated.xcconfig` left by whatever the last build happened to be — stale by construction, so that path is not used.

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
[1.0.7]: #107--2026-08-07--first-build-on-a-real-phone
