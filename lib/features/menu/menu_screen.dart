import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_scaffold.dart';
import '../../core/format/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/dish_thumb.dart';
import '../../core/widgets/veg_mark.dart';
import '../../data/supabase/menu_repository.dart';
import '../tenant/tenant_providers.dart';
import 'combos_screen.dart';
import 'item_addons_screen.dart';
import 'item_edit_screen.dart';
import 'menu_categories_screen.dart';
import 'menu_providers.dart';
import 'stock_toggle.dart';

/// The menu, on a phone: find a dish, mark it sold out or back in stock, add
/// or change one (photo, price, category, station, sizes), and manage
/// categories.
///
/// Add-ons, availability windows and combos stay on the web editor.
class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({super.key});

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = ref.watch(menuEditItemsProvider);
    final visible = ref.watch(visibleMenuItemsProvider);
    final canEdit = ref.watch(canEditMenuProvider);
    final currency = ref.watch(activeTenantProvider)?.currency ?? 'USD';
    final categories =
        ref.watch(menuCategoriesProvider).valueOrNull ?? const [];
    final picked = ref.watch(menuCategoryFilterProvider);
    final all = items.valueOrNull ?? const [];
    final soldOut = all.where((i) => effectiveIs86(ref, i)).length;

    return AppScaffold(
      title: 'Menu',
      actions: [
        PopupMenuButton<Widget Function()>(
          tooltip: 'Manage menu',
          icon: const Icon(Icons.tune),
          onSelected: (build) => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => build())),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: () => const MenuCategoriesScreen(),
              child: const ListTile(
                leading: Icon(Icons.category_outlined),
                title: Text('Categories'),
              ),
            ),
            PopupMenuItem(
              value: () => const AddOnsLibraryScreen(),
              child: const ListTile(
                leading: Icon(Icons.add_circle_outline),
                title: Text('Add-ons'),
              ),
            ),
            PopupMenuItem(
              value: () => const CombosScreen(),
              child: const ListTile(
                leading: Icon(Icons.fastfood_outlined),
                title: Text('Combos'),
              ),
            ),
          ],
        ),
      ],
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ItemEditScreen()),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Add dish'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _search,
              onChanged: (v) => ref.read(menuSearchProvider.notifier).state = v,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search dishes',
                constraints: BoxConstraints(minHeight: Tokens.tapTarget),
              ),
            ),
          ),
          if (categories.isNotEmpty)
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                children: [
                  for (final c in [null, ...categories])
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(c?.name ?? 'All'),
                        selected: picked == c?.id,
                        onSelected: (_) =>
                            ref
                                    .read(menuCategoryFilterProvider.notifier)
                                    .state =
                                c?.id,
                      ),
                    ),
                ],
              ),
            ),
          if (soldOut > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Row(
                children: [
                  Icon(
                    Icons.remove_shopping_cart_outlined,
                    size: 16,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$soldOut sold out',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: items.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _Message(
                icon: Icons.cloud_off,
                title: "Couldn't load the menu",
                body: '$e',
                onRetry: () => ref.invalidate(menuEditItemsProvider),
              ),
              data: (all) {
                if (all.isEmpty) {
                  return const _Message(
                    icon: Icons.restaurant_menu,
                    title: 'No dishes yet',
                    body:
                        'Tap Add dish to put the first one on the menu — '
                        'name, price and a photo is enough to start.',
                  );
                }
                if (visible.isEmpty) {
                  return const _Message(
                    icon: Icons.search_off,
                    title: 'No match',
                    body: 'Nothing on the menu by that name.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(menuEditItemsProvider);
                    ref.invalidate(menuCategoriesProvider);
                    ref.invalidate(menuStationsProvider);
                    ref.invalidate(menuAddOnsProvider);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(0, 4, 0, 96),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) => _ItemRow(
                      item: visible[i],
                      currency: currency,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          // By id, not by the object: the row is re-derived
                          // from a refreshed list, and a captured snapshot
                          // would show stale variants after the first edit.
                          builder: (_) => ItemEditScreen(itemId: visible[i].id),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: items.hasValue && !canEdit
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.visibility_outlined,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You can see the menu here but not change it.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.currency,
    required this.onTap,
  });

  final MenuEditItem item;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A dish with variants forces a choice, so its base price is unbuyable —
    // quote what someone can actually pay, the way the POS tiles do.
    final deltas = item.variants.map((v) => v.priceDeltaCents).toList();
    final lo = deltas.isEmpty
        ? item.basePriceCents
        : item.basePriceCents + deltas.reduce((a, b) => a < b ? a : b);
    final hi = deltas.isEmpty
        ? item.basePriceCents
        : item.basePriceCents + deltas.reduce((a, b) => a > b ? a : b);

    return ListTile(
      onTap: onTap,
      minTileHeight: 72,
      contentPadding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox.square(
          dimension: 52,
          child: DishThumb(
            name: item.name,
            imageUrl: item.imageUrl,
            monogramSize: 18,
          ),
        ),
      ),
      title: Row(
        children: [
          if (item.isVeg != null) ...[
            VegMark(isVeg: item.isVeg),
            const SizedBox(width: 6),
          ],
          Flexible(child: Text(item.name, overflow: TextOverflow.ellipsis)),
        ],
      ),
      subtitle: Text(
        [
          moneyRange(lo, hi, currency),
          if (item.categoryName != null) item.categoryName!,
          if (item.variants.isNotEmpty)
            '${item.variants.length} '
                '${item.variants.length == 1 ? 'size' : 'sizes'}',
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.tabular,
      ),
      trailing: StockSwitch(item: item),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
