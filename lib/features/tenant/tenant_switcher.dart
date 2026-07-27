import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/labels.dart';
import 'tenant_providers.dart';

/// Switches the active restaurant.
///
/// **Shown only when the user belongs to more than one** — matching the web,
/// where a single-restaurant user sees the name and no control. A picker with
/// one option is a decision that isn't one.
class TenantSwitcher extends ConsumerWidget {
  const TenantSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberships = ref.watch(membershipsProvider).valueOrNull ?? const [];
    final active = ref.watch(activeTenantProvider);
    final theme = Theme.of(context);

    if (active == null) return const SizedBox.shrink();

    if (memberships.length < 2) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(active.name, style: theme.textTheme.titleMedium),
          Text(roleLabel(active.role), style: theme.textTheme.labelSmall),
        ],
      );
    }

    return PopupMenuButton<String>(
      tooltip: 'Switch restaurant',
      onSelected: (tenantId) {
        ref.read(activeTenantSelectionProvider.notifier).select(tenantId);
      },
      itemBuilder: (context) => [
        for (final m in memberships)
          PopupMenuItem(
            value: m.tenantId,
            child: Row(
              children: [
                Icon(
                  m.tenantId == active.tenantId
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(m.name, overflow: TextOverflow.ellipsis),
                      Text(
                        roleLabel(m.role),
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  active.name,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                Text(roleLabel(active.role), style: theme.textTheme.labelSmall),
              ],
            ),
          ),
          const Icon(Icons.arrow_drop_down),
        ],
      ),
    );
  }
}
