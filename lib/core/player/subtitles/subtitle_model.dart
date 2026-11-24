import 'package:flutter/material.dart';

/// Individual subtitle text entry with start time, end time, and body text.
class CinemaSubtitleCue {
  const CinemaSubtitleCue({
    required this.start,
    required this.end,
    required this.text,
  });

  final Duration start;
  final Duration end;
  final String text;

  /// Whether this cue is active at the given video [position]
  bool isActiveAt(Duration position) {
    return position >= start && position <= end;
  }

  @override
  String toString() =>
      'CinemaSubtitleCue(${start.inSeconds}s - ${end.inSeconds}s: "$text")';
}

/// A subtitle track option available for selection.
class CinemaSubtitleTrack {
  const CinemaSubtitleTrack({
    required this.id,
    required this.label,
    required this.languageCode,
    required this.url,
    this.source = 'Provider',
    this.isEmbedded = false,
  });

  final String id;
  final String label;
  final String languageCode; // e.g. "en", "es", "fr"
  final String url;
  final String source; // e.g. "Stremio", "OpenSubtitles", "SubDL"
  final bool isEmbedded;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CinemaSubtitleTrack &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// User styling preferences for rendered subtitle text.
class CinemaSubtitleStyle {
  const CinemaSubtitleStyle({
    this.fontSize = 16.0,
    this.textColor = Colors.white,
    this.backgroundColor = const Color(0x99000000), // Semi-transparent black box
    this.textOutlineColor = Colors.black,
  });

  final double fontSize;
  final Color textColor;
  final Color backgroundColor;
  final Color textOutlineColor;

  CinemaSubtitleStyle copyWith({
    double? fontSize,
    Color? textColor,
    Color? backgroundColor,
    Color? textOutlineColor,
  }) {
    return CinemaSubtitleStyle(
      fontSize: fontSize ?? this.fontSize,
      textColor: textColor ?? this.textColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      textOutlineColor: textOutlineColor ?? this.textOutlineColor,
    );
  }
}
