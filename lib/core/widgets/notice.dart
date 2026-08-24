import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A boxed message the user can act on.
///
/// Icon **and** colour **and** words, never colour alone — this has to survive
/// a greyscale screenshot, so the icon carries the state and the tint only
/// reinforces it.
///
/// Lifted out of `login_screen.dart` and `join_code_screen.dart`, which had
/// grown two copies of the same box, when signup, email verification and
/// onboarding needed a third. One shape, so a failure reads identically
/// wherever it happens.
class AppNotice extends StatelessWidget {
  const AppNotice({
    super.key,
    required this.message,
    required this.icon,
    required this.color,
  });

  final String message;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// The error flavour of [AppNotice]. Its own name because it is by far the most
/// common one, and spelling the icon and colour at every call site is how they
/// drift apart.
class ErrorNotice extends StatelessWidget {
  const ErrorNotice({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => AppNotice(
    message: message,
    icon: Icons.error_outline,
    color: Theme.of(context).colorScheme.error,
  );
}

/// A notice you can act on: the message, the detail underneath, and the way
/// out.
///
/// Lifted out of `account_screen.dart`, which had grown the third hand-rolled
/// copy of [AppNotice]'s box when the shell needed the same thing. A failed
/// read is not an empty result — it has a recovery, and the recovery belongs in
/// the box that reports it.
///
/// [detail] is the raw failure. Kept, because "couldn't load" with nothing
/// under it is a screen nobody can debug from a photo sent by a waiter.
class RetryNotice extends StatelessWidget {
  const RetryNotice({
    super.key,
    required this.message,
    required this.onRetry,
    this.detail,
    this.icon = Icons.error_outline,
    this.color,
  });

  final String message;
  final VoidCallback onRetry;
  final String? detail;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = color ?? theme.colorScheme.error;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.1),
        border: Border.all(color: tone, width: 1.5),
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: tone),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(color: tone),
                ),
              ),
            ],
          ),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(detail!, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
