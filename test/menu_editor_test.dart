import 'package:extrahelper/data/supabase/menu_repository.dart';
import 'package:extrahelper/data/supabase/tenant_repository.dart';
import 'package:extrahelper/features/menu/item_variants_screen.dart';
import 'package:extrahelper/features/menu/menu_providers.dart';
import 'package:extrahelper/features/menu/variant_sheet.dart';
import 'package:extrahelper/features/tenant/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The menu editor on the phone.
///
/// The server is the boundary — `menu.edit` is checked by the RPCs *and* by the
/// table policies. These tests are about not offering a door that is locked,
/// and about the two things a wrong pixel here costs real money: a variant priced
/// the wrong way round, and an order the kitchen reads in the wrong order.

const _itemId = 'item-1111-2222-3333-444444444444';

MenuEditItem _item({List<MenuEditVariant> variants = const []}) => MenuEditItem(
  id: _itemId,
  name: 'Buff Sekuwa',
  basePriceCents: 0,
  variants: variants,
  categoryName: 'Grill',
);

const _small = MenuEditVariant(
  id: 'v1',
  name: '250 gm',
  priceDeltaCents: 35000,
  sort: 1,
);
const _large = MenuEditVariant(
  id: 'v2',
  name: '1 Kg',
  priceDeltaCents: 110000,
  sort: 2,
);

Widget _harness({
  required Set<String> permissions,
  List<MenuEditVariant> variants = const [_small, _large],
}) => ProviderScope(
  overrides: [
    membershipsProvider.overrideWith(
      (ref) => [
        const Membership(
          tenantId: 't1',
          name: 'The Sekuwa Station',
          slug: 'sekuwa',
          role: 'owner',
          currency: 'NPR',
          timezone: 'Asia/Kathmandu',
        ),
      ],
    ),
    permissionsProvider.overrideWith((ref) => permissions),
    menuEditItemsProvider.overrideWith(
      (ref) async => [_item(variants: variants)],
    ),
  ],
  child: const MaterialApp(home: ItemVariantsScreen(itemId: _itemId)),
);

void main() {
  group('who gets the controls', () {
    testWidgets('menu.edit gets edit, reorder and remove', (tester) async {
      await tester.pumpWidget(
        _harness(permissions: const {'menu.view', 'menu.edit'}),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Edit 250 gm'), findsOneWidget);
      expect(find.byTooltip('Remove 250 gm'), findsOneWidget);
      expect(find.text('Add variant'), findsOneWidget);
      expect(find.textContaining('not change them'), findsNothing);
    });

    testWidgets('menu.view alone gets a read-only screen', (tester) async {
      await tester.pumpWidget(_harness(permissions: const {'menu.view'}));
      await tester.pumpAndSettle();

      // The variants are still worth seeing — a manager checking a price should
      // not have to be able to change it.
      expect(find.text('250 gm'), findsOneWidget);
      expect(find.byTooltip('Edit 250 gm'), findsNothing);
      expect(find.byTooltip('Remove 250 gm'), findsNothing);
      expect(find.text('Add variant'), findsNothing);
      expect(find.textContaining('not change them'), findsOneWidget);
    });
  });

  group('reordering', () {
    testWidgets('the ends of the list have nowhere to go', (tester) async {
      await tester.pumpWidget(
        _harness(permissions: const {'menu.view', 'menu.edit'}),
      );
      await tester.pumpAndSettle();

      // The Tooltip lives *inside* IconButton, so byTooltip finds the wrapper
      // and not the button — match on the icon instead.
      IconButton button(IconData icon, int row) => tester
          .widgetList<IconButton>(find.widgetWithIcon(IconButton, icon))
          .elementAt(row);

      // First row: up is dead, down is live. Last row: the reverse.
      expect(button(Icons.keyboard_arrow_up, 0).onPressed, isNull);
      expect(button(Icons.keyboard_arrow_down, 0).onPressed, isNotNull);
      expect(button(Icons.keyboard_arrow_up, 1).onPressed, isNotNull);
      expect(button(Icons.keyboard_arrow_down, 1).onPressed, isNull);
    });
  });

  group('removing a variant', () {
    testWidgets('asks first, and names what is actually lost', (tester) async {
      await tester.pumpWidget(
        _harness(permissions: const {'menu.view', 'menu.edit'}),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Remove 250 gm'));
      await tester.pumpAndSettle();

      expect(find.text('Remove 250 gm?'), findsOneWidget);
      // Not "are you sure": deleting nulls order_items.variant_id, so history
      // forgets which variant was sold. Renaming does not.
      expect(find.textContaining('Past orders'), findsOneWidget);

      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      expect(find.text('250 gm'), findsOneWidget);
    });
  });

  group('the empty state teaches the next step', () {
    testWidgets('no variants says what a variant is for', (tester) async {
      await tester.pumpWidget(
        _harness(
          permissions: const {'menu.view', 'menu.edit'},
          variants: const [],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No variants'), findsOneWidget);
      expect(find.textContaining('base price'), findsOneWidget);
    });
  });

  group('the variant sheet', () {
    testWidgets('"Less" makes the change negative, and says the real price', (
      tester,
    ) async {
      VariantDraft? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await showVariantSheet(
                      context,
                      itemName: 'Buff Sekuwa',
                      basePriceCents: 60000,
                      currency: 'NPR',
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Half');
      await tester.enterText(find.byType(TextField).last, '200');
      await tester.pumpAndSettle();
      expect(find.text('Sells for NPR 800.00'), findsOneWidget);

      // A Half costs less than the whole dish. The sign is a tap, not a minus
      // someone has to remember to type on a phone keyboard.
      await tester.tap(find.text('Less'));
      await tester.pumpAndSettle();
      expect(find.text('Sells for NPR 400.00'), findsOneWidget);

      await tester.tap(find.text('Add variant'));
      await tester.pumpAndSettle();

      expect(result?.name, 'Half');
      expect(result?.priceDeltaCents, -20000);
    });

    testWidgets('a nameless variant cannot be saved', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showVariantSheet(
                    context,
                    itemName: 'Buff Sekuwa',
                    basePriceCents: 60000,
                    currency: 'NPR',
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });
  });

  group('the row the server sends', () {
    test('variants come back in the owner\'s order, not price order', () {
      // Half is cheaper than KG but the owner put it last — price order is
      // exactly the wrong answer, and it is what the app did before `sort`.
      final item = MenuEditItem.fromJson({
        'id': _itemId,
        'name': 'Buff Sekuwa',
        'base_price_cents': 0,
        'item_variants': [
          {'id': 'a', 'name': 'Half', 'price_delta_cents': 0, 'sort': 2},
          {'id': 'b', 'name': 'KG', 'price_delta_cents': 130000, 'sort': 1},
        ],
      });

      expect(item.variants.map((v) => v.name), ['KG', 'Half']);
    });

    test('rows written before sort existed fall back to price order', () {
      final item = MenuEditItem.fromJson({
        'id': _itemId,
        'name': 'Buff Sekuwa',
        'base_price_cents': 0,
        'item_variants': [
          {'id': 'a', 'name': 'KG', 'price_delta_cents': 130000},
          {'id': 'b', 'name': 'Half', 'price_delta_cents': 0},
        ],
      });

      expect(item.variants.map((v) => v.name), ['Half', 'KG']);
    });
  });
}
