import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_scaffold.dart';
import '../../core/env.dart';
import 'plan_usage_card.dart';
import 'settings_providers.dart';

/// What this restaurant is on, and what it is using.
///
/// **Read-only.** Selling a subscription inside the app would drag in StoreKit
/// and App Review's in-app-purchase rules for a product the web already sells
/// through its own gateway. What a manager actually needs on a phone is the
/// answer to "are we near a limit", and that is what this shows.
class PlanUsageScreen extends ConsumerWidget {
  const PlanUsageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dangerDataProvider);
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Plan & usage',
      showDrawer: false,
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Problem(
          message: '$e',
          onRetry: () => ref.invalidate(dangerDataProvider),
        ),
        data: (value) {
          if (value == null) {
            return const Center(child: Text('No restaurant selected.'));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(dangerDataProvider),
            child: ListView(
              padding: const EdgeInsets.only(top: 6, bottom: 24),
              children: [
                Card(
                  margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                  child: ListTile(
                    leading: const Icon(Icons.workspace_premium_outlined),
                    title: Text(value.planLabel),
                    subtitle: const Text('Current plan'),
                  ),
                ),
                PlanUsageCard(usage: value.usage),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Plans, invoices and payment details are managed in the '
                        'web app.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (Env.appUrl.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        // Copied rather than opened: this app carries no URL
                        // launcher, and a link is more use pasted into the
                        // browser someone is already signed in to.
                        OutlinedButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: '${Env.appUrl}/billing'),
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context)
                              ..clearSnackBars()
                              ..showSnackBar(
                                const SnackBar(
                                  content: Text('Billing link copied.'),
                                ),
                              );
                          },
                          icon: const Icon(Icons.copy_all_outlined, size: 18),
                          label: const Text('Copy billing link'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 36),
            const SizedBox(height: 12),
            Text(
              "Couldn't load your plan.",
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
