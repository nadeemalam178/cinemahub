import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:cinemahub/core/providers/fmhy_provider_engine.dart';
import 'package:cinemahub/core/providers/stremio_adapter.dart';
import 'package:cinemahub/core/streaming/diagnostics/source_health_checker.dart';
import 'package:cinemahub/core/streaming/diagnostics/streaming_logger.dart';
import 'package:cinemahub/core/streaming/models/stream_source.dart';
import 'package:cinemahub/core/streaming/player/player_router.dart';

/// In-memory mock adapter for Dio to prevent external network dependencies during tests
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

  group('1. FMHY Directory Discovery & Deduplication', () {
    test('deduplicates servers by canonical base domain', () {
      const servers = [
        FmhyServerEntry(
          id: 'vidsrc_1',
          name: 'VidSrc Primary',
          domain: 'vidsrc.to',
          movieUrlTemplate: 'https://vidsrc.to/embed/movie/{id}',
          tvUrlTemplate: 'https://vidsrc.to/embed/tv/{id}/{season}/{episode}',
        ),
        FmhyServerEntry(
          id: 'vidsrc_dup',
          name: 'VidSrc Duplicate Mirror',
          domain: 'www.vidsrc.to', // Duplicate www prefix
          movieUrlTemplate: 'https://www.vidsrc.to/embed/movie/{id}',
          tvUrlTemplate: 'https://www.vidsrc.to/embed/tv/{id}/{season}/{episode}',
        ),
        FmhyServerEntry(
          id: 'vidlink',
          name: 'VidLink Cloud',
          domain: 'vidlink.pro',
          movieUrlTemplate: 'https://vidlink.pro/movie/{id}',
          tvUrlTemplate: 'https://vidlink.pro/tv/{id}/{season}/{episode}',
        ),
      ];

      final unique = FmhyProviderEngine.deduplicateServers(servers);
      expect(unique.length, 2);
      expect(unique.first.id, 'vidsrc_1');
      expect(unique.last.id, 'vidlink');
    });

    test('constructs verified movie and series URLs without fabricating fake 1080p speed strings', () {
      const engine = FmhyProviderEngine();
      final movieStreams = engine.resolveAllStreams(
        tmdbId: '550',
        imdbId: 'tt0137523',
        isMovie: true,
      );

      expect(movieStreams, isNotEmpty);
      for (final s in movieStreams) {
        expect(s.url, isNotEmpty);
        expect(s.name, isNot(contains('Fast 1080p')));
        expect(s.name, isNot(contains('Ultra Fast 1080p')));
        expect(s.behaviorHints?['reliability'], isNull); // Fabricated reliability removed
        expect(s.behaviorHints?['attribution'], contains('FMHY Directory'));
        expect(s.behaviorHints?['headers'], isNotNull);
        expect(s.behaviorHints?['headers']['Referer'], startsWith('https://'));
      }

      final tvStreams = engine.resolveAllStreams(
        tmdbId: '1399',
        imdbId: 'tt0944947',
        isMovie: false,
        season: 1,
        episode: 1,
      );

      expect(tvStreams, isNotEmpty);
      for (final s in tvStreams) {
        expect(s.url, contains('1')); // Season or episode formatted
      }
    });

    test('handles empty or invalid content IDs cleanly', () {
      const engine = FmhyProviderEngine();
      final streams = engine.resolveAllStreams(
        tmdbId: '',
        imdbId: 'invalid-non-tt-id',
        isMovie: true,
      );

      expect(streams, isEmpty);
    });
  });

  group('2. Source Classification: Media vs Embed vs Website', () {
    test('classifies HTML embed players', () {
      final type = StreamSource.detectStreamType('https://vidsrc.to/embed/movie/550');
      expect(type, StreamType.embed);

      final typeVidLink = StreamSource.detectStreamType('https://vidlink.pro/movie/550');
      expect(typeVidLink, StreamType.embed);
    });

    test('classifies direct progressive media files', () {
      final mp4Type = StreamSource.detectStreamType('https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4');
      expect(mp4Type, StreamType.directHttp);
    });

    test('classifies HLS master playlists', () {
      final hlsType = StreamSource.detectStreamType('https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8');
      expect(hlsType, StreamType.hls);
    });

    test('classifies MPEG-DASH manifests', () {
      final dashType = StreamSource.detectStreamType('https://dash.akamaized.net/akamai/bbb_30fps/bbb_30fps.mpd');
      expect(dashType, StreamType.dash);
    });

    test('classifies ordinary non-embed directory portals and websites', () {
      final fmhyType = StreamSource.detectStreamType('https://fmhy.net/video');
      expect(fmhyType, StreamType.website);

      final redditType = StreamSource.detectStreamType('https://reddit.com/r/freemediaheckyeah');
      expect(redditType, StreamType.website);

      final explicitType = StreamSource.detectStreamType(
        'https://example-index.org/directory',
        hints: {'isOrdinaryWebsite': true},
      );
      expect(explicitType, StreamType.website);
    });

    test('routes ordinary websites to external browser and marks as not playable internally', () {
      final source = StreamSource(
        id: 'website_test',
        provider: 'FMHY Directory',
        name: 'FMHY Video Wiki',
        url: 'https://fmhy.net/video',
        type: StreamType.website,
        isPlayableInternally: false,
      );

      expect(source.isPlayableInternally, isFalse);

      const router = PlayerRouter();
      final decision = router.route(source);
      expect(decision.player, TargetPlayer.externalBrowser);
    });
  });

  group('3. Header Propagation & Referrer Preservation', () {
    test('StreamSource builds required Referer and Origin headers for embeds', () {
      const server = FmhyServerEntry(
        id: 'vidsrc_to',
        name: 'VidSrc PRO',
        domain: 'vidsrc.to',
        movieUrlTemplate: 'https://vidsrc.to/embed/movie/{id}',
        tvUrlTemplate: 'https://vidsrc.to/embed/tv/{id}/{season}/{episode}',
      );

      final headers = server.resolvedHeaders;
      expect(headers['Referer'], 'https://vidsrc.to/');
      expect(headers['Origin'], 'https://vidsrc.to');
      expect(headers['User-Agent'], contains('Mobile Safari'));
    });

    test('StreamSource.fromStreamResult preserves custom request headers', () {
      const result = StreamResult(
        name: 'VidSrc PRO',
        url: 'https://vidsrc.to/embed/movie/550',
        type: 'text/html',
        behaviorHints: {
          'isWebEmbed': true,
          'provider': 'FMHY / VidSrc PRO',
          'headers': {
            'Referer': 'https://vidsrc.to/',
            'Origin': 'https://vidsrc.to',
            'Custom-Header': 'SecretValue',
          },
        },
      );

      final source = StreamSource.fromStreamResult(result);
      expect(source.headers['Referer'], 'https://vidsrc.to/');
      expect(source.headers['Origin'], 'https://vidsrc.to');
      expect(source.headers['Custom-Header'], 'SecretValue');
    });
  });

  group('4. Source Health Tracking & Telemetry', () {
    test('tracks progressive health status transitions', () {
      final checker = SourceHealthChecker();
      const url = 'https://vidlink.pro/movie/550';

      // 1. Initial state
      var record = checker.getRecord(url);
      expect(record.status, HealthStatus.unknown);
      expect(record.isUsable, isTrue);

      // 2. Successful page load
      checker.recordSuccess(url, isVideoPlaying: false, responseTimeMs: 120);
      record = checker.getRecord(url);
      expect(record.status, HealthStatus.pageLoaded);
      expect(record.hasVerifiedPlayback, isFalse);
      expect(record.consecutiveSuccesses, 1);
      expect(record.consecutiveFailures, 0);

      // 3. Confirmed HTML5 video playback
      checker.recordSuccess(url, isVideoPlaying: true, responseTimeMs: 150);
      record = checker.getRecord(url);
      expect(record.status, HealthStatus.videoPlaying);
      expect(record.hasVerifiedPlayback, isTrue);

      // 4. Single temporary failure does not mark source permanently dead
      checker.recordFailure(url, failureType: HealthStatus.timeout, error: 'Temporary timeout');
      record = checker.getRecord(url);
      expect(record.status, HealthStatus.timeout);
      expect(record.consecutiveFailures, 1);
      expect(record.isUsable, isTrue); // Still usable!

      // 5. Three consecutive failures transitions source to unusable
      checker.recordFailure(url, failureType: HealthStatus.httpError, statusCode: 502, error: 'Bad Gateway');
      checker.recordFailure(url, failureType: HealthStatus.httpError, statusCode: 502, error: 'Bad Gateway');
      record = checker.getRecord(url);
      expect(record.consecutiveFailures, 3);
      expect(record.isUsable, isFalse); // Now marked unusable
    });

    test('probes live server endpoint and handles 200 vs 403 blocked response', () async {
      final dio = Dio();
      dio.httpClientAdapter = MockHttpClientAdapter((options) async {
        if (options.uri.host == 'blocked-mirror.com') {
          return ResponseBody.fromString(
            'Just a moment... Cloudflare challenge',
            403,
            headers: {
              Headers.contentTypeHeader: [Headers.textPlainContentType],
            },
          );
        }
        return ResponseBody.fromString(
          '<html><body><video src="stream.mp4"></video></body></html>',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.textPlainContentType],
          },
        );
      });

      final checker = SourceHealthChecker(dio: dio);

      // Probe healthy mirror
      final healthyResult = await checker.probe('https://healthy-mirror.com/embed/550');
      expect(healthyResult.isReachable, isTrue);
      expect(healthyResult.status, HealthStatus.pageLoaded);
      expect(healthyResult.statusCode, 200);

      // Probe blocked mirror
      final blockedResult = await checker.probe('https://blocked-mirror.com/embed/550');
      expect(blockedResult.isReachable, isFalse);
      expect(blockedResult.status, HealthStatus.blocked);
      expect(blockedResult.statusCode, 403);
    });

    test('redacts sensitive information in error messages', () {
      final clean = StreamingLogger.redactSensitive(
        'Failed to connect to https://proxy.com/api?api_key=secret_12345&token=auth_abc',
      );
      expect(clean, isNot(contains('secret_12345')));
      expect(clean, isNot(contains('auth_abc')));
      expect(clean, contains('api_key=[REDACTED]'));
      expect(clean, contains('token=[REDACTED]'));
    });
  });
}
