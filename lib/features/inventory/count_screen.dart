import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/supabase/inventory_repository.dart';
import '../../data/sync/sync_providers.dart';
import '../tenant/tenant_providers.dart';
import 'inventory_providers.dart';
import 'quantity.dart';
import 'scanner_sheet.dart';

/// Counting a store room: for each thing, what is actually on the shelf.
///
/// The counted number goes **through the outbox**. A walk-in or a back store
/// room is where coverage dies, and a count is a job you walk into that room to
/// do — so "saved, it goes up when you're back on coverage" is the honest
/// answer, and safe, because the value is absolute rather than a delta.
class CountScreen extends ConsumerStatefulWidget {
  const CountScreen({required this.countId, super.key});

  final String countId;

  @override
  ConsumerState<CountScreen> createState() => _CountScreenState();
}

class _CountScreenState extends ConsumerState<CountScreen> {
  /// Locally counted values, keyed by count-line id. Held here so a queued line
  /// keeps showing the number that was typed even before the server has it —
  /// the store keeper must never wonder whether the tap registered.
  final Map<String, double> _local = {};

  /// Lines with a call in flight right now.
  final Set<String> _pending = {};

  /// Lines that are queued but have **not** reached the server — offline. The
  /// call has returned (durably), so [_pending] is empty, but posting now would
  /// reconcile stock against numbers the server has never seen.
  final Set<String> _owed = {};

  /// Owned so a scan can put what it read into the box. Without a controller
  /// the list filtered while the field still showed the old text.
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = ref.watch(countLinesProvider(widget.countId));
    final canEdit = ref.watch(canEditInventoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock count'),
        actions: [
          IconButton(
            tooltip: 'Scan a label',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => _scan(lines.valueOrNull ?? const []),
          ),
        ],
      ),
      body: lines.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_off,
                  size: 40,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 12),
                Text(
                  "Couldn't open the count",
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  '$e',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () =>
                      ref.invalidate(countLinesProvider(widget.countId)),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (all) {
          // A count opened before anything was in the store room has no lines
          // at all. Without this it rendered as a blank page under a live
          // "Post the count" button — states are not optional.
          if (all.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 40,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'This count has nothing in it',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'It was opened before anything was in the store room. Go '
                      'back and start a fresh count — it picks up everything '
                      'there now.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            );
          }

          final q = _search.text.trim().toLowerCase();
          final visible = q.isEmpty
              ? all
              : all
                    .where(
                      (l) =>
                          l.name.toLowerCase().contains(q) ||
                          (l.barcode?.toLowerCase().contains(q) ?? false),
                    )
                    .toList();
          // **Not** "how many are counted".
          //
          // `start_stock_count` seeds every line's `actual_qty` with the
          // system's own on-hand figure, so every line arrives already
          // "counted" and a progress bar off that read 2 of 2 before anyone had
          // walked to a shelf. What is actually true, and actually useful at
          // posting time, is how many lines now disagree with the system —
          // those are the ones that will move stock.
          final differing = all.where((l) {
            final v = _local[l.id] ?? l.actualQty;
            return v != null && v != l.theoreticalQty;
          }).length;

          return Column(
            children: [
              _Summary(differing: differing, total: all.length),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Jump to an item',
                    constraints: BoxConstraints(minHeight: Tokens.tapTarget),
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final line = visible[i];
                    final value = _local[line.id] ?? line.actualQty;
                    return _CountRow(
                      // Keyed on the line's **stable id**. Without a key,
                      // Flutter matches rows by index, so filtering the list
                      // hands row 0's live controller — holding a number typed
                      // for another shelf — to whatever item is now first.
                      // That writes a real count against the wrong item.
                      key: ValueKey(line.id),
                      line: line,
                      value: value,
                      isPending: _pending.contains(line.id),
                      isOwed: _owed.contains(line.id),
                      enabled: canEdit,
                      onCount: (v) => _record(line, v),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      // Nothing to post when the count has no lines — an enabled button that
      // does nothing is worse than no button.
      bottomNavigationBar: canEdit && (lines.valueOrNull?.isNotEmpty ?? false)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                // Posting reconciles stock to what the **server** holds. Doing
                // that while counts are still sitting in the outbox would
                // reconcile against numbers it has never seen — and the count
                // is closed afterwards, so those queued writes would then be
                // refused. Blocked until the queue is empty.
                child: FilledButton.icon(
                  onPressed: _pending.isEmpty && _owed.isEmpty ? _post : null,
                  icon: Icon(
                    _owed.isEmpty
                        ? Icons.check_circle_outline
                        : Icons.cloud_upload_outlined,
                  ),
                  label: Text(switch ((_pending.length, _owed.length)) {
                    (0, 0) => 'Post the count',
                    (final p, 0) => '$p still saving',
                    (_, final o) =>
                      '$o count${o == 1 ? '' : 's'} waiting for coverage',
                  }),
                ),
              ),
            )
          : null,
    );
  }

  Future<void> _scan(List<StockCountLine> lines) async {
    final code = await showScannerSheet(context);
    if (code == null || !mounted) return;
    final match = lines.where((l) => l.barcode == code).firstOrNull;
    setState(() => _search.text = match?.name ?? code);
    if (match == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nothing in this count carries the code $code.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _record(StockCountLine line, double actual) async {
    final queue = ref.read(orderQueueProvider);
    if (queue == null) return;

    setState(() {
      _local[line.id] = actual;
      _pending.add(line.id);
    });

    final outcome = await queue.setCountActual(
      countItemId: line.id,
      actual: actual,
    );
    if (!mounted) return;

    setState(() {
      _pending.remove(line.id);
      if (outcome.error == null && !outcome.synced) {
        _owed.add(line.id);
      } else {
        _owed.remove(line.id);
      }
    });

    if (outcome.error != null) {
      // The server refused — say so and drop the optimistic number, or the
      // screen would keep showing a figure nobody recorded.
      setState(() => _local.remove(line.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(outcome.error ?? "That count wasn't saved.")),
      );
    } else if (!outcome.synced) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Saved. It goes up the moment you're back on coverage.",
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _post() async {
    final tenant = ref.read(activeTenantProvider);
    if (tenant == null) return;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (_) => const _PostSheet(),
    );
    if (ok != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final n = await ref
          .read(inventoryRepositoryProvider(tenant.tenantId))
          .postCount(widget.countId);
      ref.invalidate(inventoryItemsProvider);
      ref.invalidate(openCountProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            n == 0
                ? 'Posted. Everything matched — no stock changed.'
                : 'Posted. $n item${n == 1 ? '' : 's'} corrected.',
          ),
        ),
      );
      navigator.pop();
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

/// What posting this count would actually do.
class _Summary extends StatelessWidget {
  const _Summary({required this.differing, required this.total});

  final int differing;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Icon(
            differing == 0
                ? Icons.check_circle_outline
                : Icons.difference_outlined,
            size: 16,
            color: differing == 0
                ? semantic.goodText
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              differing == 0
                  ? '$total ${total == 1 ? 'item' : 'items'} · nothing differs from the system yet'
                  : '$total ${total == 1 ? 'item' : 'items'} · $differing '
                        '${differing == 1 ? 'differs' : 'differ'} from the system',
              style: theme.textTheme.labelMedium?.tabular,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountRow extends StatefulWidget {
  const _CountRow({
    required this.line,
    required this.value,
    required this.isPending,
    required this.isOwed,
    required this.enabled,
    required this.onCount,
    super.key,
  });

  final StockCountLine line;
  final double? value;
  final bool isPending;

  /// Queued, durable, but not on the server yet.
  final bool isOwed;

  final bool enabled;
  final ValueChanged<double> onCount;

  @override
  State<_CountRow> createState() => _CountRowState();
}

class _CountRowState extends State<_CountRow> {
  /// The row owns its controller. Keyed by the line's **stable id** upstream,
  /// never by its content — a signature key rebuilds the row on every keystroke
  /// and loses the caret mid-number.
  late final TextEditingController _controller = TextEditingController(
    text: widget.value == null ? '' : qty(widget.value!),
  );
  late final FocusNode _focus = FocusNode()..addListener(_onFocusChange);

  /// The model changed under us — a refusal dropped the optimistic number, or
  /// the count was refetched. Without this the field kept showing a figure the
  /// rest of the row had already disowned.
  ///
  /// Never while the field has focus: that would rewrite what someone is
  /// mid-way through typing.
  @override
  void didUpdateWidget(_CountRow old) {
    super.didUpdateWidget(old);
    if (_focus.hasFocus || widget.value == old.value) return;
    final text = widget.value == null ? '' : qty(widget.value!);
    if (_controller.text != text) _controller.text = text;
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Committed on blur rather than on every keystroke: typing "12" would
  /// otherwise queue a 1 and then a 12.
  void _onFocusChange() {
    if (_focus.hasFocus) return;
    _commit();
  }

  void _commit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final parsed = double.tryParse(text);
    if (parsed == null || parsed < 0) {
      _controller.text = widget.value == null ? '' : qty(widget.value!);
      return;
    }
    if (parsed == widget.value) return;
    widget.onCount(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final line = widget.line;
    final counted = widget.value;
    final variance = counted == null ? null : counted - line.theoreticalQty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.name, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 2),
                // Wrap, not Row: with a variance *and* a queued badge this
                // overflowed by 57px on a 1080-wide phone, and a long item name
                // or a larger text scale would only make it worse.
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 2,
                  runSpacing: 2,
                  children: [
                    Text(
                      'System ${qtyWithUom(line.theoreticalQty, line.uom)}',
                      style: theme.textTheme.bodySmall?.tabular,
                    ),
                    if (variance != null && variance != 0) ...[
                      const SizedBox(width: 8),
                      Icon(
                        variance > 0
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
                        size: 13,
                        color: variance > 0
                            ? semantic.goodText
                            : semantic.attentionText,
                      ),
                      const SizedBox(width: 2),
                      // Word + sign + arrow. Three signals, none of them colour.
                      Text(
                        '${variance > 0 ? 'Over' : 'Short'} '
                        '${signedQty(variance, line.uom)}',
                        style: theme.textTheme.bodySmall?.tabular.copyWith(
                          color: variance > 0
                              ? semantic.goodText
                              : semantic.attentionText,
                        ),
                      ),
                    ],
                    if (widget.isPending || widget.isOwed) ...[
                      const SizedBox(width: 8),
                      Icon(
                        widget.isOwed
                            ? Icons.cloud_upload_outlined
                            : Icons.schedule,
                        size: 13,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        widget.isOwed ? 'Waiting for coverage' : 'Saving',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 104,
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              enabled: widget.enabled,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              textAlign: TextAlign.right,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _commit(),
              style: theme.textTheme.titleMedium?.tabular,
              decoration: InputDecoration(
                isDense: true,
                hintText: '—',
                suffixText: line.uom,
                constraints: const BoxConstraints(minHeight: Tokens.tapTarget),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Posting is the moment stock actually moves, so it names the consequence.
class _PostSheet extends StatelessWidget {
  const _PostSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle_outline),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Post this count?',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              // No "lines nobody counted are left alone" here: the server seeds
              // every line with the system's own figure, so from this app there
              // is no such thing as an untouched line. Saying otherwise would
              // promise a safety net that does not exist.
              'On-hand becomes what you counted, every difference is written to '
              'the stock ledger with your name on it, and the count can no '
              'longer be edited.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Keep counting'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Post the count'),
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
