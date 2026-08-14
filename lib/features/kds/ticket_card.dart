import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../data/supabase/kds_repository.dart';
import 'kds_constants.dart';

/// One station's ticket for one order.
///
/// A cook plates dish by dish, so the dish is the unit of work: every live line
/// carries its own one-tap advance. The whole-ticket button is the shortcut for
/// the common case where the plate goes out together.
class TicketCard extends StatelessWidget {
  const TicketCard({
    super.key,
    required this.ticket,
    required this.now,
    required this.canBump,
    required this.onAdvanceLine,
    required this.onAdvanceTicket,
    required this.onLineLongPress,
    this.onReprint,
  });

  final KdsTicket ticket;
  final DateTime now;

  /// False for a viewer — the board stays readable, the buttons don't exist.
  /// The RPCs enforce `kds.bump` regardless.
  final bool canBump;

  final void Function(KdsLine line, KotStatus status) onAdvanceLine;
  final void Function(KotStatus status) onAdvanceTicket;
  final void Function(KdsLine line) onLineLongPress;

  /// Queue this ticket again. Null without `order.view` — the RPC checks the
  /// same key, and a control that can only fail is worse than none.
  ///
  /// A jammed roll, a ticket blown off the rail, a station that came online
  /// after the order fired: the paper is gone and the board still has it.
  final VoidCallback? onReprint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final age = ticketAge(ticket.createdAt, now);
    final ageColor = ticketAgeColor(context, age);
    final status = ticket.status;
    final meta = kotStatusMeta[status]!;
    final next = nextKotStatus(status);

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusLg),
        side: BorderSide(color: ageColor, width: age.late ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    ticket.destination,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                // Age is stated, not just tinted: this is the most important
                // signal on a kitchen screen and it is read across a room.
                Icon(age.icon, size: 16, color: ageColor),
                const SizedBox(width: 4),
                Text(
                  age.label,
                  style: theme.textTheme.labelLarge?.copyWith(color: ageColor),
                ),
                if (onReprint != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: onReprint,
                    icon: const Icon(Icons.print_outlined),
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Print this ticket again',
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(
                  meta.icon,
                  size: 14,
                  color: kotStatusColor(context, status),
                ),
                const SizedBox(width: 4),
                Text(
                  '${meta.label} · ${ticket.station}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
            const Divider(height: 18),
            for (final line in ticket.lines)
              _Line(
                line: line,
                canBump: canBump,
                onAdvance: onAdvanceLine,
                onLongPress: onLineLongPress,
              ),
            if (canBump && next != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => onAdvanceTicket(next),
                  icon: Icon(kotStatusMeta[next]!.icon),
                  label: Text('${kotStatusMeta[next]!.action} all'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.line,
    required this.canBump,
    required this.onAdvance,
    required this.onLongPress,
  });

  final KdsLine line;
  final bool canBump;
  final void Function(KdsLine, KotStatus) onAdvance;
  final void Function(KdsLine) onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final meta = kotStatusMeta[line.status]!;
    final next = nextKotStatus(line.status);
    final tone = kotStatusColor(context, line.status);

    // A cancelled dish stays visible, struck through. The cook needs to know it
    // was ordered and is not coming — removing it silently is how a plate goes
    // out anyway.
    final voided = line.isVoid;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              '${line.qty}×',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: voided ? semantic.neutral : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.name,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      decoration: voided ? TextDecoration.lineThrough : null,
                      color: voided ? semantic.neutral : null,
                    ),
                  ),
                  if (line.modifiers.isNotEmpty)
                    Text(
                      line.modifiers.join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                  if ((line.notes ?? '').isNotEmpty)
                    Text(
                      line.notes!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: semantic.attentionText,
                      ),
                    ),
                  if (voided)
                    Text(
                      'Cancelled',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: semantic.dangerText,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (voided)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Icon(Icons.close, size: 18, color: semantic.neutral),
            )
          else if (!canBump || next == null)
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 4),
              child: Row(
                children: [
                  Icon(meta.icon, size: 16, color: tone),
                  const SizedBox(width: 4),
                  Text(
                    meta.label,
                    style: theme.textTheme.labelMedium?.copyWith(color: tone),
                  ),
                ],
              ),
            )
          else
            // Long-press opens the full picker — a mis-tap needs a way back,
            // and a cook should not have to hunt for it mid-service.
            GestureDetector(
              onLongPress: () => onLongPress(line),
              child: OutlinedButton.icon(
                onPressed: () => onAdvance(line, next),
                icon: Icon(kotStatusMeta[next]!.icon, size: 18),
                label: Text(kotStatusMeta[next]!.action),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(88, Tokens.tapTarget),
                  foregroundColor: kotStatusColor(context, next),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
