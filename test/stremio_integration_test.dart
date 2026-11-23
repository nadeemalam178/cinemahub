import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:cinemahub/core/providers/stremio_adapter.dart';
import 'package:cinemahub/core/providers/stremio_torrent_scraper.dart';
import 'package:cinemahub/core/streaming/diagnostics/streaming_logger.dart';
import 'package:cinemahub/core/streaming/models/stream_source.dart';
import 'package:cinemahub/core/streaming/player/player_router.dart';

/// In-memory mock adapter for Dio to prevent any real network requests during tests
class MockHttpClientAdapter implements HttpClientAdapter {
  MockHttpClientAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. Stremio Manifest Parsing & Resource Configurations', () {
    test('parses simple string resources manifest', () {
      final json = {
        'id': 'org.stremio.test',
        'name': 'Test Simple Addon',
        'version': '1.0.0',
        'description': 'Tests simple resources',
        'resources': ['stream', 'catalog'],
        'types': ['movie', 'series'],
        'idPrefixes': ['tt'],
      };

      final manifest = AddonManifest.fromJson(json);
      expect(manifest.id, 'org.stremio.test');
      expect(manifest.name, 'Test Simple Addon');
      expect(manifest.supportsResource('stream'), isTrue);
      expect(manifest.supportsResource('catalog'), isTrue);
      expect(manifest.supportsResource('meta'), isFalse);
      expect(manifest.supportsType('movie'), isTrue);
      expect(manifest.supportsType('series'), isTrue);
      expect(manifest.supportsType('anime'), isFalse);
    });

    test('parses complex object resources manifest with space-separated types', () {
      final json = {
        'id': 'org.elfhosted.mediafusion',
        'name': 'MediaFusion',
        'version': '4.2.0',
        'description': 'ElfHosted MediaFusion',
        'resources': [
          {
            'name': 'stream',
            'types': 'movie series anime',
            'idPrefixes': 'tt kitsu',
          },
          {
            'name': 'catalog',
            'types': ['movie'],
          }
        ],
        'types': 'movie series',
      };

      final manifest = AddonManifest.fromJson(json);
      expect(manifest.supportsResource('stream'), isTrue);
      expect(manifest.parsedResources.length, 2);
      expect(manifest.parsedResources.first.types, ['movie', 'series', 'anime']);
      expect(manifest.parsedResources.first.idPrefixes, ['tt', 'kitsu']);
    });

    test('checks stream support for movie and series with ID prefixes', () {
      final json = {
        'id': 'org.torrentio',
        'name': 'Torrentio',
        'version': '1.0.12',
        'description': 'Torrentio provider',
        'resources': [
          {
            'name': 'stream',
            'types': ['movie', 'series'],
            'idPrefixes': ['tt'],
          }
        ],
        'types': ['movie', 'series'],
      };

      final manifest = AddonManifest.fromJson(json);
      expect(manifest.supportsStreamFor('movie', id: 'tt1254207'), isTrue);
      expect(manifest.supportsStreamFor('series', id: 'tt0903747:1:1'), isTrue);
      expect(manifest.supportsStreamFor('movie', id: 'kitsu:550'), isFalse);
      expect(manifest.supportsStreamFor('channel', id: 'tt1254207'), isFalse);
    });
  });

  group('2. Movie vs Series Protocol URL Formatting', () {
    test('movie requests format exact /stream/movie/{imdbId}.json endpoint', () async {
      String? requestedUrl;
      final dio = Dio();
      dio.httpClientAdapter = MockHttpClientAdapter((options) async {
        requestedUrl = options.uri.toString();
        return ResponseBody.fromString(
          '{"streams": []}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final adapter = StremioAdapter(dio: dio);
      final results = await adapter.fetchStreams(
        baseUrl: 'https://torrentio.strem.fun',
        type: 'movie',
        id: 'tt1254207',
      );

      expect(requestedUrl, 'https://torrentio.strem.fun/stream/movie/tt1254207.json');
      expect(results, isEmpty);
    });

    test('series requests format exact /stream/series/{imdbId}:{season}:{episode}.json endpoint', () async {
      String? requestedUrl;
      final dio = Dio();
      dio.httpClientAdapter = MockHttpClientAdapter((options) async {
        requestedUrl = options.uri.toString();
        return ResponseBody.fromString(
          '{"streams": []}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final adapter = StremioAdapter(dio: dio);
      await adapter.fetchStreams(
        baseUrl: 'https://torrentio.strem.fun',
        type: 'series',
        id: 'tt0903747',
        season: 1,
        episode: 1,
      );

      expect(requestedUrl, 'https://torrentio.strem.fun/stream/series/tt0903747:1:1.json');
    });

    test('series request missing season or episode is rejected without movie fallback', () async {
      final scraper = StremioTorrentScraper();
      final streams = await scraper.fetchAllTorrentStreams(
        type: 'series',
        imdbId: 'tt0903747',
        season: null,
        episode: null,
      );

      expect(streams, isEmpty);
    });
  });

  group('3. StreamSource Classification Engine', () {
    test('classifies direct MP4 stream', () {
      final type = StreamSource.detectStreamType('https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4');
      expect(type, StreamType.directHttp);
    });

    test('classifies HLS master playlist', () {
      final type = StreamSource.detectStreamType('https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8');
      expect(type, StreamType.hls);
    });

    test('classifies MPEG-DASH manifest', () {
      final type = StreamSource.detectStreamType('https://dash.akamaized.net/akamai/bbb_30fps/bbb_30fps.mpd');
      expect(type, StreamType.dash);
    });

    test('classifies Web Embed stream', () {
      final type = StreamSource.detectStreamType('https://vidsrc.to/embed/movie/tt1254207');
      expect(type, StreamType.embed);
    });

    test('classifies Magnet URI', () {
      final type = StreamSource.detectStreamType('magnet:?xt=urn:btih:d2474e86c95b19b8bcfdbda72436049feab74516&dn=Ubuntu');
      expect(type, StreamType.magnet);
    });

    test('classifies extensionless direct-download URL with video MIME type', () {
      final type = StreamSource.detectStreamType(
        'https://cdn.example.org/download/stream_chunk_99212',
        mimeType: 'video/mp4',
      );
      expect(type, StreamType.directHttp);
    });

    test('classifies streams with authentication query parameters correctly', () {
      final mp4Type = StreamSource.detectStreamType('https://example.com/secure_video.mp4?token=xyz123&expires=99999999');
      expect(mp4Type, StreamType.directHttp);

      final hlsType = StreamSource.detectStreamType('https://example.com/secure_playlist.m3u8?auth=secret_token');
      expect(hlsType, StreamType.hls);
    });
  });

  group('4. Stremio Torrent Stream Parsing & Real-Debrid', () {
    test('parses torrent infoHash, fileIdx, sources, and seeders into clean magnet URI', () {
      final raw = {
        'name': 'Torrentio\n1080p',
        'title': 'Big.Buck.Bunny.1080p.mkv\n👤 42 💾 2.3 GB ⚙️ Torrentio',
        'infoHash': 'd2474e86c95b19b8bcfdbda72436049feab74516',
        'fileIdx': 0,
        'sources': [
          'tracker:udp://tracker.opentrackr.org:1337/announce',
          'tracker:udp://open.demonii.com:1337/announce',
        ],
        'behaviorHints': {
          'filename': 'Big.Buck.Bunny.1080p.mkv',
        },
      };

      final streamResult = StreamResult.fromJson(raw);
      expect(streamResult.hash, 'd2474e86c95b19b8bcfdbda72436049feab74516');
      expect(streamResult.fileIndex, 0);
      expect(streamResult.url, startsWith('magnet:?xt=urn:btih:d2474e86c95b19b8bcfdbda72436049feab74516'));
      expect(streamResult.url, contains('&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337%2Fannounce'));

      final source = StreamSource.fromStreamResult(streamResult, providerName: 'Torrentio');
      expect(source.type, StreamType.magnet);
      expect(source.quality, '1080p FHD');
      expect(source.seeders, 42);
      expect(source.formattedSize, '2.3 GB');
      expect(source.isPlayableInternally, isTrue); // Magnet playable internally via torrent streamer
    });

    test('never defaults unknown quality to 1080p or seeders to 10', () {
      final raw = {
        'name': 'Unknown Addon',
        'title': 'Release.With.No.Tags.mkv',
        'infoHash': 'aabbccddeeff00112233445566778899aabbccdd',
      };

      final streamResult = StreamResult.fromJson(raw);
      final source = StreamSource.fromStreamResult(streamResult);
      expect(source.quality, isNull);
      expect(source.seeders, isNull);
    });

    test('parses Real-Debrid direct HTTPS stream and routes to native player', () {
      final raw = {
        'name': '[RD+] Torrentio\n4K',
        'title': 'Big.Buck.Bunny.2160p.UHD.mkv\n💾 8.5 GB',
        'url': 'https://download.real-debrid.com/d/XYZABC123/Big.Buck.Bunny.2160p.mkv',
        'behaviorHints': {
          'filename': 'Big.Buck.Bunny.2160p.mkv',
          'isDebrid': true,
        },
      };

      final streamResult = StreamResult.fromJson(raw);
      final source = StreamSource.fromStreamResult(streamResult, providerName: 'Torrentio (RD)');
      expect(source.type, StreamType.directHttp);
      expect(source.isDebrid, isTrue);
      expect(source.isPlayableInternally, isTrue);
      expect(source.quality, '4K UHD');
      expect(source.formattedSize, '8.5 GB');

      const router = PlayerRouter();
      final decision = router.route(source);
      expect(decision.player, TargetPlayer.nativePlayer);
    });

    test('handles missing infoHash and empty URL cleanly', () {
      final raw = {
        'name': 'Broken Stream',
        'title': 'Broken',
      };

      final streamResult = StreamResult.fromJson(raw);
      final source = StreamSource.fromStreamResult(streamResult);
      expect(source.isPlayableInternally, isFalse);
      expect(source.failureReason, contains('empty'));
    });

    test('handles missing or malformed IMDb ID cleanly', () async {
      final scraper = StremioTorrentScraper();
      final streams = await scraper.fetchAllTorrentStreams(
        type: 'movie',
        imdbId: 'invalid-id-without-tt',
      );
      expect(streams, isEmpty);
    });
  });

  group('5. Diagnostics & Secret Redaction', () {
    test('redacts Real-Debrid token from URL paths', () {
      const url = 'https://torrentio.strem.fun/realdebrid=secret_api_token_12345/stream/movie/tt1254207.json';
      final clean = StreamingLogger.redactSensitive(url);
      expect(clean, 'https://torrentio.strem.fun/realdebrid=[REDACTED]/stream/movie/tt1254207.json');
      expect(clean, isNot(contains('secret_api_token_12345')));
    });

    test('redacts basic auth credentials from URLs', () {
      const url = 'https://myuser:mypassword123@proxy.example.com/playlist.m3u8';
      final clean = StreamingLogger.redactSensitive(url);
      expect(clean, 'https://[USER]:[REDACTED]@proxy.example.com/playlist.m3u8');
      expect(clean, isNot(contains('mypassword123')));
    });

    test('redacts query string API keys and tokens', () {
      const url = 'https://api.example.com/v1/stream?api_key=AIzaSySecret999&token=bearer_4455';
      final clean = StreamingLogger.redactSensitive(url);
      expect(clean, contains('api_key=[REDACTED]'));
      expect(clean, contains('token=[REDACTED]'));
      expect(clean, isNot(contains('AIzaSySecret999')));
      expect(clean, isNot(contains('bearer_4455')));
    });

    test('redacts Bearer authorization tokens', () {
      const header = 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0';
      final clean = StreamingLogger.redactSensitive(header);
      expect(clean, 'Bearer [REDACTED]');
    });
  });

  group('6. Addon Fallback, HTTP Errors & Stream Deduplication', () {
    test('handles HTTP 403, 404, 429, and 500 status codes gracefully in StremioAdapter', () async {
      for (final statusCode in [403, 404, 429, 500, 502]) {
        final dio = Dio();
        dio.httpClientAdapter = MockHttpClientAdapter((options) async {
          return ResponseBody.fromString(
            'Error response',
            statusCode,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        });

        final adapter = StremioAdapter(dio: dio);
        final manifest = await adapter.fetchManifest('https://failing-addon.com');
        expect(manifest, isNull);

        final streams = await adapter.fetchStreams(
          baseUrl: 'https://failing-addon.com',
          type: 'movie',
          id: 'tt1254207',
        );
        expect(streams, isEmpty);
      }
    });

    test('deduplicates duplicate torrent streams with same infoHash and fileIdx', () async {
      final dio = Dio();
      dio.httpClientAdapter = MockHttpClientAdapter((options) async {
        if (options.uri.path.endsWith('/manifest.json')) {
          return ResponseBody.fromString(
            '{"id": "test", "version": "1.0.0", "name": "Test Addon", "description": "Test", "resources": ["stream"], "types": ["movie"]}',
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        return ResponseBody.fromString(
          '''
          {
            "streams": [
              {
                "name": "Addon A\\n1080p",
                "title": "Movie.1080p.mkv\\n👤 50 💾 2.0 GB",
                "infoHash": "1111222233334444555566667777888899990000",
                "fileIdx": 0
              },
              {
                "name": "Addon B\\n1080p",
                "title": "Movie.1080p.mkv\\n👤 50 💾 2.0 GB",
                "infoHash": "1111222233334444555566667777888899990000",
                "fileIdx": 0
              }
            ]
          }
          ''',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final adapter = StremioAdapter(dio: dio);
      final scraper = StremioTorrentScraper(adapter: adapter);

      final streams = await scraper.fetchAllTorrentStreams(
        type: 'movie',
        imdbId: 'tt1254207',
      );

      // Duplicate stream should be removed
      expect(streams.length, 1);
      expect(streams.first.hash, '1111222233334444555566667777888899990000');
    });

    test('ranks streams by Real-Debrid, then genuine seeders, then Quality', () async {
      final dio = Dio();
      dio.httpClientAdapter = MockHttpClientAdapter((options) async {
        if (options.uri.path.endsWith('/manifest.json')) {
          return ResponseBody.fromString(
            '{"id": "test", "version": "1.0.0", "name": "Test Addon", "description": "Test", "resources": ["stream"], "types": ["movie"]}',
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        return ResponseBody.fromString(
          '''
          {
            "streams": [
              {
                "name": "Addon Low Seeds\\n1080p",
                "title": "Movie.1080p.mkv\\n👤 5 💾 2.0 GB",
                "infoHash": "aaaa222233334444555566667777888899990000",
                "fileIdx": 0
              },
              {
                "name": "Addon High Seeds 4K\\n4K",
                "title": "Movie.2160p.UHD.mkv\\n👤 120 💾 10.0 GB",
                "infoHash": "bbbb222233334444555566667777888899990000",
                "fileIdx": 0
              }
            ]
          }
          ''',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final adapter = StremioAdapter(dio: dio);
      final scraper = StremioTorrentScraper(adapter: adapter);

      final streams = await scraper.fetchAllTorrentStreams(
        type: 'movie',
        imdbId: 'tt1254207',
      );

      expect(streams.length, 2);
      expect(streams.first.hash, 'bbbb222233334444555566667777888899990000'); // 120 seeds 4K first
    });
  });
}
