import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_service.dart';
import '../../core/admin/admin_service.dart';
import '../../core/update/update_service.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/theme/cinemahub_colors.dart';
import '../../core/theme/cinemahub_tokens.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/theme_provider.dart';
import '../../features/admin/admin_dashboard.dart';
import 'playback_diagnostics_screen.dart';

/// Settings: theme switching, notifications, administration, and OTA updates.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '...';
  bool _checkingUpdates = false;
  bool _sendingTestNotif = false;

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

      if (update != null && update.hasUpdate) {
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

  Future<void> _triggerTestNotification() async {
    setState(() => _sendingTestNotif = true);
    try {
      await NotificationService.instance.sendTestNotification();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notification fired! Check your notification tray.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Notification error: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingTestNotif = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = context.watch<ThemeProvider>();
    final auth = context.watch<AuthService>();
    final admin = context.watch<AdminService>();

    final user = auth.user;
    final displayName = (user?.displayName != null && user!.displayName!.trim().isNotEmpty)
        ? user.displayName!.trim()
        : (user?.email != null && user!.email!.isNotEmpty ? user.email! : 'Approved Member');

    final userInitial = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'C';

    return Scaffold(
      backgroundColor: CinemahubColors.background(Theme.of(context).brightness),
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: ListView(
        padding: CinemahubSpacing.pagePadding,
        physics: const BouncingScrollPhysics(),
        children: [
          // Account Profile Card (Displays User Display Name)
          GlassCard(
            accentColor: CinemahubColors.primary,
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [CinemahubColors.primary, Color(0xFF8F0F35)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: CinemahubColors.primary.withValues(alpha: 0.35),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      userInitial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (user?.email != null && user?.displayName != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          user!.email!,
                          style: TextStyle(
                            color: isDark ? Colors.white60 : Colors.black54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: (auth.isAdmin || admin.isAdmin)
                                  ? CinemahubColors.primary.withValues(alpha: 0.15)
                                  : Colors.green.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              (auth.isAdmin || admin.isAdmin)
                                  ? 'OWNER / ADMIN'
                                  : 'ACTIVE MEMBER',
                              style: TextStyle(
                                color: (auth.isAdmin || admin.isAdmin)
                                    ? CinemahubColors.primary
                                    : (isDark ? Colors.greenAccent : Colors.green.shade800),
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Sign Out',
                  icon: Icon(
                    Icons.logout_rounded,
                    color: isDark ? Colors.white60 : Colors.black45,
                  ),
                  onPressed: () => auth.signOut(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Appearance Section
          _SectionTitle('Theme & Display', isDark: isDark),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.palette_outlined, color: Colors.blueAccent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Appearance Mode',
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            switch (theme.mode) {
                              AppThemeMode.system => 'Auto: Follows Android system theme',
                              AppThemeMode.dark => 'Fixed: Deep cinematic obsidian',
                              AppThemeMode.light => 'Fixed: Pure platinum daylight',
                            },
                            style: TextStyle(
                              color: isDark ? Colors.white60 : Colors.black54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF101018) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Row(
                    children: [
                      _ThemeSegment(
                        label: 'Auto (System)',
                        icon: Icons.brightness_auto_rounded,
                        isSelected: theme.mode == AppThemeMode.system,
                        onTap: () => theme.setMode(AppThemeMode.system),
                      ),
                      _ThemeSegment(
                        label: 'Dark',
                        icon: Icons.dark_mode_rounded,
                        isSelected: theme.mode == AppThemeMode.dark,
                        onTap: () => theme.setMode(AppThemeMode.dark),
                      ),
                      _ThemeSegment(
                        label: 'Light',
                        icon: Icons.light_mode_rounded,
                        isSelected: theme.mode == AppThemeMode.light,
                        onTap: () => theme.setMode(AppThemeMode.light),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Push Notifications Section
          _SectionTitle('Alerts & Notifications', isDark: isDark),
          GlassCard(
            onTap: _sendingTestNotif ? null : _triggerTestNotification,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.notifications_active_outlined, color: Colors.amber, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Push Notifications',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        'FCM & local heads-up alerts active',
                        style: TextStyle(
                          color: isDark ? Colors.white60 : Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton(
                  onPressed: _sendingTestNotif ? null : _triggerTestNotification,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    side: BorderSide(
                      color: isDark ? Colors.white24 : Colors.black26,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _sendingTestNotif
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          'Test Alert',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Admin Dashboard (Exclusively shown if user has admin privileges)
          if (auth.isAdmin || admin.isAdmin) ...[
            _SectionTitle('Administration', isDark: isDark),
            GlassCard(
              accentColor: Colors.deepPurpleAccent,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AdminDashboard()),
                );
              },
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: Colors.deepPurpleAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings_rounded,
                      color: Colors.purpleAccent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Admin Dashboard',
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          'Manage user approvals and platform settings',
                          style: TextStyle(
                            color: isDark ? Colors.white60 : Colors.black54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: isDark ? Colors.white60 : Colors.black45,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Playback Engine Diagnostics (Exclusively for Admins/Owners or in Debug Mode)
          if (auth.isAdmin || admin.isAdmin || kDebugMode) ...[
            _SectionTitle('Diagnostics', isDark: isDark),
            GlassCard(
              accentColor: Colors.tealAccent,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PlaybackDiagnosticsScreen()),
                );
              },
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: Colors.tealAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.speed_rounded,
                      color: Colors.tealAccent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Playback Engine Diagnostics',
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          'Test MP4, HLS, DASH, Embed, Magnet & Error routing',
                          style: TextStyle(
                            color: isDark ? Colors.white60 : Colors.black54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: isDark ? Colors.white60 : Colors.black45,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Updates & Version Section
          _SectionTitle('About & Updates', isDark: isDark),
          GlassCard(
            onTap: _checkingUpdates ? null : _checkForUpdates,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: CinemahubColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.system_update_rounded,
                    color: CinemahubColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Check for Updates (OTA)',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        _checkingUpdates
                            ? 'Connecting to GitHub releases…'
                            : 'Current Version: $_version',
                        style: TextStyle(
                          color: isDark ? Colors.white60 : Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_checkingUpdates)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: CinemahubColors.primary),
                  )
                else
                  const Icon(Icons.download_rounded, color: CinemahubColors.primary, size: 22),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _ThemeSegment extends StatelessWidget {
  const _ThemeSegment({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? CinemahubColors.primary
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: CinemahubColors.primary.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected
                    ? Colors.white
                    : (isDark ? Colors.white60 : Colors.black54),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Colors.white70 : Colors.black87),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {required this.isDark});
  final String title;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: isDark ? Colors.white54 : Colors.black45,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
