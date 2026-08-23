import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../data/supabase/danger_repository.dart';

/// Pick who the restaurant is being handed to.
///
/// Returns the chosen member; the caller then asks for the confirm phrase. Two
/// steps on purpose — choosing a name and agreeing to lose the restaurant are
/// different decisions, and one dialog that does both gets tapped through.
Future<TransferMember?> showTransferOwnershipSheet(
  BuildContext context, {
  required List<TransferMember> members,
}) => showModalBottomSheet<TransferMember>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _TransferSheet(members: members),
);

class _TransferSheet extends StatefulWidget {
  const _TransferSheet({required this.members});

  final List<TransferMember> members;

  @override
  State<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<_TransferSheet> {
  TransferMember? _picked;
  bool _understood = false;

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
              'Transfer ownership',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            // The web's five bullets, verbatim: an owner who reads this on one
            // client and acts on the other should not find a different set of
            // consequences described.
            for (final line in const [
              'A restaurant has exactly one owner at a time.',
              'Your role changes to Manager once you transfer.',
              'The new owner can remove you or delete the restaurant.',
              'You can only transfer to someone already on your team.',
              'This cannot be reversed — the new owner must transfer it back.',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ', style: theme.textTheme.bodySmall),
                    Expanded(
                      child: Text(line, style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            if (widget.members.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Nobody else is on the team yet. Add a manager first, on the '
                  'web under Team.',
                  style: theme.textTheme.bodyMedium,
                ),
              )
            else
              Flexible(
                child: RadioGroup<String>(
                  groupValue: _picked?.userId,
                  onChanged: (userId) => setState(() {
                    _picked = widget.members
                        .where((m) => m.userId == userId)
                        .firstOrNull;
                  }),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final member in widget.members)
                        RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          value: member.userId,
                          title: Text(member.email),
                          subtitle: member.roleName == null
                              ? null
                              : Text(member.roleName!),
                        ),
                    ],
                  ),
                ),
              ),
            if (widget.members.isNotEmpty) ...[
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _understood,
                onChanged: (value) =>
                    setState(() => _understood = value ?? false),
                title: const Text(
                  'I understand I will no longer own this restaurant.',
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: Tokens.tapTarget + 4,
                child: FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    foregroundColor: theme.colorScheme.onErrorContainer,
                    backgroundColor: theme.colorScheme.errorContainer,
                  ),
                  onPressed: _picked != null && _understood
                      ? () => Navigator.of(context).pop(_picked)
                      : null,
                  child: const Text('Continue'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
