import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_scaffold.dart';
import '../../core/format/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/supabase/menu_repository.dart';
import '../tenant/tenant_providers.dart';
import 'item_variants_screen.dart';
import 'menu_providers.dart';

/// The menu, on a phone: find a dish, fix its sizes.
///
/// Deliberately narrower than the web editor — photo, add-ons, kitchen routing
/// and availability stay there. This is the thing an owner does standing in
/// the restaurant: a size is wrong, or a size is in the wrong order.
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

    return AppScaffold(
      title: 'Menu',
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
                        'Add dishes on the web app under Menu. They show up '
                        'here to price and size.',
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
                  onRefresh: () async => ref.invalidate(menuEditItemsProvider),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(0, 4, 0, 32),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) => _ItemRow(
                      item: visible[i],
                      currency: currency,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          // By id, not by the object: the row is re-derived
                          // from a refreshed list, and a captured snapshot
                          // would show stale sizes after the first edit.
                          builder: (_) =>
                              ItemVariantsScreen(itemId: visible[i].id),
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
    // A dish with sizes forces a choice, so its base price is unbuyable —
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(item.name),
      subtitle: Text(
        item.variants.isEmpty
            ? (item.categoryName ?? 'No sizes')
            : '${item.variants.length} '
                  '${item.variants.length == 1 ? 'size' : 'sizes'}'
                  ' · ${item.variants.map((v) => v.name).join(', ')}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            moneyRange(lo, hi, currency),
            style: theme.textTheme.bodyMedium?.tabular,
          ),
          if (item.is86)
            Text(
              '86',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
        ],
      ),
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
