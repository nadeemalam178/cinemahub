import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/admin/admin_service.dart';
import '../../core/auth/auth_service.dart';
import '../../core/theme/cinemahub_colors.dart';
import '../../core/theme/cinemahub_tokens.dart';
import '../../core/theme/widgets.dart';

/// Owner/admin dashboard for managing users and content providers.
class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  Future<void> _runAction(
    BuildContext context,
    Future<void> Function() action, {
    required String successMessage,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(
        SnackBar(content: Text(successMessage), behavior: SnackBarBehavior.floating),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Action failed: $e'),
          backgroundColor: CinemahubColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminService>();
    final auth = context.watch<AuthService>();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin Dashboard'),
          actions: [
            IconButton(
              onPressed: () => admin.checkAdminStatus(),
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh Admin Status',
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.group_rounded), text: 'Users'),
              Tab(icon: Icon(Icons.extension_rounded), text: 'Providers'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _UsersTab(admin: admin, auth: auth, onRunAction: _runAction),
            _ProvidersTab(admin: admin, onRunAction: _runAction),
          ],
        ),
      ),
    );
  }
}

class _UsersTab extends StatelessWidget {
  const _UsersTab({
    required this.admin,
    required this.auth,
    required this.onRunAction,
  });

  final AdminService admin;
  final AuthService auth;
  final Future<void> Function(
    BuildContext context,
    Future<void> Function() action, {
    required String successMessage,
  }) onRunAction;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: admin.userStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingState();
        }
        if (snapshot.hasError) {
          return ErrorState(message: 'Failed to load users: ${snapshot.error}');
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
                value: users.where((u) => u['status'] == 'pending').length.toString(),
                icon: Icons.hourglass_top_rounded,
              ),
              const SizedBox(height: CinemahubSpacing.lg),
              _StatsCard(
                title: 'Active Users',
                value: users.where((u) => u['status'] == 'approved').length.toString(),
                icon: Icons.person_rounded,
              ),
              const SizedBox(height: CinemahubSpacing.xxxl),
              Text(
                'Registered Users',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: CinemahubSpacing.md),
              if (users.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('No registered users found.')),
                )
              else
                ...users.map((user) {
                  final uid = (user['uid'] as String?) ?? '';
                  final role = (user['role'] as String?) ?? 'user';
                  final isSelf = uid == auth.user?.uid;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: CinemahubSpacing.md),
                    child: _UserCard(
                      user: user,
                      isSelf: isSelf,
                      onApprove: uid.isEmpty
                          ? null
                          : () => onRunAction(
                                context,
                                () => admin.approveUser(uid),
                                successMessage: 'User approved.',
                              ),
                      onSuspend: uid.isEmpty || isSelf || role == 'owner'
                          ? null
                          : () => onRunAction(
                                context,
                                () => admin.suspendUser(uid),
                                successMessage: 'User suspended.',
                              ),
                      onToggleAdmin: uid.isEmpty || isSelf || role == 'owner'
                          ? null
                          : () {
                              final nextRole = role == 'admin' ? 'user' : 'admin';
                              onRunAction(
                                context,
                                () => admin.setUserRole(uid, nextRole),
                                successMessage: 'Role updated to $nextRole.',
                              );
                            },
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}

class _ProvidersTab extends StatelessWidget {
  const _ProvidersTab({
    required this.admin,
    required this.onRunAction,
  });

  final AdminService admin;
  final Future<void> Function(
    BuildContext context,
    Future<void> Function() action, {
    required String successMessage,
  }) onRunAction;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: admin.providerStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingState();
        }
        if (snapshot.hasError) {
          return ErrorState(message: 'Failed to load providers: ${snapshot.error}');
        }
        final providers = snapshot.data ?? [];
        if (providers.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No providers configured in Firestore.'),
            ),
          );
        }
        return ListView.separated(
          padding: CinemahubSpacing.pagePadding,
          itemCount: providers.length,
          separatorBuilder: (_, __) => const SizedBox(height: CinemahubSpacing.md),
          itemBuilder: (context, index) {
            final p = providers[index];
            final id = (p['id'] as String?) ?? '';
            final name = (p['name'] as String?) ?? id;
            final version = (p['version'] as String?) ?? '1.0.0';
            final enabled = (p['enabled'] as bool?) ?? false;
            final priority = (p['priority'] as num?)?.toInt() ?? 100;

            return CinemaCard(
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: (enabled ? CinemahubColors.success : Colors.grey)
                          .withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.dns_rounded,
                      color: enabled ? CinemahubColors.success : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: CinemahubSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          'ID: $id • v$version • Priority $priority',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: enabled,
                    onChanged: id.isEmpty
                        ? null
                        : (val) => onRunAction(
                              context,
                              () => val
                                  ? admin.enableProvider(id)
                                  : admin.disableProvider(id),
                              successMessage: val
                                  ? 'Enabled $name'
                                  : 'Disabled $name',
                            ),
                  ),
                ],
              ),
            );
          },
        );
      },
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
    required this.isSelf,
    this.onApprove,
    this.onSuspend,
    this.onToggleAdmin,
  });

  final Map<String, dynamic> user;
  final bool isSelf;
  final VoidCallback? onApprove;
  final VoidCallback? onSuspend;
  final VoidCallback? onToggleAdmin;

  @override
  Widget build(BuildContext context) {
    final status = (user['status'] as String?) ?? 'pending';
    final role = user['role'] as String?;
    final displayName = user['displayName'] as String?;
    final email = user['email'] as String?;
    final titleText = (displayName != null && displayName.isNotEmpty)
        ? displayName
        : (email != null && email.isNotEmpty ? email : 'User');
    final subtitleText = (displayName != null && displayName.isNotEmpty && email != null)
        ? email
        : null;

    return CinemaCard(
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
                  isSelf ? '$titleText (You)' : titleText,
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
                Wrap(
                  spacing: CinemahubSpacing.sm,
                  runSpacing: 4,
                  children: [
                    Pill(
                      text: status,
                      color: switch (status) {
                        'approved' => CinemahubColors.success,
                        'suspended' => CinemahubColors.danger,
                        'pending' => CinemahubColors.warning,
                        _ => CinemahubColors.info,
                      },
                    ),
                    if (role != null)
                      Pill(
                        text: role,
                        color: CinemahubColors.primary,
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (status != 'approved' && onApprove != null)
            IconButton(
              tooltip: status == 'suspended' ? 'Re-approve User' : 'Approve User',
              onPressed: onApprove,
              icon: const Icon(Icons.check_circle_rounded),
              color: CinemahubColors.success,
            ),
          if (status != 'suspended' && onSuspend != null)
            IconButton(
              tooltip: 'Suspend User',
              onPressed: onSuspend,
              icon: const Icon(Icons.block_rounded),
              color: CinemahubColors.danger,
            ),
          if (status == 'approved' && onToggleAdmin != null)
            IconButton(
              tooltip: role == 'admin' ? 'Demote to User' : 'Promote to Admin',
              onPressed: onToggleAdmin,
              icon: Icon(
                role == 'admin'
                    ? Icons.shield_outlined
                    : Icons.admin_panel_settings_rounded,
              ),
              color: CinemahubColors.primary,
            ),
        ],
      ),
    );
  }
}
