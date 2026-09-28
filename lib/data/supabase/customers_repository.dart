import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pos_repository.dart' show PosFailure, PosTransientFailure;
import 'supabase_providers.dart';

/// Coerce a PostgREST number that may arrive as `int`, `num` or, for a
/// `bigint`, a decimal `String`. Anything else is a zero, not a crash.
int _int(Object? v) =>
    v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0);

String? _blankToNull(String? s) {
  final t = s?.trim();
  return (t == null || t.isEmpty) ? null : t;
}

/// A guest in the tenant's book, with their loyalty balance and what they owe.
///
/// The credit figures come from `customer_credit_summary`, not the `customers`
/// row — see [CustomersRepository.overview] for how the two are stitched.
class CrmCustomer {
  const CrmCustomer({
    required this.id,
    this.name,
    this.phone,
    this.email,
    this.points = 0,
    this.tier = 'bronze',
    this.owesCents = 0,
    this.unpaidBills = 0,
  });

  final String id;
  final String? name;
  final String? phone;
  final String? email;
  final int points;
  final String tier;
  final int owesCents;
  final int unpaidBills;

  bool get owes => owesCents > 0;

  String get label => name ?? phone ?? email ?? 'Guest';

  /// "Max · 9767288510" — the label, then whichever contact detail the label
  /// did not already use.
  String get describe {
    final parts = <String>[label];
    if (name != null) {
      final contact = phone ?? email;
      if (contact != null) parts.add(contact);
    } else if (phone != null && email != null) {
      parts.add(email!);
    }
    return parts.join(' · ');
  }

  /// From `customers` selected as
  /// `id, name, phone, email, loyalty_accounts(points_balance, tier)`.
  /// `loyalty_accounts` embeds as a list, or as one object when PostgREST
  /// knows the relation is one-to-one, or not at all; a guest who never
  /// earned a point has none, which is zero points on bronze, not a null.
  static CrmCustomer fromRow(Map<String, dynamic> row) {
    final raw = row['loyalty_accounts'];
    final loyalty = switch (raw) {
      Map<String, dynamic> m => m,
      List<dynamic> l => l.whereType<Map<String, dynamic>>().firstOrNull,
      _ => null,
    };
    return CrmCustomer(
      id: row['id'] as String,
      name: _blankToNull(row['name'] as String?),
      phone: _blankToNull(row['phone'] as String?),
      email: _blankToNull(row['email'] as String?),
      points: _int(loyalty?['points_balance']),
      tier: (loyalty?['tier'] as String?) ?? 'bronze',
    );
  }

  CrmCustomer withCredit({required int owesCents, required int unpaidBills}) =>
      CrmCustomer(
        id: id,
        name: name,
        phone: phone,
        email: email,
        points: points,
        tier: tier,
        owesCents: owesCents,
        unpaidBills: unpaidBills,
      );
}

/// One bill on a guest's tab, as `customer_bill_history` returns it.
class CustomerBillRow {
  const CustomerBillRow({
    required this.billId,
    required this.createdAt,
    required this.status,
    required this.totalCents,
    required this.paidCents,
    required this.outstandingCents,
    this.tableLabel,
    this.itemsSummary,
  });

  final String billId;
  final DateTime createdAt;
  final String status;
  final int totalCents;
  final int paidCents;
  final int outstandingCents;
  final String? tableLabel;
  final String? itemsSummary;

  bool get unpaid => outstandingCents > 0;

  static CustomerBillRow fromRow(Map<String, dynamic> row) => CustomerBillRow(
    billId: row['bill_id'] as String,
    createdAt: DateTime.parse(row['created_at'] as String),
    status: row['status'] as String? ?? 'open',
    totalCents: _int(row['total_cents']),
    paidCents: _int(row['paid_cents']),
    outstandingCents: _int(row['outstanding_cents']),
    tableLabel: _blankToNull(row['table_label'] as String?),
    itemsSummary: _blankToNull(row['items_summary'] as String?),
  );
}

/// A guest's rating, from `feedback` selected as
/// `id, rating, comment, created_at, customers(name)`.
class CustomerFeedback {
  const CustomerFeedback({
    required this.id,
    required this.createdAt,
    this.rating,
    this.comment,
    this.customerName,
  });

  final String id;
  final int? rating;
  final String? comment;
  final DateTime createdAt;
  final String? customerName;

  static CustomerFeedback fromRow(Map<String, dynamic> row) {
    final c = row['customers'];
    return CustomerFeedback(
      id: row['id'] as String,
      rating: row['rating'] == null ? null : _int(row['rating']),
      comment: _blankToNull(row['comment'] as String?),
      createdAt: DateTime.parse(row['created_at'] as String),
      customerName: c is Map<String, dynamic>
          ? _blankToNull(c['name'] as String?)
          : null,
    );
  }
}

/// Everything the Customers screen shows in one load.
class CrmOverview {
  const CrmOverview({
    required this.customers,
    required this.totalOwedCents,
    required this.debtors,
    required this.feedback,
  });

  /// Debtors first (largest debt on top), then everyone else in list order.
  final List<CrmCustomer> customers;

  /// Summed over every credit row the tenant has, not just the ones listed.
  final int totalOwedCents;

  /// How many guests owe anything at all — credit rows with nothing
  /// outstanding are not debtors, see [countDebtors].
  final int debtors;

  final List<CustomerFeedback> feedback;

  /// The guests in [creditRows] (as `customer_credit_summary` returns them)
  /// who still owe something. The summary may carry a row for a guest whose
  /// tab was settled but whose bill is still `partial`/`open` — zero owed is
  /// not a debt.
  static int countDebtors(List<Map<String, dynamic>> creditRows) =>
      creditRows.where(_owing).length;

  static bool _owing(Map<String, dynamic> r) =>
      _int(r['outstanding_cents']) > 0;

  /// Stable: two debtors owing the same keep their incoming order, and the
  /// non-debtors keep theirs.
  static List<CrmCustomer> debtorsFirst(List<CrmCustomer> customers) {
    final indexed = customers.indexed.toList()
      ..sort((a, b) {
        final aOwes = a.$2.owesCents;
        final bOwes = b.$2.owesCents;
        if (aOwes > 0 && bOwes > 0 && aOwes != bOwes) {
          return bOwes.compareTo(aOwes);
        }
        if (aOwes > 0 && bOwes <= 0) return -1;
        if (bOwes > 0 && aOwes <= 0) return 1;
        return a.$1.compareTo(b.$1);
      });
    return indexed.map((e) => e.$2).toList();
  }
}

/// The customer book: who the guests are, what they owe, what they said.
///
/// Every write is an RPC (`loyalty_adjust`, `update_customer`,
/// `delete_customer`, `merge_customers`) — the permission rules, the phone
/// uniqueness and the points ledger all live in SQL, same as the web's
/// `loyalty/actions.ts`.
class CustomersRepository {
  const CustomersRepository(this._client, this._tenantId);

  final SupabaseClient _client;
  final String _tenantId;

  static const _select =
      'id, name, phone, email, loyalty_accounts(points_balance, tier)';

  /// The screen's one load.
  ///
  /// Empty [query]: the newest 50 guests, the latest 20 ratings, and every
  /// debtor — a guest who owes money is appended even when they fell off the
  /// newest-50 window, so the debt list is never quietly short. Non-empty:
  /// a server-side search across name, phone and email, no feedback, and no
  /// debtor back-fill (a search shows what matched, nothing more). The
  /// totals always cover the whole tenant.
  Future<CrmOverview> overview({String query = ''}) async {
    final q = query.trim();
    final searching = q.isNotEmpty;

    // Parsing stays inside the try too: a row shaped differently from what
    // `fromRow` expects is a transient "couldn't load", not a raw TypeError
    // on the screen.
    try {
      // The `or` filter is parsed as text, so anything that is punctuation
      // *to that parser* is stripped before it gets there — commas and parens
      // separate its terms, quotes and backslashes quote them.
      final safe = searching
          ? q.replaceAll(RegExp(r'[,()*"\\]'), ' ').trim()
          : '';
      final Future<dynamic> customers;
      if (searching && safe.isEmpty) {
        customers = Future<List<Map<String, dynamic>>>.value(const []);
      } else if (searching) {
        customers = _client
            .from('customers')
            .select(_select)
            .eq('tenant_id', _tenantId)
            .or('name.ilike.%$safe%,phone.ilike.%$safe%,email.ilike.%$safe%')
            .order('name')
            .limit(30);
      } else {
        customers = _client
            .from('customers')
            .select(_select)
            .eq('tenant_id', _tenantId)
            .order('created_at', ascending: false)
            .limit(50);
      }

      // Explicitly `dynamic`: PostgREST's builders are each a differently-typed
      // Future, and inference lands on `Object` and refuses the list.
      final results = await Future.wait<dynamic>([
        customers,
        _client.rpc<dynamic>(
          'customer_credit_summary',
          params: {'_tenant': _tenantId},
        ),
        if (searching)
          Future<List<Map<String, dynamic>>>.value(const [])
        else
          _client
              .from('feedback')
              .select('id, rating, comment, created_at, customers(name)')
              .eq('tenant_id', _tenantId)
              .order('created_at', ascending: false)
              .limit(20),
      ]);
      var customerRows = _rows(results[0]);
      final creditRows = _rows(results[1]);
      final feedbackRows = _rows(results[2]);

      if (!searching) {
        // Only a guest who actually owes earns a place past the newest-50
        // window; a settled row in the summary is not a debt to show.
        final listed = customerRows.map((r) => r['id'] as String).toSet();
        final missing = creditRows
            .where(CrmOverview._owing)
            .map((r) => r['customer_id'] as String?)
            .nonNulls
            .where((id) => !listed.contains(id))
            .toSet()
            .toList();
        if (missing.isNotEmpty) {
          final extra = await _client
              .from('customers')
              .select(_select)
              .eq('tenant_id', _tenantId)
              .inFilter('id', missing);
          customerRows = [...customerRows, ..._rows(extra)];
        }
      }

      final credit = _creditById(creditRows);
      final guests = customerRows
          .map((r) => _withCredit(CrmCustomer.fromRow(r), credit[r['id']]))
          .toList();

      return CrmOverview(
        customers: CrmOverview.debtorsFirst(guests),
        totalOwedCents: creditRows.fold(
          0,
          (n, r) => n + _int(r['outstanding_cents']),
        ),
        debtors: CrmOverview.countDebtors(creditRows),
        feedback: feedbackRows.map(CustomerFeedback.fromRow).toList(),
      );
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    } catch (_) {
      throw const PosTransientFailure("Couldn't load customers.");
    }
  }

  /// One guest with their credit, or null when no such row is in this
  /// tenant. The detail screen reads this rather than fishing the guest out
  /// of the (possibly search-filtered) overview list.
  Future<CrmCustomer?> customer(String id) => _read(() async {
    final results = await Future.wait<dynamic>([
      _client
          .from('customers')
          .select(_select)
          .eq('tenant_id', _tenantId)
          .eq('id', id)
          .maybeSingle(),
      _client.rpc<dynamic>(
        'customer_credit_summary',
        params: {'_tenant': _tenantId},
      ),
    ]);
    final row = results[0];
    if (row is! Map<String, dynamic>) return null;
    final credit = _creditById(_rows(results[1]));
    return _withCredit(CrmCustomer.fromRow(row), credit[id]);
  });

  static Map<String, Map<String, dynamic>> _creditById(
    List<Map<String, dynamic>> creditRows,
  ) => {
    for (final r in creditRows)
      if (r['customer_id'] is String) r['customer_id'] as String: r,
  };

  static CrmCustomer _withCredit(CrmCustomer c, Map<String, dynamic>? mine) =>
      mine == null
      ? c
      : c.withCredit(
          owesCents: _int(mine['outstanding_cents']),
          unpaidBills: _int(mine['unpaid_bills']),
        );

  /// Every non-void bill this guest was on, newest first.
  Future<List<CustomerBillRow>> history(String customerId, {int limit = 50}) =>
      _read(() async {
        final res = await _client.rpc<dynamic>(
          'customer_bill_history',
          params: {
            '_tenant': _tenantId,
            '_customer': customerId,
            '_limit': limit,
          },
        );
        return _rows(res).map(CustomerBillRow.fromRow).toList();
      });

  /// Hand out or take back points by hand. [type] is `earn` or `burn`;
  /// [points] is always the positive size of the move.
  Future<void> adjustPoints({
    required String customerId,
    required int points,
    required String type,
  }) {
    if (points <= 0) {
      throw const PosFailure('Points must be a positive whole number.');
    }
    return _write('loyalty_adjust', {
      '_customer_id': customerId,
      '_points': points,
      '_type': type,
      '_reference': type == 'earn' ? 'manual earn' : 'manual redeem',
    });
  }

  /// Rename or re-number a guest. Blank fields are sent as null.
  Future<void> update({
    required String customerId,
    String? name,
    String? phone,
    String? email,
  }) {
    final n = _blankToNull(name);
    final p = _blankToNull(phone);
    if (n == null && p == null) {
      throw const PosFailure('Enter a name or a phone number.');
    }
    return _write('update_customer', {
      '_customer_id': customerId,
      '_name': n,
      '_phone': p,
      '_email': _blankToNull(email),
    });
  }

  Future<void> delete(String customerId) =>
      _write('delete_customer', {'_customer_id': customerId});

  /// Fold [dropId] into [keepId]: orders, points and feedback move over, then
  /// the dropped row goes.
  Future<void> merge({required String keepId, required String dropId}) {
    if (keepId == dropId) {
      throw const PosFailure('Pick two different customers to merge.');
    }
    return _write('merge_customers', {'_keep_id': keepId, '_drop_id': dropId});
  }

  // --- Helpers -------------------------------------------------------------

  Future<T> _read<T>(Future<T> Function() work) async {
    try {
      return await work();
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    } catch (_) {
      throw const PosTransientFailure("Couldn't load customers.");
    }
  }

  Future<void> _write(String fn, Map<String, dynamic> params) async {
    try {
      await _client.rpc<dynamic>(fn, params: params);
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    } catch (_) {
      throw const PosTransientFailure("Couldn't reach the customer book.");
    }
  }

  static List<Map<String, dynamic>> _rows(Object? result) =>
      (result as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();

  /// Turn the RPCs' SQL prose into something staff can act on. Anything
  /// unmapped passes through — an opaque message beats a swallowed one.
  static String _friendly(String message) {
    final m = message.toLowerCase();
    if (m.contains('permission denied') ||
        m.contains('not authorized') ||
        m.contains('not permitted') ||
        m.contains('require a manager') ||
        m.contains('requires a manager')) {
      return "You don't have permission to do that.";
    }
    if ((m.contains('phone') && m.contains('already')) ||
        m.contains('duplicate')) {
      return 'That phone number belongs to another customer.';
    }
    if (m.contains('name or phone required')) {
      return 'Enter a name or a phone number.';
    }
    return message.split('\n').first;
  }
}

final customersRepositoryProvider =
    Provider.family<CustomersRepository, String>(
      (ref, tenantId) =>
          CustomersRepository(ref.watch(supabaseProvider), tenantId),
    );
