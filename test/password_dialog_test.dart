import 'dart:math';

import 'package:extrahelper/data/supabase/team_repository.dart';
import 'package:extrahelper/features/team/password_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A password typed here is told across a counter, so what the dialog
/// accepts is what the server accepts, and what it generates can be read
/// aloud without "is that a zero or an O".

Widget _host({required bool create, required ValueChanged<String?> onDone}) =>
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () async {
                final p = await showPasswordDialog(
                  context,
                  email: 'cook@sekuwa.co',
                  create: create,
                );
                onDone(p);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

void main() {
  group('passwordProblem', () {
    test('mirrors the web: length 8–72, letters and numbers', () {
      expect(passwordProblem('abc1234'), 'Use at least 8 characters.');
      expect(
        passwordProblem('a' * 72 + '1'),
        'Keep it to 72 characters or fewer.',
      );
      expect(passwordProblem('abcdefgh'), 'Mix letters and numbers.');
      expect(passwordProblem('12345678'), 'Mix letters and numbers.');
      expect(passwordProblem('abcd-2345-wxyz'), isNull);
    });
  });

  group('generatePassword', () {
    test('is xxxx-2345-xxxx with no look-alike characters', () {
      final p = generatePassword(Random(7));
      expect(p, matches(RegExp(r'^[a-z]{4}-[0-9]{4}-[a-z]{4}$')));
      expect(p, isNot(contains(RegExp('[01lIoO]'))));
      expect(passwordProblem(p), isNull);
    });
  });

  testWidgets('the button waits for 8 characters and hands back the text', (
    tester,
  ) async {
    String? out;
    await tester.pumpWidget(_host(create: false, onDone: (p) => out = p));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Set a new password'), findsOneWidget);
    expect(find.textContaining('old password stops working'), findsOneWidget);
    FilledButton button() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Set password'),
    );
    expect(button().onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'abcdefgh');
    await tester.pumpAndSettle();
    expect(button().onPressed, isNotNull);

    // Long enough but no digit: refused here with the server's sentence.
    await tester.tap(find.text('Set password'));
    await tester.pumpAndSettle();
    expect(find.text('Mix letters and numbers.'), findsOneWidget);
    expect(out, isNull);

    await tester.enterText(find.byType(TextField), 'abcd2345');
    await tester.tap(find.text('Set password'));
    await tester.pumpAndSettle();
    expect(out, 'abcd2345');
  });

  testWidgets('Generate one fills a valid password and shows it', (
    tester,
  ) async {
    String? out;
    await tester.pumpWidget(_host(create: true, onDone: (p) => out = p));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Create login'), findsWidgets);
    await tester.tap(find.text('Generate one'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.obscureText, isFalse);
    expect(
      field.controller!.text,
      matches(RegExp(r'^[a-z]{4}-[0-9]{4}-[a-z]{4}$')),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Create login'));
    await tester.pumpAndSettle();
    expect(out, field.controller!.text);
  });
}
