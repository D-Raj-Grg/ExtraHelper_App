import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../data/supabase/branches_repository.dart';

/// A branch as typed, before it is saved.
class BranchDraft {
  const BranchDraft({required this.name, this.address});

  final String name;
  final String? address;
}

/// Add or edit one branch.
///
/// Owns its controllers and disposes them in its own `State` — see
/// `menu/variant_sheet.dart` for the crash this avoids.
Future<BranchDraft?> showBranchSheet(
  BuildContext context, {
  Branch? editing,
}) => showModalBottomSheet<BranchDraft>(
  context: context,
  isScrollControlled: true,
  builder: (_) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: _BranchSheet(editing: editing),
  ),
);

class _BranchSheet extends StatefulWidget {
  const _BranchSheet({this.editing});

  final Branch? editing;

  @override
  State<_BranchSheet> createState() => _BranchSheetState();
}

class _BranchSheetState extends State<_BranchSheet> {
  late final TextEditingController _name;
  late final TextEditingController _address;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.editing?.name ?? '');
    _address = TextEditingController(text: widget.editing?.address ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  void _submit() {
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = 'Give the branch a name.');
      return;
    }
    Navigator.of(context).pop(
      BranchDraft(name: _name.text.trim(), address: _address.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.editing == null ? 'Add a branch' : 'Edit branch',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: widget.editing == null,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Name',
                hintText: 'Lakeside, Airport, Main street',
                border: const OutlineInputBorder(),
                errorText: _nameError,
              ),
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _address,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Address',
                helperText: 'Optional. Printed on receipts for this branch.',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: Tokens.tapTarget + 4,
              child: FilledButton(
                onPressed: _submit,
                child: Text(
                  widget.editing == null ? 'Add branch' : 'Save branch',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
