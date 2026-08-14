import 'package:extrahelper/features/pos/void_reason_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reproduces the crash seen on the emulator: dismissing the void-reason
/// dialog blew the whole app away with
/// `'_dependents.isEmpty': is not true` (framework.dart, InheritedElement).
///
/// The pattern under test is the one `_askVoidReason` used: a controller owned
/// by the *caller*, disposed the moment `showDialog` resolves. The dialog's
/// `TextField` is still mounted for one more frame at that point, so its
/// `dispose()` touches a dead controller, the element never finishes
/// deactivating, and the InheritedElements above it assert.
void main() {
  testWidgets('dismissing a dialog that owns its reason field is clean', (
    tester,
  ) async {
    String? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showVoidReasonDialog(
                  context: context,
                  title: 'Void this line?',
                  body: '1 × Tuborg is already with the kitchen.',
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
    expect(find.text('Void this line?'), findsOneWidget);

    // Type something, then back out — the caret path is the one that crashed.
    await tester.enterText(find.byType(TextField), 'guest changed their mind');
    await tester.pump();
    await tester.tap(find.text('Keep it'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(result, isNull);
    expect(find.text('Void this line?'), findsNothing);
  });

  testWidgets('confirming returns the trimmed reason', (tester) async {
    String? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showVoidReasonDialog(
                  context: context,
                  title: 'Void this line?',
                  body: 'body',
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
    await tester.enterText(find.byType(TextField), '  spilled  ');
    await tester.pump();
    await tester.tap(find.text('Void line'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(result, 'spilled');
  });

  testWidgets('an empty reason cannot be submitted', (tester) async {
    var closed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                await showVoidReasonDialog(
                  context: context,
                  title: 'Void this line?',
                  body: 'body',
                );
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Void line'));
    await tester.pumpAndSettle();

    expect(closed, isFalse);
    expect(find.text('Void this line?'), findsOneWidget);
  });
}
