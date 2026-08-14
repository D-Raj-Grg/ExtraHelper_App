import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// Asks how many people are eating. Returns the count, or null if the waiter
/// backed out.
///
/// A stepper rather than a keyboard: this is answered at the table, one-handed,
/// and the number is nearly always small. `place_staff_order` and the web action
/// both clamp to 1..200, so the buttons stop where the server does rather than
/// letting someone type a figure that gets silently changed.
Future<int?> showGuestsDialog({required BuildContext context, int? current}) {
  return showDialog<int>(
    context: context,
    builder: (_) => _GuestsDialog(current: current),
  );
}

const _minGuests = 1;
const _maxGuests = 200;

class _GuestsDialog extends StatefulWidget {
  const _GuestsDialog({this.current});

  final int? current;

  @override
  State<_GuestsDialog> createState() => _GuestsDialogState();
}

class _GuestsDialogState extends State<_GuestsDialog> {
  late int _count = (widget.current ?? 2).clamp(_minGuests, _maxGuests);

  void _by(int delta) =>
      setState(() => _count = (_count + delta).clamp(_minGuests, _maxGuests));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('How many guests?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Covers are what turn takings into an average spend per guest on '
            'the reports.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                onPressed: _count > _minGuests ? () => _by(-1) : null,
                iconSize: 22,
                constraints: const BoxConstraints(
                  minWidth: Tokens.tapTarget,
                  minHeight: Tokens.tapTarget,
                ),
                icon: const Icon(Icons.remove),
                tooltip: 'One fewer',
              ),
              SizedBox(
                width: 96,
                child: Text(
                  '$_count',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium,
                  semanticsLabel: '$_count guest${_count == 1 ? '' : 's'}',
                ),
              ),
              IconButton.filledTonal(
                onPressed: _count < _maxGuests ? () => _by(1) : null,
                iconSize: 22,
                constraints: const BoxConstraints(
                  minWidth: Tokens.tapTarget,
                  minHeight: Tokens.tapTarget,
                ),
                icon: const Icon(Icons.add),
                tooltip: 'One more',
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_count),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
