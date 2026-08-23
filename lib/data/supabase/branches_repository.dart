import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pos_repository.dart' show PosFailure, PosTransientFailure;
import 'supabase_providers.dart';

/// One trading location.
///
/// The default branch is the one every existing order, printer and station
/// points at when it names no branch of its own, which is why it cannot be
/// renamed away or deleted.
class Branch {
  const Branch({
    required this.id,
    required this.name,
    this.address,
    this.isDefault = false,
  });

  final String id;
  final String name;
  final String? address;
  final bool isDefault;

  static Branch fromJson(Map<String, dynamic> json) => Branch(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    address: (json['address'] as String?)?.trim().isEmpty ?? true
        ? null
        : (json['address'] as String).trim(),
    isDefault: json['is_default'] == true,
  );
}

/// Branches, as plain table work.
///
/// `branches_manage` is `for all` to owners and managers, so RLS is the whole
/// gate — but it fails *silently*, matching zero rows rather than raising.
/// Every write here reads its result back for that reason.
class BranchesRepository {
  const BranchesRepository(this._client, this._tenantId);

  final SupabaseClient _client;
  final String _tenantId;

  Future<List<Branch>> list() async {
    try {
      final rows = await _client
          .from('branches')
          .select('id, name, address, is_default')
          .eq('tenant_id', _tenantId)
          // Default first: it is the one everything else falls back to, so it
          // belongs at the top of the list rather than alphabetised into it.
          .order('is_default', ascending: false)
          .order('name');
      return rows.map(Branch.fromJson).toList();
    } on PostgrestException catch (e) {
      throw PosFailure(e.message);
    } catch (_) {
      throw const PosTransientFailure("Couldn't load your branches.");
    }
  }

  Future<String> create({required String name, String? address}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw const PosFailure('Give the branch a name.');
    try {
      final rows = await _client
          .from('branches')
          .insert({
            'tenant_id': _tenantId,
            'name': trimmed,
            'address': _address(address),
          })
          .select('id');
      if (rows.isEmpty) throw _refused;
      return rows.first['id'] as String;
    } on PostgrestException catch (e) {
      throw PosFailure(e.message);
    } on PosFailure {
      rethrow;
    } catch (_) {
      throw const PosTransientFailure("Couldn't add that branch just now.");
    }
  }

  Future<void> update({
    required String id,
    required String name,
    String? address,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw const PosFailure('Give the branch a name.');
    try {
      final rows = await _client
          .from('branches')
          .update({'name': trimmed, 'address': _address(address)})
          .eq('id', id)
          .eq('tenant_id', _tenantId)
          .select('id');
      if (rows.isEmpty) throw _refused;
    } on PostgrestException catch (e) {
      throw PosFailure(e.message);
    } on PosFailure {
      rethrow;
    } catch (_) {
      throw const PosTransientFailure("Couldn't save that branch just now.");
    }
  }

  /// Refused client-side for the default branch as well as server-side: the
  /// screen never offers the control, and this is the backstop if it ever does.
  Future<void> remove(Branch branch) async {
    if (branch.isDefault) {
      throw const PosFailure(
        "The default branch can't be deleted — everything without a branch of "
        'its own belongs to it.',
      );
    }
    try {
      final rows = await _client
          .from('branches')
          .delete()
          .eq('id', branch.id)
          .eq('tenant_id', _tenantId)
          .select('id');
      if (rows.isEmpty) throw _refused;
    } on PostgrestException catch (e) {
      throw PosFailure(e.message);
    } on PosFailure {
      rethrow;
    } catch (_) {
      throw const PosTransientFailure("Couldn't delete that branch just now.");
    }
  }

  static const _refused = PosFailure(
    'Only an owner or manager can change branches.',
  );

  static String? _address(String? raw) {
    final trimmed = raw?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}

final branchesRepositoryProvider = Provider.family<BranchesRepository, String>(
  (ref, tenantId) => BranchesRepository(ref.watch(supabaseProvider), tenantId),
);
