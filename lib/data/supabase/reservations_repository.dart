import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pos_repository.dart' show PosFailure, PosTransientFailure;
import 'supabase_providers.dart';

String? _blankToNull(String? s) {
  final t = s?.trim();
  return (t == null || t.isEmpty) ? null : t;
}

int _int(Object? v) =>
    v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0);

/// The `reservation_status` enum. The server owns the transitions; this is
/// only what the UI offers.
enum ReservationStatus {
  pending,
  confirmed,
  seated,
  cancelled,
  noShow;

  String get wire => this == noShow ? 'no_show' : name;

  static ReservationStatus fromWire(String? s) => switch (s) {
    'confirmed' => confirmed,
    'seated' => seated,
    'cancelled' => cancelled,
    'no_show' => noShow,
    _ => pending,
  };

  /// Still ahead of the guest arriving.
  bool get isOpen => this == pending || this == confirmed;

  /// Display hint only — `set_reservation_status` is the authority.
  List<ReservationStatus> get nextStatuses => switch (this) {
    pending => const [confirmed, cancelled],
    confirmed => const [seated, noShow, cancelled],
    _ => const [],
  };
}

/// One row of `reservations`, with its guest and table joined in.
class Reservation {
  const Reservation({
    required this.id,
    required this.guestName,
    required this.partySize,
    required this.reservedAt,
    required this.status,
    this.tableId,
    this.tableLabel,
    this.guestPhone,
    this.notes,
  });

  final String id;
  final String? tableId;
  final String? tableLabel;
  final String guestName;
  final String? guestPhone;
  final int partySize;

  /// Local time.
  final DateTime reservedAt;
  final ReservationStatus status;
  final String? notes;

  /// A to-one join arrives as a map, or as a one-item list; null if absent.
  static Map<String, dynamic>? _join(Object? v) {
    if (v is Map<String, dynamic>) return v;
    if (v is List && v.isNotEmpty && v.first is Map<String, dynamic>) {
      return v.first as Map<String, dynamic>;
    }
    return null;
  }

  factory Reservation.fromRow(Map<String, dynamic> row) {
    final customer = _join(row['customers']);
    final table = _join(row['restaurant_tables']);
    final at = row['reserved_at'];
    return Reservation(
      id: row['id'] as String,
      tableId: row['table_id'] as String?,
      tableLabel: _blankToNull(table?['label'] as String?),
      guestName: _blankToNull(customer?['name'] as String?) ?? 'Guest',
      guestPhone: _blankToNull(customer?['phone'] as String?),
      partySize: _int(row['party_size']),
      reservedAt:
          (at is String ? DateTime.tryParse(at)?.toLocal() : null) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      status: ReservationStatus.fromWire(row['status'] as String?),
      notes: _blankToNull(row['notes'] as String?),
    );
  }
}

/// What the new-reservation form hands to [ReservationsRepository.create].
class ReservationDraft {
  ReservationDraft({
    this.name = '',
    this.phone = '',
    this.partySize = 2,
    DateTime? when,
    this.tableId,
    this.notes = '',
  }) : when = when ?? DateTime.now();

  String name;
  String phone;
  int partySize;
  DateTime when;
  String? tableId;
  String notes;

  String? validate() {
    if (name.trim().isEmpty) return "Enter the guest's name.";
    if (partySize < 1 || partySize > 50) {
      return 'Party size is between 1 and 50.';
    }
    return null;
  }
}

/// Bookings: listed from `reservations`, written through the same
/// `create_reservation` / `set_reservation_status` RPCs the web calls.
class ReservationsRepository {
  const ReservationsRepository(this._client, this._tenantId);

  final SupabaseClient _client;
  final String _tenantId;

  static const _select =
      'id, table_id, party_size, reserved_at, status, notes, '
      'customers!fk_reservations_customer(name, phone), '
      'restaurant_tables(label)';

  /// Soonest first, from [from] onward.
  Future<List<Reservation>> list({required DateTime from}) async {
    try {
      final rows = await _client
          .from('reservations')
          .select(_select)
          .eq('tenant_id', _tenantId)
          .gte('reserved_at', from.toUtc().toIso8601String())
          .order('reserved_at', ascending: true)
          .limit(300);
      return (rows as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(Reservation.fromRow)
          .toList();
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    } catch (_) {
      throw const PosTransientFailure("Couldn't load reservations.");
    }
  }

  Future<String> create(ReservationDraft d) async {
    final problem = d.validate();
    if (problem != null) throw PosFailure(problem);
    final res = await _write('create_reservation', {
      '_tenant': _tenantId,
      '_name': d.name.trim(),
      '_phone': _blankToNull(d.phone),
      '_party': d.partySize,
      '_when': d.when.toUtc().toIso8601String(),
      '_table_id': d.tableId,
      '_notes': _blankToNull(d.notes),
    });
    return res is String ? res : '';
  }

  Future<void> setStatus(String id, ReservationStatus s) =>
      _write('set_reservation_status', {'_id': id, '_status': s.wire});

  Future<dynamic> _write(String fn, Map<String, dynamic> params) async {
    try {
      return await _client.rpc<dynamic>(fn, params: params);
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    } catch (_) {
      throw const PosTransientFailure("Couldn't reach reservations.");
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

final reservationsRepositoryProvider =
    Provider.family<ReservationsRepository, String>(
      (ref, tenantId) =>
          ReservationsRepository(ref.watch(supabaseProvider), tenantId),
    );
