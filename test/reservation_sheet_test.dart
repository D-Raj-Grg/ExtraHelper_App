import 'package:extrahelper/data/supabase/tenant_repository.dart';
import 'package:extrahelper/data/sync/sync_providers.dart';
import 'package:extrahelper/features/pos/models.dart';
import 'package:extrahelper/features/pos/pos_providers.dart';
import 'package:extrahelper/features/reservations/reservation_sheet.dart';
import 'package:extrahelper/features/tenant/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoTables extends TablesNotifier {
  @override
  Future<List<PosTable>> build() async => const [];
}

Widget _app() => ProviderScope(
  overrides: [
    membershipsProvider.overrideWith(
      (ref) => [
        Membership(
          tenantId: 't1',
          name: 'The Sekuwa Station',
          slug: 'sekuwa',
          role: 'manager',
          currency: 'NPR',
          timezone: 'Asia/Kathmandu',
        ),
      ],
    ),
    isOnlineProvider.overrideWith((ref) => Stream.value(true)),
    tablesProvider.overrideWith(_NoTables.new),
  ],
  child: MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showReservationSheet(context),
          child: const Text('open'),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('a blank name is refused with a message', (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add reservation'));
    await tester.pumpAndSettle();
    expect(find.text("Enter the guest's name."), findsOneWidget);
    expect(find.text('New reservation'), findsOneWidget);
  });

  testWidgets('party size stepper stays within 1 to 50', (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.byTooltip('Fewer guests'));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
    final minus = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.remove),
    );
    expect(minus.onPressed, isNull);
  });
}
