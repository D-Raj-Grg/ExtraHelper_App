import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/choice_chip.dart';
import 'team_providers.dart';

/// Who to add, and as what. The sheet collects it; the caller writes it.
class AddMemberDraft {
  const AddMemberDraft({required this.email, required this.roleId});

  final String email;
  final String roleId;
}

/// Add someone by email.
///
/// Pops a draft rather than writing: a sheet's controllers must not outlive its
/// `State`, and a sheet that awaits its own write is how they do.
Future<AddMemberDraft?> showAddMemberSheet(
  BuildContext context, {
  required List<RoleOption> roles,
}) => showModalBottomSheet<AddMemberDraft>(
  context: context,
  isScrollControlled: true,
  builder: (context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: _AddMemberSheet(roles: roles),
  ),
);

class _AddMemberSheet extends StatefulWidget {
  const _AddMemberSheet({required this.roles});

  final List<RoleOption> roles;

  @override
  State<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<_AddMemberSheet> {
  final _email = TextEditingController();

  /// **No default.** Pre-selecting the first-sorted role is how someone gets
  /// handed Owner by accident; the web deliberately starts empty too.
  String? _roleId;

  static final _pattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  bool get _valid => _pattern.hasMatch(_email.text.trim()) && _roleId != null;

  @override
  void initState() {
    super.initState();
    _email.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add someone', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textCapitalization: TextCapitalization.none,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'name@example.com',
                constraints: BoxConstraints(minHeight: Tokens.tapTarget),
              ),
            ),
            const SizedBox(height: 16),
            Text('Role', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final role in widget.roles)
                  AppChoiceChip(
                    label: role.name,
                    selected: _roleId == role.id,
                    showCheck: true,
                    onSelect: () => setState(() => _roleId = role.id),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'If they already have an account they join right away. '
              'Otherwise we hold an invite until they sign up.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _valid
                    ? () => Navigator.of(context).pop(
                        AddMemberDraft(
                          email: _email.text.trim(),
                          roleId: _roleId!,
                        ),
                      )
                    : null,
                child: const Text('Add'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
