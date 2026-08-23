import 'package:flutter/material.dart';

/// Does what was typed count as the phrase?
///
/// Trimmed and case-insensitive, matching the web exactly. Anything stricter
/// punishes an autocapitalised first letter on a phone keyboard, which is a
/// worse outcome than the marginal safety it buys: the point of the phrase is
/// to force someone to read the name of the thing they are about to destroy,
/// not to test their typing.
bool phraseMatches(String typed, String phrase) =>
    typed.trim().toLowerCase() == phrase.trim().toLowerCase();

/// Last step before something irreversible: retype the phrase, or the button
/// stays dead.
///
/// Returns true only if the phrase matched and the button was pressed.
Future<bool> showConfirmPhraseDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String phrase,
  required String phraseHint,
  required String confirmLabel,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    // Not dismissible by tapping away, for once: this dialog is the last guard
    // in front of a destructive call and a stray tap should not clear it.
    barrierDismissible: false,
    builder: (context) => _ConfirmPhraseDialog(
      title: title,
      message: message,
      phrase: phrase,
      phraseHint: phraseHint,
      confirmLabel: confirmLabel,
    ),
  );
  return confirmed == true;
}

/// A `StatefulWidget` so the controller belongs to the dialog and dies with it.
/// One created beside `showDialog` and disposed after the await takes the app
/// down on `'_dependents.isEmpty': is not true`.
class _ConfirmPhraseDialog extends StatefulWidget {
  const _ConfirmPhraseDialog({
    required this.title,
    required this.message,
    required this.phrase,
    required this.phraseHint,
    required this.confirmLabel,
  });

  final String title;
  final String message;
  final String phrase;
  final String phraseHint;
  final String confirmLabel;

  @override
  State<_ConfirmPhraseDialog> createState() => _ConfirmPhraseDialogState();
}

class _ConfirmPhraseDialogState extends State<_ConfirmPhraseDialog> {
  final _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  bool get _matches => phraseMatches(_typed.text, widget.phrase);

  void _confirm() {
    if (!_matches) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          const SizedBox(height: 16),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Type '),
                TextSpan(
                  text: widget.phrase,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: ' (${widget.phraseHint})',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
                const TextSpan(text: ' to confirm.'),
              ],
            ),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _typed,
            autofocus: true,
            // All three off: a keyboard that helpfully capitalises or corrects
            // the restaurant's name turns the guard into a fight.
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.none,
            decoration: InputDecoration(
              hintText: widget.phrase,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _confirm(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.tonal(
          onPressed: _matches ? _confirm : null,
          style: FilledButton.styleFrom(
            foregroundColor: theme.colorScheme.onErrorContainer,
            backgroundColor: theme.colorScheme.errorContainer,
          ),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
