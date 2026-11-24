import 'subtitle_model.dart';

/// Parser for WebVTT (.vtt) and SubRip (.srt) subtitle files.
class SubtitleParser {
  /// Parse raw SRT or WebVTT content string into a chronological list of CinemaSubtitleCues
  static List<CinemaSubtitleCue> parse(String content) {
    if (content.trim().isEmpty) return const [];

    final isVtt = content.toUpperCase().startsWith('WEBVTT');
    if (isVtt) {
      return _parseVtt(content);
    }
    return _parseSrt(content);
  }

  static List<CinemaSubtitleCue> _parseSrt(String content) {
    final cues = <CinemaSubtitleCue>[];
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    final blocks = normalized.split(RegExp(r'\n\s*\n'));

    for (final block in blocks) {
      final lines = block.trim().split('\n');
      if (lines.length < 2) continue;

      int timeLineIdx = -1;
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].contains('-->')) {
          timeLineIdx = i;
          break;
        }
      }

      if (timeLineIdx == -1) continue;

      final timeParts = lines[timeLineIdx].split('-->');
      if (timeParts.length < 2) continue;

      final start = _parseTimestamp(timeParts[0].trim());
      final end = _parseTimestamp(timeParts[1].trim().split(' ')[0]);

      if (start == null || end == null) continue;

      final textLines = lines.sublist(timeLineIdx + 1);
      final rawText = textLines.join('\n');
      final cleanText = _stripHtml(rawText);

      if (cleanText.isNotEmpty) {
        cues.add(CinemaSubtitleCue(start: start, end: end, text: cleanText));
      }
    }

    cues.sort((a, b) => a.start.compareTo(b.start));
    return cues;
  }

  static List<CinemaSubtitleCue> _parseVtt(String content) {
    final cues = <CinemaSubtitleCue>[];
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    final blocks = normalized.split(RegExp(r'\n\s*\n'));

    for (final block in blocks) {
      if (block.toUpperCase().startsWith('WEBVTT')) continue;
      final lines = block.trim().split('\n');

      int timeLineIdx = -1;
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].contains('-->')) {
          timeLineIdx = i;
          break;
        }
      }

      if (timeLineIdx == -1) continue;

      final timeParts = lines[timeLineIdx].split('-->');
      if (timeParts.length < 2) continue;

      final start = _parseTimestamp(timeParts[0].trim());
      final end = _parseTimestamp(timeParts[1].trim().split(' ')[0]);

      if (start == null || end == null) continue;

      final textLines = lines.sublist(timeLineIdx + 1);
      final rawText = textLines.join('\n');
      final cleanText = _stripHtml(rawText);

      if (cleanText.isNotEmpty) {
        cues.add(CinemaSubtitleCue(start: start, end: end, text: cleanText));
      }
    }

    cues.sort((a, b) => a.start.compareTo(b.start));
    return cues;
  }

  static Duration? _parseTimestamp(String raw) {
    try {
      final clean = raw.replaceAll(',', '.').trim();
      final parts = clean.split(':');

      if (parts.length == 3) {
        final hours = int.parse(parts[0]);
        final minutes = int.parse(parts[1]);
        final secParts = parts[2].split('.');
        final seconds = int.parse(secParts[0]);
        final millis = secParts.length > 1
            ? int.parse(secParts[1].padRight(3, '0').substring(0, 3))
            : 0;

        return Duration(
          hours: hours,
          minutes: minutes,
          seconds: seconds,
          milliseconds: millis,
        );
      } else if (parts.length == 2) {
        final minutes = int.parse(parts[0]);
        final secParts = parts[1].split('.');
        final seconds = int.parse(secParts[0]);
        final millis = secParts.length > 1
            ? int.parse(secParts[1].padRight(3, '0').substring(0, 3))
            : 0;

        return Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: millis,
        );
      }
    } catch (_) {}
    return null;
  }

  /// Strip HTML and WebVTT cue styling tags
  static String _stripHtml(String text) {
    return text
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
  }
}
