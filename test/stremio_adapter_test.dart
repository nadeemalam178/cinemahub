import 'package:flutter_test/flutter_test.dart';
import 'package:cinemahub/core/providers/stremio_adapter.dart';

void main() {
  group('StreamResult Parsing', () {
    test('parses direct http url', () {
      final json = {
        'name': '1080p Stream',
        'url': 'https://example.com/video.mp4',
        'type': 'video/mp4',
      };
      final stream = StreamResult.fromJson(json);
      expect(stream.name, '1080p Stream');
      expect(stream.url, 'https://example.com/video.mp4');
      expect(stream.isVideo, isTrue);
    });

    test('converts infoHash to magnet link when url is absent', () {
      final json = {
        'name': 'P2P Stream',
        'infoHash': 'abc123def456',
        'type': 'application/octet-stream',
      };
      final stream = StreamResult.fromJson(json);
      expect(stream.name, 'P2P Stream');
      expect(stream.url, startsWith('magnet:?xt=urn:btih:abc123def456'));
      expect(stream.hash, 'abc123def456');
    });

    test('handles empty or missing url gracefully', () {
      final json = {
        'name': 'Empty Stream',
      };
      final stream = StreamResult.fromJson(json);
      expect(stream.name, 'Empty Stream');
      expect(stream.url, '');
      expect(stream.hash, isNull);
    });
  });
}
