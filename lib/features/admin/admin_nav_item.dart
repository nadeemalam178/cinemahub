import 'package:flutter/material.dart';

import '../../core/theme/cinemahub_colors.dart';
import '../../core/theme/cinemahub_tokens.dart';

/// Admin navigation item for the shell.
class AdminNavItem extends StatelessWidget {
  const AdminNavItem({super.key, required this.isActive, required this.onTap});

  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: CinemahubRadius.allPill,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: CinemahubSpacing.md,
          vertical: CinemahubSpacing.sm,
        ),
        decoration: BoxDecoration(
          borderRadius: CinemahubRadius.allPill,
          color: isActive
              ? CinemahubColors.primary.withValues(alpha: 0.12)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive ? CinemahubColors.primary : Colors.transparent,
              ),
            ),
            const SizedBox(width: CinemahubSpacing.sm),
            Text(
              'Admin',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: isActive ? CinemahubColors.primary : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}