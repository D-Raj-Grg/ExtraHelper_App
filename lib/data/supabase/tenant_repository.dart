import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'settings_repository.dart' show TaxRule;
import 'supabase_providers.dart';

/// A restaurant the signed-in user belongs to, with the settings every money
/// and time rendering needs.
///
/// Currency and timezone come from `tenant_settings` — never hardcoded
/// (rule 2). The defaults below apply only when a tenant has no settings row.
class Membership {
  const Membership({
    required this.tenantId,
    required this.name,
    required this.slug,
    required this.role,
    required this.currency,
    required this.timezone,
  });

  final String tenantId;
  final String name;
  final String slug;
  final String role;
  final String currency;
  final String timezone;

  static Membership fromRow(Map<String, dynamic> row) {
    final tenant = row['tenants'] as Map<String, dynamic>?;
    final settingsRaw = tenant?['tenant_settings'];
    final settings = switch (settingsRaw) {
      List() when settingsRaw.isNotEmpty =>
        settingsRaw.first as Map<String, dynamic>,
      Map<String, dynamic>() => settingsRaw,
      _ => null,
    };

    return Membership(
      tenantId: row['tenant_id'] as String,
      name: (tenant?['name'] as String?) ?? '',
      slug: (tenant?['slug'] as String?) ?? '',
      role: (row['role'] as String?) ?? 'waiter',
      currency: (settings?['currency'] as String?) ?? 'USD',
      timezone: (settings?['timezone'] as String?) ?? 'UTC',
    );
  }
}

/// A membership awaiting owner approval. Grants no access — it exists so the
/// app can say "waiting for approval" instead of "no access", which are
/// different problems with different fixes.
class PendingMembership {
  const PendingMembership({required this.tenantId, required this.name});

  final String tenantId;
  final String name;
}

/// Result of redeeming a join code.
class JoinResult {
  const JoinResult({
    required this.tenantName,
    required this.status,
    required this.alreadyMember,
  });

  final String tenantName;

  /// `pending` until an owner approves, `active` if the user was already in.
  final String status;

  final bool alreadyMember;
}

class TenantRepository {
  const TenantRepository(this._client);

  final SupabaseClient _client;

  static const _select =
      'role, tenant_id, tenants(name, slug, tenant_settings(currency, timezone))';

  /// Restaurants the user can actually work in.
  ///
  /// **`status = 'active'` is load-bearing**: a pending membership is a request,
  /// not access. Matching the web's `fetchMemberships`, which filters the same
  /// way — and ordering by tenant_id so "the first one" is stable rather than
  /// whatever Postgres returned this time.
  Future<List<Membership>> activeMemberships() async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];

    final rows = await _client
        .from('user_tenants')
        .select(_select)
        .eq('user_id', user.id)
        .eq('status', 'active')
        .order('tenant_id', ascending: true);

    return rows.map((r) => Membership.fromRow(r)).toList();
  }

  /// Redeemed or invited, not yet approved.
  Future<List<PendingMembership>> pendingMemberships() async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];

    final rows = await _client
        .from('user_tenants')
        .select('tenant_id, tenants(name)')
        .eq('user_id', user.id)
        .eq('status', 'pending');

    return rows.map((r) {
      final tenant = r['tenants'] as Map<String, dynamic>?;
      return PendingMembership(
        tenantId: r['tenant_id'] as String,
        name: (tenant?['name'] as String?) ?? 'this restaurant',
      );
    }).toList();
  }

  /// Redeem a join code → a **pending** membership an owner then approves.
  ///
  /// The RPC is `security definer` and does the validation (active, unexpired,
  /// not already a member); this only translates its errors into something a
  /// waiter standing in a restaurant can act on.
  Future<JoinResult> redeemJoinCode(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) throw const TenantFailure('Enter the code.');

    try {
      final data =
          await _client.rpc('redeem_join_code', params: {'_code': trimmed})
              as Map<String, dynamic>;
      return JoinResult(
        tenantName: (data['name'] as String?) ?? 'the restaurant',
        status: (data['status'] as String?) ?? 'pending',
        alreadyMember: (data['already'] as bool?) ?? false,
      );
    } on PostgrestException catch (e) {
      // 22023 is what the RPC raises for a bad or expired code.
      if (e.code == '22023' || e.message.contains('invalid or expired')) {
        throw const TenantFailure(
          "That code isn't valid any more. Ask your manager for a new one.",
        );
      }
      throw TenantFailure(e.message);
    } catch (_) {
      throw const TenantFailure(
        "Couldn't reach the server. Check your connection and try again.",
      );
    }
  }

  /// Create a restaurant and make the caller its owner.
  ///
  /// `provision_tenant` is `security definer` and does all of it in one call:
  /// the tenant, its settings row, a default `Main` branch, the owner
  /// membership and the seeded system roles. Authenticated users cannot INSERT
  /// into `tenants` directly under RLS, which is exactly why the RPC exists —
  /// do not try to assemble this client-side.
  ///
  /// Tax rules and service charge are applied **after**, as a plain update, the
  /// same way `app/onboarding/actions.ts` does it: they are not RPC arguments,
  /// and by this point the owner membership exists so RLS permits the write.
  /// A failure there leaves a usable restaurant with default tax settings
  /// rather than no restaurant at all, so it is reported without discarding the
  /// tenant that was created.
  ///
  /// Returns the new tenant's id.
  Future<String> provisionTenant({
    required String name,
    required String currency,
    required String timezone,
    double serviceCharge = 0,
    List<TaxRule> taxRules = const [],
    bool forceNew = false,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const TenantFailure('Restaurant name is required.');
    }

    final String tenantId;
    try {
      tenantId =
          await _client.rpc(
                'provision_tenant',
                params: {
                  '_name': trimmed,
                  '_currency': currency,
                  '_timezone': timezone,
                  '_force_new': forceNew,
                },
              )
              as String;
    } on PostgrestException catch (e) {
      throw TenantFailure(switch (e.code) {
        '22023' => 'Restaurant name is required.',
        '28000' => "You're signed out — sign in again.",
        _ => e.message,
      });
    } catch (_) {
      throw const TenantFailure(
        "Couldn't reach the server. Check your connection and try again.",
      );
    }

    if (taxRules.isNotEmpty || serviceCharge > 0) {
      try {
        await _client
            .from('tenant_settings')
            .update({
              'tax_rules': taxRules.map((r) => r.toJson()).toList(),
              'service_charge': serviceCharge,
            })
            .eq('tenant_id', tenantId);
      } catch (_) {
        throw TenantFailure(
          'Created "$trimmed", but the tax and service charge settings did not '
          'save. Set them in Settings.',
        );
      }
    }

    return tenantId;
  }

  /// Granular permission keys for this tenant.
  ///
  /// Always from the server — never derived from a role string held in the app,
  /// which the user could not change but the app could get wrong. Falls back to
  /// the base role server-side, so this is authoritative either way.
  Future<Set<String>> permissions(String tenantId) async {
    final data =
        await _client.rpc('get_my_permissions', params: {'_tenant': tenantId})
            as List<dynamic>;
    return data.map((e) => e as String).toSet();
  }
}

class TenantFailure implements Exception {
  const TenantFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

final tenantRepositoryProvider = Provider<TenantRepository>(
  (ref) => TenantRepository(ref.watch(supabaseProvider)),
);
