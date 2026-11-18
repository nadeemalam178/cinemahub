import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'cinemahub_colors.dart';
import 'cinemahub_tokens.dart';
import 'glass.dart';

/// ---------------------------------------------------------------------------
/// CinemaHub reusable UI primitives.
/// ---------------------------------------------------------------------------

/// A gradient, rounded primary action button with micro-interaction.
class CinemaButton extends StatelessWidget {
  const CinemaButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.gradient = true,
    this.expanded = true,
    this.loading = false,
    this.outlined = false,
    this.large = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool gradient;
  final bool expanded;
  final bool loading;
  final bool outlined;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final content = loading
        ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: large ? 22 : 20),
                const SizedBox(width: CinemahubSpacing.sm),
              ],
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: outlined
                      ? Theme.of(context).colorScheme.onSurface
                      : Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          );

    final button = Material(
      color: Colors.transparent,
      child: Ink(
        decoration: outlined
            ? BoxDecoration(
                borderRadius: CinemahubRadius.allPill,
                border: Border.all(
                  color: Theme.of(context).colorScheme.onSurface.withValues(
                    alpha: 0.3,
                  ),
                ),
              )
            : BoxDecoration(
                borderRadius: CinemahubRadius.allPill,
                gradient: gradient ? CinemahubColors.brandGradient : null,
                color: gradient ? null : CinemahubColors.primary,
                boxShadow: gradient
                    ? [
                        BoxShadow(
                          color: CinemahubColors.primary.withValues(alpha: 0.35),
                          blurRadius: CinemahubElevation.elevated,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
        child: InkWell(
          borderRadius: CinemahubRadius.allPill,
          onTap: loading ? null : onPressed,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: CinemahubSpacing.xl,
              vertical: large ? CinemahubSpacing.lg : CinemahubSpacing.md,
            ),
            child: content,
          ),
        ),
      ),
    );

    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// A frosted glass card with optional press feedback.
class CinemaCard extends StatelessWidget {
  const CinemaCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.radius = CinemahubRadius.allLg,
    this.glass = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final BorderRadius radius;
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final base = Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: radius,
          color: glass
              ? Colors.transparent
              : Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurface.withValues(
              alpha: 0.06,
            ),
          ),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: padding ?? CinemahubSpacing.cardPadding,
            child: child,
          ),
        ),
      ),
    );

    if (!glass) return base;
    return GlassPanel(
      radius: radius,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: padding ?? CinemahubSpacing.cardPadding,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A shimmer loading placeholder block.
class ShimmerBox extends StatelessWidget {
  const ShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.radius = CinemahubRadius.md,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark
          ? CinemahubColors.darkSurfaceHigh
          : CinemahubColors.lightSurfaceHigh,
      highlightColor: isDark
          ? CinemahubColors.darkSurfaceElevated
          : CinemahubColors.lightSurface,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          color: Colors.white,
        ),
      ),
    );
  }
}

/// A standard page-level loading state.
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(strokeWidth: 2.6),
          ),
          if (message != null) ...[
            const SizedBox(height: CinemahubSpacing.lg),
            Text(message!, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

/// A friendly empty state.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: CinemahubSpacing.pagePadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.primary.withValues(
                  alpha: 0.12,
                ),
              ),
              child: Icon(
                icon,
                size: 40,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: CinemahubSpacing.xl),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: CinemahubSpacing.sm),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: CinemahubSpacing.xl),
              CinemaButton(
                label: actionLabel!,
                onPressed: onAction,
                expanded: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A retryable error state.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.title = 'Something went wrong',
  });

  final String message;
  final VoidCallback? onRetry;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: CinemahubSpacing.pagePadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 52,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: CinemahubSpacing.lg),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: CinemahubSpacing.sm),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: CinemahubSpacing.xl),
              CinemaButton(
                label: 'Try again',
                icon: Icons.refresh_rounded,
                onPressed: onRetry,
                expanded: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A small pill badge.
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.text,
    this.icon,
    this.color,
  });

  final String text;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CinemahubSpacing.md,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        borderRadius: CinemahubRadius.allPill,
        color: c.withValues(alpha: 0.16),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: c),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: c),
          ),
        ],
      ),
    );
  }
}

/// A section header used across home and browse screens.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.onSeeAll,
  });

  final String title;
  final String? trailing;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: CinemahubSpacing.lg,
        bottom: CinemahubSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          if (trailing != null)
            GestureDetector(
              onTap: onSeeAll,
              child: Text(
                trailing!,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}