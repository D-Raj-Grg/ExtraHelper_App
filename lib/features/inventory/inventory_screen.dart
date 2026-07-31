import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/supabase/inventory_repository.dart';
import '../tenant/tenant_providers.dart';
import 'adjust_sheet.dart';
import 'count_screen.dart';
import 'inventory_providers.dart';
import 'quantity.dart';
import 'scanner_sheet.dart';

/// The store room: what is here, what is short, and the two things you do about
/// it — count it, or correct it.
class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  /// Owned here so a scan can put the code it read into the box. Driving the
  /// provider alone filtered the list while the field still showed the old
  /// text, which reads as the search having been ignored.
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setSearch(String v) {
    if (_search.text != v) _search.text = v;
    ref.read(inventorySearchProvider.notifier).state = v;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = ref.watch(inventoryItemsProvider);
    final visible = ref.watch(visibleInventoryProvider);
    final canEdit = ref.watch(canEditInventoryProvider);
    final openCount = ref.watch(openCountProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Store room'),
        actions: [
          IconButton(
            tooltip: 'Scan a label',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => _scan(context),
          ),
        ],
      ),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _openCount(context),
              icon: Icon(
                openCount == null ? Icons.playlist_add_check : Icons.edit_note,
              ),
              label: Text(openCount == null ? 'Start a count' : 'Resume count'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _search,
              onChanged: _setSearch,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search by name or barcode',
                constraints: BoxConstraints(minHeight: Tokens.tapTarget),
              ),
            ),
          ),
          Expanded(
            child: items.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _Message(
                icon: Icons.cloud_off,
                title: "Couldn't load the store room",
                body: '$e',
                onRetry: () => ref.invalidate(inventoryItemsProvider),
              ),
              data: (all) {
                if (all.isEmpty) {
                  return const _Message(
                    icon: Icons.inventory_2_outlined,
                    title: 'Nothing in the store room yet',
                    body:
                        'Add the things you buy — flour, oil, gas — on the web '
                        'app under Inventory. They show up here to count.',
                  );
                }
                if (visible.isEmpty) {
                  return const _Message(
                    icon: Icons.search_off,
                    title: 'No match',
                    body: 'Nothing here by that name or code.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(inventoryItemsProvider);
                    ref.invalidate(openCountProvider);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(0, 4, 0, 96),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) => _ItemRow(
                      item: visible[i],
                      canEdit: canEdit,
                      onAdjust: () => _adjust(context, visible[i]),
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
                        'You can see stock here but not change it.',
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

  Future<void> _scan(BuildContext context) async {
    final code = await showScannerSheet(context);
    if (code == null || !context.mounted) return;

    // Match against what is already on screen first: offline, that is the only
    // answer available, and online it is the same answer without a round trip.
    final known = ref
        .read(inventoryItemsProvider)
        .valueOrNull
        ?.where((i) => i.barcode == code)
        .firstOrNull;
    if (known != null) {
      _setSearch(known.name);
      return;
    }
    // Put the raw code in the search box: it shows what was read, and it is the
    // string to paste into the web app when labelling the item.
    _setSearch(code);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('No item carries the code $code yet.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openCount(BuildContext context) async {
    final tenant = ref.read(activeTenantProvider);
    if (tenant == null) return;
    final repo = ref.read(inventoryRepositoryProvider(tenant.tenantId));

    var countId = ref.read(openCountProvider).valueOrNull?.id;
    if (countId == null) {
      try {
        countId = await repo.startCount();
      } on Object catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
        return;
      }
      ref.invalidate(openCountProvider);
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CountScreen(countId: countId!)),
    );
    ref.invalidate(inventoryItemsProvider);
    ref.invalidate(openCountProvider);
  }

  Future<void> _adjust(BuildContext context, InventoryItem item) async {
    final tenant = ref.read(activeTenantProvider);
    if (tenant == null) return;

    final change = await showAdjustSheet(context, item);
    if (change == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      // Deliberately **not** queued: a delta replayed twice moves stock twice,
      // and `adjust_inventory` takes no idempotency key. Offline this fails
      // honestly rather than pretending.
      await ref
          .read(inventoryRepositoryProvider(tenant.tenantId))
          .adjust(
            itemId: item.id,
            delta: change.delta,
            type: change.type,
            reason: change.reason,
          );
      ref.invalidate(inventoryItemsProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text('${item.name}  ${signedQty(change.delta, item.uom)}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.canEdit,
    required this.onAdjust,
  });

  final InventoryItem item;
  final bool canEdit;
  final VoidCallback onAdjust;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;

    return ListTile(
      minTileHeight: Tokens.tapTarget + 12,
      onTap: canEdit ? onAdjust : null,
      title: Text(item.name),
      subtitle: Text(
        [
          if (item.category != null && item.category!.isNotEmpty) item.category,
          'reorder at ${qtyWithUom(item.reorderLevel, item.uom)}',
        ].whereType<String>().join('  ·  '),
        style: theme.textTheme.bodySmall?.tabular,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            qtyWithUom(item.currentQty, item.uom),
            style: theme.textTheme.titleMedium?.tabular,
          ),
          if (item.isLow)
            // Colour is the *third* signal here: the word and the icon carry it
            // on their own, which is what makes this survive greyscale.
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.warning_amber_outlined,
                  size: 14,
                  color: semantic.attentionText,
                ),
                const SizedBox(width: 4),
                Text(
                  'Low',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: semantic.attentionText,
                  ),
                ),
              ],
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
              style: theme.textTheme.bodySmall,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
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
