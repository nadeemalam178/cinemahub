import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/admin/admin_service.dart';
import '../../core/theme/cinemahub_colors.dart';
import '../../core/theme/cinemahub_tokens.dart';
import '../../core/theme/widgets.dart';

/// Owner-only admin dashboard.
class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            onPressed: () => admin.checkAdminStatus(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: admin.userStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingState();
          }
          if (snapshot.hasError) {
            return ErrorState(message: 'Failed to load users');
          }
          final users = snapshot.data ?? [];
          return RefreshIndicator(
            onRefresh: () => admin.checkAdminStatus(),
            child: ListView(
              padding: CinemahubSpacing.pagePadding,
              children: [
                _StatsCard(
                  title: 'Total Users',
                  value: users.length.toString(),
                  icon: Icons.group_rounded,
                ),
                const SizedBox(height: CinemahubSpacing.lg),
                _StatsCard(
                  title: 'Pending Approval',
                  value: users
                      .where((u) => u['status'] == 'pending')
                      .length
                      .toString(),
                  icon: Icons.hourglass_top_rounded,
                ),
                const SizedBox(height: CinemahubSpacing.lg),
                _StatsCard(
                  title: 'Active Users',
                  value: users
                      .where((u) => u['status'] == 'approved')
                      .length
                      .toString(),
                  icon: Icons.person_rounded,
                ),
                const SizedBox(height: CinemahubSpacing.xxxl),
                Text(
                  'Registered Users',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: CinemahubSpacing.md),
                ...users.map((user) => _UserCard(
                  user: user,
                  onApprove: () => admin.approveUser(user['uid']),
                  onSuspend: () => admin.suspendUser(user['uid']),
                )),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return CinemaCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: CinemahubColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: CinemahubColors.primary),
          ),
          const SizedBox(width: CinemahubSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.onApprove,
    required this.onSuspend,
  });

  final Map<String, dynamic> user;
  final VoidCallback onApprove;
  final VoidCallback onSuspend;

  @override
  Widget build(BuildContext context) {
    final status = user['status'] as String?;
    final displayName = user['displayName'] as String?;
    final email = user['email'] as String?;
    final titleText = (displayName != null && displayName.isNotEmpty)
        ? displayName
        : (email != null && email.isNotEmpty ? email : 'User');
    final subtitleText = (displayName != null && displayName.isNotEmpty && email != null)
        ? email
        : null;

    return CinemaCard(
      onTap: status == 'pending' ? null : () {},
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: CinemahubColors.primary.withValues(alpha: 0.12),
            ),
            child: const Icon(Icons.person_rounded, size: 24),
          ),
          const SizedBox(width: CinemahubSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titleText,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (subtitleText != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitleText,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    Pill(
                      text: status ?? 'unknown',
                      color: switch (status) {
                        'approved' => CinemahubColors.success,
                        'suspended' => CinemahubColors.danger,
                        'pending' => CinemahubColors.warning,
                        _ => CinemahubColors.info,
                      },
                    ),
                    if (user['role'] != null)
                      const SizedBox(width: CinemahubSpacing.sm),
                    if (user['role'] != null)
                      Pill(
                        text: user['role'],
                        color: CinemahubColors.primary,
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (status == 'pending') ...[
            IconButton(
              onPressed: onApprove,
              icon: const Icon(Icons.check_circle_rounded),
              color: CinemahubColors.success,
            ),
            IconButton(
              onPressed: onSuspend,
              icon: const Icon(Icons.block_rounded),
              color: CinemahubColors.danger,
            ),
          ],
        ],
      ),
    );
  }
}