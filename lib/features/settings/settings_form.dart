import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// The bits every settings form screen repeats.
///
/// Not a framework — three small widgets and one dialog, kept together so the
/// save bar, the read-only notice and the discard prompt say the same thing on
/// every screen. A staff app that words "you can't change this" four different
/// ways reads like four different apps.

/// A titled group of fields. Matches the web's card-per-concern grouping so the
/// two clients can be talked about with the same words over the phone.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.detail,
  });

  final String title;
  final String? detail;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 4),
              Text(
                detail!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// A label above a field, in the weight the section titles are not.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.detail});

  final String text;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (detail != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              detail!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// The bar along the bottom: one button, or the sentence explaining why there
/// isn't one.
///
/// In a [SafeArea] because on a gesture-navigation phone the home indicator
/// sits exactly where a full-width button's bottom edge wants to be.
class SettingsSaveBar extends StatelessWidget {
  const SettingsSaveBar({
    super.key,
    required this.canEdit,
    required this.dirty,
    required this.busy,
    required this.onSave,
    this.readOnlyNotice = 'An owner or manager can change these.',
    this.label = 'Save',
  });

  final bool canEdit;
  final bool dirty;
  final bool busy;
  final VoidCallback onSave;
  final String readOnlyNotice;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 3,
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: canEdit
              ? SizedBox(
                  height: Tokens.tapTarget + 4,
                  child: FilledButton(
                    onPressed: dirty && !busy ? onSave : null,
                    child: busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(label),
                  ),
                )
              : Row(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        readOnlyNotice,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Asked when someone backs out of a screen with unsaved edits.
///
/// Returns true to leave. Phrased around what is lost, not around the button
/// that was pressed — "Discard" alone is ambiguous about which way is which.
Future<bool> confirmDiscard(BuildContext context) async {
  final leave = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Leave without saving?'),
      content: const Text('Your changes on this screen will be lost.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep editing'),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Discard'),
        ),
      ],
    ),
  );
  return leave == true;
}
