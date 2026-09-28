import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_scaffold.dart';
import '../../core/widgets/choice_chip.dart';
import '../../data/supabase/menu_repository.dart';
import '../../data/supabase/pos_repository.dart' show PosFailure;
import '../tenant/tenant_providers.dart';
import 'menu_providers.dart';

/// The times a dish is on the menu — breakfast only, weekend special. No
/// windows means any time. Times are the restaurant's own clock, the same
/// wall-clock values the web editor writes.
class ItemAvailabilityScreen extends ConsumerStatefulWidget {
  const ItemAvailabilityScreen({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<ItemAvailabilityScreen> createState() =>
      _ItemAvailabilityScreenState();
}

class _ItemAvailabilityScreenState
    extends ConsumerState<ItemAvailabilityScreen> {
  bool _busy = false;

  Future<void> _run(
    Future<void> Function(MenuRepository r) work,
    String done,
  ) async {
    final tenant = ref.read(activeTenantProvider);
    if (tenant == null || _busy) return;
    setState(() => _busy = true);
    String message;
    try {
      await work(ref.read(menuRepositoryProvider(tenant.tenantId)));
      message = done;
      ref.invalidate(menuEditItemsProvider);
    } on PosFailure catch (e) {
      message = e.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _add() async {
    final w = await showModalBottomSheet<_Window>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _WindowSheet(),
    );
    if (w == null) return;
    await _run(
      (r) => r.addAvailability(
        itemId: widget.itemId,
        dayOfWeek: w.day,
        start: w.start,
        end: w.end,
      ),
      'Time window added.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = ref.watch(canEditMenuProvider);
    final item = (ref.watch(menuEditItemsProvider).valueOrNull ?? const [])
        .where((i) => i.id == widget.itemId)
        .firstOrNull;
    final windows = item?.availability ?? const <MenuAvailability>[];

    return AppScaffold(
      title: item == null ? 'When it’s sold' : 'When · ${item.name}',
      showDrawer: false,
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _add,
              icon: const Icon(Icons.add),
              label: const Text('Add time window'),
            )
          : null,
      body: windows.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Sold any time. Add a window to limit it — breakfast from '
                  '07:00 to 11:00, or Saturdays only.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              children: [
                for (final w in windows)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      minTileHeight: 56,
                      leading: const Icon(Icons.schedule),
                      title: Text(w.dayLabel),
                      subtitle: Text(w.window),
                      trailing: canEdit
                          ? IconButton(
                              tooltip:
                                  'Remove ${w.dayLabel} ${w.window} window',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: _busy
                                  ? null
                                  : () => _run(
                                      (r) => r.removeAvailability(w.id),
                                      'Window removed.',
                                    ),
                            )
                          : null,
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Window {
  const _Window(this.day, this.start, this.end);

  final int? day;
  final String start;
  final String end;
}

class _WindowSheet extends StatefulWidget {
  const _WindowSheet();

  @override
  State<_WindowSheet> createState() => _WindowSheetState();
}

class _WindowSheetState extends State<_WindowSheet> {
  int? _day;
  TimeOfDay _start = const TimeOfDay(hour: 7, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 11, minute: 0);

  static String _hm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pick(bool start) async {
    final t = await showTimePicker(
      context: context,
      initialTime: start ? _start : _end,
    );
    if (t == null) return;
    setState(() => start ? _start = t : _end = t);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final same = _hm(_start) == _hm(_end);
    final overnight = _hm(_end).compareTo(_hm(_start)) < 0;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Add time window', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            Text('Day', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppChoiceChip(
                  label: 'Every day',
                  selected: _day == null,
                  showCheck: true,
                  onSelect: () => setState(() => _day = null),
                ),
                for (var d = 0; d < 7; d++)
                  AppChoiceChip(
                    label: dayNames[d].substring(0, 3),
                    selected: _day == d,
                    showCheck: true,
                    onSelect: () => setState(() => _day = d),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: () => _pick(true),
                    icon: const Icon(Icons.login),
                    label: Text('From ${_hm(_start)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: () => _pick(false),
                    icon: const Icon(Icons.logout),
                    label: Text('Until ${_hm(_end)}'),
                  ),
                ),
              ],
            ),
            if (same || overnight)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  same
                      ? 'Start and end are the same — pick a later end.'
                      : 'Ends after midnight, the next morning.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: same ? theme.colorScheme.error : null,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: same
                  ? null
                  : () => Navigator.of(
                      context,
                    ).pop(_Window(_day, _hm(_start), _hm(_end))),
              child: const Text('Add window'),
            ),
          ],
        ),
      ),
    );
  }
}
