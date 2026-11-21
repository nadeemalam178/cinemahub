import 'package:flutter/material.dart';

import '../../core/theme/cinemahub_colors.dart';
import '../../core/theme/cinemahub_logo.dart';
import '../../core/theme/cinemahub_tokens.dart';

/// Branded splash with cinematic ambient lighting, 3D animated emblem, and smooth wordmark reveal.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  late final Animation<double> _taglineFade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.65, curve: Curves.easeIn),
    );

    _scale = Tween<double>(begin: 0.75, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.75, curve: Curves.easeOutBack),
      ),
    );

    _taglineFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.45, 0.95, curve: Curves.easeIn),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onFinished();
      }
    });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Ambient Background Glow
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.0, -0.1),
                radius: 0.95,
                colors: [
                  Color(0xFF2E0509),
                  Color(0xFF120305),
                  Colors.black,
                ],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),

          // 2. Center Content with animated logo & wordmark
          Center(
            child: FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Animated 3D Logo Emblem
                    const CinemaHubLogo(
                      size: 72,
                      showWordmark: false,
                      animated: true,
                    ),
                    const SizedBox(height: CinemahubSpacing.xxl),

                    // Wordmark
                    const CinemaHubLogo(
                      size: 26,
                      showWordmark: true,
                    ),

                    const SizedBox(height: CinemahubSpacing.lg),

                    // Tagline
                    FadeTransition(
                      opacity: _taglineFade,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 24,
                            height: 1,
                            color: Colors.white24,
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Text(
                              'YOUR PRIVATE CINEMA',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 2.5,
                              ),
                            ),
                          ),
                          Container(
                            width: 24,
                            height: 1,
                            color: Colors.white24,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 3. Bottom Loading Pulse Indicator
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: Center(
              child: FadeTransition(
                opacity: _taglineFade,
                child: const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(CinemahubColors.primary),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
