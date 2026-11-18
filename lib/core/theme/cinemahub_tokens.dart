import 'package:flutter/material.dart';
import 'cinemahub_colors.dart';

/// CinemaHub design tokens: spacing, radius, elevation, typography.
///
/// These values are deliberately fixed (no media queries) so the design stays
/// consistent and cheap to render on mid-range Android devices.
class CinemahubSpacing {
  CinemahubSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  static const EdgeInsets pagePadding = EdgeInsets.symmetric(
    horizontal: lg,
    vertical: md,
  );

  static const EdgeInsets cardPadding = EdgeInsets.all(md);
}

class CinemahubRadius {
  CinemahubRadius._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double pill = 999;

  static const BorderRadius allMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius allLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius allXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius allPill = BorderRadius.all(Radius.circular(pill));
}

class CinemahubElevation {
  CinemahubElevation._();

  static const double none = 0;
  static const double flat = 1;
  static const double raised = 4;
  static const double elevated = 8;
  static const double floating = 16;
}

/// Typography tokens. Uses the default Material font family with tuned sizes
/// and weights for a premium cinematic feel.
class CinemahubTypography {
  CinemahubTypography._();

  static TextTheme textTheme(Brightness brightness) {
    final color = brightness == Brightness.dark
        ? CinemahubColors.onDark
        : CinemahubColors.onLight;

    final muted = brightness == Brightness.dark
        ? CinemahubColors.onDarkMuted
        : CinemahubColors.onLightMuted;

    final base = ThemeData(
      brightness: brightness,
      useMaterial3: true,
    ).textTheme;

    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(
        fontSize: 44,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.2,
        color: color,
      ),
      displayMedium: base.displayMedium?.copyWith(
        fontSize: 34,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        color: color,
      ),
      headlineLarge: base.headlineLarge?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: color,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: color,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: color,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: color,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: color,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        fontSize: 16,
        height: 1.5,
        color: color,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        fontSize: 14,
        height: 1.45,
        color: color,
      ),
      bodySmall: base.bodySmall?.copyWith(
        fontSize: 12,
        height: 1.4,
        color: muted,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: color,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
        color: muted,
      ),
    );
  }
}