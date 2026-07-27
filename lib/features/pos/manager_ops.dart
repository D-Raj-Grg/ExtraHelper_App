import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/labels.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/sync/order_queue.dart';
import '../../data/sync/sync_providers.dart';
import 'models.dart';
import 'order_composer.dart';
import 'pos_providers.dart';

/// Manager ops: 86 a dish, set a table's state.
///
/// Both are queued through the outbox, because both are things *other* staff
/// need to see — a sold-out dish, a table freed — and both are safe to replay,
/// being last-write-wins on a single row. Both are also enforced again inside
/// their RPC, so what follows is an affordance, not a gate.

/// Sold out, or back on. Reached by long-pressing a dish in the composer.
Future<void> showItem86Sheet({
  required BuildContext context,
  required WidgetRef ref,
  required PosMenuItem item,
}) async {
  final queue = ref.read(orderQueueProvider);
  if (queue == null) return;

  final turnOff = !item.is86;
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    builder: (sheetContext) => _ConfirmSheet(
      icon: turnOff ? Icons.remove_shopping_cart : Icons.restart_alt,
      title: turnOff ? 'Mark ${item.name} sold out?' : 'Put ${item.name} back?',
      body: turnOff
          ? 'It disappears from every waiter’s phone and the web POS, and '
                'nobody can order it until someone puts it back.'
          : 'It becomes orderable again on every phone and on the web POS.',
      confirmLabel: turnOff ? 'Mark sold out' : 'Put it back',
      destructive: turnOff,
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final outcome = await queue.setItem86(itemId: item.id, is86: turnOff);
  if (!context.mounted) return;
  _report(
    context,
    outcome,
    done: turnOff ? '${item.name} is sold out.' : '${item.name} is back on.',
    queued: turnOff
        ? 'Saved. Other phones see it sold out once you’re back on coverage.'
        : 'Saved. It goes back on once you’re back on coverage.',
  );
  ref.invalidate(outboxStatusProvider);
}

/// Free / occupied / reserved / bill requested / cleaning, from the board.
Future<void> showTableStateSheet({
  required BuildContext context,
  required WidgetRef ref,
  required PosTable table,
}) async {
  final queue = ref.read(orderQueueProvider);
  if (queue == null) return;

  final chosen = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    builder: (sheetContext) => _TableStateSheet(table: table),
  );
  if (chosen == null || chosen == table.state || !context.mounted) return;

  final outcome = await queue.setTableState(tableId: table.id, state: chosen);
  if (!context.mounted) return;
  _report(
    context,
    outcome,
    done:
        'Table ${table.label} is now ${tableStateLabel(chosen).toLowerCase()}.',
    queued:
        'Saved. The board updates for everyone once you’re back on '
        'coverage.',
  );
  ref.invalidate(outboxStatusProvider);
  await ref.read(tablesProvider.notifier).refresh();
}

/// Queued-but-not-sent is a success, and says so. A refusal is the server's
/// sentence, shown as-is.
void _report(
  BuildContext context,
  QueueOutcome outcome, {
  required String done,
  required String queued,
}) {
  final scheme = Theme.of(context).colorScheme;
  final failed = outcome.isRejected;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              failed
                  ? Icons.error_outline
                  : outcome.synced
                  ? Icons.check_circle_outline
                  : Icons.cloud_upload_outlined,
              size: 20,
              color: failed ? scheme.onError : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                failed ? outcome.error! : (outcome.synced ? done : queued),
              ),
            ),
          ],
        ),
        backgroundColor: failed ? scheme.error : null,
      ),
    );
}

class _ConfirmSheet extends StatelessWidget {
  const _ConfirmSheet({
    required this.icon,
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.destructive,
  });

  final IconData icon;
  final String title;
  final String body;
  final String confirmLabel;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: destructive ? semantic.attentionText : semantic.goodText,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: 10),
          // Name the real consequence, never "are you sure?".
          Text(body, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(confirmLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TableStateSheet extends StatelessWidget {
  const _TableStateSheet({required this.table});

  final PosTable table;

  static const _states = [
    'free',
    'occupied',
    'reserved',
    'bill_requested',
    'cleaning',
  ];

  static IconData _icon(String state) => switch (state) {
    'free' => Icons.event_available,
    'occupied' => Icons.people,
    'reserved' => Icons.bookmark_outline,
    'bill_requested' => Icons.receipt_long,
    'cleaning' => Icons.cleaning_services,
    _ => Icons.help_outline,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Text(
                'Table ${table.label}',
                style: theme.textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                'Freeing a table with a live order is refused by the server — '
                'close or cancel the order first.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            for (final state in _states)
              ListTile(
                minTileHeight: Tokens.tapTarget,
                leading: Icon(
                  _icon(state),
                  color: tableStateColor(context, state),
                ),
                title: Text(tableStateLabel(state)),
                // The tick, not the colour, is what says "this one".
                trailing: state == table.state ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(state),
              ),
          ],
        ),
      ),
    );
  }
}

/// What managers did today, and why.
final auditLogProvider = FutureProvider.autoDispose<List<PosAuditEntry>>((
  ref,
) async {
  final repo = ref.watch(posRepoProvider);
  if (repo == null) return const [];
  return repo.auditLog();
});

/// The manager's log — voids, discounts, stock and table changes.
///
/// `audit_logs` RLS restricts SELECT to owners and managers, so a waiter who
/// reached this screen would see an empty list rather than someone else's data.
class ManagerLogScreen extends ConsumerWidget {
  const ManagerLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(auditLogProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Manager log')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(auditLogProvider),
        child: log.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              const SizedBox(height: 80),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 36,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Couldn't load the log.",
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$e',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: () => ref.invalidate(auditLogProvider),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          data: (entries) {
            if (entries.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 60),
                  PosEmptyState(
                    icon: Icons.fact_check_outlined,
                    title: 'Nothing to review',
                    body:
                        'Voids, discounts, stock changes and table changes show '
                        'up here with who did them and why.',
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _LogRow(entry: entries[i]),
            );
          },
        ),
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});

  final PosAuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = context.semantic;

    final (icon, color, label) = switch (entry.action) {
      'void' => (Icons.block, semantic.dangerText, 'Void'),
      'discount' => (Icons.percent, semantic.warningText, 'Discount'),
      'item_86' => (
        Icons.remove_shopping_cart,
        semantic.attentionText,
        'Sold out',
      ),
      'item_unset_86' => (Icons.restart_alt, semantic.goodText, 'Back on'),
      'table_state' => (Icons.table_restaurant, semantic.infoText, 'Table'),
      _ => (Icons.article_outlined, semantic.neutral, entry.action),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(color: scheme.outline),
        borderRadius: BorderRadius.circular(Tokens.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              // Colour never carries it alone — the word is right there.
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  entry.subject,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _clock(entry.createdAt),
                style: (theme.textTheme.bodySmall ?? const TextStyle()).tabular,
              ),
            ],
          ),
          if (entry.reason != null) ...[
            const SizedBox(height: 6),
            Text(entry.reason!, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 4),
          Text(
            entry.actorName ?? 'Account since removed',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  static String _clock(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour < 12 ? 'am' : 'pm'}';
  }
}
