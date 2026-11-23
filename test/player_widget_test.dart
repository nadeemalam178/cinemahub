import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cinemahub/core/player/video_player_widget.dart';
import 'package:cinemahub/core/providers/stremio_adapter.dart';

void main() {
  group('CinemaPlayer Widget', () {
    testWidgets('renders error state on empty stream URL without crashing', (tester) async {
      const emptyStream = StreamResult(
        name: 'Invalid Stream',
        url: '',
        type: 'video/mp4',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CinemaPlayer(
              stream: emptyStream,
              allowExternalPlayer: true,
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('Playback Failed'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    testWidgets('renders error fallback on non-http scheme gracefully', (tester) async {
      const invalidStream = StreamResult(
        name: 'Invalid Scheme Stream',
        url: 'invalid://stream',
        type: 'video/mp4',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CinemaPlayer(
              stream: invalidStream,
              allowExternalPlayer: true,
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('Playback Failed'), findsOneWidget);
      expect(find.text('Open External Player'), findsOneWidget);
    });
  });
}
