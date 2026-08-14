/// Moving orders between tables: transfer the lot, merge two onto one bill, or
/// split some dishes off to a table of their own.
///
/// All three are online-only and **never queued**. Each one writes a
/// destination table's state and an audit row, and `split_order_items` mints an
/// order id on the server that the screen has to have — a replayed split would
/// arrive with nowhere to send the waiter.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/table_glyph.dart';
import 'models.dart';
import 'pos_providers.dart';

/// Pick a table other than the one being moved from.
///
/// Free tables lead, because that is what a transfer usually wants; occupied
/// ones stay pickable, because merging two parties is a real thing that
/// happens and refusing it would send the waiter to the web app.
Future<PosTable?> showTablePicker({
  required BuildContext context,
  required WidgetRef ref,
  required PosTable exclude,
  required String title,
  required String body,
  bool freeOnly = false,
}) {
  final tables = ref.read(tablesProvider).valueOrNull ?? const <PosTable>[];
  final options =
      tables
          .where((t) => t.id != exclude.id && (!freeOnly || t.isFree))
          .toList()
        ..sort((a, b) {
          if (a.isFree != b.isFree) return a.isFree ? -1 : 1;
          return a.label.compareTo(b.label);
        });

  return showModalBottomSheet<PosTable>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _TablePicker(title: title, body: body, options: options),
  );
}

class _TablePicker extends StatelessWidget {
  const _TablePicker({
    required this.title,
    required this.body,
    required this.options,
  });

  final String title;
  final String body;
  final List<PosTable> options;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(body, style: theme.textTheme.bodySmall),
            const SizedBox(height: 14),
            if (options.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'There is no other table to move this to. Add one on the web '
                  'app under Tables.',
                  style: theme.textTheme.bodyMedium,
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: options.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final table = options[i];
                    return ListTile(
                      minTileHeight: Tokens.tapTarget,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Tokens.radiusMd),
                        side: BorderSide(color: theme.colorScheme.outline),
                      ),
                      leading: TableGlyph(
                        seats: table.capacity,
                        filled: !table.isFree,
                        size: 28,
                      ),
                      title: Text('Table ${table.label}'),
                      subtitle: Text(
                        table.isFree ? 'Free' : 'In use — this would merge',
                      ),
                      onTap: () => Navigator.of(context).pop(table),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pick the dishes that are moving. Returns their `order_items` ids.
///
/// Voided lines are not offered: they are already off the bill, and moving one
/// would put a struck-through dish on a table nobody ordered it at.
Future<List<String>?> showSplitLinePicker({
  required BuildContext context,
  required PosOrder order,
  required String currency,
}) {
  final movable = order.lines.where((l) => !l.isVoid).toList();
  return showModalBottomSheet<List<String>>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _SplitLinePicker(lines: movable, currency: currency),
  );
}

class _SplitLinePicker extends StatefulWidget {
  const _SplitLinePicker({required this.lines, required this.currency});

  final List<PosOrderLine> lines;
  final String currency;

  @override
  State<_SplitLinePicker> createState() => _SplitLinePickerState();
}

class _SplitLinePickerState extends State<_SplitLinePicker> {
  final _picked = <String>{};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Everything would leave the original order empty, which is a transfer
    // wearing a costume — and the server would leave an orphan behind.
    final wouldEmpty =
        _picked.length == widget.lines.length && widget.lines.isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Which dishes are moving?', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'They move to a new order on the table you pick next. The rest '
              'stay where they are.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.lines.length,
                itemBuilder: (context, i) {
                  final line = widget.lines[i];
                  return CheckboxListTile(
                    // Key on the id, never on the content.
                    key: ValueKey(line.id),
                    value: _picked.contains(line.id),
                    onChanged: (on) => setState(() {
                      if (on ?? false) {
                        _picked.add(line.id);
                      } else {
                        _picked.remove(line.id);
                      }
                    }),
                    title: Text('${line.qty}× ${line.nameSnapshot}'),
                    subtitle: Text(
                      money(line.lineTotalCents, widget.currency),
                      style: (theme.textTheme.bodySmall ?? const TextStyle())
                          .tabular,
                    ),
                  );
                },
              ),
            ),
            if (wouldEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'That is every dish — transfer the whole order instead.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _picked.isEmpty || wouldEmpty
                      ? null
                      : () => Navigator.of(context).pop(_picked.toList()),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, Tokens.tapTarget),
                  ),
                  child: Text(
                    _picked.isEmpty
                        ? 'Pick dishes'
                        : 'Move ${_picked.length} '
                              'dish${_picked.length == 1 ? '' : 'es'}',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
