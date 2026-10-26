import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pos_repository.dart' show PosFailure, PosTransientFailure;
import 'supabase_providers.dart';

/// The first thing wrong with a new table, as a sentence, or null.
String? validateTableDraft(String label, int capacity) {
  if (label.trim().isEmpty) return 'Give the table a label.';
  if (capacity < 1 || capacity > 50) return 'Seats are between 1 and 50.';
  return null;
}

/// Floors and tables: `create_floor`, `create_table`, `delete_table`.
class TablesAdminRepository {
  const TablesAdminRepository(this._client, this._tenantId);

  final SupabaseClient _client;
  final String _tenantId;

  Future<String> createFloor(String name) async {
    if (name.trim().isEmpty) throw const PosFailure('Give the floor a name.');
    final res = await _write('create_floor', {
      '_tenant': _tenantId,
      '_name': name.trim(),
    });
    return res is String ? res : '';
  }

  Future<String> createTable({
    required String label,
    required int capacity,
    String? floorId,
  }) async {
    final problem = validateTableDraft(label, capacity);
    if (problem != null) throw PosFailure(problem);
    final res = await _write('create_table', {
      '_tenant': _tenantId,
      '_label': label.trim(),
      '_capacity': capacity,
      '_floor_id': floorId,
    });
    return res is String ? res : '';
  }

  Future<void> deleteTable(String tableId) =>
      _write('delete_table', {'_table_id': tableId});

  Future<dynamic> _write(String fn, Map<String, dynamic> params) async {
    try {
      return await _client.rpc<dynamic>(fn, params: params);
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    } catch (_) {
      throw const PosTransientFailure("Couldn't reach the floor plan.");
    }
  }

  static String _friendly(String message) {
    final m = message.toLowerCase();
    if (m.contains('permission denied') ||
        m.contains('not authorized') ||
        m.contains('not permitted')) {
      return "You don't have permission to do that.";
    }
    return message.split('\n').first;
  }
}

final tablesAdminRepositoryProvider =
    Provider.family<TablesAdminRepository, String>(
      (ref, tenantId) =>
          TablesAdminRepository(ref.watch(supabaseProvider), tenantId),
    );
