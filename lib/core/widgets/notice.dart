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
