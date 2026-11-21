import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/auth_service.dart';
import '../../core/admin/admin_service.dart';
import '../../core/update/update_service.dart';
import '../../core/theme/cinemahub_colors.dart';
import '../../core/theme/cinemahub_tokens.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/theme_provider.dart';
import '../../features/admin/admin_dashboard.dart';

/// Settings: theme, account, Real-Debrid & Stremio Addons, about, and in-app OTA updates.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '...';
  bool _checkingUpdates = false;
  String _realDebridKey = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadDebridKey();
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
          _version = 'v1.4.0';
        });
      }
    }
  }

  Future<void> _loadDebridKey() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _realDebridKey = prefs.getString('real_debrid_key') ?? '';
      });
    }
  }

  Future<void> _saveDebridKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('real_debrid_key', key.trim());
    if (mounted) {
      setState(() {
        _realDebridKey = key.trim();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Real-Debrid API Key saved!')),
      );
    }
  }

  void _showDebridDialog() {
    final textController = TextEditingController(text: _realDebridKey);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: CinemahubColors.darkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.bolt_rounded, color: CinemahubColors.gold),
            SizedBox(width: 8),
            Text('Real-Debrid Setup', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your Real-Debrid API token to unlock instant 4K high-speed direct streaming with ZERO ads and zero buffering.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: textController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Enter RD API token...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.black38,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Get token at: real-debrid.com/apitoken',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          if (_realDebridKey.isNotEmpty)
            TextButton(
              onPressed: () {
                _saveDebridKey('');
                Navigator.pop(ctx);
              },
              child: const Text('Clear', style: TextStyle(color: Colors.redAccent)),
            ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: CinemahubColors.primary),
            onPressed: () {
              _saveDebridKey(textController.text);
              Navigator.pop(ctx);
            },
            child: const Text('Save Token'),
          ),
        ],
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final auth = context.watch<AuthService>();
    final admin = context.watch<AdminService>();

    final hasDebrid = _realDebridKey.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings & Profile', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: ListView(
        padding: CinemahubSpacing.pagePadding,
        physics: const BouncingScrollPhysics(),
        children: [
          // Account Profile Card
          GlassCard(
            accentColor: CinemahubColors.primary,
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [CinemahubColors.primary, Color(0xFF8B0000)],
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
                      (auth.user?.email != null && auth.user!.email!.isNotEmpty)
                          ? auth.user!.email![0].toUpperCase()
                          : 'C',
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        auth.user?.email ?? 'Signed in User',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: (auth.isAdmin || admin.isAdmin)
                                  ? CinemahubColors.primary.withValues(alpha: 0.2)
                                  : Colors.green.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              (auth.isAdmin || admin.isAdmin) ? '👑 Owner / Admin' : '✨ Approved Member',
                              style: TextStyle(
                                color: (auth.isAdmin || admin.isAdmin)
                                    ? CinemahubColors.primary
                                    : Colors.greenAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
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
                  icon: const Icon(Icons.logout_rounded, color: Colors.white60),
                  onPressed: () => auth.signOut(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Streaming & Debrid Configuration
          _SectionTitle('Streaming & Debrid'),
          GlassCard(
            onTap: _showDebridDialog,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: CinemahubColors.gold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.bolt_rounded, color: CinemahubColors.gold, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Real-Debrid Account',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      Text(
                        hasDebrid ? 'Active • Direct 4K Zero-Ad CDN' : 'Connect for 4K instant playback',
                        style: TextStyle(
                          color: hasDebrid ? Colors.greenAccent : Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: hasDebrid ? Colors.green.withValues(alpha: 0.2) : Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    hasDebrid ? 'CONNECTED' : 'SETUP',
                    style: TextStyle(
                      color: hasDebrid ? Colors.greenAccent : Colors.white60,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Appearance Settings
          const SizedBox(height: 8),
          _SectionTitle('Appearance & Display'),
          GlassCard(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.palette_outlined, color: Colors.blueAccent, size: 24),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('App Theme', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      Text('System default, Dark or Light mode', style: TextStyle(color: Colors.white60, fontSize: 12)),
                    ],
                  ),
                ),
                DropdownButton<AppThemeMode>(
                  value: theme.mode,
                  dropdownColor: CinemahubColors.darkSurface,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: AppThemeMode.system, child: Text('System')),
                    DropdownMenuItem(value: AppThemeMode.dark, child: Text('Dark')),
                    DropdownMenuItem(value: AppThemeMode.light, child: Text('Light')),
                  ],
                  onChanged: (mode) {
                    if (mode != null) theme.setMode(mode);
                  },
                ),
              ],
            ),
          ),

          // Admin Dashboard (Clean: Only shown if user has admin privileges)
          if (auth.isAdmin || admin.isAdmin) ...[
            const SizedBox(height: 8),
            _SectionTitle('Administration'),
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
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.deepPurpleAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.purpleAccent, size: 24),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Admin Dashboard', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        Text('Manage friend approvals and users', style: TextStyle(color: Colors.white60, fontSize: 12)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white60),
                ],
              ),
            ),
          ],

          // Updates & About Section
          const SizedBox(height: 8),
          _SectionTitle('About & Updates'),
          GlassCard(
            onTap: _checkingUpdates ? null : _checkForUpdates,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: CinemahubColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.system_update_rounded, color: CinemahubColors.primary, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Check for Updates (OTA)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(
                        _checkingUpdates ? 'Connecting to GitHub releases...' : 'Current Version: $_version',
                        style: const TextStyle(color: Colors.white60, fontSize: 12),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
