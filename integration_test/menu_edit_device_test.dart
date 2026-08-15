import 'package:extrahelper/app/app.dart';
import 'package:extrahelper/core/env.dart';
import 'package:extrahelper/data/local/database.dart';
import 'package:extrahelper/data/print/print_providers.dart';
import 'package:extrahelper/data/supabase/pos_repository.dart';
import 'package:extrahelper/data/sync/sync_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The on-device pass for the menu editor.
///
/// The widget suite proves what is drawn from a fixture; this proves the whole
/// path — a real build, a real session, real RPCs, real RLS — and that the
/// **till agrees with the editor**, which is the thing that costs money if it
/// is wrong.
///
/// Run against a throwaway tenant, never a real one:
///
///   flutter test integration_test/menu_edit_device_test.dart -d DEVICE \
///     --dart-define-from-file=env.json \
///     --dart-define=TEST_EMAIL=... --dart-define=TEST_PASSWORD=...
const _email = String.fromEnvironment('TEST_EMAIL');
const _password = String.fromEnvironment('TEST_PASSWORD');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an owner reorders a size, and the till follows', (tester) async {
    expect(
      _email.isNotEmpty && _password.isNotEmpty,
      isTrue,
      reason: 'pass TEST_EMAIL and TEST_PASSWORD as --dart-define',
    );

    Env.assertConfigured();
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabasePublishableKey,
    );
    // Sign in before the first frame so the router's redirect resolves to the
    // POS rather than bouncing through the login screen.
    await Supabase.instance.client.auth.signInWithPassword(
      email: _email,
      password: _password,
    );

    final db = await openAppDatabase();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const SyncLoop(child: PrintLoop(child: ExtraHelperApp())),
      ),
    );

    // Memberships, permissions and the menu are all network reads on a cold
    // start; settle in steps rather than one long pumpAndSettle, which times
    // out against a real backend.
    Future<void> settle([int rounds = 30]) async {
      for (var i = 0; i < rounds; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    await settle();

    // Drawer → Menu.
    final drawerButton = find.byTooltip('Open navigation menu');
    expect(drawerButton, findsWidgets, reason: 'the app never reached a shell');
    await tester.tap(drawerButton.first);
    await settle(10);
    await tester.tap(find.text('Menu'));
    await settle(20);

    // The dish, then its sizes.
    expect(find.text('Buff Sekuwa'), findsWidgets);
    await tester.tap(find.text('Buff Sekuwa').first);
    await settle(20);

    List<String> sizesOnScreen() => tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.title as Text?)?.data ?? '')
        .where((s) => s.isNotEmpty)
        .toList();

    final before = sizesOnScreen();
    expect(before.length, greaterThanOrEqualTo(2));

    // Move the first size down and wait for the refreshed list.
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down).first);
    await settle(20);

    final after = sizesOnScreen();
    expect(
      after.first,
      before[1],
      reason: 'the row that was second should now be first',
    );
    expect(after.toSet(), before.toSet(), reason: 'nothing else changed');

    // Now the till. The POS board shows orders, not dishes — a waiter reaches
    // the menu by starting one — so the check that matters is the till's own
    // read path, run here against the same live session: if `PosRepository`
    // came back in a different order, the phone would offer the sizes one way
    // in the editor and another at the till.
    final client = Supabase.instance.client;
    final membership = await client
        .from('user_tenants')
        .select('tenant_id')
        .limit(1)
        .single();
    final tillMenu = await PosRepository(
      client,
      membership['tenant_id'] as String,
    ).menu();
    final dish = tillMenu.firstWhere((i) => i.name == 'Buff Sekuwa');

    expect(
      dish.variants.map((v) => v.name).toList(),
      after,
      reason: "the till lists the sizes in the editor's order",
    );
  });
}
