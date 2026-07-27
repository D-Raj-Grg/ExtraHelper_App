import 'package:flutter/material.dart';

/// Asks for the reason a fired line is being voided. Returns the trimmed
/// reason, or null if the waiter kept the line.
///
/// **The dialog owns its controller.** The caller must not create one and
/// dispose it after `await` — `showDialog`'s future resolves a frame before the
/// `TextField` is actually unmounted, so a caller-side `dispose()` kills the
/// controller out from under a live widget. That crashed the whole app with
/// `'_dependents.isEmpty': is not true`: the field's own `dispose` throws on the
/// dead controller, its element never finishes deactivating, and the
/// `InheritedElement`s above it assert. Covered by `void_reason_dialog_test`.
Future<String?> showVoidReasonDialog({
  required BuildContext context,
  required String title,
  required String body,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _VoidReasonDialog(title: title, body: body),
  );
}

class _VoidReasonDialog extends StatefulWidget {
  const _VoidReasonDialog({required this.title, required this.body});

  final String title;
  final String body;

  @override
  State<_VoidReasonDialog> createState() => _VoidReasonDialogState();
}

class _VoidReasonDialogState extends State<_VoidReasonDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _reason.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.body),
          const SizedBox(height: 14),
          TextField(
            controller: _reason,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: 'Reason',
              hintText: 'e.g. guest changed their mind',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Keep it'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Void line')),
      ],
    );
  }
}
