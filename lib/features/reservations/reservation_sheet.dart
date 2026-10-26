import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/when.dart';
import '../../core/theme/tokens.dart';
import '../../data/supabase/pos_repository.dart' show PosFailure;
import '../../data/supabase/reservations_repository.dart';
import '../pos/pos_providers.dart';
import '../tenant/tenant_providers.dart';
import 'reservations_providers.dart';

/// New reservation form. Creates the booking itself and refreshes the list;
/// resolves true when one was made.
///
/// Owns its controllers in its own `State` (see the coupon sheet for why).
Future<bool?> showReservationSheet(BuildContext context) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        // The sheet's own context, so the padding follows the keyboard.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: const _ReservationSheet(),
      ),
    );

class _ReservationSheet extends ConsumerStatefulWidget {
  const _ReservationSheet();

  @override
  ConsumerState<_ReservationSheet> createState() => _ReservationSheetState();
}

class _ReservationSheetState extends ConsumerState<_ReservationSheet> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _notes;
  int _party = 2;
  late DateTime _when;
  String? _tableId;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _phone = TextEditingController();
    _notes = TextEditingController();
    final n = DateTime.now();
    _when = DateTime(n.year, n.month, n.day, n.hour + 1);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _when.isBefore(today) ? today : _when,
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(
      () => _when = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _when.hour,
        _when.minute,
      ),
    );
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
    );
    if (picked == null) return;
    setState(
      () => _when = DateTime(
        _when.year,
        _when.month,
        _when.day,
        picked.hour,
        picked.minute,
      ),
    );
  }

  Future<void> _submit() async {
    final draft = ReservationDraft(
      name: _name.text,
      phone: _phone.text,
      partySize: _party,
      when: _when,
      tableId: _tableId,
      notes: _notes.text,
    );
    final problem = draft.validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final tenant = ref.read(activeTenantProvider);
    if (tenant == null) return;
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      await ref
          .read(reservationsRepositoryProvider(tenant.tenantId))
          .create(draft);
      ref.invalidate(reservationsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Reservation added.')));
      Navigator.of(context).pop(true);
    } on PosFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't save the reservation.");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tables = ref.watch(tablesProvider).valueOrNull ?? const [];
    final tableValid = tables.any((t) => t.id == _tableId);
    const tap = Size(0, Tokens.tapTarget);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('New reservation', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Guest name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone (optional)'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text('Party size', style: theme.textTheme.bodyLarge),
              ),
              IconButton(
                tooltip: 'Fewer guests',
                constraints: const BoxConstraints.tightFor(
                  width: Tokens.tapTarget,
                  height: Tokens.tapTarget,
                ),
                onPressed: _party > 1 ? () => setState(() => _party--) : null,
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 36,
                child: Text(
                  '$_party',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'More guests',
                constraints: const BoxConstraints.tightFor(
                  width: Tokens.tapTarget,
                  height: Tokens.tapTarget,
                ),
                onPressed: _party < 50 ? () => setState(() => _party++) : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: tap),
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(billDate(_when)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: tap),
                  onPressed: _pickTime,
                  icon: const Icon(Icons.schedule, size: 18),
                  label: Text(clockTime(_when)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            key: ValueKey('tables-${tables.length}'),
            initialValue: tableValid ? _tableId : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Table (optional)'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('No table yet'),
              ),
              for (final t in tables)
                DropdownMenuItem<String?>(
                  value: t.id,
                  child: Text('${t.label} · seats ${t.capacity}'),
                ),
            ],
            onChanged: (v) => setState(() => _tableId = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: tap),
            onPressed: _saving ? null : _submit,
            child: Text(_saving ? 'Saving…' : 'Add reservation'),
          ),
        ],
      ),
    );
  }
}
