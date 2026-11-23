import 'package:flutter/material.dart';

/// CinemaHub brand colour tokens.
///
/// Design language: premium cinematic with tasteful glass, soft gradients and
/// rounded surfaces. Dark mode is the primary experience; light mode is fully
/// supported. Every colour is defined once and consumed via tokens so the
/// whole app shares a single source of truth.
class CinemahubColors {
  CinemahubColors._();

  // ---------------------------------------------------------------------------
  // Brand
  // ---------------------------------------------------------------------------

  /// Signature CinemaHub crimson — used for accent, focus and primary actions.
  static const Color primary = Color(0xFFE50950);

  /// Deep brand red used in gradients.
  static const Color primaryDeep = Color(0xFF8F0F35);

  /// Warm gold accent for ratings, badges and highlights.
  static const Color gold = Color(0xFFF5B942);

  /// Success green.
  static const Color success = Color(0xFF2ECC71);

  /// Warning amber.
  static const Color warning = Color(0xFFF39C12);

  /// Destructive red.
  static const Color danger = Color(0xFFE74C3C);

  /// Info blue.
  static const Color info = Color(0xFF3498DB);

  // ---------------------------------------------------------------------------
  // Dark scheme
  // ---------------------------------------------------------------------------

  static const Color darkBackground = Color(0xFF08080E);
  static const Color darkSurface = Color(0xFF12121C);
  static const Color darkSurfaceElevated = Color(0xFF1A1A28);
  static const Color darkSurfaceHigh = Color(0xFF242436);
  static const Color darkScrim = Color(0xCC000000);
  static const Color onDark = Color(0xFFF5F5FA);
  static const Color onDarkMuted = Color(0xFF9090A8);

  // ---------------------------------------------------------------------------
  // Light scheme
  // ---------------------------------------------------------------------------

  static const Color lightBackground = Color(0xFFF6F7FB);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceElevated = Color(0xFFFBFBFE);
  static const Color lightSurfaceHigh = Color(0xFFECEEF6);
  static const Color lightScrim = Color(0x66000000);
  static const Color onLight = Color(0xFF0D0E15);
  static const Color onLightMuted = Color(0xFF5E6072);

  // ---------------------------------------------------------------------------
  // Gradient helpers
  // ---------------------------------------------------------------------------

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryDeep, primary],
  );

  /// A soft cinematic gradient for hero banners.
  static const LinearGradient bannerScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Colors.transparent, Color(0xE6000000)],
    stops: [0.35, 1.0],
  );

  // ---------------------------------------------------------------------------
  // Schemes
  // ---------------------------------------------------------------------------

  static ColorScheme get darkScheme => const ColorScheme.dark(
    primary: primary,
    onPrimary: Colors.white,
    primaryContainer: primaryDeep,
    onPrimaryContainer: Colors.white,
    secondary: gold,
    onSecondary: Color(0xFF1A1400),
    surface: darkSurface,
    onSurface: onDark,
    surfaceContainerHighest: darkSurfaceHigh,
    error: danger,
    onError: Colors.white,
  );

  static ColorScheme get lightScheme => const ColorScheme.light(
    primary: primary,
    onPrimary: Colors.white,
    primaryContainer: primaryDeep,
    onPrimaryContainer: Colors.white,
    secondary: gold,
    onSecondary: Color(0xFF1A1400),
    surface: lightSurface,
    onSurface: onLight,
    surfaceContainerHighest: lightSurfaceHigh,
    error: danger,
    onError: Colors.white,
  );

  static Color background(Brightness b) =>
      b == Brightness.dark ? darkBackground : lightBackground;

  static Color surface(Brightness b) =>
      b == Brightness.dark ? darkSurface : lightSurface;

  static Color surfaceElevated(Brightness b) =>
      b == Brightness.dark ? darkSurfaceElevated : lightSurfaceElevated;

  static Color surfaceHigh(Brightness b) =>
      b == Brightness.dark ? darkSurfaceHigh : lightSurfaceHigh;

  static Color onBackground(Brightness b) =>
      b == Brightness.dark ? onDark : onLight;

  static Color muted(Brightness b) =>
      b == Brightness.dark ? onDarkMuted : onLightMuted;
}