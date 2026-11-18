import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_service.dart';
import '../../core/admin/admin_service.dart';
import '../../core/theme/cinemahub_tokens.dart';
import '../../core/theme/theme_provider.dart';
import '../../features/admin/admin_dashboard.dart';

/// Settings: theme, account, providers, about. Admin dashboard access.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final auth = context.watch<AuthService>();
    final admin = context.watch<AdminService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: CinemahubSpacing.pagePadding,
        children: [
          _SectionTitle('Appearance'),
          _OptionTile(
            icon: Icons.dark_mode_outlined,
            title: 'Theme',
            subtitle: 'Follow system, dark or light',
            trailing: DropdownButton<AppThemeMode>(
              value: theme.mode,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(
                  value: AppThemeMode.system,
                  child: Text('System'),
                ),
                DropdownMenuItem(
                  value: AppThemeMode.dark,
                  child: Text('Dark'),
                ),
                DropdownMenuItem(
                  value: AppThemeMode.light,
                  child: Text('Light'),
                ),
              ],
              onChanged: (mode) {
                if (mode != null) theme.setMode(mode);
              },
            ),
          ),
          const Divider(),
          _SectionTitle('Account'),
          _OptionTile(
            icon: Icons.person_outline_rounded,
            title: auth.user?.email ?? 'Signed in',
            subtitle: auth.isAdmin ? 'Owner / Admin' : 'Member',
          ),
          _OptionTile(
            icon: Icons.logout_rounded,
            title: 'Sign out',
            onTap: () => auth.signOut(),
          ),
          const Divider(),
          _SectionTitle('Admin'),
          if (auth.isAdmin || admin.isAdmin)
            _OptionTile(
              icon: Icons.admin_panel_settings_rounded,
              title: 'Admin Dashboard',
              subtitle: 'Manage users and providers',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AdminDashboard()),
                );
              },
            ),
          if (!auth.isAdmin && !admin.isAdmin)
            _OptionTile(
              icon: Icons.lock_outline_rounded,
              title: 'Admin Dashboard',
              subtitle: 'Contact owner for access',
            ),
          const Divider(),
          _SectionTitle('About'),
          _OptionTile(
            icon: Icons.info_outline_rounded,
            title: 'Version',
            subtitle: '1.0.0+1',
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: CinemahubSpacing.sm),
      child: Text(title, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: trailing,
      onTap: onTap,
      shape: RoundedRectangleBorder(
        borderRadius: CinemahubRadius.allMd,
      ),
    );
  }
}