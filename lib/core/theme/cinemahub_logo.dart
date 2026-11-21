import 'package:flutter/material.dart';
import 'cinemahub_colors.dart';

/// Premium 3D-effect Cinematic Logo for CinemaHub with glow, metallic gold, and neon crimson depth.
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
    if (widget.animated) {
      _animController = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 3),
      )..repeat(reverse: true);
      _glowAnimation = Tween<double>(begin: 0.25, end: 0.65).animate(
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
        SizedBox(width: widget.size * 0.3),
        _buildWordmark(),
      ],
    );
  }

  Widget _buildEmblem() {
    final emblemWidget = Container(
      width: widget.size * 1.35,
      height: widget.size * 1.35,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.2, -0.3),
          radius: 0.9,
          colors: [
            Color(0xFFFF2A3A),
            CinemahubColors.primary,
            Color(0xFF6B0008),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: CinemahubColors.primary.withValues(alpha: 0.45),
            blurRadius: widget.size * 0.6,
            spreadRadius: 1,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: widget.size * 0.3,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: CinemahubColors.gold.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Soft inner glow
            Icon(
              Icons.play_arrow_rounded,
              size: widget.size * 0.85,
              color: CinemahubColors.gold.withValues(alpha: 0.25),
            ),
            // Sharp crisp white play glyph
            Icon(
              Icons.play_arrow_rounded,
              size: widget.size * 0.75,
              color: Colors.white,
            ),
          ],
        ),
      ),
    );

    if (widget.animated && _glowAnimation != null) {
      return AnimatedBuilder(
        animation: _glowAnimation!,
        builder: (context, child) => Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: CinemahubColors.primary.withValues(alpha: _glowAnimation!.value),
                blurRadius: widget.size * 0.9,
                spreadRadius: widget.size * 0.2,
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
    final fontSize = widget.size * 0.65;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: widget.size * 0.28,
            vertical: widget.size * 0.1,
          ),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFE50914), Color(0xFFB00610)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(widget.size * 0.2),
            boxShadow: [
              BoxShadow(
                color: CinemahubColors.primary.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 0.8,
            ),
          ),
          child: Text(
            'CINEMA',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.8,
              fontSize: fontSize * 0.85,
            ),
          ),
        ),
        SizedBox(width: widget.size * 0.14),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFFFFEA79), Color(0xFFFFC107), Color(0xFFFF9800)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: Text(
            'HUB',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.2,
              fontSize: fontSize,
              shadows: [
                Shadow(
                  color: CinemahubColors.gold.withValues(alpha: 0.6),
                  blurRadius: 10,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
