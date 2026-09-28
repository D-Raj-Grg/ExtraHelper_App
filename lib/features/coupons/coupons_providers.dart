import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/supabase/coupons_repository.dart';
import '../tenant/tenant_providers.dart';

/// Network-only: a usage count is a promise to a guest, and a stale one is a
/// wrong one. Keyed off the tenant *id*, not the Membership, as loyalty does.
final couponsProvider = FutureProvider.autoDispose<List<Coupon>>((ref) async {
  final tenantId = ref.watch(activeTenantProvider.select((m) => m?.tenantId));
  if (tenantId == null) throw StateError('No restaurant selected.');
  return ref.watch(couponsRepositoryProvider(tenantId)).list();
});
