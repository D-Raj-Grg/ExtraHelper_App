import 'package:extrahelper/features/pos/models.dart';
import 'package:extrahelper/features/tables_admin/add_table_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<TableDraft?> Function() _open(WidgetTester tester) {
  TableDraft? result;
  var done = false;
  return () async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showAddTableSheet(
                  context,
                  floors: const [PosFloor(id: 'f1', name: 'Rooftop', sort: 0)],
                );
                done = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(done, isFalse);
    return result;
  };
}

void main() {
  testWidgets('empty label is refused and the sheet stays open', (
    tester,
  ) async {
    await _open(tester)();
    await tester.tap(find.widgetWithText(FilledButton, 'Add table'));
    await tester.pumpAndSettle();
    expect(find.text('Add table'), findsWidgets);
    expect(find.byType(AddTableSheet), findsOneWidget);
  });

  testWidgets('stepper clamps at 1 and 50', (tester) async {
    await _open(tester)();
    for (var i = 0; i < 60; i++) {
      await tester.tap(find.byTooltip('More seats'));
    }
    await tester.pump();
    expect(find.text('50'), findsOneWidget);
    for (var i = 0; i < 60; i++) {
      await tester.tap(find.byTooltip('Fewer seats'));
    }
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('a valid draft pops with label, seats and floor', (tester) async {
    TableDraft? got;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => got = await showAddTableSheet(
              context,
              floors: const [PosFloor(id: 'f1', name: 'Rooftop', sort: 0)],
              initialFloorId: 'f1',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'T9');
    await tester.tap(find.byTooltip('More seats'));
    await tester.tap(find.widgetWithText(FilledButton, 'Add table'));
    await tester.pumpAndSettle();
    expect(got?.label, 'T9');
    expect(got?.capacity, 5);
    expect(got?.floorId, 'f1');
  });
}
