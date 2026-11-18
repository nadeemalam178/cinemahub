import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_service.dart';
import '../../core/theme/cinemahub_colors.dart';
import '../../core/theme/cinemahub_tokens.dart';
import '../../core/theme/widgets.dart';

/// Google Sign-In entry point.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.auth, this.configError});

  final AuthService auth;
  final String? configError;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.auth.signInWithGoogle();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final configError = widget.configError;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? const [Color(0xFF1A0B18), CinemahubColors.darkBackground]
                : const [Color(0xFFFCE4EC), CinemahubColors.lightBackground],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: CinemahubSpacing.pagePadding,
            child: Column(
              children: [
                const Spacer(),
                Icon(
                  Icons.movie_filter_rounded,
                  size: 72,
                  color: CinemahubColors.primary,
                ),
                const SizedBox(height: CinemahubSpacing.md),
                Text(
                  'CinemaHub',
                  style: Theme.of(context).textTheme.displayMedium,
                ),
                const SizedBox(height: CinemahubSpacing.sm),
                Text(
                  'A private cinema for approved friends',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: CinemahubSpacing.xxxl),
                if (configError != null) ...[
                  Container(
                    padding: const EdgeInsets.all(CinemahubSpacing.md),
                    decoration: BoxDecoration(
                      borderRadius: CinemahubRadius.allLg,
                      color: CinemahubColors.warning.withValues(alpha: 0.12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          color: CinemahubColors.warning,
                        ),
                        const SizedBox(width: CinemahubSpacing.sm),
                        Expanded(
                          child: Text(
                            configError,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: CinemahubSpacing.lg),
                ],
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: CinemahubColors.danger,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: CinemahubSpacing.md),
                ],
                CinemaButton(
                  label: _loading ? 'Signing in…' : 'Continue with Google',
                  icon: Icons.g_mobiledata_rounded,
                  onPressed: _loading ? null : _signIn,
                  loading: _loading,
                ),
                const SizedBox(height: CinemahubSpacing.md),
                Text(
                  'Access is restricted to invited friends. '
                  'Your account must be approved before you can continue.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const Spacer(flex: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}