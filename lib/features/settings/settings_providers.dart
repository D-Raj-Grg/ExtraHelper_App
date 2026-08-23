import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/print/print_models.dart';
import '../../data/print/print_repository.dart';
import '../../data/supabase/branches_repository.dart';
import '../../data/supabase/danger_repository.dart';
import '../../data/supabase/profile_repository.dart';
import '../../data/supabase/settings_repository.dart';
import '../tenant/tenant_providers.dart';

/// Reads behind the settings screens.
///
/// All `autoDispose`: settings are looked at rarely and changed rarely, and a
/// cached copy that outlives the screen is a copy that goes stale while someone
/// edits the same restaurant on the web.
final tenantSettingsProvider = FutureProvider.autoDispose<TenantSettings?>((
  ref,
) async {
  final tenant = ref.watch(activeTenantProvider);
  if (tenant == null) return null;
  return ref.watch(settingsRepositoryProvider(tenant.tenantId)).load();
});

final branchesProvider = FutureProvider.autoDispose<List<Branch>>((ref) async {
  final tenant = ref.watch(activeTenantProvider);
  if (tenant == null) return const [];
  return ref.watch(branchesRepositoryProvider(tenant.tenantId)).list();
});

/// The printer registry with its document assignments. Read-only on mobile:
/// `save_printer` and `delete_printer` exist, but a phone has no way to
/// discover a USB id or a CUPS queue name, and half a registry editor is worse
/// than none.
final printerRegistryProvider =
    FutureProvider.autoDispose<List<PrinterRegistryRow>>((ref) async {
      final tenant = ref.watch(activeTenantProvider);
      if (tenant == null) return const [];
      return ref.watch(printRepositoryProvider(tenant.tenantId)).registry();
    });

final printerLimitProvider = FutureProvider.autoDispose<int?>((ref) async {
  final tenant = ref.watch(activeTenantProvider);
  if (tenant == null) return null;
  return ref.watch(printRepositoryProvider(tenant.tenantId)).printerLimit();
});

/// Plan, usage and the members ownership can be handed to. One query path
/// serves both the plan screen and the dangerous area, so the two can never
/// disagree about what the restaurant is using.
final dangerDataProvider = FutureProvider.autoDispose<DangerData?>((ref) async {
  final tenant = ref.watch(activeTenantProvider);
  if (tenant == null) return null;
  return ref.watch(dangerRepositoryProvider(tenant.tenantId)).load();
});

/// Not tenant-scoped — a profile follows the person between restaurants.
final myProfileProvider = FutureProvider.autoDispose<Profile?>(
  (ref) => ref.watch(profileRepositoryProvider).load(),
);
