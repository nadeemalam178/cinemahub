import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_service.dart';
import '../../core/admin/admin_service.dart';
import '../../core/update/update_service.dart';
import '../../core/theme/cinemahub_tokens.dart';
import '../../core/theme/theme_provider.dart';
import '../../features/admin/admin_dashboard.dart';

/// Settings: theme, account, providers, about, OTA updates. Admin dashboard access.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '...';
  bool _checkingUpdates = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _version = 'v${info.version}+${info.buildNumber}';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _version = 'v1.1.0';
        });
      }
    }
  }

  Future<void> _checkForUpdates() async {
    setState(() => _checkingUpdates = true);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      final updateService = Provider.of<UpdateService?>(context, listen: false);
      if (updateService == null) {
        if (!mounted) return;
        setState(() => _checkingUpdates = false);
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Update service is currently unavailable.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      final update = await updateService.checkForUpdate();
      if (!mounted) return;
      setState(() => _checkingUpdates = false);

      if (update != null) {
        await updateService.showUpdateDialog(context, update);
      } else {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('You are on the latest version ($_version).'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _checkingUpdates = false);
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Failed to check for updates: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

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
          _SectionTitle('About & Updates'),
          _OptionTile(
            icon: Icons.info_outline_rounded,
            title: 'Version',
            subtitle: _version,
          ),
          _OptionTile(
            icon: Icons.system_update_alt_rounded,
            title: 'Check for Updates',
            subtitle: _checkingUpdates
                ? 'Checking GitHub for releases...'
                : 'Get the latest features and fixes',
            trailing: _checkingUpdates
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: _checkingUpdates ? null : _checkForUpdates,
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