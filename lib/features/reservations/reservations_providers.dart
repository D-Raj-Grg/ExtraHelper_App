import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/supabase/reservations_repository.dart';
import '../tenant/tenant_providers.dart';

/// Today's and upcoming bookings, soonest first. Network-only.
final reservationsProvider = FutureProvider.autoDispose<List<Reservation>>((
  ref,
) async {
  final tenantId = ref.watch(activeTenantProvider.select((m) => m?.tenantId));
  if (tenantId == null) throw StateError('No restaurant selected.');
  final now = DateTime.now();
  final startOfToday = DateTime(now.year, now.month, now.day);
  return ref
      .watch(reservationsRepositoryProvider(tenantId))
      .list(from: startOfToday);
});
