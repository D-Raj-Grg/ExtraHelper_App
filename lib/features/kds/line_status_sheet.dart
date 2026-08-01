import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../data/supabase/kds_repository.dart';
import 'kds_constants.dart';

/// The full status picker for one dish.
///
/// The one-tap button on the line only ever moves forward, which is right for
/// the rush. This is the way back — a dish marked ready too early, or one that
/// needs putting back on the pass.
Future<KotStatus?> showLineStatusSheet(BuildContext context, KdsLine line) {
  return showModalBottomSheet<KotStatus>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${line.qty}× ${line.name}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text('Where is this dish?', style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              for (final status in kotFlow)
                ListTile(
                  minTileHeight: Tokens.tapTarget,
                  leading: Icon(
                    kotStatusMeta[status]!.icon,
                    color: kotStatusColor(sheetContext, status),
                  ),
                  title: Text(kotStatusMeta[status]!.label),
                  subtitle: Text(kotStatusMeta[status]!.hint),
                  trailing: status == line.status
                      ? const Icon(Icons.check, size: 20)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(status),
                ),
            ],
          ),
        ),
      );
    },
  );
}
