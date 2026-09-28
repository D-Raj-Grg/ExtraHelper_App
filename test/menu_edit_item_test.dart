import 'package:extrahelper/data/supabase/menu_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a dish row carries photo, category, veg mark, station and stock', () {
    final item = MenuEditItem.fromJson({
      'id': 'i1',
      'name': 'Buff Sekuwa',
      'base_price_cents': 45000,
      'is_86': true,
      'category_id': 'c1',
      'description': '  Grilled on charcoal  ',
      'image_url': 'https://x/menu-images/t/i1.jpg?v=1',
      'is_veg': false,
      'menu_categories': {'name': 'Grill'},
      'item_station_routes': [
        {'station_id': 's1'},
      ],
      'item_modifiers': [
        {'modifier_id': 'm1', 'is_default': false, 'max_qty': 2},
      ],
      'item_availability': [
        {
          'id': 'a2',
          'day_of_week': 6,
          'start_time': '18:00:00',
          'end_time': '22:00:00',
        },
        {
          'id': 'a1',
          'day_of_week': null,
          'start_time': '07:00:00',
          'end_time': '11:00:00',
        },
      ],
      'item_variants': <Map<String, dynamic>>[],
    });
    expect(item.is86, isTrue);
    expect(item.categoryId, 'c1');
    expect(item.categoryName, 'Grill');
    expect(item.description, 'Grilled on charcoal');
    expect(item.imageUrl, contains('i1.jpg'));
    expect(item.isVeg, isFalse);
    expect(item.stationIds, ['s1']);
    expect(item.addOns.single.maxQty, 2);
    // Every-day windows sort first, then by day.
    expect(item.availability.map((a) => a.id), ['a1', 'a2']);
    expect(item.availability.first.dayLabel, 'Every day');
    expect(item.availability.last.window, '18:00–22:00');
  });

  test('unmarked veg stays null and a blank description is none', () {
    final item = MenuEditItem.fromJson({
      'id': 'i2',
      'name': 'Tea',
      'base_price_cents': 5000,
      'description': '   ',
      'item_station_routes': <Map<String, dynamic>>[],
    });
    expect(item.isVeg, isNull);
    expect(item.description, isNull);
    expect(item.stationIds, isEmpty);
    expect(item.addOns, isEmpty);
    expect(item.availability, isEmpty);
    expect(item.is86, isFalse);
  });

  test('cost price is read when present, on the dish and its sizes', () {
    final item = MenuEditItem.fromJson({
      'id': 'i3',
      'name': 'Buff Sekuwa',
      'base_price_cents': 45000,
      'menu_item_costs': {'cost_cents': 18000},
      'item_variants': [
        {
          'id': 'v1',
          'name': 'Half',
          'price_delta_cents': -20000,
          'sort': 0,
          'item_variant_costs': {'cost_cents': 9000},
        },
        {
          'id': 'v2',
          'name': 'Full',
          'price_delta_cents': 0,
          'sort': 1,
          // The row exists but the cost was cleared.
          'item_variant_costs': {'cost_cents': null},
        },
      ],
    });
    expect(item.costCents, 18000);
    expect(item.variants.first.costCents, 9000);
    expect(item.variants.last.costCents, isNull);
  });

  test('cost embed hidden by RLS (no profit.view) is null, never 0', () {
    final item = MenuEditItem.fromJson({
      'id': 'i4',
      'name': 'Tea',
      'base_price_cents': 5000,
      'menu_item_costs': null,
      'item_variants': [
        {
          'id': 'v1',
          'name': 'Small',
          'price_delta_cents': 0,
          'sort': 0,
          'item_variant_costs': null,
        },
      ],
    });
    expect(item.costCents, isNull);
    expect(item.variants.single.costCents, isNull);
  });

  test('cost embed absent from the select is null too', () {
    final item = MenuEditItem.fromJson({
      'id': 'i5',
      'name': 'Tea',
      'base_price_cents': 5000,
      'item_variants': [
        {'id': 'v1', 'name': 'Small', 'price_delta_cents': 0, 'sort': 0},
      ],
    });
    expect(item.costCents, isNull);
    expect(item.variants.single.costCents, isNull);
  });

  test('a draft leaves the cost alone unless it was set', () {
    const untouched = MenuItemDraft(name: 'Tea', basePriceCents: 5000);
    expect(untouched.costSet, isFalse);
    expect(untouched.costCents, isNull);

    const cleared = MenuItemDraft(
      name: 'Tea',
      basePriceCents: 5000,
      costSet: true,
    );
    expect(cleared.costSet, isTrue);
    expect(cleared.costCents, isNull, reason: 'set + null clears the cost');
  });

  test('a combo keeps its dishes and quantities, skipping malformed rows', () {
    final c = MenuCombo.fromJson({
      'id': 'k1',
      'name': 'Lunch set',
      'price_cents': 30000,
      'is_active': false,
      'items': [
        {'item_id': 'i1', 'qty': 2},
        {'qty': 1},
      ],
    });
    expect(c.items, [(itemId: 'i1', qty: 2)]);
    expect(c.isActive, isFalse);
  });
}
