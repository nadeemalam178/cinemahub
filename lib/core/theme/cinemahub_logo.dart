import 'package:flutter/material.dart';
import 'cinemahub_colors.dart';

/// Clean, premium cinematic logo for CinemaHub.
/// Built with balanced proportions, refined typography, and zero tacky gradient artifacts.
class CinemaHubLogo extends StatefulWidget {
  const CinemaHubLogo({
    super.key,
    this.size = 32,
    this.showWordmark = true,
    this.animated = false,
  });

  final double size;
  final bool showWordmark;
  final bool animated;

  @override
  State<CinemaHubLogo> createState() => _CinemaHubLogoState();
}

class _CinemaHubLogoState extends State<CinemaHubLogo>
    with SingleTickerProviderStateMixin {
  AnimationController? _animController;
  Animation<double>? _glowAnimation;

  @override
  void initState() {
    super.initState();
    final isTesting = WidgetsBinding.instance is! WidgetsFlutterBinding;
    if (widget.animated && !isTesting) {
      _animController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2400),
      )..repeat(reverse: true);
      _glowAnimation = Tween<double>(begin: 0.2, end: 0.55).animate(
        CurvedAnimation(parent: _animController!, curve: Curves.easeInOut),
      );
    }
  }

  @override
  void dispose() {
    _animController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final emblem = _buildEmblem();

    if (!widget.showWordmark) {
      return emblem;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        emblem,
        SizedBox(width: widget.size * 0.35),
        _buildWordmark(),
      ],
    );
  }

  Widget _buildEmblem() {
    final s = widget.size * 1.25;
    final emblemWidget = Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(s * 0.32),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFF2A4B),
            CinemahubColors.primary,
            Color(0xFF8B0720),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: CinemahubColors.primary.withValues(alpha: 0.4),
            blurRadius: s * 0.5,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: s * 0.25,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.22),
          width: 1.2,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.play_arrow_rounded,
          size: s * 0.68,
          color: Colors.white,
        ),
      ),
    );

    if (widget.animated && _glowAnimation != null) {
      return AnimatedBuilder(
        animation: _glowAnimation!,
        builder: (context, child) => Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(s * 0.32),
            boxShadow: [
              BoxShadow(
                color: CinemahubColors.primary
                    .withValues(alpha: _glowAnimation!.value),
                blurRadius: s * 0.8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: child,
        ),
        child: emblemWidget,
      );
    }

    return emblemWidget;
  }

  Widget _buildWordmark() {
    final fontSize = widget.size * 0.68;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          'CINEMA',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.4,
            fontSize: fontSize,
            fontFamily: 'Montserrat',
          ),
        ),
        const SizedBox(width: 3),
        Text(
          'HUB',
          style: TextStyle(
            color: CinemahubColors.primary,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.8,
            fontSize: fontSize,
            fontFamily: 'Montserrat',
          ),
        ),
      ],
    );
  }
}
