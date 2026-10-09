import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/supabase/coupon_batches_repository.dart';
import '../../data/supabase/coupons_repository.dart';
import '../../data/supabase/flyer_designs_repository.dart';
import '../tenant/tenant_providers.dart';

/// Network-only: a usage count is a promise to a guest, and a stale one is a
/// wrong one. Keyed off the tenant *id*, not the Membership, as loyalty does.
final couponsProvider = FutureProvider.autoDispose<List<Coupon>>((ref) async {
  final tenantId = ref.watch(activeTenantProvider.select((m) => m?.tenantId));
  if (tenantId == null) throw StateError('No restaurant selected.');
  return ref.watch(couponsRepositoryProvider(tenantId)).list();
});

/// The strip above the list. A failure just hides the strip — the list
/// below is the screen's job and has its own retry.
final couponStatsProvider = FutureProvider.autoDispose<CouponStats>((
  ref,
) async {
  final tenantId = ref.watch(activeTenantProvider.select((m) => m?.tenantId));
  if (tenantId == null) throw StateError('No restaurant selected.');
  return ref.watch(couponBatchesRepositoryProvider(tenantId)).stats();
});

/// Flyer print runs, newest first. Network-only, like the coupons.
final couponBatchesProvider = FutureProvider.autoDispose<List<CouponBatch>>((
  ref,
) async {
  final tenantId = ref.watch(activeTenantProvider.select((m) => m?.tenantId));
  if (tenantId == null) throw StateError('No restaurant selected.');
  return ref.watch(couponBatchesRepositoryProvider(tenantId)).list();
});

/// The codes of one run, keyed by the run's id.
final batchCodesProvider = FutureProvider.autoDispose
    .family<List<BatchCode>, String>((ref, batchId) async {
      final tenantId = ref.watch(
        activeTenantProvider.select((m) => m?.tenantId),
      );
      if (tenantId == null) throw StateError('No restaurant selected.');
      return ref
          .watch(couponBatchesRepositoryProvider(tenantId))
          .codes(batchId);
    });

/// Saved flyer designs, newest first.
final flyerDesignsProvider = FutureProvider.autoDispose<List<FlyerDesign>>((
  ref,
) async {
  final tenantId = ref.watch(activeTenantProvider.select((m) => m?.tenantId));
  if (tenantId == null) throw StateError('No restaurant selected.');
  return ref.watch(flyerDesignsRepositoryProvider(tenantId)).list();
});
