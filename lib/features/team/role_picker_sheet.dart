import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import 'team_providers.dart';

/// Pick a role for someone already on the team. Pops the id; the caller writes.
Future<String?> showRolePickerSheet(
  BuildContext context, {
  required List<RoleOption> roles,
  required String email,
  String? currentRoleId,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Role for $email',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final role in roles)
                ListTile(
                  minTileHeight: Tokens.tapTarget,
                  title: Text(role.name),
                  selected: role.id == currentRoleId,
                  // A check, not just the selected tint — the current role has
                  // to be readable in greyscale.
                  trailing: role.id == currentRoleId
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.of(context).pop(role.id),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    ),
  ),
);
