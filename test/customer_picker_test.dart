import 'package:extrahelper/features/pos/bill_models.dart';
import 'package:extrahelper/features/pos/checkout_customer_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Picking a guest who has been in before.
///
/// The point of the picker is the id: `attach_bill_customer` finds someone
/// again only by phone, so a guest saved with a name and no number would come
/// back as a duplicate every visit. A picked row must therefore travel out as
/// [PickCustomerAction], never as a name-and-phone attach.

const _billId = 'bill-1111-2222-3333-444444444444';

BillSnapshot _snapshot({BillCustomer? customer}) => BillSnapshot(
  bill: Bill(
    id: _billId,
    status: 'open',
    createdAt: DateTime(2026, 8, 20),
    subtotalCents: 45000,
    taxCents: 0,
    serviceChargeCents: 0,
    discountCents: 0,
    tipCents: 0,
    roundingCents: 0,
    totalCents: 45000,
    tableLabel: 'A1',
  ),
  lines: const [],
  payments: const [],
  charges: const [],
  discounts: const [],
  settings: const TenantMoneySettings(),
  customer: customer,
);

const _book = [
  CustomerHit(id: 'c1', name: 'Rita Gurung', phone: '9800000001', points: 120),
  CustomerHit(id: 'c2', name: 'Bikash', points: 0),
];

Future<CustomerAction?> _open(
  WidgetTester tester, {
  BillCustomer? customer,
  Future<List<CustomerHit>> Function(String)? search,
  List<String>? queries,
  Future<void> Function()? act,
}) async {
  CustomerAction? action;

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              action = await showCustomerSheet(
                context: context,
                snapshot: _snapshot(customer: customer),
                currency: 'NPR',
                search:
                    search ??
                    (q) async {
                      queries?.add(q);
                      if (q.isEmpty) return _book;
                      return _book
                          .where(
                            (c) => c.label.toLowerCase().contains(
                              q.toLowerCase(),
                            ),
                          )
                          .toList();
                    },
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  if (act != null) {
    await act();
    await tester.pumpAndSettle();
  }
  return action;
}

void main() {
  testWidgets('the book is listed as soon as the sheet opens', (tester) async {
    await _open(tester);

    expect(find.text('Rita Gurung'), findsOneWidget);
    expect(find.text('Bikash'), findsOneWidget);
  });

  testWidgets('typing narrows the list', (tester) async {
    final queries = <String>[];
    await _open(
      tester,
      queries: queries,
      act: () => tester.enterText(find.byType(TextField).first, 'rita'),
    );

    expect(queries, contains('rita'));
    expect(find.text('Rita Gurung'), findsOneWidget);
    expect(find.text('Bikash'), findsNothing);
  });

  testWidgets('a picked guest travels out by id', (tester) async {
    final action = await _open(
      tester,
      act: () => tester.tap(find.text('Bikash')),
    );

    expect(action, isA<PickCustomerAction>());
    expect((action! as PickCustomerAction).customerId, 'c2');
  });

  testWidgets('an empty book says so rather than showing nothing', (
    tester,
  ) async {
    await _open(tester, search: (_) async => const []);

    expect(find.text('Nobody by that name or number yet.'), findsOneWidget);
  });

  testWidgets('a bill that already has a guest shows no picker', (
    tester,
  ) async {
    await _open(
      tester,
      customer: const BillCustomer(id: 'c1', name: 'Rita Gurung', points: 120),
    );

    expect(find.text('Search guests'), findsNothing);
    expect(find.text('Loyalty points'), findsOneWidget);
  });

  testWidgets('with no search wired in, the manual fields still work', (
    tester,
  ) async {
    CustomerAction? action;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                action = await showCustomerSheet(
                  context: context,
                  snapshot: _snapshot(),
                  currency: 'NPR',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Search guests'), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'Walk-in Sita');
    await tester.tap(find.text('Attach guest'));
    await tester.pumpAndSettle();
    // One more pump: the sheet's future resolves a microtask after it pops.
    await tester.pumpAndSettle();

    expect(action, isA<AttachCustomerAction>());
    expect((action! as AttachCustomerAction).name, 'Walk-in Sita');
  });
}
