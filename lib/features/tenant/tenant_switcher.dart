import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/labels.dart';
import '../../core/theme/tokens.dart';
import 'tenant_providers.dart';

/// Which restaurant you are in, at the top of the drawer.
///
/// It lives here rather than in the app bar title because the bar's job is to
/// name the surface — "POS", "Store room" — the way the web app's page frame
/// does. The restaurant is context, and context belongs where you go looking
/// for it.
///
/// **Switching is offered only to someone who belongs to more than one**,
/// matching the web: a picker with one option is a decision that isn't one.
class TenantDrawerHeader extends ConsumerStatefulWidget {
  const TenantDrawerHeader({super.key});

  @override
  ConsumerState<TenantDrawerHeader> createState() => _TenantDrawerHeaderState();
}

class _TenantDrawerHeaderState extends ConsumerState<TenantDrawerHeader> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final memberships = ref.watch(membershipsProvider).valueOrNull ?? const [];
    final active = ref.watch(activeTenantProvider);
    final theme = Theme.of(context);

    if (active == null) {
      return const SizedBox(height: Tokens.tapTarget);
    }

    final canSwitch = memberships.length >= 2;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 8, 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  active.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                Text(
                  roleLabel(active.role),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
          if (canSwitch)
            Icon(_expanded ? Icons.expand_less : Icons.expand_more),
        ],
      ),
    );

    if (!canSwitch) return header;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Semantics(
            button: true,
            label: 'Switch restaurant',
            child: header,
          ),
        ),
        if (_expanded)
          for (final m in memberships)
            ListTile(
              minTileHeight: Tokens.tapTarget,
              leading: Icon(
                m.tenantId == active.tenantId
                    ? Icons.check_circle
                    : Icons.circle_outlined,
                size: 20,
              ),
              title: Text(
                m.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              // The slug, because two restaurants can carry the same name and
              // the picker is useless if it can't tell them apart. The web hit
              // this and fixed it the same way.
              subtitle: Text(
                '@${m.slug} · ${roleLabel(m.role)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall,
              ),
              onTap: () {
                setState(() => _expanded = false);
                if (m.tenantId == active.tenantId) return;
                ref
                    .read(activeTenantSelectionProvider.notifier)
                    .select(m.tenantId);
              },
            ),
      ],
    );
  }
}
