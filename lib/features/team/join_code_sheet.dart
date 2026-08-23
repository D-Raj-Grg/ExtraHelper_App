import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/widgets/choice_chip.dart';
import 'team_providers.dart';

/// "Leave it to the server's default" — mapped back to null by the caller,
/// because `create_join_code` defaults the argument itself.
const kDefaultJoinRole = '__default__';

/// Which role a join code should hand out. Pops the choice; the caller writes.
Future<String?> showJoinCodeSheet(
  BuildContext context, {
  required List<RoleOption> roles,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Join code', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Anyone with the code can ask to join as this role. You still '
            'approve them before they get in.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppChoiceChip(
                label: 'Default (Waiter)',
                selected: false,
                onSelect: () => Navigator.of(context).pop(kDefaultJoinRole),
              ),
              for (final role in roles)
                AppChoiceChip(
                  label: role.name,
                  selected: false,
                  onSelect: () => Navigator.of(context).pop(role.id),
                ),
            ],
          ),
        ],
      ),
    ),
  ),
);

/// Show a code that was just created.
Future<void> showJoinCodeResultDialog(
  BuildContext context, {
  required String code,
}) => showDialog<void>(
  context: context,
  builder: (context) => _JoinCodeResultDialog(code: code),
);

class _JoinCodeResultDialog extends StatefulWidget {
  const _JoinCodeResultDialog({required this.code});

  final String code;

  @override
  State<_JoinCodeResultDialog> createState() => _JoinCodeResultDialogState();
}

class _JoinCodeResultDialogState extends State<_JoinCodeResultDialog> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Share this code'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Selectable, so "write it down" below is honest even if the copy
          // button fails.
          SelectableText(
            widget.code,
            style: theme.textTheme.titleLarge?.copyWith(
              fontFamily: 'monospace',
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "They'll appear here as waiting for approval until you approve "
            'them.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: _copy,
          icon: Icon(_copied ? Icons.check : Icons.copy_outlined),
          label: Text(_copied ? 'Copied' : 'Copy'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.code));
      if (!mounted) return;
      setState(() => _copied = true);
      await Future<void>.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _copied = false);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              "Couldn't copy — the code is on screen, write it down.",
            ),
          ),
        );
    }
  }
}
