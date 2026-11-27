import 'package:cinemahub/core/providers/stremio_adapter.dart';
import 'package:cinemahub/core/streaming/models/stream_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StreamSource.detectStreamType', () {
    test('detects magnet links, urn:btih, and torrent hints', () {
      expect(
        StreamSource.detectStreamType(
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567',
        ),
        StreamType.magnet,
      );
      expect(
        StreamSource.detectStreamType(
          'urn:btih:0123456789abcdef0123456789abcdef01234567',
        ),
        StreamType.magnet,
      );
      expect(
        StreamSource.detectStreamType(
          '',
          hints: {'isTorrent': true, 'infoHash': '0123456789abcdef'},
        ),
        StreamType.magnet,
      );
    });

    test('detects HLS, DASH, MP4, and Debrid streams', () {
      expect(
        StreamSource.detectStreamType('https://cdn.example.com/master.m3u8?token=abc'),
        StreamType.hls,
      );
      expect(
        StreamSource.detectStreamType('https://cdn.example.com/manifest.mpd'),
        StreamType.dash,
      );
      expect(
        StreamSource.detectStreamType('https://cdn.example.com/video.mp4?range=1'),
        StreamType.directHttp,
      );
      expect(
        StreamSource.detectStreamType('https://download.real-debrid.com/d/XYZ123/movie'),
        StreamType.directHttp,
      );
    });

    test('distinguishes FMHY embeds from ordinary website portals', () {
      expect(
        StreamSource.detectStreamType('https://vidsrc.to/embed/movie/550'),
        StreamType.embed,
      );
      expect(
        StreamSource.detectStreamType('https://vidlink.pro/movie/550'),
        StreamType.embed,
      );
      expect(
        StreamSource.detectStreamType('https://fmhy.net/video'),
        StreamType.website,
      );
    });
  });

  group('StreamSource.ensureTrackers & fromStreamResult', () {
    test('appends default trackers when magnet has none', () {
      const bare = 'magnet:?xt=urn:btih:abcdef1234567890';
      final enriched = StreamSource.ensureTrackers(bare);
      expect(enriched.startsWith(bare), isTrue);
      expect(enriched.contains('&tr='), isTrue);
    });

    test('does not duplicate trackers if already present', () {
      const withTracker =
          'magnet:?xt=urn:btih:abcdef1234567890&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337';
      expect(StreamSource.ensureTrackers(withTracker), equals(withTracker));
    });

    test('builds magnet URI with trackers from infoHash when url is empty', () {
      const result = StreamResult(
        name: 'Torrentio\n1080p',
        url: '',
        type: 'application/x-bittorrent',
        hash: 'dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c',
        description: 'Movie.2024.1080p.WEB-DL 👤 142 💾 2.4 GB',
      );
      final source = StreamSource.fromStreamResult(result);
      expect(source.type, StreamType.magnet);
      expect(source.isPlayableInternally, isTrue);
      expect(source.url, startsWith('magnet:?xt=urn:btih:dd8255ec'));
      expect(source.url, contains('&tr='));
      expect(source.quality, '1080p FHD');
      expect(source.seeders, 142);
      expect(source.sizeBytes, closeTo(2.4 * 1024 * 1024 * 1024, 1024));
    });
  });

  group('StreamSource metadata extractors', () {
    test('extracts quality, seeders, language, and size cleanly', () {
      const text = 'Movie.2160p.WEB-DL.Multi 👤 89 💾 4.5 GB';
      expect(StreamSource.extractQuality(text), '4K UHD');
      expect(StreamSource.extractSeeders(text), 89);
      expect(StreamSource.extractLanguage(text), 'Multi Audio');
      expect(StreamSource.extractSizeBytes(text), (4.5 * 1024 * 1024 * 1024).round());
    });
  });
}
