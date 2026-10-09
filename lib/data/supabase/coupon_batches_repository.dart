import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pos_repository.dart' show PosFailure, PosTransientFailure;
import 'supabase_providers.dart';

/// PostgREST sends `bigint`/`numeric` as a number or, sometimes, a string.
int _int(Object? v) =>
    v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0);

double _double(Object? v) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

DateTime? _maybeDate(Object? v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;

/// The prefix a run's codes start with (`SUMMER-K7Q2XM`). Mirrors the web's
/// `createCouponBatch` check; the server builds the rest.
final runPrefixShape = RegExp(r'^[A-Z0-9]{2,8}$');

/// The one row of `coupon_stats`: how many campaigns are in each state, and
/// what they have given away. Same numbers as the web's strip.
class CouponStats {
  const CouponStats({
    this.active = 0,
    this.scheduled = 0,
    this.expired = 0,
    this.usedUp = 0,
    this.paused = 0,
    this.redemptions = 0,
    this.discountGivenCents = 0,
  });

  final int active;
  final int scheduled;
  final int expired;
  final int usedUp;
  final int paused;
  final int redemptions;
  final int discountGivenCents;

  int get total => active + scheduled + expired + usedUp + paused;

  static CouponStats fromRow(Map<String, dynamic> row) => CouponStats(
    active: _int(row['active']),
    scheduled: _int(row['scheduled']),
    expired: _int(row['expired']),
    usedUp: _int(row['used_up']),
    paused: _int(row['paused']),
    redemptions: _int(row['redemptions']),
    discountGivenCents: _int(row['discount_given_cents']),
  );
}

/// One row of `list_coupon_batches`: a flyer print run.
class CouponBatch {
  const CouponBatch({
    required this.id,
    required this.name,
    required this.type,
    required this.value,
    required this.createdAt,
    this.validFrom,
    this.validTo,
    this.issued = 0,
    this.redeemed = 0,
    this.active = 0,
    this.shared = 0,
    this.designId,
  });

  final String id;
  final String name;

  /// `percent` or `flat`.
  final String type;
  final double value;
  final DateTime? validFrom;

  /// Exclusive: the codes stop working at this instant.
  final DateTime? validTo;
  final DateTime createdAt;
  final int issued;
  final int redeemed;

  /// Codes currently switched on. Zero with `issued > 0` is a paused run.
  final int active;

  /// Codes noted as handed out.
  final int shared;

  /// The saved flyer design this run prints on; null until one is chosen.
  final String? designId;

  bool get isPercent => type == 'percent';
  bool get isPaused => issued > 0 && active == 0;

  /// Codes still free to give out: not shared and not yet used.
  int get unused => (issued - redeemed - shared).clamp(0, issued);

  static CouponBatch fromRow(Map<String, dynamic> row) => CouponBatch(
    id: row['id'] as String,
    name: (row['name'] as String? ?? '').trim(),
    type: (row['type'] as String?) == 'flat' ? 'flat' : 'percent',
    value: _double(row['value']),
    validFrom: _maybeDate(row['valid_from']),
    validTo: _maybeDate(row['valid_to']),
    createdAt: _maybeDate(row['created_at']) ?? DateTime.now(),
    issued: _int(row['issued']),
    redeemed: _int(row['redeemed']),
    active: _int(row['active']),
    shared: _int(row['shared']),
    designId: row['design_id'] as String?,
  );
}

/// One row of `get_batch_codes`.
class BatchCode {
  const BatchCode({
    required this.code,
    required this.redeemed,
    required this.isActive,
    required this.shared,
  });

  final String code;
  final bool redeemed;
  final bool isActive;
  final bool shared;

  static BatchCode fromRow(Map<String, dynamic> row) => BatchCode(
    code: (row['code'] as String? ?? '').trim().toUpperCase(),
    redeemed: row['redeemed'] as bool? ?? false,
    isActive: row['is_active'] as bool? ?? true,
    shared: row['shared'] as bool? ?? false,
  );
}

/// What the New run form hands to [CouponBatchesRepository.create].
class RunDraft {
  const RunDraft({
    required this.name,
    required this.count,
    required this.prefix,
    required this.type,
    required this.value,
    this.validFrom,
    this.validTo,
    this.dineInOnly = false,
  });

  final String name;
  final int count;
  final String prefix;
  final String type;
  final double value;
  final DateTime? validFrom;

  /// Exclusive end (start of the day after the last valid day).
  final DateTime? validTo;
  final bool dineInOnly;

  /// The sentence the web's `createCouponBatch` would give, or null when the
  /// draft is fine. The server re-checks everything.
  String? validate({DateTime? now}) {
    if (name.trim().isEmpty) return 'Give the run a name.';
    if (count < 1 || count > 1000) return 'A run is 1 to 1000 codes.';
    if (!runPrefixShape.hasMatch(prefix.trim().toUpperCase())) {
      return 'The prefix is 2 to 8 letters or digits.';
    }
    if (!value.isFinite || value <= 0) return 'Enter a discount above zero.';
    if (type == 'percent' && value > 100) {
      return "A discount can't be more than 100%.";
    }
    final from = validFrom;
    final to = validTo;
    if (from != null && to != null && !to.isAfter(from)) {
      return 'The coupon must end after it starts.';
    }
    if (to != null && !to.isAfter(now ?? DateTime.now())) {
      return 'That end date has already passed.';
    }
    return null;
  }

  /// The `create_coupon_batch` argument map, as the web sends it: null order
  /// types is "any", instants as ISO-8601 UTC.
  Map<String, dynamic> toRpcParams(String tenantId) => {
    '_tenant': tenantId,
    '_name': name.trim(),
    '_count': count,
    '_prefix': prefix.trim().toUpperCase(),
    '_type': type,
    '_value': value,
    '_valid_from': validFrom?.toUtc().toIso8601String(),
    '_valid_to': validTo?.toUtc().toIso8601String(),
    '_min_subtotal_cents': 0,
    '_once_per_customer': false,
    '_order_types': dineInOnly ? const ['dine_in'] : null,
  };
}

/// What the Edit run form hands back: a name and a window. Codes, prefix and
/// discount are on paper by now, so the server does not let them move.
class RunEdit {
  const RunEdit({required this.name, this.validFrom, this.validTo});

  final String name;
  final DateTime? validFrom;
  final DateTime? validTo;

  String? validate() {
    if (name.trim().isEmpty) return 'Give the run a name.';
    final from = validFrom;
    final to = validTo;
    if (from != null && to != null && !to.isAfter(from)) {
      return 'The coupon must end after it starts.';
    }
    return null;
  }
}

/// The flyer runs and the strip above the coupon list. Reads are
/// `coupon_stats`, `list_coupon_batches` and `get_batch_codes` under
/// `coupons.view`; writes are `create_coupon_batch`, `update_coupon_batch`,
/// `set_batch_active` and `mark_coupon_shared` under `coupons.manage` — the
/// same RPCs the web's Flyers tab calls.
class CouponBatchesRepository {
  const CouponBatchesRepository(this._client, this._tenantId);

  final SupabaseClient _client;
  final String _tenantId;

  Future<CouponStats> stats() => _read(() async {
    final res = await _client.rpc<dynamic>(
      'coupon_stats',
      params: {'_tenant': _tenantId},
    );
    final rows = _rows(res);
    return rows.isEmpty ? const CouponStats() : CouponStats.fromRow(rows.first);
  });

  Future<List<CouponBatch>> list() => _read(() async {
    final res = await _client.rpc<dynamic>(
      'list_coupon_batches',
      params: {'_tenant': _tenantId},
    );
    return _rows(res).map(CouponBatch.fromRow).toList();
  });

  Future<List<BatchCode>> codes(String batchId) => _read(() async {
    final res = await _client.rpc<dynamic>(
      'get_batch_codes',
      params: {'_batch': batchId},
    );
    return _rows(res).map(BatchCode.fromRow).toList();
  });

  /// Returns the new run's id.
  Future<String> create(RunDraft draft) async {
    final problem = draft.validate();
    if (problem != null) throw PosFailure(problem);
    final res = await _write(
      'create_coupon_batch',
      draft.toRpcParams(_tenantId),
    );
    return res is String ? res : '';
  }

  Future<void> update(String batchId, RunEdit edit) async {
    final problem = edit.validate();
    if (problem != null) throw PosFailure(problem);
    await _write('update_coupon_batch', {
      '_batch': batchId,
      '_name': edit.name.trim(),
      '_valid_from': edit.validFrom?.toUtc().toIso8601String(),
      '_valid_to': edit.validTo?.toUtc().toIso8601String(),
    });
  }

  /// Pause or resume every code of the run at once.
  Future<void> setActive(String batchId, bool active) =>
      _write('set_batch_active', {'_batch': batchId, '_active': active});

  /// A note for the owner ("this flyer went out"); never affects redeeming.
  Future<void> markShared(String batchId, String code, {bool shared = true}) =>
      _write('mark_coupon_shared', {
        '_batch': batchId,
        '_code': code,
        '_shared': shared,
      });

  // --- Helpers -------------------------------------------------------------

  Future<T> _read<T>(Future<T> Function() work) async {
    try {
      return await work();
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    } catch (_) {
      throw const PosTransientFailure("Couldn't load the flyers.");
    }
  }

  Future<dynamic> _write(String fn, Map<String, dynamic> params) async {
    try {
      return await _client.rpc<dynamic>(fn, params: params);
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    } catch (_) {
      throw const PosTransientFailure("Couldn't reach the flyers.");
    }
  }

  static List<Map<String, dynamic>> _rows(Object? result) =>
      (result as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();

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

final couponBatchesRepositoryProvider =
    Provider.family<CouponBatchesRepository, String>(
      (ref, tenantId) =>
          CouponBatchesRepository(ref.watch(supabaseProvider), tenantId),
    );
