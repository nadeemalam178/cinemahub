import 'dart:ui';

import 'package:flutter/material.dart';

import 'cinemahub_colors.dart';
import 'cinemahub_tokens.dart';

/// Frosted / Liquid-Glass surface.
///
/// Used sparingly: on hero banners, bottom nav and modal sheets. Heavy blur is
/// intentionally avoided on the main scrolling content to keep frame times
/// stable on mid-range Android hardware.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.blur = 18,
    this.saturation = 1.6,
    this.radius = CinemahubRadius.allLg,
    this.tint,
    this.padding,
  });

  final Widget child;
  final double blur;
  final double saturation;
  final BorderRadius radius;
  final Color? tint;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            color:
                tint ??
                (isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.05)),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.black.withValues(alpha: 0.06),
            ),
          ),
          child: Padding(
            padding: padding ?? EdgeInsets.zero,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A soft cinematic scrim overlay used on banners and hero headers.
class ScrimOverlay extends StatelessWidget {
  const ScrimOverlay({
    super.key,
    this.begin = 0.4,
    this.stops = const [0.4, 1.0],
    this.topColor = Colors.transparent,
  });

  final double begin;
  final List<double> stops;
  final Color topColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            topColor,
            isDark ? CinemahubColors.darkScrim : CinemahubColors.lightScrim,
          ],
          stops: stops,
        ),
      ),
    );
  }
}