import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_scaffold.dart';
import '../../core/format/money.dart';
import '../../data/supabase/menu_repository.dart';
import '../tenant/tenant_providers.dart';
import 'menu_providers.dart';
import 'variant_sheet.dart';

/// One dish's sizes: add, rename, reprice, reorder, remove.
///
/// Takes an **id, not an item**. Every write refreshes the list, so a captured
/// object would keep showing the values from before the first edit.
class ItemVariantsScreen extends ConsumerStatefulWidget {
  const ItemVariantsScreen({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<ItemVariantsScreen> createState() => _ItemVariantsScreenState();
}

class _ItemVariantsScreenState extends ConsumerState<ItemVariantsScreen> {
  /// One flag for the whole list: two writes racing on the same item would
  /// renumber against each other.
  bool _busy = false;

  MenuEditItem? get _item => ref
      .watch(menuEditItemsProvider)
      .valueOrNull
      ?.where((i) => i.id == widget.itemId)
      .firstOrNull;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = _item;
    final canEdit = ref.watch(canEditMenuProvider);
    final currency = ref.watch(activeTenantProvider)?.currency ?? 'USD';

    if (item == null) {
      return const AppScaffold(
        title: 'Sizes',
        showDrawer: false,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final variants = item.variants;

    return AppScaffold(
      title: item.name,
      subtitle: 'Base ${money(item.basePriceCents, currency)}',
      showDrawer: false,
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : () => _add(context, item, currency),
              icon: const Icon(Icons.add),
              label: const Text('Add size'),
            )
          : null,
      body: variants.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.straighten,
                      size: 40,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text('No sizes', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                      canEdit
                          ? 'The dish sells at its base price. Add a size when '
                                'a Half or a 1 kg costs something different.'
                          : 'The dish sells at its base price.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: variants.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) => _VariantRow(
                variant: variants[i],
                basePriceCents: item.basePriceCents,
                currency: currency,
                canEdit: canEdit && !_busy,
                isFirst: i == 0,
                isLast: i == variants.length - 1,
                onEdit: () => _edit(context, item, variants[i], currency),
                onMoveUp: () => _move(context, variants[i], up: true),
                onMoveDown: () => _move(context, variants[i], up: false),
                onDelete: () => _delete(context, variants[i]),
              ),
            ),
      bottomNavigationBar: canEdit
          ? null
          : SafeArea(
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
                        'You can see the sizes but not change them.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  MenuRepository? get _repo {
    final tenant = ref.read(activeTenantProvider);
    if (tenant == null) return null;
    return ref.read(menuRepositoryProvider(tenant.tenantId));
  }

  /// Runs one write, then refreshes. Every failure reaches the person who made
  /// the change — a menu edit that silently did nothing is how a price stays
  /// wrong through a service.
  Future<void> _run(
    BuildContext context,
    Future<void> Function(MenuRepository repo) write,
  ) async {
    final repo = _repo;
    if (repo == null || _busy) return;
    setState(() => _busy = true);
    try {
      await write(repo);
      ref.invalidate(menuEditItemsProvider);
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add(
    BuildContext context,
    MenuEditItem item,
    String currency,
  ) async {
    final draft = await showVariantSheet(
      context,
      itemName: item.name,
      basePriceCents: item.basePriceCents,
      currency: currency,
    );
    if (draft == null || !context.mounted) return;
    await _run(
      context,
      (repo) => repo.addVariant(
        itemId: item.id,
        name: draft.name,
        priceDeltaCents: draft.priceDeltaCents,
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    MenuEditItem item,
    MenuEditVariant variant,
    String currency,
  ) async {
    final draft = await showVariantSheet(
      context,
      itemName: item.name,
      basePriceCents: item.basePriceCents,
      currency: currency,
      editing: variant,
    );
    if (draft == null || !context.mounted) return;
    await _run(
      context,
      (repo) => repo.updateVariant(
        variantId: variant.id,
        name: draft.name,
        priceDeltaCents: draft.priceDeltaCents,
      ),
    );
  }

  Future<void> _move(
    BuildContext context,
    MenuEditVariant variant, {
    required bool up,
  }) => _run(context, (repo) async {
    await repo.moveVariant(variantId: variant.id, up: up);
  });

  Future<void> _delete(BuildContext context, MenuEditVariant variant) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${variant.name}?'),
        // The real consequence, not "are you sure": deleting the row nulls
        // `order_items.variant_id`, so finished orders stop saying which size
        // went out. Renaming keeps that history.
        content: const Text(
          'Past orders will stop showing which size was sold. To fix a name or '
          'a price, edit the size instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _run(context, (repo) => repo.deleteVariant(variant.id));
  }
}

class _VariantRow extends StatelessWidget {
  const _VariantRow({
    required this.variant,
    required this.basePriceCents,
    required this.currency,
    required this.canEdit,
    required this.isFirst,
    required this.isLast,
    required this.onEdit,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
  });

  final MenuEditVariant variant;
  final int basePriceCents;
  final String currency;
  final bool canEdit;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onEdit;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sign = variant.priceDeltaCents < 0 ? '−' : '+';
    final delta = money(variant.priceDeltaCents.abs(), currency);

    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      title: Text(variant.name),
      subtitle: Text(
        '$sign$delta  ·  sells for '
        '${money(basePriceCents + variant.priceDeltaCents, currency)}',
        style: theme.textTheme.bodySmall,
      ),
      trailing: canEdit
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Move up',
                  icon: const Icon(Icons.keyboard_arrow_up),
                  onPressed: isFirst ? null : onMoveUp,
                ),
                IconButton(
                  tooltip: 'Move down',
                  icon: const Icon(Icons.keyboard_arrow_down),
                  onPressed: isLast ? null : onMoveDown,
                ),
                IconButton(
                  tooltip: 'Edit ${variant.name}',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: onEdit,
                ),
                IconButton(
                  tooltip: 'Remove ${variant.name}',
                  icon: Icon(
                    Icons.delete_outline,
                    color: theme.colorScheme.error,
                  ),
                  onPressed: onDelete,
                ),
              ],
            )
          : null,
    );
  }
}
