import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cinemahub_colors.dart';
import 'cinemahub_tokens.dart';

/// CinemaHub theme mode selector.
enum AppThemeMode { system, dark, light }

/// Manages theme selection and persists it across launches.
class ThemeProvider extends ChangeNotifier {
  static const _key = 'cinemahub.theme_mode';

  AppThemeMode _mode = AppThemeMode.system;
  AppThemeMode get mode => _mode;
  set mode(AppThemeMode value) {
    if (_mode != value) {
      _mode = value;
      notifyListeners();
    }
  }

  ThemeMode get themeMode => switch (_mode) {
    AppThemeMode.system => ThemeMode.system,
    AppThemeMode.dark => ThemeMode.dark,
    AppThemeMode.light => ThemeMode.light,
  };

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      _mode = AppThemeMode.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => AppThemeMode.system,
      );
      notifyListeners();
    }
  }

  Future<void> setMode(AppThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }

  /// Builds a theme for the given brightness.
  ThemeData buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = isDark
        ? CinemahubColors.darkScheme
        : CinemahubColors.lightScheme;

    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: CinemahubColors.background(brightness),
      cardTheme: CardThemeData(
        elevation: CinemahubElevation.none,
        color: CinemahubColors.surface(brightness),
        shape: RoundedRectangleBorder(
          borderRadius: CinemahubRadius.allLg,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: CinemahubColors.surfaceElevated(brightness),
        shape: const ContinuousRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(CinemahubRadius.xl),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: CinemahubColors.surfaceElevated(brightness),
        shape: const ContinuousRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(CinemahubRadius.lg),
          ),
        ),
      ),
      textTheme: CinemahubTypography.textTheme(brightness),
      iconTheme: IconThemeData(
        color: CinemahubColors.onBackground(brightness),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: CinemahubColors.onBackground(brightness),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: CinemahubColors.primary,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: CinemahubColors.primary,
        thumbColor: CinemahubColors.primary,
        inactiveTrackColor: CinemahubColors.muted(brightness).withValues(
          alpha: 0.3,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: CinemahubColors.background(brightness),
        elevation: CinemahubElevation.none,
        centerTitle: false,
        titleTextStyle: CinemahubTypography.textTheme(
          brightness,
        ).titleLarge,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: CinemahubColors.surface(brightness).withValues(
          alpha: 0.92,
        ),
        indicatorColor: CinemahubColors.primary.withValues(alpha: 0.18),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 72,
      ),
      dividerTheme: DividerThemeData(
        color: CinemahubColors.muted(brightness).withValues(alpha: 0.12),
      ),
    );
  }
}