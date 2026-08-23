import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pos_repository.dart' show PosFailure, PosTransientFailure;
import 'supabase_providers.dart';

/// What the restaurant is using, against what its plan allows.
///
/// A null limit means no ceiling — either the plan does not name that one, or
/// the restaurant is on trial, which unlocks everything.
class ResourceUsage {
  const ResourceUsage({
    this.customers = 0,
    this.tables = 0,
    this.staff = 0,
    this.menuItems = 0,
    this.customersLimit,
    this.tablesLimit,
    this.staffLimit,
    this.menuItemsLimit,
  });

  final int customers;
  final int tables;
  final int staff;
  final int menuItems;
  final int? customersLimit;
  final int? tablesLimit;
  final int? staffLimit;
  final int? menuItemsLimit;
}

/// Someone ownership could be handed to.
class TransferMember {
  const TransferMember({
    required this.userId,
    required this.email,
    this.roleName,
  });

  final String userId;
  final String email;
  final String? roleName;
}

class DangerData {
  const DangerData({
    required this.planLabel,
    required this.usage,
    required this.members,
    this.deletionScheduledAt,
  });

  final String planLabel;
  final ResourceUsage usage;
  final List<TransferMember> members;

  /// Non-null while a deletion is pending. Seven days' grace, after which
  /// `purge_scheduled_tenants` takes it for good.
  final DateTime? deletionScheduledAt;
}

/// The owner-only surface: plan, usage, and the three ways to end things.
///
/// Every write is an RPC that re-checks `has_tenant_role(_tenant, 'owner')`
/// inside its own body, so the role check on the screen is a courtesy — this
/// cannot be talked past by a client that lies about who it is.
class DangerRepository {
  const DangerRepository(this._client, this._tenantId);

  final SupabaseClient _client;
  final String _tenantId;

  Future<DangerData> load() async {
    try {
      // Head counts, the subscription, the member list and the deletion clock,
      // all at once — the screen has nothing to show until it has all of them.
      final results = await Future.wait<dynamic>([
        _count('customers'),
        _count('restaurant_tables'),
        _count('user_tenants', activeOnly: true),
        _count('menu_items'),
        _client
            .from('subscriptions')
            .select('status, plan:plans(name, limits)')
            .eq('tenant_id', _tenantId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle(),
        _client.rpc<dynamic>(
          'list_tenant_members',
          params: {'_tenant': _tenantId},
        ),
        _client
            .from('tenants')
            .select('deletion_scheduled_at')
            .eq('id', _tenantId)
            .maybeSingle(),
      ]);

      final customers = results[0] as int;
      final tables = results[1] as int;
      final staff = results[2] as int;
      final menuItems = results[3] as int;
      final sub = results[4] as Map<String, dynamic>?;
      final memberRows = results[5];
      final tenantRow = results[6] as Map<String, dynamic>?;

      final plan = sub?['plan'] is Map
          ? Map<String, dynamic>.from(sub!['plan'] as Map)
          : null;
      // No subscription row at all also counts as a trial: that is what a
      // restaurant looks like before it has ever paid.
      final isTrial = sub == null || sub['status'] == 'trialing';
      final planName = plan?['name'] as String?;
      final planLabel = planName == null
          ? 'Trial'
          : (isTrial ? '$planName Trial' : planName);

      // A trial unlocks everything, so the counts are shown with no ceiling.
      final limits = isTrial || plan?['limits'] is! Map
          ? const <String, dynamic>{}
          : Map<String, dynamic>.from(plan!['limits'] as Map);
      int? cap(String key) => switch (limits[key]) {
        int n => n,
        num n => n.round(),
        _ => null,
      };

      final members = <TransferMember>[];
      if (memberRows is List) {
        for (final raw in memberRows.whereType<Map<String, dynamic>>()) {
          final row = Map<String, dynamic>.from(raw);
          final userId = row['user_id'] as String?;
          // Pending invites have no user to hand a restaurant to, and the
          // current owner is not a candidate to become the owner.
          if (userId == null) continue;
          if (row['status'] != 'active') continue;
          if (row['base_role'] == 'owner') continue;
          members.add(
            TransferMember(
              userId: userId,
              email: row['email'] as String? ?? '',
              roleName: row['role_name'] as String?,
            ),
          );
        }
      }

      return DangerData(
        planLabel: planLabel,
        usage: ResourceUsage(
          customers: customers,
          tables: tables,
          staff: staff,
          menuItems: menuItems,
          customersLimit: cap('customers'),
          tablesLimit: cap('tables'),
          staffLimit: cap('staff'),
          menuItemsLimit: cap('menu_items'),
        ),
        members: members,
        deletionScheduledAt: _time(tenantRow?['deletion_scheduled_at']),
      );
    } on PostgrestException catch (e) {
      throw PosFailure(e.message);
    } catch (_) {
      throw const PosTransientFailure("Couldn't load your plan just now.");
    }
  }

  /// Wipe the named domains. `everything` is a sentinel the server expands.
  Future<void> resetTenant(List<String> domains) async {
    if (domains.isEmpty) {
      throw const PosFailure('Choose what to reset.');
    }
    await _call('reset_tenant', {'_tenant': _tenantId, '_domains': domains});
  }

  /// Hand the restaurant over. The caller becomes a manager on success, so the
  /// screen they are standing on stops being theirs.
  Future<void> transferOwnership(String toUserId) =>
      _call('transfer_tenant_ownership', {
        '_tenant': _tenantId,
        '_to_user': toUserId,
      });

  /// Start the seven-day clock. Returns when it runs out, if the server says.
  Future<DateTime?> requestDeletion() async {
    final result = await _call('request_tenant_deletion', {
      '_tenant': _tenantId,
    });
    return _time(result);
  }

  Future<void> cancelDeletion() =>
      _call('cancel_tenant_deletion', {'_tenant': _tenantId});

  Future<dynamic> _call(String fn, Map<String, dynamic> params) async {
    try {
      return await _client.rpc<dynamic>(fn, params: params);
    } on PostgrestException catch (e) {
      throw PosFailure(
        e.message.contains('not authorized') || e.message.contains('owner')
            ? 'Only the owner can do this.'
            : e.message,
      );
    } catch (_) {
      throw const PosTransientFailure(
        "That didn't go through. Check the restaurant before trying again.",
      );
    }
  }

  Future<int> _count(String table, {bool activeOnly = false}) async {
    var query = _client
        .from(table)
        .select('*')
        .eq('tenant_id', _tenantId);
    if (activeOnly) query = query.eq('status', 'active');
    final response = await query.count(CountOption.exact);
    return response.count;
  }

  static DateTime? _time(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toLocal();
  }
}

final dangerRepositoryProvider = Provider.family<DangerRepository, String>(
  (ref, tenantId) => DangerRepository(ref.watch(supabaseProvider), tenantId),
);
