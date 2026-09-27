import 'package:extrahelper/data/supabase/expenses_repository.dart';
import 'package:extrahelper/features/expenses/expense_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _categories = [
  ExpenseCategory(id: 'c-food', name: 'Food'),
  ExpenseCategory(id: 'c-repairs', name: 'Repairs'),
  ExpenseCategory(id: 'c-other', name: 'Other'),
];

Widget _host({List<ExpenseCategory> categories = _categories}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: FilledButton(
            onPressed: () => showExpenseSheet(
              context,
              categories: categories,
              currency: 'NPR',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('the category dropdown opens on Other', (tester) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The dropdown shows its selected value as text; "Other" is the pick.
    expect(find.text('Other'), findsOneWidget);
    expect(find.text('Food'), findsNothing);
  });

  testWidgets('without an Other category the first one is picked', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        categories: const [
          ExpenseCategory(id: 'a', name: 'Gas'),
          ExpenseCategory(id: 'b', name: 'Ice'),
        ],
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Gas'), findsOneWidget);
    expect(find.text('Ice'), findsNothing);
  });

  testWidgets('the close icon dismisses the sheet', (tester) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Log an expense'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Log an expense'), findsNothing);
  });
}
