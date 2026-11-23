import 'dart:async';
import 'package:flutter/material.dart';

import '../../core/theme/cinemahub_colors.dart';
import '../../core/theme/cinemahub_logo.dart';
import '../../core/theme/cinemahub_tokens.dart';

/// Clean, cinematic splash screen with smooth fade transition and automatic timeout protection.
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
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    // Smooth, cinematic opacity reveal
    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic),
    );

    // Subtle, graceful scale: starts at 0.94x and settles naturally at 1.0x
    _scale = Tween<double>(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.85, curve: Curves.easeOutCubic),
      ),
    );

    _taglineFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.4, 1.0, curve: Curves.easeIn),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // Wait a brief moment at full visibility, then complete
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) widget.onFinished();
        });
      }
    });

    _controller.forward();

    // Safety timeout: Guarantee transition even if animation or auth event is delayed
    _timeoutTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) widget.onFinished();
    });
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08080E),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Ambient Background Vignette
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.0, -0.1),
                radius: 1.0,
                colors: [
                  Color(0xFF22050D),
                  Color(0xFF100307),
                  Color(0xFF08080E),
                ],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),

          // 2. Centered Logo and Tagline
          Center(
            child: FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CinemaHubLogo(
                      size: 46,
                      showWordmark: true,
                      animated: true,
                    ),
                    const SizedBox(height: CinemahubSpacing.xl),
                    FadeTransition(
                      opacity: _taglineFade,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 20,
                            height: 1,
                            color: Colors.white24,
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'PRIVATE STREAMING PLATFORM',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 2.2,
                              ),
                            ),
                          ),
                          Container(
                            width: 20,
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
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(CinemahubColors.primary),
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
