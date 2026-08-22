import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pos_repository.dart' show PosFailure, PosTransientFailure;
import 'supabase_providers.dart';

/// When the trading day may start, and nothing else.
///
/// The same seven options the web's Settings page offers, because the value is
/// validated against that list on the server side too — the phone must not be
/// able to set a cutoff the browser would refuse. The column's own
/// `check (day_cutoff_minutes >= 0 and < 720)` is the backstop.
const dayCutoffOptions = <int, String>{
  0: 'Midnight',
  60: '1:00 am',
  120: '2:00 am',
  180: '3:00 am',
  240: '4:00 am',
  300: '5:00 am',
  360: '6:00 am',
};

/// Tenant settings the app is allowed to change.
///
/// Deliberately narrow. Currency, tax and receipt branding are set up once on
/// the web and have no business being edited one-handed mid-service; the day
/// cutoff is here because it is the thing that decides which day the report in
/// front of you covers.
class SettingsRepository {
  const SettingsRepository(this._client, this._tenantId);

  final SupabaseClient _client;
  final String _tenantId;

  /// Move the boundary the trading day turns over on.
  ///
  /// A plain table update, not an RPC, because `tenant_settings_owner_write`
  /// already restricts writes to owners and managers — the same set the UI
  /// gates on. RLS is the boundary here, exactly as it is for every other
  /// write in this app.
  ///
  /// **Retroactive.** Every past day re-buckets, on both clients and on the
  /// POS, because `tenant_day_start` reads this column. The caller confirms
  /// before calling.
  Future<void> setDayCutoff(int minutes) async {
    if (!dayCutoffOptions.containsKey(minutes)) {
      throw const PosFailure('That is not a day-start time we offer.');
    }
    try {
      // `.select()` so a blocked write is an error rather than a lie. RLS does
      // not raise on an update that matches nothing — it silently affects zero
      // rows — so without reading the result back, someone without the role
      // would be told the day had moved when it had not.
      final changed = await _client
          .from('tenant_settings')
          .update({'day_cutoff_minutes': minutes})
          .eq('tenant_id', _tenantId)
          .select('tenant_id');

      if (changed.isEmpty) {
        throw const PosFailure(
          'Only an owner or manager can change when the day starts.',
        );
      }
    } on PostgrestException catch (e) {
      throw PosFailure(e.message);
    } on PosFailure {
      rethrow;
    } catch (_) {
      throw const PosTransientFailure("Couldn't save that just now.");
    }
  }
}

final settingsRepositoryProvider = Provider.family<SettingsRepository, String>(
  (ref, tenantId) => SettingsRepository(ref.watch(supabaseProvider), tenantId),
);
