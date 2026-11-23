import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/update/update_service.dart';
import '../../core/theme/cinemahub_colors.dart';
import '../home/home_screen.dart';
import '../search/search_screen.dart';
import '../library/library_screen.dart';
import '../settings/settings_screen.dart';

/// Root shell: Frosted glass bottom navigation across the main destinations.
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

    // The 4 core destinations. Admin Dashboard is cleanly housed inside Settings.
    const destinations = <NavigationDestination>[
      NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home_rounded),
        label: 'Home',
      ),
      NavigationDestination(
        icon: Icon(Icons.search_outlined),
        selectedIcon: Icon(Icons.search_rounded),
        label: 'Search',
      ),
      NavigationDestination(
        icon: Icon(Icons.bookmark_outline_rounded),
        selectedIcon: Icon(Icons.bookmark_rounded),
        label: 'My List',
      ),
      NavigationDestination(
        icon: Icon(Icons.person_outline_rounded),
        selectedIcon: Icon(Icons.person_rounded),
        label: 'Settings',
      ),
    ];

    const List<Widget> pages = [
      HomeScreen(),
      SearchScreen(),
      LibraryScreen(),
      SettingsScreen(),
    ];

    final currentIndex = _index.clamp(0, pages.length - 1);

    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: currentIndex, children: pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.1),
              blurRadius: 24,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              decoration: BoxDecoration(
                color: (isDark ? const Color(0xFF101018) : Colors.white)
                    .withValues(alpha: isDark ? 0.75 : 0.85),
                border: Border(
                  top: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.black.withValues(alpha: 0.06),
                    width: 1.2,
                  ),
                ),
              ),
              child: NavigationBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                selectedIndex: currentIndex,
                indicatorColor: CinemahubColors.primary.withValues(alpha: 0.25),
                onDestinationSelected: (i) {
                  setState(() => _index = i);
                },
                destinations: destinations,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
