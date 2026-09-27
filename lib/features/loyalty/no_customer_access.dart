import 'package:flutter/material.dart';

/// The locked door both Customers screens show to someone without
/// `loyalty.view`. One widget, so the list and the detail cannot drift into
/// two different explanations of the same rule.
class NoCustomerAccess extends StatelessWidget {
  const NoCustomerAccess({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text('No customer access', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              "Your role in this restaurant doesn't include seeing "
              'customers. An owner or manager can change that under Team.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
