import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/tokens.dart';
import '../../data/supabase/team_repository.dart' show passwordProblem;

/// Type or generate a password for a staff member, to be told in person.
/// Returns the password, or null when dismissed. The caller writes.
///
/// [create] is the invite case — the account does not exist yet and is made
/// with this password. Copy of the web's `PasswordDialog`.
///
/// Owns its controller and disposes it in its own `State`.
Future<String?> showPasswordDialog(
  BuildContext context, {
  required String email,
  required bool create,
}) => showDialog<String>(
  context: context,
  builder: (_) => _PasswordDialog(email: email, create: create),
);

/// `xxxx-2345-xxxx`: letters, digits, letters. Look-alikes (0/O, 1/l/I) are
/// left out because this gets read aloud across a counter.
@visibleForTesting
String generatePassword([Random? random]) {
  final r = random ?? Random.secure();
  const letters = 'abcdefghjkmnpqrstuvwxyz';
  const digits = '23456789';
  String pick(String from, int n) =>
      List.generate(n, (_) => from[r.nextInt(from.length)]).join();
  return '${pick(letters, 4)}-${pick(digits, 4)}-${pick(letters, 4)}';
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.email, required this.create});

  final String email;
  final bool create;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _password = TextEditingController();
  bool _visible = false;
  bool _copied = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _password.addListener(() {
      if (_error != null || _copied) {
        setState(() {
          _error = null;
          _copied = false;
        });
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _generate() {
    _password.text = generatePassword();
    setState(() => _visible = true);
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: _password.text));
      if (mounted) setState(() => _copied = true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
        ?..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              "Couldn't copy — show the password and copy it by hand.",
            ),
          ),
        );
    }
  }

  void _submit() {
    final problem = passwordProblem(_password.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.of(context).pop(_password.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = _password.text.length >= 8;
    return AlertDialog(
      title: Text(widget.create ? 'Create login' : 'Set a new password'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.email, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: !_visible,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              maxLength: 72,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: InputDecoration(
                labelText: widget.create ? 'Password' : 'New password',
                helperText: 'At least 8 characters, with letters and numbers.',
                helperMaxLines: 2,
                errorText: _error,
                border: const OutlineInputBorder(),
                counterText: '',
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: _visible ? 'Hide password' : 'Show password',
                      onPressed: () => setState(() => _visible = !_visible),
                      icon: Icon(
                        _visible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy password',
                      onPressed: _password.text.isEmpty ? null : _copy,
                      icon: Icon(_copied ? Icons.check : Icons.copy_outlined),
                    ),
                  ],
                ),
              ),
              onSubmitted: (_) => ready ? _submit() : null,
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _generate,
                icon: const Icon(Icons.casino_outlined, size: 18),
                label: const Text('Generate one'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.create
                  ? 'We create their account and add them to the team as '
                        'active. Nothing is emailed — tell them the password '
                        'in person.'
                  : 'Their old password stops working right away. Nothing is '
                        'emailed — tell them the new one in person.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, Tokens.tapTarget),
          ),
          onPressed: ready ? _submit : null,
          child: Text(widget.create ? 'Create login' : 'Set password'),
        ),
      ],
    );
  }
}
