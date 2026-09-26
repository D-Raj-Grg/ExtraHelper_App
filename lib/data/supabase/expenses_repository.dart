import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'pos_repository.dart' show PosFailure, PosTransientFailure;
import 'supabase_providers.dart';

/// Where the money for an expense came from. Only [cash] lowers the cash the
/// restaurant should have in hand at night; [owner] is outside money.
enum PaidFrom {
  cash('cash', 'Cash', "Taken from today's cash"),
  online('online', 'Online / eSewa', 'Paid by QR, wallet or bank'),
  owner('owner', "Owner's pocket", 'Outside money, not from sales');

  const PaidFrom(this.wire, this.label, this.hint);

  final String wire;
  final String label;
  final String hint;

  static PaidFrom from(String? v) =>
      values.firstWhere((p) => p.wire == v, orElse: () => PaidFrom.cash);
}

class ExpenseCategory {
  const ExpenseCategory({
    required this.id,
    required this.name,
    this.archived = false,
  });

  final String id;
  final String name;
  final bool archived;

  static ExpenseCategory fromJson(Map<String, dynamic> j) => ExpenseCategory(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    archived: j['archived_at'] != null,
  );
}

class Expense {
  const Expense({
    required this.id,
    required this.categoryId,
    required this.category,
    required this.amountCents,
    required this.note,
    required this.paidFrom,
    required this.createdAt,
    this.by,
    this.voided = false,
    this.voidReason,
    this.editable = false,
    this.receiptPath,
    this.canAttach = false,
  });

  final String id;
  final String categoryId;
  final String category;
  final int amountCents;
  final String note;
  final PaidFrom paidFrom;
  final DateTime createdAt;
  final String? by;
  final bool voided;
  final String? voidReason;

  /// Server-decided: a manager, or the logger on the same business day.
  final bool editable;

  /// Object path in the private `expense-receipts` bucket; sign to view.
  final String? receiptPath;

  /// The logger or a manager may attach, replace or remove the photo.
  final bool canAttach;

  bool get hasReceipt => receiptPath != null;

  static Expense fromJson(Map<String, dynamic> j) => Expense(
    id: j['id'] as String,
    categoryId: j['category_id'] as String,
    category: j['category'] as String? ?? '',
    amountCents: (j['amount_cents'] as num).toInt(),
    note: j['note'] as String? ?? '',
    paidFrom: PaidFrom.from(j['paid_from'] as String?),
    createdAt: DateTime.parse(j['created_at'] as String),
    by: j['by'] as String?,
    voided: j['voided'] == true,
    voidReason: j['void_reason'] as String?,
    editable: j['editable'] == true,
    receiptPath: j['receipt_path'] as String?,
    canAttach: j['can_attach'] == true,
  );
}

/// One range's expenses, as `report_expenses` bucketed them by business day.
class ExpenseRange {
  const ExpenseRange({
    required this.totalCents,
    required this.count,
    required this.cashCents,
    required this.onlineCents,
    required this.ownerCents,
    required this.byCategory,
  });

  final int totalCents;
  final int count;
  final int cashCents;
  final int onlineCents;
  final int ownerCents;
  final List<({String name, int amountCents, int count})> byCategory;

  static int _i(Object? v) => (v as num?)?.toInt() ?? 0;

  static ExpenseRange fromJson(Map<String, dynamic> j) {
    final from = (j['by_paid_from'] as Map<String, dynamic>?) ?? const {};
    return ExpenseRange(
      totalCents: _i(j['total_cents']),
      count: _i(j['count']),
      cashCents: _i(from['cash']),
      onlineCents: _i(from['online']),
      ownerCents: _i(from['owner']),
      byCategory: ((j['by_category'] as List<dynamic>?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(
            (c) => (
              name: c['name'] as String? ?? '',
              amountCents: _i(c['amount_cents']),
              count: _i(c['count']),
            ),
          )
          .toList(),
    );
  }
}

/// One business day of expenses, exactly as `expenses_day` resolved it.
///
/// The day and "today" both come from the server — the phone cannot work out a
/// trading day (see `day_report_providers.dart`).
class ExpenseDay {
  const ExpenseDay({
    required this.day,
    required this.today,
    required this.dayLabel,
    required this.items,
    required this.canViewAll,
    required this.canManage,
    required this.canCloseDay,
  });

  final String day;
  final String today;
  final String dayLabel;
  final List<Expense> items;
  final bool canViewAll;
  final bool canManage;
  final bool canCloseDay;

  bool get isToday => day == today;

  List<Expense> get live => items.where((e) => !e.voided).toList();

  int get totalCents => live.fold(0, (s, e) => s + e.amountCents);

  int totalFrom(PaidFrom p) =>
      live.where((e) => e.paidFrom == p).fold(0, (s, e) => s + e.amountCents);

  static ExpenseDay fromJson(Map<String, dynamic> j) => ExpenseDay(
    day: j['day'] as String? ?? '',
    today: j['today'] as String? ?? '',
    dayLabel: j['day_label'] as String? ?? '',
    items: ((j['items'] as List<dynamic>?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(Expense.fromJson)
        .toList(),
    canViewAll: j['can_view_all'] == true,
    canManage: j['can_manage'] == true,
    canCloseDay: j['can_close_day'] == true,
  );
}

/// Expenses and the night count.
///
/// Every write is an RPC (`record_expense`, `update_expense`, `void_expense`,
/// `close_day`, category RPCs) — the permission rules and the drawer link live
/// in SQL, not here.
class ExpensesRepository {
  const ExpensesRepository(this._client, this._tenantId);

  final SupabaseClient _client;
  final String _tenantId;

  Future<ExpenseDay> day({String? day}) => _guard(() async {
    final res = await _client.rpc(
      'expenses_day',
      params: {'_tenant': _tenantId, '_day': ?day},
    );
    return ExpenseDay.fromJson(res as Map<String, dynamic>);
  }, "Couldn't load expenses.");

  Future<List<ExpenseCategory>> categories() => _guard(() async {
    final rows = await _client
        .from('expense_categories')
        .select('id, name, archived_at')
        .eq('tenant_id', _tenantId)
        .order('sort')
        .order('name');
    return rows.map(ExpenseCategory.fromJson).toList();
  }, "Couldn't load categories.");

  /// Idempotent on [clientKey]: a replay returns the row that already landed.
  Future<String> record({
    required String categoryId,
    required int amountCents,
    required String note,
    required PaidFrom paidFrom,
    required String clientKey,
    String? businessDate,
  }) => _guard(() async {
    final res = await _client.rpc(
      'record_expense',
      params: {
        '_tenant': _tenantId,
        '_category': categoryId,
        '_amount_cents': amountCents,
        '_note': note,
        '_paid_from': paidFrom.wire,
        '_client_key': clientKey,
        '_business_date': ?businessDate,
      },
    );
    return res as String;
  }, "Couldn't save that expense just now.");

  Future<void> update({
    required String id,
    required String categoryId,
    required int amountCents,
    required String note,
    required PaidFrom paidFrom,
  }) => _guard(
    () => _client.rpc(
      'update_expense',
      params: {
        '_id': id,
        '_category': categoryId,
        '_amount_cents': amountCents,
        '_note': note,
        '_paid_from': paidFrom.wire,
      },
    ),
    "Couldn't save that change just now.",
  );

  Future<void> voidExpense({required String id, required String reason}) =>
      _guard(
        () =>
            _client.rpc('void_expense', params: {'_id': id, '_reason': reason}),
        "Couldn't void that expense just now.",
      );

  Future<void> saveCategory({String? id, required String name}) => _guard(
    () => _client.rpc(
      'upsert_expense_category',
      params: {'_tenant': _tenantId, '_id': id, '_name': name},
    ),
    "Couldn't save that category just now.",
  );

  Future<void> archiveCategory(String id) => _guard(
    () => _client.rpc(
      'archive_expense_category',
      params: {'_tenant': _tenantId, '_id': id},
    ),
    "Couldn't retire that category just now.",
  );

  /// The night count. Re-closing a day overwrites the earlier count.
  Future<void> closeDay({
    required String day,
    required int cashCents,
    int? onlineCents,
    String? note,
  }) => _guard(
    () => _client.rpc(
      'close_day',
      params: {
        '_tenant': _tenantId,
        '_day': day,
        '_cash_counted_cents': cashCents,
        '_online_counted_cents': ?onlineCents,
        if (note != null && note.trim().isNotEmpty) '_note': note.trim(),
      },
    ),
    "Couldn't save the count just now.",
  );

  static const _bucket = 'expense-receipts';

  /// Rolling window ending now — the same "last 7 / last 30 days" the web
  /// Reports page uses. Null when the caller lacks `reports.view`.
  Future<ExpenseRange?> range({required Duration span}) => _guard(() async {
    final to = DateTime.now().toUtc();
    final res = await _client.rpc<dynamic>(
      'report_expenses',
      params: {
        '_tenant': _tenantId,
        '_from': to.subtract(span).toIso8601String(),
        '_to': to.toIso8601String(),
      },
    );
    return res == null
        ? null
        : ExpenseRange.fromJson(res as Map<String, dynamic>);
  }, "Couldn't load the totals.");

  /// The server id of an expense logged through the outbox, by its key.
  Future<String?> idForClientKey(String clientKey) => _guard(() async {
    final row = await _client
        .from('expenses')
        .select('id')
        .eq('tenant_id', _tenantId)
        .eq('client_key', clientKey)
        .maybeSingle();
    return row?['id'] as String?;
  }, "Couldn't find that expense.");

  /// Upload under a fresh name, link it through `set_expense_receipt` (which
  /// re-checks who may change it), then delete whatever it replaced.
  Future<void> attachReceipt({
    required String expenseId,
    required List<int> bytes,
    required String contentType,
    required String ext,
  }) async {
    final path = '$_tenantId/$expenseId/${const Uuid().v4()}.$ext';
    final store = _client.storage.from(_bucket);
    try {
      await store.uploadBinary(
        path,
        Uint8List.fromList(bytes),
        fileOptions: FileOptions(contentType: contentType),
      );
    } on StorageException catch (e) {
      throw PosFailure(e.message);
    } catch (_) {
      throw const PosTransientFailure("Couldn't upload the photo just now.");
    }
    final String? previous;
    try {
      previous = await _guard(
        () async =>
            await _client.rpc<dynamic>(
                  'set_expense_receipt',
                  params: {'_id': expenseId, '_path': path},
                )
                as String?,
        "Couldn't attach the photo just now.",
      );
    } on PosFailure {
      await _quietRemove(path);
      rethrow;
    }
    if (previous != null) await _quietRemove(previous);
  }

  Future<void> removeReceipt(String expenseId) async {
    final previous = await _guard(
      () async =>
          await _client.rpc<dynamic>(
                'set_expense_receipt',
                params: {'_id': expenseId, '_path': null},
              )
              as String?,
      "Couldn't remove the photo just now.",
    );
    if (previous != null) await _quietRemove(previous);
  }

  /// A short-lived link to view a photo; the bucket is private.
  Future<String> receiptUrl(String path) => _guard(
    () => _client.storage.from(_bucket).createSignedUrl(path, 60 * 10),
    "Couldn't open the photo just now.",
  );

  /// Orphan cleanup only — a leftover object costs storage, not correctness.
  Future<void> _quietRemove(String path) async {
    try {
      await _client.storage.from(_bucket).remove([path]);
    } catch (_) {}
  }

  static Future<T> _guard<T>(Future<T> Function() work, String offline) async {
    try {
      return await work();
    } on PostgrestException catch (e) {
      throw PosFailure(e.message);
    } on StorageException catch (e) {
      throw PosFailure(e.message);
    } on PosFailure {
      rethrow;
    } catch (_) {
      throw PosTransientFailure(offline);
    }
  }
}

final expensesRepositoryProvider = Provider.family<ExpensesRepository, String>(
  (ref, tenantId) => ExpensesRepository(ref.watch(supabaseProvider), tenantId),
);
