import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/supabase/day_report_repository.dart';
import '../tenant/tenant_providers.dart';

/// Move a `YYYY-MM-DD` date string by whole days.
///
/// Pure calendar arithmetic in UTC, deliberately: a date string names a *day*,
/// not an instant, so no timezone belongs anywhere near it. Building a local
/// `DateTime` here would drag the device's zone into a boundary the server
/// owns — the mistake this whole feature is shaped to avoid. `DateTime.utc`
/// normalises overflow, so Aug 31 + 1 and Dec 31 + 1 are free.
///
/// The web does the same thing the same way (`day-report.ts`), so the two
/// clients page through days identically.
String shiftDay(String ymd, int days) {
  final parts = ymd.split('-');
  if (parts.length != 3) return ymd;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return ymd;

  String p(int n) => n.toString().padLeft(2, '0');

  final at = DateTime.utc(y, m, d + days);
  return '${at.year.toString().padLeft(4, '0')}-${p(at.month)}-${p(at.day)}';
}

/// Which day the sheet is showing, and which day is "today".
///
/// Both matter, and the second is the awkward one: **the phone cannot work out
/// what today is.** `intl` has no IANA database and the trading day can start
/// at 4am, so the only authority is the server. Asking for a null day gets the
/// current business day back in the payload, and that is how [knownToday] gets
/// filled in.
class DayCursorState {
  const DayCursorState({this.selected, this.knownToday});

  /// `YYYY-MM-DD`, or null meaning **today** — which is the only way to ask
  /// for today, since we cannot name it ourselves until the server has.
  final String? selected;

  /// Today's business day, once a payload has told us. Null until then.
  final String? knownToday;

  bool get isToday => selected == null || selected == knownToday;

  /// Whether there is an earlier day to move to.
  ///
  /// False until a payload has landed: with no day named and no today known
  /// there is nothing to subtract from, and a chevron that does nothing when
  /// pressed is worse than one that is visibly not ready yet.
  bool get canGoBack => selected != null || knownToday != null;

  /// Whether there is a later day to move to.
  ///
  /// Unknown today ⇒ **false**, which fails safe: the worst case is a disabled
  /// chevron and a "Today" button that still works, rather than paging into
  /// tomorrow and rendering a day that has not happened.
  bool get canGoForward {
    final at = selected;
    final today = knownToday;
    if (at == null || today == null) return false;
    return at.compareTo(today) < 0;
  }

  DayCursorState copyWith({String? selected, String? knownToday}) =>
      DayCursorState(
        selected: selected ?? this.selected,
        knownToday: knownToday ?? this.knownToday,
      );
}

class DayCursor extends Notifier<DayCursorState> {
  @override
  DayCursorState build() {
    // Switching restaurants resets to that restaurant's today — a day string
    // means nothing across tenants, whose trading days differ.
    ref.watch(activeTenantProvider);
    return const DayCursorState();
  }

  /// Record the day the server resolved as *today*. Called when a payload lands.
  ///
  /// Only a payload for a **null** request answers "what day is it".
  /// `DayReport.day` names the day the report covers, and the screen feeds every
  /// payload through here — so without this guard a past day's report would
  /// overwrite [DayCursorState.knownToday], collapse `canGoForward`, hide "Back
  /// to today", and strand the user on the day they stepped back to.
  ///
  /// It also drops a stale today-response that lands after a step back, since by
  /// then the cursor has already named a day.
  void rememberToday(String day) {
    if (state.selected != null) return; // Not an answer about today.
    if (day.isEmpty || state.knownToday == day) return;
    state = state.copyWith(knownToday: day);
  }

  void previous() {
    final at = state.selected ?? state.knownToday;
    if (at == null) return; // Nothing loaded yet; nothing to step back from.
    state = state.copyWith(selected: shiftDay(at, -1));
  }

  void next() {
    if (!state.canGoForward) return;
    state = state.copyWith(selected: shiftDay(state.selected!, 1));
  }

  /// Back to today — by clearing the selection, not by naming a date, so the
  /// server re-resolves it. A day boundary can pass while the app is open.
  void today() {
    state = DayCursorState(knownToday: state.knownToday);
  }
}

final dayCursorProvider = NotifierProvider<DayCursor, DayCursorState>(
  DayCursor.new,
);

/// The day-close sheet for the selected day.
///
/// **Network-only**, like the dashboard: this is the number a manager signs the
/// till off against, and a stale one is worse than an honest failure. The POS
/// is the surface that works offline.
final dayReportProvider = FutureProvider.autoDispose<DayReport>((ref) async {
  final tenant = ref.watch(activeTenantProvider);
  if (tenant == null) throw const DayReportForbidden();
  // `select`, not the whole cursor: recording today's date changes the state
  // object without changing which day is being asked for, and watching the
  // whole thing would invalidate this provider and fetch the same day twice
  // every time the screen opened.
  final day = ref.watch(dayCursorProvider.select((c) => c.selected));
  return ref
      .watch(dayReportRepositoryProvider(tenant.tenantId))
      .report(day: day);
});

/// The day's orders, over the window the report itself reported.
///
/// Depends on the report rather than computing bounds, so the ledger can never
/// describe a different day from the totals above it.
final dayOrdersProvider = FutureProvider.autoDispose<DayOrdersPage>((
  ref,
) async {
  final tenant = ref.watch(activeTenantProvider);
  if (tenant == null) return const DayOrdersPage(orders: [], truncated: false);
  final report = await ref.watch(dayReportProvider.future);
  return ref
      .watch(dayReportRepositoryProvider(tenant.tenantId))
      .orders(from: report.from, to: report.to);
});
