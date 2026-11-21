import 'dart:ui';
import 'package:flutter/material.dart';

import 'cinemahub_colors.dart';
import 'cinemahub_tokens.dart';

/// Frosted / Liquid-Glass surface with ambient lighting and depth borders.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.blur = 20,
    this.saturation = 1.8,
    this.radius = CinemahubRadius.allLg,
    this.tint,
    this.borderGradient,
    this.padding,
    this.boxShadow,
  });

  final Widget child;
  final double blur;
  final double saturation;
  final BorderRadius radius;
  final Color? tint;
  final Gradient? borderGradient;
  final EdgeInsetsGeometry? padding;
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultTint = isDark
        ? const Color(0xFF161622).withValues(alpha: 0.65)
        : Colors.white.withValues(alpha: 0.75);

    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: boxShadow ?? [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding ?? EdgeInsets.zero,
            decoration: BoxDecoration(
              borderRadius: radius,
              color: tint ?? defaultTint,
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.08),
                width: 1.2,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Frosted Glass Card for lists, stats, and settings items.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 12),
    this.borderRadius = 16,
    this.accentColor,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double borderRadius;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget content = GlassPanel(
      radius: BorderRadius.circular(borderRadius),
      blur: 16,
      tint: accentColor != null
          ? accentColor!.withValues(alpha: isDark ? 0.12 : 0.08)
          : (isDark ? const Color(0xFF181824).withValues(alpha: 0.65) : Colors.white.withValues(alpha: 0.7)),
      padding: padding,
      child: child,
    );

    if (onTap != null) {
      content = GestureDetector(
        onTap: onTap,
        child: content,
      );
    }

    return Padding(
      padding: margin,
      child: content,
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
