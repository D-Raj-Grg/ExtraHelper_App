import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/sync/outbox.dart';
import '../../data/sync/sync_providers.dart';

/// Connection and what the app still owes the server — one band, under the
/// app bar, on every screen.
///
/// This used to be two things: a badge in the app bar that **vanished when the
/// outbox was clean**, so the bar changed width mid-service, and a separate
/// offline banner below it. They describe one situation, so they are one strip.
///
/// It is also the only coloured band in the app frame. Colour in the chrome
/// means exactly one thing: *this work is not on the server yet.*
///
/// Three facts, never conflated:
///
/// * **Offline** — a state, not an error. Say it plainly and promise the thing
///   the waiter actually cares about.
/// * **Owed** — writes are queued and will land. A count, not an alarm.
/// * **Failed** — the server refused something and gave up. That needs a
///   person, so it is a warning with the reason attached.
///
/// Colour never carries any of them alone: each has an icon and a word or a
/// number beside it, so this survives a greyscale screenshot.
class SyncStrip extends ConsumerWidget {
  const SyncStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;
    final status = ref.watch(outboxStatusProvider).valueOrNull;
    final pending = status?.pending ?? 0;
    final dead = status?.dead.length ?? 0;

    if (online && pending == 0 && dead == 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final semantic = context.semantic;

    final (
      IconData icon,
      Color tone,
      Color toneText,
      String message,
    ) = switch ((dead > 0, online)) {
      (true, _) => (
        Icons.report_gmailerrorred_outlined,
        semantic.attention,
        semantic.attentionText,
        '$dead write${dead == 1 ? '' : 's'} refused — tap to see why',
      ),
      (false, false) when pending > 0 => (
        Icons.cloud_off,
        semantic.warning,
        semantic.warningText,
        'Offline · $pending waiting — saved on this phone',
      ),
      (false, false) => (
        Icons.cloud_off,
        semantic.warning,
        semantic.warningText,
        'Offline — orders are saved on this phone and sent when coverage is back',
      ),
      (false, true) => (
        Icons.cloud_upload_outlined,
        semantic.info,
        semantic.infoText,
        '$pending waiting to send',
      ),
    };

    return Material(
      color: tone.withValues(alpha: 0.16),
      child: InkWell(
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => const _SyncStatusDialog(),
        ),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: Tokens.tapTarget),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: tone)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: toneText),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.labelMedium?.copyWith(color: toneText),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 18, color: toneText),
            ],
          ),
        ),
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
    OutboxKind.menu86 => 'Sold out / back on',
    OutboxKind.tableState => 'Table state',
    OutboxKind.stockCount => 'Counted quantity',
    OutboxKind.kotLine => 'Dish status',
    OutboxKind.kotTicket => 'Ticket status',
    OutboxKind.orderServed => 'Delivered to the table',
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
