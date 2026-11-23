import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/auth/auth_service.dart';
import '../../core/theme/cinemahub_logo.dart';
import '../../core/theme/cinemahub_tokens.dart';
import '../settings/playback_diagnostics_screen.dart';

/// Clean, cinematic Google Sign-In entry point.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.auth, this.configError});

  final AuthService auth;
  final String? configError;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _loading = false;

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
    });
    try {
      await widget.auth.signInWithGoogle();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    e.toString().replaceFirst('Exception: ', ''),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF99000D),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08080E),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Subtle cinematic ambient background
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.0, -0.3),
                radius: 1.1,
                colors: [
                  Color(0xFF22050D),
                  Color(0xFF100307),
                  Color(0xFF08080E),
                ],
                stops: [0.0, 0.45, 1.0],
              ),
            ),
          ),

          // 2. Main Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const Spacer(flex: 3),

                  // Brand Hero Mark
                  const CinemaHubLogo(
                    size: 42,
                    showWordmark: true,
                    animated: true,
                  ),
                  const SizedBox(height: CinemahubSpacing.md),

                  Text(
                    'A curated private cinema for approved members',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.3,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const Spacer(flex: 2),

                  // Google Sign-In High-Contrast Action Button
                  _GoogleSignInButton(
                    loading: _loading,
                    onPressed: _loading ? null : _signIn,
                  ),

                  const SizedBox(height: CinemahubSpacing.lg),

                  // Subtle Invitation Note
                  Text(
                    'Access is restricted to invited friends. New accounts are\nautomatically placed in review for approval.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 12,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  if (kDebugMode) ...[
                    const SizedBox(height: CinemahubSpacing.xl),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const PlaybackDiagnosticsScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.bug_report_outlined,
                          size: 16, color: Colors.white38),
                      label: const Text(
                        'Playback Engine Diagnostics',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ),
                  ],

                  const Spacer(flex: 2),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Authentic, high-contrast Google Sign-In Button compliant with Google brand guidelines.
class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({
    required this.loading,
    this.onPressed,
  });

  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: 0.3),
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: loading ? null : onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFF1F1F1F)),
                    ),
                  )
                else ...[
                  // Multi-colored official Google 'G' icon glyph
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CustomPaint(
                      painter: _GoogleGLogoPainter(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Continue with Google',
                    style: TextStyle(
                      color: Color(0xFF1F1F1F),
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      letterSpacing: 0.1,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Precise vector painter for the official Google 'G' brand logo.
class _GoogleGLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final center = Offset(w / 2, h / 2);
    final radius = w / 2;

    // Center bar (Blue)
    final bluePaint = Paint()..color = const Color(0xFF4285F4);

    // Center bar (Blue)
    final barRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(w * 0.45, h * 0.38, w * 0.98, h * 0.62),
      const Radius.circular(2),
    );
    canvas.drawRRect(barRect, bluePaint);

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.22
      ..strokeCap = StrokeCap.butt;

    final arcRect = Rect.fromCircle(center: center, radius: radius * 0.78);

    // Blue arc (top-right to right)
    arcPaint.color = const Color(0xFF4285F4);
    canvas.drawArc(arcRect, -0.4, 0.95, false, arcPaint);

    // Green arc (bottom-right to bottom)
    arcPaint.color = const Color(0xFF34A853);
    canvas.drawArc(arcRect, 0.55, 1.35, false, arcPaint);

    // Yellow arc (bottom-left to left)
    arcPaint.color = const Color(0xFFFBBC05);
    canvas.drawArc(arcRect, 1.9, 1.25, false, arcPaint);

    // Red arc (left to top-right)
    arcPaint.color = const Color(0xFFEA4335);
    canvas.drawArc(arcRect, 3.15, 1.5, false, arcPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
