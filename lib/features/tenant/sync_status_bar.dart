import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/sync/outbox.dart';
import '../../data/sync/sync_providers.dart';

/// What the app still owes the server, in the app bar.
///
/// Two different facts, never conflated:
///
/// * **Owed** — writes are queued and will land. A count, not an alarm.
/// * **Failed** — the server refused something and gave up. That needs a
///   person, so it is a warning with the reason attached.
///
/// Colour never carries either state alone: both have an icon and a number or
/// word beside them, so this survives a greyscale screenshot.
class SyncStatusAction extends ConsumerWidget {
  const SyncStatusAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(outboxStatusProvider).valueOrNull;
    if (status == null || status.isClean) return const SizedBox.shrink();

    final semantic = context.semantic;
    final failed = status.dead.isNotEmpty;

    return IconButton(
      tooltip: failed
          ? '${status.dead.length} write${status.dead.length == 1 ? '' : 's'} failed'
          : '${status.pending} waiting to send',
      icon: Badge(
        label: Text('${failed ? status.dead.length : status.pending}'),
        backgroundColor: failed ? semantic.attentionText : semantic.infoText,
        child: Icon(
          failed
              ? Icons.report_gmailerrorred_outlined
              : Icons.cloud_upload_outlined,
        ),
      ),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (_) => const _SyncStatusDialog(),
      ),
    );
  }
}

/// Offline is a **state, not an error**. Say it plainly, above the board, and
/// promise the thing the waiter actually cares about.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;
    if (online) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final semantic = context.semantic;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: semantic.warning,
      child: Row(
        children: [
          Icon(Icons.cloud_off, size: 18, color: semantic.warningText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No coverage — orders are saved on this phone and sent when it '
              'comes back.',
              style: theme.textTheme.labelMedium?.copyWith(
                color: semantic.warningText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncStatusDialog extends ConsumerWidget {
  const _SyncStatusDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = ref.watch(outboxStatusProvider).valueOrNull;
    final dead = status?.dead ?? const <OutboxEntry>[];

    return AlertDialog(
      title: const Text('Waiting to send'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            status == null || status.pending == 0
                ? 'Nothing is waiting.'
                : '${status.pending} write${status.pending == 1 ? '' : 's'} '
                      'will go out as soon as there is coverage. You can keep '
                      'taking orders.',
            style: theme.textTheme.bodyMedium,
          ),
          if (dead.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Refused by the server', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              'These will not be retried. Check the order, then re-do them by '
              'hand.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            for (final entry in dead)
              _DeadRow(
                entry: entry,
                onDismiss: () async {
                  await ref.read(outboxStoreProvider).discard(entry.id);
                  ref.invalidate(outboxStatusProvider);
                },
              ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: () async {
            await ref.read(replayEngineProvider)?.run();
            ref.invalidate(outboxStatusProvider);
          },
          child: const Text('Try now'),
        ),
      ],
    );
  }
}

class _DeadRow extends StatelessWidget {
  const _DeadRow({required this.entry, required this.onDismiss});

  final OutboxEntry entry;
  final VoidCallback onDismiss;

  static String _describe(OutboxKind kind) => switch (kind) {
    OutboxKind.order => 'New order',
    OutboxKind.amendAdd => 'Added dish',
    OutboxKind.amendVoid => 'Voided line',
    OutboxKind.fire => 'Send to kitchen',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: semantic.attentionText),
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: semantic.attentionText),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_describe(entry.kind), style: theme.textTheme.labelLarge),
                Text(
                  entry.lastError ?? 'No reason given.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            icon: const Icon(Icons.close, size: 18),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}
