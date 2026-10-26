import 'package:extrahelper/data/supabase/tenant_repository.dart';
import 'package:extrahelper/data/sync/sync_providers.dart';
import 'package:extrahelper/features/pos/models.dart';
import 'package:extrahelper/features/pos/pos_providers.dart';
import 'package:extrahelper/features/tables_admin/tables_admin_screen.dart';
import 'package:extrahelper/features/tenant/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Tables extends TablesNotifier {
  _Tables(this.rows, {this.fail = false});
  final List<PosTable> rows;
  final bool fail;

  @override
  Future<List<PosTable>> build() async {
    if (fail) throw Exception('boom');
    return rows;
  }
}

class _Floors extends FloorsNotifier {
  @override
  Future<List<PosFloor>> build() async => const [
    PosFloor(id: 'f1', name: 'Rooftop', sort: 0),
  ];
}

const _tables = [
  PosTable(
    id: 'a',
    label: 'T1',
    capacity: 4,
    state: 'free',
    floorId: 'f1',
    qrToken: 'tok1',
  ),
  PosTable(id: 'b', label: 'T2', capacity: 2, state: 'occupied'),
];

Widget _app({
  required Set<String> permissions,
  List<PosTable> tables = _tables,
  bool fail = false,
  String role = 'waiter',
}) {
  return ProviderScope(
    overrides: [
      membershipsProvider.overrideWith(
        (ref) => [
          Membership(
            tenantId: 't1',
            name: 'The Sekuwa Station',
            slug: 'sekuwa',
            role: role,
            currency: 'NPR',
            timezone: 'Asia/Kathmandu',
          ),
        ],
      ),
      permissionsProvider.overrideWith((ref) => permissions),
      isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      tablesProvider.overrideWith(() => _Tables(tables, fail: fail)),
      floorsProvider.overrideWith(_Floors.new),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, _) => const TablesAdminScreen()),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('tables are grouped by floor with a state chip', (tester) async {
    await tester.pumpWidget(_app(permissions: const {'tables.view'}));
    await tester.pumpAndSettle();
    expect(find.text('Rooftop'), findsOneWidget);
    expect(find.text('No floor'), findsOneWidget);
    expect(find.text('T1'), findsOneWidget);
    expect(find.text('Free'), findsOneWidget);
    expect(find.text('Occupied'), findsOneWidget);
    expect(find.text('QR'), findsNWidgets(2));
  });

  testWidgets('edit controls are hidden without tables.edit', (tester) async {
    await tester.pumpWidget(_app(permissions: const {'tables.view'}));
    await tester.pumpAndSettle();
    expect(find.text('Add table'), findsNothing);
    expect(find.text('Add floor'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('tables.edit shows add and delete', (tester) async {
    await tester.pumpWidget(
      _app(permissions: const {'tables.view', 'tables.edit'}),
    );
    await tester.pumpAndSettle();
    expect(find.text('Add table'), findsOneWidget);
    expect(find.text('Add floor'), findsOneWidget);
    expect(find.text('Delete'), findsNWidgets(2));
  });

  testWidgets('delete warns the printed QR will stop working', (tester) async {
    await tester.pumpWidget(
      _app(permissions: const {'tables.view', 'tables.edit'}),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('will stop working'), findsOneWidget);
  });

  testWidgets('without tables.view it shows the locked door', (tester) async {
    await tester.pumpWidget(_app(permissions: const {}));
    await tester.pumpAndSettle();
    expect(find.text('No tables access'), findsOneWidget);
    expect(find.text('T1'), findsNothing);
  });

  testWidgets('empty list teaches the next step', (tester) async {
    await tester.pumpWidget(
      _app(permissions: const {'tables.view', 'tables.edit'}, tables: const []),
    );
    await tester.pumpAndSettle();
    expect(find.text('No tables yet'), findsOneWidget);
  });

  testWidgets('a failed load offers a retry', (tester) async {
    await tester.pumpWidget(
      _app(permissions: const {'tables.view'}, fail: true),
    );
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load the tables."), findsOneWidget);
  });
}
