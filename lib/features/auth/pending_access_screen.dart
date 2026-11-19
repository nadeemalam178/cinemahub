import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_service.dart';
import '../../core/theme/cinemahub_colors.dart';
import '../../core/theme/cinemahub_tokens.dart';
import '../../core/theme/widgets.dart';

/// Shown when an account is awaiting approval, or has been suspended.
class PendingAccessScreen extends StatelessWidget {
  const PendingAccessScreen({
    super.key,
    required this.auth,
    this.suspended = false,
  });

  final AuthService auth;
  final bool suspended;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: CinemahubSpacing.pagePadding,
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 108,
                height: 108,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (suspended
                          ? CinemahubColors.danger
                          : CinemahubColors.warning)
                      .withValues(alpha: 0.14),
                ),
                child: Icon(
                  suspended
                      ? Icons.block_rounded
                      : Icons.hourglass_top_rounded,
                  size: 52,
                  color: suspended
                      ? CinemahubColors.danger
                      : CinemahubColors.warning,
                ),
              ),
              const SizedBox(height: CinemahubSpacing.xl),
              Text(
                suspended ? 'Account suspended' : 'Awaiting approval',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: CinemahubSpacing.md),
              Text(
                suspended
                    ? 'Your access to CinemaHub has been suspended by the '
                          'owner. Contact them if you believe this is a mistake.'
                    : 'Thanks for signing in! Your request has been received. '
                          'The owner will review and approve your access '
                          'shortly. This screen refreshes automatically.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: CinemahubSpacing.xxxl),
              CinemaButton(
                label: 'Sign out',
                icon: Icons.logout_rounded,
                onPressed: () => context.read<AuthService>().signOut(),
                expanded: false,
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}