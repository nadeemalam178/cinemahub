import 'package:flutter/material.dart';
import 'subtitle_model.dart';

/// Real-time subtitle overlay widget rendered over the video viewport.
class SubtitleOverlay extends StatelessWidget {
  const SubtitleOverlay({
    super.key,
    required this.cues,
    required this.position,
    this.syncDelay = Duration.zero,
    this.style = const CinemaSubtitleStyle(),
  });

  final List<CinemaSubtitleCue> cues;
  final Duration position;
  final Duration syncDelay;
  final CinemaSubtitleStyle style;

  @override
  Widget build(BuildContext context) {
    if (cues.isEmpty) return const SizedBox.shrink();

    final adjustedPosition = position + syncDelay;
    final activeCues = cues.where((cue) => cue.isActiveAt(adjustedPosition)).toList();

    if (activeCues.isEmpty) return const SizedBox.shrink();

    final activeText = activeCues.map((c) => c.text).join('\n');

    return IgnorePointer(
      child: Container(
        alignment: Alignment.bottomCenter,
        padding: const EdgeInsets.only(bottom: 28, left: 24, right: 24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: style.backgroundColor,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            activeText,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: style.textColor,
              fontSize: style.fontSize,
              fontWeight: FontWeight.bold,
              height: 1.25,
              shadows: [
                Shadow(
                  offset: const Offset(1, 1),
                  blurRadius: 2.0,
                  color: style.textOutlineColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
