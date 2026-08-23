import 'package:extrahelper/data/supabase/danger_repository.dart';
import 'package:extrahelper/data/supabase/tenant_repository.dart';
import 'package:extrahelper/features/settings/confirm_phrase_dialog.dart';
import 'package:extrahelper/features/settings/danger_domains.dart';
import 'package:extrahelper/features/settings/danger_reset_screen.dart';
import 'package:extrahelper/features/settings/danger_screen.dart';
import 'package:extrahelper/features/settings/settings_providers.dart';
import 'package:extrahelper/features/tenant/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// The dangerous area.
///
/// Every RPC behind it re-checks owner inside its own body, so none of this is
/// the security boundary. What is tested here is that the guard in front of an
/// irreversible action actually holds: the button stays dead until the
/// restaurant's name has been typed out.

Membership _member(String role) => Membership(
  tenantId: 't1',
  name: 'The Sekuwa Station',
  slug: 'sekuwa',
  role: role,
  currency: 'NPR',
  timezone: 'Asia/Kathmandu',
);

DangerData _danger({DateTime? scheduled}) => DangerData(
  planLabel: 'Pro Trial',
  usage: const ResourceUsage(
    customers: 42,
    tables: 12,
    staff: 5,
    menuItems: 88,
    tablesLimit: 20,
  ),
  members: const [
    TransferMember(
      userId: 'u2',
      email: 'manager@sekuwa.test',
      roleName: 'Manager',
    ),
  ],
  deletionScheduledAt: scheduled,
);

Widget _harness({
  required Widget child,
  String role = 'owner',
  DangerData? data,
}) => ProviderScope(
  overrides: [
    membershipsProvider.overrideWith((ref) => [_member(role)]),
    permissionsProvider.overrideWith(
      (ref) => const {'settings.view', 'settings.edit'},
    ),
    dangerDataProvider.overrideWith((ref) async => data ?? _danger()),
  ],
  child: MaterialApp.router(
    routerConfig: GoRouter(
      initialLocation: '/',
      routes: [GoRoute(path: '/', builder: (_, _) => child)],
    ),
  ),
);

void main() {
  group('phraseMatches', () {
    test('exact, trimmed and case-insensitive all count', () {
      expect(phraseMatches('Sekuwa', 'Sekuwa'), isTrue);
      expect(phraseMatches('  sekuwa  ', 'Sekuwa'), isTrue);
      expect(phraseMatches('SEKUWA', 'sekuwa'), isTrue);
    });

    test('close is not close enough', () {
      expect(phraseMatches('Sekuw', 'Sekuwa'), isFalse);
      expect(phraseMatches('', 'Sekuwa'), isFalse);
      expect(phraseMatches('the sekuwa station', 'Sekuwa'), isFalse);
    });
  });

  group('the confirm phrase guard', () {
    testWidgets('the button is dead until the name is typed', (tester) async {
      var confirmed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  confirmed = await showConfirmPhraseDialog(
                    context,
                    title: 'Delete it?',
                    message: 'Everything goes.',
                    phrase: 'Sekuwa',
                    phraseHint: 'the restaurant name',
                    confirmLabel: 'Delete restaurant',
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

      final button = find.widgetWithText(FilledButton, 'Delete restaurant');
      expect(tester.widget<FilledButton>(button).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'Sekuw');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(button).onPressed, isNull);

      await tester.enterText(find.byType(TextField), '  sekuwa ');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(confirmed, isTrue);
    });

    testWidgets('cancelling means no', (tester) async {
      var confirmed = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  confirmed = await showConfirmPhraseDialog(
                    context,
                    title: 'Delete it?',
                    message: 'Everything goes.',
                    phrase: 'Sekuwa',
                    phraseHint: 'the restaurant name',
                    confirmLabel: 'Delete restaurant',
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
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(confirmed, isFalse);
    });
  });

  group('the dangerous area', () {
    testWidgets('an owner gets all three actions and the usage', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(child: const DangerScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Pro Trial'), findsOneWidget);
      // A trial has no ceiling on customers, but tables carries one.
      expect(find.text('42'), findsOneWidget);
      expect(find.text('12 of 20'), findsOneWidget);
      expect(find.text('Reset restaurant'), findsOneWidget);
      expect(find.text('Transfer ownership'), findsOneWidget);
      expect(find.text('Delete restaurant'), findsOneWidget);
    });

    testWidgets('a manager cannot stand here at all', (tester) async {
      await tester.pumpWidget(
        _harness(child: const DangerScreen(), role: 'manager'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Only the owner can open this.'), findsOneWidget);
      expect(find.text('Reset restaurant'), findsNothing);
    });

    testWidgets('a pending deletion shows the clock and the way out', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          child: const DangerScreen(),
          data: _danger(scheduled: DateTime(2026, 9, 1, 10)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Scheduled for deletion'), findsOneWidget);
      expect(find.text('Cancel deletion'), findsOneWidget);
      // Asking to delete something already scheduled is not a second thing
      // that can happen.
      expect(find.text('Delete restaurant'), findsNothing);
    });
  });

  group('reset', () {
    testWidgets('nothing selected means the button stays dead', (tester) async {
      await tester.pumpWidget(_harness(child: const DangerResetScreen()));
      await tester.pumpAndSettle();

      final button = find.widgetWithText(FilledButton, 'Reset it!');
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
    });

    testWidgets('picking an area arms it', (tester) async {
      await tester.pumpWidget(_harness(child: const DangerResetScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();

      expect(find.text('1 of ${resetDomains.length} selected'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Reset it!'))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('"reset everything" takes over the individual choices', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(child: const DangerResetScreen()));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Reset everything'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Reset everything'));
      await tester.pumpAndSettle();

      expect(find.text('Everything selected'), findsOneWidget);
      // Every individual row is ticked and frozen — still readable, so the
      // list still says what is about to go. Checked by label rather than by
      // position: the list is lazy, and after a scroll the built tiles are not
      // the first eleven.
      for (final domain in resetDomains) {
        final row = find.ancestor(
          of: find.text(domain.label),
          matching: find.byType(CheckboxListTile),
        );
        if (row.evaluate().isEmpty) continue;
        final tile = tester.widget<CheckboxListTile>(row);
        expect(tile.value, isTrue, reason: domain.label);
        expect(tile.onChanged, isNull, reason: domain.label);
      }
    });

    testWidgets('the reset confirm asks for the restaurant name', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(child: const DangerResetScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Reset it!'));
      await tester.pumpAndSettle();

      expect(find.text('Reset The Sekuwa Station?'), findsOneWidget);
      expect(find.textContaining('the restaurant name'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Reset now'))
            .onPressed,
        isNull,
      );
    });
  });

  group('the reset domain catalog', () {
    test('is the same eleven the web wipes, by the same keys', () {
      expect(resetDomains, hasLength(11));
      expect(resetDomains.map((d) => d.key), [
        'menu',
        'tables',
        'finance',
        'space',
        'customers',
        'suppliers',
        'inventory',
        'website',
        'staff',
        'orders',
        'activity',
      ]);
      expect(resetEverything, 'everything');
    });
  });
}
