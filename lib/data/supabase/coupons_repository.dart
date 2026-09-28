import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pos_repository.dart' show PosFailure, PosTransientFailure;
import 'supabase_providers.dart';

/// Coerce a PostgREST number that may arrive as `int`, `num` or, for a
/// `bigint`/`numeric`, a decimal `String`. Anything else is a zero.
int _int(Object? v) =>
    v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0);

/// `numeric` columns arrive as a `String` from PostgREST; `value` is one.
double _double(Object? v) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

int? _maybeInt(Object? v) => v == null ? null : _int(v);

DateTime? _maybeDate(Object? v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;

String? _blankToNull(String? s) {
  final t = s?.trim();
  return (t == null || t.isEmpty) ? null : t;
}

/// The shape a code must have — mirrors the `coupons_code_shape` check
/// constraint, so a bad code is refused here with a sentence rather than
/// there with a constraint name.
final couponCodeShape = RegExp(r'^[A-Z0-9-]{4,24}$');

/// What a rule can be limited to. A QR-table order is dine-in as far as a
/// rule is concerned (the server folds `qr` into `dine_in`), so the form
/// never offers it. Same list and order as the web's `COUPON_ORDER_TYPES`.
const couponOrderTypes = ['dine_in', 'pickup', 'delivery'];

/// One row of `list_coupons`.
class Coupon {
  const Coupon({
    required this.id,
    required this.code,
    required this.type,
    required this.value,
    required this.isActive,
    required this.createdAt,
    this.name,
    this.validFrom,
    this.validTo,
    this.usageLimit,
    this.usedCount = 0,
    this.minSubtotalCents = 0,
    this.oncePerCustomer = false,
    this.orderTypes,
    this.redemptions = 0,
    this.discountGivenCents = 0,
    this.lastRedeemedAt,
  });

  final String id;
  final String code;
  final String? name;

  /// `percent` or `flat`.
  final String type;

  /// Percent points for `percent`; whole currency units for `flat`.
  final double value;
  final bool isActive;
  final DateTime? validFrom;

  /// Exclusive: the coupon stops working at this instant.
  final DateTime? validTo;
  final int? usageLimit;
  final int usedCount;
  final int minSubtotalCents;
  final bool oncePerCustomer;

  /// Null means any order type.
  final List<String>? orderTypes;
  final DateTime createdAt;

  /// How many bills carry it — what "Delete" is refused on.
  final int redemptions;
  final int discountGivenCents;
  final DateTime? lastRedeemedAt;

  bool get isPercent => type == 'percent';

  /// A redeemed coupon keeps its code; the server refuses a change.
  bool get codeLocked => redemptions > 0;

  static Coupon fromRow(Map<String, dynamic> row) {
    final types = row['order_types'];
    return Coupon(
      id: row['id'] as String,
      code: (row['code'] as String? ?? '').trim().toUpperCase(),
      name: _blankToNull(row['name'] as String?),
      type: (row['type'] as String?) == 'flat' ? 'flat' : 'percent',
      value: _double(row['value']),
      isActive: row['is_active'] as bool? ?? true,
      validFrom: _maybeDate(row['valid_from']),
      validTo: _maybeDate(row['valid_to']),
      usageLimit: _maybeInt(row['usage_limit']),
      usedCount: _int(row['used_count']),
      minSubtotalCents: _int(row['min_subtotal_cents']),
      oncePerCustomer: row['once_per_customer'] as bool? ?? false,
      orderTypes: types is List ? types.whereType<String>().toList() : null,
      createdAt: _maybeDate(row['created_at']) ?? DateTime.now(),
      redemptions: _int(row['redemptions']),
      discountGivenCents: _int(row['discount_given_cents']),
      lastRedeemedAt: _maybeDate(row['last_redeemed_at']),
    );
  }

  /// The same coupon as a draft, for editing or for a pause/resume that
  /// re-sends every field unchanged (there is no separate pause RPC).
  CouponDraft toDraft() => CouponDraft(
    id: id,
    code: code,
    name: name,
    type: type,
    value: value,
    isActive: isActive,
    validFrom: validFrom,
    validTo: validTo,
    usageLimit: usageLimit,
    minSubtotalCents: minSubtotalCents,
    oncePerCustomer: oncePerCustomer,
    orderTypes: orderTypes,
  );
}

/// What the form hands to [CouponsRepository.save]. [id] null creates;
/// [code] null or blank lets the server make one (`SAVE10-7KQ2`).
class CouponDraft {
  const CouponDraft({
    this.id,
    this.code,
    this.name,
    required this.type,
    required this.value,
    this.isActive = true,
    this.validFrom,
    this.validTo,
    this.usageLimit,
    this.minSubtotalCents = 0,
    this.oncePerCustomer = false,
    this.orderTypes,
  });

  final String? id;
  final String? code;
  final String? name;
  final String type;
  final double value;
  final bool isActive;
  final DateTime? validFrom;
  final DateTime? validTo;
  final int? usageLimit;
  final int minSubtotalCents;
  final bool oncePerCustomer;
  final List<String>? orderTypes;

  CouponDraft copyWith({bool? isActive}) => CouponDraft(
    id: id,
    code: code,
    name: name,
    type: type,
    value: value,
    isActive: isActive ?? this.isActive,
    validFrom: validFrom,
    validTo: validTo,
    usageLimit: usageLimit,
    minSubtotalCents: minSubtotalCents,
    oncePerCustomer: oncePerCustomer,
    orderTypes: orderTypes,
  );

  /// The first thing wrong with this draft, as a sentence, or null. Mirrors
  /// the web's `saveCoupon` checks so both clients refuse the same input.
  String? validate() {
    final c = _blankToNull(code)?.toUpperCase();
    if (c != null && !couponCodeShape.hasMatch(c)) {
      return 'A code is 4 to 24 letters, numbers or dashes.';
    }
    if (type != 'percent' && type != 'flat') return 'Pick a discount type.';
    if (value.isNaN || value <= 0) return 'Enter a discount above zero.';
    if (type == 'percent' && value > 100) {
      return "Percent off can't exceed 100.";
    }
    if (usageLimit != null && usageLimit! < 1) {
      return 'A usage limit is at least 1, or blank for no limit.';
    }
    if (minSubtotalCents < 0) return "Minimum order can't be negative.";
    if (validFrom != null && validTo != null && !validTo!.isAfter(validFrom!)) {
      return 'The coupon must end after it starts.';
    }
    return null;
  }

  /// Every order type, or none, means no rule — the server stores null.
  List<String>? get effectiveOrderTypes {
    final t = orderTypes;
    if (t == null || t.isEmpty || t.length >= couponOrderTypes.length) {
      return null;
    }
    return t;
  }
}

/// The flyer codes: what they are worth, when they run, how often they were
/// used. Every write is an RPC (`upsert_coupon`, `delete_coupon`) carrying
/// the `coupons.manage` check; the list is `list_coupons` under
/// `coupons.view` — the same three the web's Coupons page calls.
class CouponsRepository {
  const CouponsRepository(this._client, this._tenantId);

  final SupabaseClient _client;
  final String _tenantId;

  /// Active first, then newest — the order `list_coupons` returns.
  Future<List<Coupon>> list() => _read(() async {
    final res = await _client.rpc<dynamic>(
      'list_coupons',
      params: {'_tenant': _tenantId},
    );
    return _rows(res).map(Coupon.fromRow).toList();
  });

  /// Create (id null) or edit. Returns the coupon's id.
  Future<String> save(CouponDraft draft) async {
    final problem = draft.validate();
    if (problem != null) throw PosFailure(problem);
    final res = await _write('upsert_coupon', {
      '_tenant': _tenantId,
      '_id': draft.id,
      '_code': _blankToNull(draft.code)?.toUpperCase(),
      '_name': _blankToNull(draft.name),
      '_type': draft.type,
      '_value': draft.value,
      '_is_active': draft.isActive,
      '_valid_from': draft.validFrom?.toUtc().toIso8601String(),
      '_valid_to': draft.validTo?.toUtc().toIso8601String(),
      '_usage_limit': draft.usageLimit,
      '_min_subtotal_cents': draft.minSubtotalCents,
      '_once_per_customer': draft.oncePerCustomer,
      '_order_types': draft.effectiveOrderTypes,
    });
    return res is String ? res : draft.id ?? '';
  }

  /// Pause or resume: the same upsert with only `_is_active` flipped, which
  /// is how the web does it too.
  Future<void> setActive(Coupon coupon, bool active) =>
      save(coupon.toDraft().copyWith(isActive: active));

  /// Refused by the server once the coupon is on a bill — "pause it
  /// instead", which the screen offers up front.
  Future<void> delete(String id) => _write('delete_coupon', {'_id': id});

  // --- Helpers -------------------------------------------------------------

  Future<T> _read<T>(Future<T> Function() work) async {
    try {
      return await work();
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    } catch (_) {
      throw const PosTransientFailure("Couldn't load coupons.");
    }
  }

  Future<dynamic> _write(String fn, Map<String, dynamic> params) async {
    try {
      return await _client.rpc<dynamic>(fn, params: params);
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    } catch (_) {
      throw const PosTransientFailure("Couldn't reach the coupon list.");
    }
  }

  static List<Map<String, dynamic>> _rows(Object? result) =>
      (result as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();

  /// The RPCs already raise sentences ("A coupon with this code already
  /// exists"); only the permission wording needs a translation.
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

final couponsRepositoryProvider = Provider.family<CouponsRepository, String>(
  (ref, tenantId) => CouponsRepository(ref.watch(supabaseProvider), tenantId),
);
