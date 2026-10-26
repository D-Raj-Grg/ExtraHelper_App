import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../data/supabase/tables_admin_repository.dart'
    show validateTableDraft;
import '../pos/models.dart';

/// What the add-table sheet hands back.
class TableDraft {
  const TableDraft({required this.label, required this.capacity, this.floorId});

  final String label;
  final int capacity;
  final String? floorId;
}

Future<TableDraft?> showAddTableSheet(
  BuildContext context, {
  required List<PosFloor> floors,
  String? initialFloorId,
}) => showModalBottomSheet<TableDraft>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (sheetContext) => Padding(
    padding: EdgeInsets.only(
      bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
    ),
    child: AddTableSheet(floors: floors, initialFloorId: initialFloorId),
  ),
);

class AddTableSheet extends StatefulWidget {
  const AddTableSheet({super.key, required this.floors, this.initialFloorId});

  final List<PosFloor> floors;
  final String? initialFloorId;

  @override
  State<AddTableSheet> createState() => _AddTableSheetState();
}

class _AddTableSheetState extends State<AddTableSheet> {
  final _label = TextEditingController();
  int _capacity = 4;
  String? _floorId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _floorId = widget.floors.any((f) => f.id == widget.initialFloorId)
        ? widget.initialFloorId
        : null;
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  void _bump(int by) =>
      setState(() => _capacity = (_capacity + by).clamp(1, 50));

  void _submit() {
    final label = _label.text.trim();
    final problem = validateTableDraft(label, _capacity);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.of(
      context,
    ).pop(TableDraft(label: label, capacity: _capacity, floorId: _floorId));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Add table',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _label,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: const InputDecoration(
                labelText: 'Table label',
                hintText: 'T7',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text('Seats', style: theme.textTheme.bodyLarge),
                ),
                IconButton(
                  tooltip: 'Fewer seats',
                  constraints: const BoxConstraints.tightFor(
                    width: Tokens.tapTarget,
                    height: Tokens.tapTarget,
                  ),
                  onPressed: _capacity > 1 ? () => _bump(-1) : null,
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    '$_capacity',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'More seats',
                  constraints: const BoxConstraints.tightFor(
                    width: Tokens.tapTarget,
                    height: Tokens.tapTarget,
                  ),
                  onPressed: _capacity < 50 ? () => _bump(1) : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            if (widget.floors.isNotEmpty) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                initialValue: _floorId,
                decoration: const InputDecoration(labelText: 'Floor'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('No floor'),
                  ),
                  for (final f in widget.floors)
                    DropdownMenuItem<String?>(value: f.id, child: Text(f.name)),
                ],
                onChanged: (v) => setState(() => _floorId = v),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, Tokens.tapTarget),
              ),
              child: const Text('Add table'),
            ),
          ],
        ),
      ),
    );
  }
}
