import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/supabase/menu_repository.dart';
import '../../data/sync/sync_providers.dart';
import '../pos/pos_providers.dart' show menuProvider;
import 'menu_providers.dart';

/// What this phone last set, by dish id, until the server's list agrees.
///
/// The stock write goes through the outbox (`set_item_86`, last-write-wins),
/// so it lands with no signal too. Without this the switch would snap back to
/// the server's old value while the write is still queued.
final stockOverridesProvider = StateProvider<Map<String, bool>>(
  (_) => const {},
);

/// Sold out right now, as far as this phone knows.
bool effectiveIs86(WidgetRef ref, MenuEditItem item) =>
    ref.watch(stockOverridesProvider)[item.id] ?? item.is86;

Future<void> setStock(
  BuildContext context,
  WidgetRef ref,
  MenuEditItem item, {
  required bool inStock,
}) async {
  final queue = ref.read(orderQueueProvider);
  if (queue == null) return;
  final is86 = !inStock;
  // Taken before the await: the row that asked may be rebuilt or gone by the
  // time the write settles, so neither its context nor its ref is used after.
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final overrides = container.read(stockOverridesProvider.notifier);
  overrides.state = {...overrides.state, item.id: is86};

  final outcome = await queue.setItem86(itemId: item.id, is86: is86);
  container.invalidate(outboxStatusProvider);

  if (outcome.isRejected) {
    // Refused: drop the optimistic value so the switch shows the truth.
    overrides.state = {...overrides.state}..remove(item.id);
    messenger
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(outcome.error!)));
    return;
  }
  if (outcome.synced) {
    container.invalidate(menuProvider);
    container.invalidate(menuEditItemsProvider);
    // Hand the switch back to the server's value once the fresh list is in,
    // so a later change from another phone isn't masked by this one.
    unawaited(
      container
          .read(menuEditItemsProvider.future)
          .then(
            (_) => overrides.state = {...overrides.state}..remove(item.id),
            onError: (_) {},
          ),
    );
  }
  messenger
    ?..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(
          !outcome.synced
              ? 'Saved on this phone. Other screens update once you’re back online.'
              : is86
              ? '${item.name} is sold out. Nobody can order it until it is back.'
              : '${item.name} is back in stock.',
        ),
      ),
    );
}

/// Compact switch for a menu row. The word beside it carries the state, so it
/// reads the same in greyscale.
class StockSwitch extends ConsumerWidget {
  const StockSwitch({super.key, required this.item});

  final MenuEditItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final is86 = effectiveIs86(ref, item);
    final canSet = ref.watch(canSetStockProvider);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: is86
              ? '${item.name} sold out. Turn on to put back in stock'
              : '${item.name} in stock. Turn off to mark sold out',
          child: Switch(
            value: !is86,
            onChanged: canSet
                ? (v) => setStock(context, ref, item, inStock: v)
                : null,
          ),
        ),
        Text(
          is86 ? 'Sold out' : 'In stock',
          style: theme.textTheme.labelSmall?.copyWith(
            color: is86
                ? theme.colorScheme.error
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: is86 ? FontWeight.w700 : null,
          ),
        ),
      ],
    );
  }
}

/// The same control as a full-width tile, for the dish screen.
class StockToggleTile extends ConsumerWidget {
  const StockToggleTile({super.key, required this.item});

  final MenuEditItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final is86 = effectiveIs86(ref, item);
    final canSet = ref.watch(canSetStockProvider);
    return Card(
      margin: EdgeInsets.zero,
      child: SwitchListTile(
        value: !is86,
        onChanged: canSet
            ? (v) => setStock(context, ref, item, inStock: v)
            : null,
        secondary: Icon(
          is86
              ? Icons.remove_shopping_cart_outlined
              : Icons.check_circle_outline,
        ),
        title: Text(is86 ? 'Sold out' : 'In stock'),
        subtitle: Text(
          is86
              ? 'Nobody can order it — POS, QR or online — until you turn it back on.'
              : canSet
              ? 'Turn off when it runs out for today.'
              : 'Only an owner, manager or the kitchen can change stock.',
        ),
      ),
    );
  }
}
