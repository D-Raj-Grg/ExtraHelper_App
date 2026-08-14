import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase/bill_repository.dart';
import '../../data/supabase/pos_repository.dart' show PosFailure;
import '../../data/supabase/supabase_providers.dart';
import '../../data/sync/sync_providers.dart';
import '../tenant/tenant_providers.dart';
import 'bill_models.dart';
import 'pos_providers.dart';

/// The checkout repository for the active restaurant.
final billRepoProvider = Provider<BillRepository?>((ref) {
  final tenant = ref.watch(activeTenantProvider);
  if (tenant == null) return null;
  return ref.watch(billRepositoryProvider(tenant.tenantId));
});

/// Discount the bill, or one of its lines.
final canDiscountProvider = Provider<bool>(
  (ref) =>
      ref.watch(isManagerProvider) &&
      ref.watch(hasPermissionProvider('order.discount')),
);

/// Void a line off a bill.
final canVoidLineProvider = Provider<bool>(
  (ref) =>
      ref.watch(isManagerProvider) &&
      ref.watch(hasPermissionProvider('order.void')),
);

/// Give money back.
final canRefundProvider = Provider<bool>(
  (ref) =>
      ref.watch(isManagerProvider) &&
      ref.watch(hasPermissionProvider('payment.refund')),
);

/// Extra charges and a complimentary bill, on the other hand, are gated on the
/// **key alone** server-side — `add_bill_charge`, `remove_bill_charge` and
/// `set_bill_complimentary` check `has_permission` and no role. Kept separate
/// from [canDiscountProvider] so the sheet offers exactly what will work.
final canChargeProvider = Provider<bool>(
  (ref) => ref.watch(hasPermissionProvider('order.discount')),
);

/// The message shown wherever checkout needs a connection and hasn't got one.
///
/// One string, one place: a waiter who meets this on the board and again on the
/// bill screen should be told the same thing both times.
const offlineCheckoutMessage =
    'No coverage — checkout needs a connection. The order is safe; settle it '
    "when you're back.";

/// One bill, whole, refetched after every change.
///
/// **Not cached and never written to [posCacheProvider].** Everywhere else in
/// this app stale beats absent; here it is the other way round. A total from
/// ten minutes ago is a figure a guest can be charged on, and another terminal
/// may have discounted it since.
///
/// **Auto-disposed on purpose.** A plain family keeps every instance alive for
/// the life of the container, which would mean two things this class exists to
/// prevent: each bill opened during a shift leaves its realtime channel and
/// debounce timer subscribed forever, and re-entering a bill re-shows the
/// cached `AsyncData` without re-running [build] — so a cashier could be quoted
/// a total from earlier in the service. Disposing on the way out makes "never
/// cached" true rather than merely intended.
class BillSnapshotNotifier
    extends AutoDisposeFamilyAsyncNotifier<BillSnapshot, String> {
  String get _billId => arg;

  RealtimeChannel? _channel;
  Timer? _debounce;

  @override
  Future<BillSnapshot> build(String billId) async {
    final repo = ref.watch(billRepoProvider);
    if (repo == null) {
      throw const PosFailure('No restaurant selected.');
    }

    // Say it, don't spin. With no coverage the HTTP call sits on a long
    // timeout, and a spinner that never resolves reads as a broken app.
    if (!await ref.read(connectivityProvider).isOnline()) {
      throw const PosFailure(offlineCheckoutMessage);
    }

    _subscribe(billId);
    ref.onDispose(() {
      _debounce?.cancel();
      final channel = _channel;
      _channel = null;
      if (channel != null) unawaited(channel.unsubscribe());
    });

    return repo.snapshot(billId);
  }

  /// Keep this bill honest while two people are looking at it.
  ///
  /// The counter and the phone can hold the same bill open, and a payment taken
  /// at one must not leave the other still offering to take it. A scoped,
  /// debounced refetch rather than merging rows in place: the totals are the
  /// server's, and there is no correct way to recompute them here.
  void _subscribe(String billId) {
    final client = ref.read(supabaseProvider);
    // Without the JWT on the socket, RLS drops every event and the screen
    // merely looks "not live" — the same trap the tables board documents.
    final token = client.auth.currentSession?.accessToken;
    if (token != null) client.realtime.setAuth(token);

    _channel = client
        .channel('bill_$billId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'bills',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: billId,
          ),
          callback: (_) => _scheduleRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'payments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'bill_id',
            value: billId,
          ),
          callback: (_) => _scheduleRefresh(),
        )
        .subscribe();
  }

  void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), refresh);
  }

  /// Re-read from the server.
  ///
  /// A failed refresh never replaces a good bill with an error — the cashier is
  /// mid-payment and the figures on screen are still the ones the server last
  /// agreed to.
  Future<void> refresh() async {
    final repo = ref.read(billRepoProvider);
    if (repo == null) return;
    final wasPaid = state.valueOrNull?.bill.isPaid ?? false;
    try {
      final next = await repo.snapshot(_billId);
      state = AsyncData(next);
      if (next.bill.isPaid && !wasPaid) _onSettled();
    } catch (e, st) {
      if (state.valueOrNull != null) return;
      state = AsyncError(e, st);
    }
  }

  /// Run a money write, then re-read.
  ///
  /// **Every lever on the checkout screen goes through this**, so "the server
  /// recomputed it" stays the only source of a total. A screen that adjusted a
  /// figure locally and refreshed later would show, for however many hundred
  /// milliseconds, a number nobody has agreed to.
  ///
  /// Failures are rethrown for the screen to show. The refresh still runs after
  /// one — a write that landed and then failed to answer must not leave a stale
  /// figure on screen — but it is **not awaited on that path**: the connection
  /// that just failed is the one the re-read would use, and making the cashier
  /// watch a spinner for a full HTTP timeout before they can read "we didn't get
  /// an answer" is the exact shape `CLAUDE.md` warns about.
  Future<void> mutate(Future<void> Function(BillRepository repo) write) async {
    final repo = ref.read(billRepoProvider);
    if (repo == null) return;
    try {
      await write(repo);
    } catch (_) {
      unawaited(refresh());
      rethrow;
    }
    await refresh();
  }

  /// The bill just closed. Everything that was showing it as owed is now wrong.
  ///
  /// `record_payment` closes the order and frees the table on the last share,
  /// so the board is stale the instant this happens — and the Bills tab would
  /// otherwise keep offering a bill that has nothing left to take.
  void _onSettled() {
    ref
      ..invalidate(activeOrdersProvider)
      ..invalidate(openBillsProvider)
      ..invalidate(filteredBillsProvider)
      ..invalidate(completedOrdersProvider);
    unawaited(ref.read(tablesProvider.notifier).refresh());
  }
}

final billSnapshotProvider = AsyncNotifierProvider.autoDispose
    .family<BillSnapshotNotifier, BillSnapshot, String>(
      BillSnapshotNotifier.new,
    );

/// Bills still owed money. The only route back to an order that has been billed.
final openBillsProvider = FutureProvider.autoDispose<List<OpenBillRow>>((
  ref,
) async {
  final repo = ref.watch(billRepoProvider);
  if (repo == null) return const [];
  if (!await ref.read(connectivityProvider).isOnline()) {
    throw const PosFailure(offlineCheckoutMessage);
  }
  return repo.openBills();
});

/// What the Bills tab is listing.
///
/// A bill settled five minutes ago used to be unreachable from the phone: the
/// tab only ever showed what was owed, so the moment a cashier took the last
/// rupee the receipt went out of reach — which is exactly when someone asks for
/// a copy of it.
enum BillFilter {
  /// Every bill with money outstanding, however old. Not date-bound: a debt
  /// does not stop being one at midnight.
  owed(label: 'Owed', statuses: ['open', 'partial'], dayBound: false),

  /// Settled today. Older ones are a reports question.
  paid(label: 'Paid', statuses: ['paid'], dayBound: true),

  /// Written off today.
  voided(label: 'Void', statuses: ['void'], dayBound: true),

  /// Everything from today, whatever became of it.
  today(
    label: 'All today',
    statuses: ['open', 'partial', 'paid', 'void'],
    dayBound: true,
  );

  const BillFilter({
    required this.label,
    required this.statuses,
    required this.dayBound,
  });

  final String label;
  final List<String> statuses;

  /// Whether the list is capped to the trading day that has just been served.
  final bool dayBound;
}

final billFilterProvider = NotifierProvider<BillFilterNotifier, BillFilter>(
  BillFilterNotifier.new,
);

class BillFilterNotifier extends Notifier<BillFilter> {
  @override
  BillFilter build() => BillFilter.owed;

  void select(BillFilter filter) => state = filter;
}

/// The Bills tab's list for the chosen filter.
///
/// Not cached, like everything else that quotes money: a total from ten minutes
/// ago is a figure a guest could be charged on, and another terminal may have
/// discounted it since.
final filteredBillsProvider = FutureProvider.autoDispose<List<OpenBillRow>>((
  ref,
) async {
  final repo = ref.watch(billRepoProvider);
  final posRepo = ref.watch(posRepoProvider);
  // Watched **before** the offline bail-out, and that ordering is the point: a
  // `watch` after a throw never registers, so a chip tapped while the list is
  // showing the offline error would move the highlight and re-run nothing. The
  // tab would sit on a stale error until a pull-to-refresh.
  final filter = ref.watch(billFilterProvider);

  if (repo == null) return const [];
  if (!await ref.read(connectivityProvider).isOnline()) {
    throw const PosFailure(offlineCheckoutMessage);
  }

  // The day boundary is the server's — the same `tenant_day_start` the
  // Completed tab uses, so the two tabs never disagree about when today began.
  final since = filter.dayBound ? await posRepo?.tenantDayStart() : null;
  return repo.bills(
    statuses: filter.statuses,
    since: since,
    // Settled lists are bound on when the bill was *settled*, not opened — see
    // `BillRepository.bills`. "All today" includes owed bills, which have no
    // settlement to speak of, so it stays on when they were opened.
    sinceColumn: filter == BillFilter.paid || filter == BillFilter.voided
        ? 'updated_at'
        : 'created_at',
  );
});
