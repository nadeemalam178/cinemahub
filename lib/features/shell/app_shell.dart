import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_service.dart';
import '../../core/update/update_service.dart';
import '../../core/theme/cinemahub_colors.dart';
import '../home/home_screen.dart';
import '../search/search_screen.dart';
import '../library/library_screen.dart';
import '../settings/settings_screen.dart';
import '../admin/admin_dashboard.dart';

/// Root shell: bottom navigation across the main destinations.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkOtaUpdate();
    });
  }

  Future<void> _checkOtaUpdate() async {
    try {
      final updateService = Provider.of<UpdateService?>(context, listen: false);
      if (updateService == null) return;
      final update = await updateService.checkForUpdate();
      if (update != null && update.hasUpdate && mounted) {
        await updateService.showUpdateDialog(context, update);
      }
    } catch (e) {
      debugPrint('AppShell OTA Check Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = context.watch<AuthService>();

    // Build destinations based on admin status
    final destinations = [
      const NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home_rounded),
        label: 'Home',
      ),
      const NavigationDestination(
        icon: Icon(Icons.search_outlined),
        selectedIcon: Icon(Icons.search_rounded),
        label: 'Search',
      ),
      const NavigationDestination(
        icon: Icon(Icons.bookmark_outline_rounded),
        selectedIcon: Icon(Icons.bookmark_rounded),
        label: 'My List',
      ),
      const NavigationDestination(
        icon: Icon(Icons.admin_panel_settings_outlined),
        selectedIcon: Icon(Icons.admin_panel_settings_rounded),
        label: 'Admin',
      ),
      const NavigationDestination(
        icon: Icon(Icons.person_outline_rounded),
        selectedIcon: Icon(Icons.person_rounded),
        label: 'Settings',
      ),
    ];

    // Admin page
    final List<Widget> allPages = [
      const HomeScreen(),
      const SearchScreen(),
      const LibraryScreen(),
      const AdminDashboard(),
      const SettingsScreen(),
    ];

    // Track if admin panel was selected
    int currentIndex = _index;
    if (!auth.isAdmin && _index >= 3) {
      // If user is not admin but admin tab is selected, redirect to Settings
      currentIndex = 4;
    }

    return Scaffold(
      body: IndexedStack(index: currentIndex, children: allPages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: CinemahubColors.surface(isDark ? Brightness.dark : Brightness.light)
              .withValues(alpha: 0.9),
          border: Border(
            top: BorderSide(
              color: CinemahubColors.muted(
                isDark ? Brightness.dark : Brightness.light,
              ).withValues(alpha: 0.1),
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: currentIndex,
          onDestinationSelected: (i) {
            if (!auth.isAdmin && i == 3) {
              // Non-admins can't access admin panel
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Admin access required')),
              );
              return;
            }
            setState(() => _index = i);
          },
          destinations: destinations,
        ),
      ),
    );
  }
}