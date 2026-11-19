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

      expect(find.text('Playback unavailable'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    testWidgets('renders error fallback on non-http scheme gracefully', (tester) async {
      const magnetStream = StreamResult(
        name: 'Magnet Stream',
        url: 'magnet:?xt=urn:btih:12345',
        type: 'application/octet-stream',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CinemaPlayer(
              stream: magnetStream,
              allowExternalPlayer: true,
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('Playback unavailable'), findsOneWidget);
      expect(find.text('Try opening externally'), findsOneWidget);
    });

    testWidgets('disposing uninitialized player does not throw LateInitializationError', (tester) async {
      const emptyStream = StreamResult(
        name: 'Disposal Test Stream',
        url: '',
        type: 'video/mp4',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CinemaPlayer(
              stream: emptyStream,
            ),
          ),
        ),
      );

      await tester.pump();

      // Replace widget to trigger disposal of CinemaPlayer
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox.shrink(),
          ),
        ),
      );

      await tester.pump();
      expect(find.byType(CinemaPlayer), findsNothing);
    });
  });
}
