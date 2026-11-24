import 'package:flutter_test/flutter_test.dart';
import 'package:cinemahub/core/player/subtitles/subtitle_model.dart';
import 'package:cinemahub/core/player/subtitles/subtitle_parser.dart';

void main() {
  group('SubtitleParser Unit Tests', () {
    test('Parses standard SRT format correctly', () {
      const srt = '''
1
00:00:01,000 --> 00:00:04,500
Hello, welcome to CinemaHub!

2
00:00:05,000 --> 00:00:08,200
<b>Enjoy</b> seamless streaming.
''';

      final cues = SubtitleParser.parse(srt);

      expect(cues.length, equals(2));
      expect(cues[0].start, equals(const Duration(seconds: 1)));
      expect(cues[0].end, equals(const Duration(seconds: 4, milliseconds: 500)));
      expect(cues[0].text, equals('Hello, welcome to CinemaHub!'));

      expect(cues[1].start, equals(const Duration(seconds: 5)));
      expect(cues[1].text, equals('Enjoy seamless streaming.'));
    });

    test('Parses WebVTT format correctly', () {
      const vtt = '''
WEBVTT

00:01.000 --> 00:05.000
First WebVTT caption

00:06.000 --> 00:10.000
Second WebVTT caption
''';

      final cues = SubtitleParser.parse(vtt);

      expect(cues.length, equals(2));
      expect(cues[0].start, equals(const Duration(seconds: 1)));
      expect(cues[0].text, equals('First WebVTT caption'));
      expect(cues[1].start, equals(const Duration(seconds: 6)));
      expect(cues[1].text, equals('Second WebVTT caption'));
    });

    test('Handles isActiveAt with sync delay', () {
      final cue = CinemaSubtitleCue(
        start: const Duration(seconds: 10),
        end: const Duration(seconds: 15),
        text: 'Sync test',
      );

      expect(cue.isActiveAt(const Duration(seconds: 12)), isTrue);
      expect(cue.isActiveAt(const Duration(seconds: 8)), isFalse);
      expect(cue.isActiveAt(const Duration(seconds: 16)), isFalse);
    });
  });
}
