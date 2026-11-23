import 'package:flutter_test/flutter_test.dart';
import 'package:cinemahub/core/streaming/models/stream_source.dart';
import 'package:cinemahub/core/streaming/models/media_request.dart';
import 'package:cinemahub/core/streaming/models/source_error.dart';
import 'package:cinemahub/core/streaming/player/player_router.dart';
import 'package:cinemahub/core/streaming/diagnostics/streaming_logger.dart';
import 'package:cinemahub/core/providers/stremio_adapter.dart';

void main() {
  group('StreamSource Model & Format Detection', () {
    test('detects direct MP4 media format correctly', () {
      final type = StreamSource.detectStreamType('https://cdn.example.com/video.mp4');
      expect(type, StreamType.directHttp);
    });

    test('detects direct MP4 with complex query parameters correctly', () {
      final type = StreamSource.detectStreamType('https://cdn.example.com/video.mp4?expires=1700000&token=xyz#t=10');
      expect(type, StreamType.directHttp);
    });

    test('does not misclassify web embed pages with mp4 in query parameters', () {
      final type = StreamSource.detectStreamType('https://streamhub.to/watch?title=action&utm_source=mp4news');
      expect(type, StreamType.embed);
    });

    test('detects HLS .m3u8 stream correctly', () {
      final type = StreamSource.detectStreamType('https://streaming.server.net/live/master.m3u8?token=xyz');
      expect(type, StreamType.hls);
    });

    test('detects MPEG-DASH .mpd stream correctly', () {
      final type = StreamSource.detectStreamType('https://dash.cdn.com/manifest.mpd');
      expect(type, StreamType.dash);
    });

    test('detects BitTorrent magnet URIs correctly', () {
      final type = StreamSource.detectStreamType('magnet:?xt=urn:btih:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855&dn=Test');
      expect(type, StreamType.magnet);
    });

    test('detects web embed player URLs correctly', () {
      final type = StreamSource.detectStreamType('https://vidsrc.to/embed/movie/550');
      expect(type, StreamType.embed);
    });

    test('respects behaviorHints override when provided', () {
      final type = StreamSource.detectStreamType(
        'https://unknown-service.com/watch',
        hints: {'isWebEmbed': true},
      );
      expect(type, StreamType.embed);
    });

    test('detects HLS and DASH formats from MIME type hints', () {
      final hlsType = StreamSource.detectStreamType(
        'https://cdn.example.com/stream/index',
        mimeType: 'application/x-mpegURL',
      );
      expect(hlsType, StreamType.hls);

      final dashType = StreamSource.detectStreamType(
        'https://cdn.example.com/stream/manifest',
        mimeType: 'application/dash+xml',
      );
      expect(dashType, StreamType.dash);
    });

    test('converts legacy StreamResult to StreamSource preserving headers and metadata', () {
      const legacy = StreamResult(
        name: 'VidSrc PRO Server [1080p]',
        url: 'https://vidsrc.pm/embed/movie/550',
        type: 'embed',
        behaviorHints: {
          'isWebEmbed': true,
          'provider': 'FMHY / VidSrc',
          'headers': {
            'Referer': 'https://vidsrc.pm/',
            'Origin': 'https://vidsrc.pm',
            'User-Agent': 'CustomUA/1.0',
          },
          'speed': 'Fast CDN',
        },
      );

      final source = StreamSource.fromStreamResult(legacy);

      expect(source.name, 'VidSrc PRO Server [1080p]');
      expect(source.provider, 'FMHY / VidSrc');
      expect(source.url, 'https://vidsrc.pm/embed/movie/550');
      expect(source.type, StreamType.embed);
      expect(source.headers['Referer'], 'https://vidsrc.pm/');
      expect(source.headers['Origin'], 'https://vidsrc.pm');
      expect(source.headers['User-Agent'], 'CustomUA/1.0');
      expect(source.metadata['speed'], 'Fast CDN');
      expect(source.isPlayableInternally, isTrue);
    });
  });

  group('MediaRequest Model & Canonical IDs', () {
    test('constructs movie request and generates canonical ID', () {
      const request = MediaRequest(
        tmdbId: '550',
        imdbId: 'tt0137523',
        title: 'Fight Club',
        type: MediaType.movie,
        year: 1999,
      );

      expect(request.type, MediaType.movie);
      expect(request.tmdbId, '550');
      expect(request.imdbId, 'tt0137523');
      expect(request.title, 'Fight Club');
      expect(request.canonicalId, 'tt0137523');
      expect(request.isMovie, isTrue);
      expect(request.isSeries, isFalse);
    });

    test('constructs series request and formats season & episode identifier', () {
      const request = MediaRequest(
        tmdbId: '1396',
        imdbId: 'tt0903747',
        title: 'Breaking Bad',
        type: MediaType.series,
        season: 5,
        episode: 14,
      );

      expect(request.type, MediaType.series);
      expect(request.season, 5);
      expect(request.episode, 14);
      expect(request.canonicalId, 'tt0903747:5:14');
      expect(request.isSeries, isTrue);
    });

    test('falls back to tmdb canonical id when imdb id is omitted', () {
      const request = MediaRequest(
        tmdbId: '872585',
        title: 'Oppenheimer',
        type: MediaType.movie,
      );

      expect(request.canonicalId, 'tmdb:872585');
    });
  });

  group('PlayerRouter Routing Decisions', () {
    const router = PlayerRouter();

    test('routes direct HTTP MP4 stream to NativePlayer', () {
      const source = StreamSource(
        id: '1',
        provider: 'DirectCDN',
        name: 'Test 1080p MP4',
        url: 'https://archive.org/download/test/video.mp4',
        type: StreamType.directHttp,
        isPlayableInternally: true,
      );

      final decision = router.route(source);
      expect(decision.player, TargetPlayer.nativePlayer);
      expect(decision.reason, contains('Direct media stream'));
    });

    test('routes HLS .m3u8 stream to NativePlayer', () {
      const source = StreamSource(
        id: '2',
        provider: 'HLSProvider',
        name: 'Live HLS Feed',
        url: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
        type: StreamType.hls,
        isPlayableInternally: true,
      );

      final decision = router.route(source);
      expect(decision.player, TargetPlayer.nativePlayer);
    });

    test('routes web embed to WebPlayer', () {
      const source = StreamSource(
        id: '3',
        provider: 'VidSrc',
        name: 'VidSrc Embed',
        url: 'https://vidsrc.to/embed/movie/550',
        type: StreamType.embed,
        isPlayableInternally: true,
      );

      final decision = router.route(source);
      expect(decision.player, TargetPlayer.webPlayer);
    });

    test('routes BitTorrent magnet to TorrentNotice without crashing native player', () {
      const source = StreamSource(
        id: '4',
        provider: 'Torrentio',
        name: 'Torrentio 1080p (24 Seeders)',
        url: 'magnet:?xt=urn:btih:1234567890abcdef&dn=Test+Movie',
        type: StreamType.magnet,
        isPlayableInternally: false,
      );

      final decision = router.route(source);
      expect(decision.player, TargetPlayer.nativePlayer);
      expect(decision.reason, contains('BitTorrent P2P magnet link routed to internal Torrent Streamer'));
    });

    test('rejects empty stream URLs as Unsupported', () {
      const source = StreamSource(
        id: '5',
        provider: 'BrokenProvider',
        name: 'Empty Stream',
        url: '',
        type: StreamType.directHttp,
        isPlayableInternally: false,
      );

      final decision = router.route(source);
      expect(decision.player, TargetPlayer.unsupported);
      expect(decision.reason, contains('empty or malformed'));
    });
  });

  group('StreamingLogger Sensitive Redaction & Diagnostics', () {
    test('redacts Real-Debrid API keys and tokens from log messages and URLs', () {
      StreamingLogger.instance.clear();

      const sensitiveUrl = 'https://torrentio.strem.fun/realdebrid=SUPER_SECRET_RD_API_TOKEN_12345/stream/movie/tt0137523.json';
      StreamingLogger.instance.log(
        stage: 'TestAudit',
        message: 'Loaded stremio endpoint with token: SUPER_SECRET_RD_API_TOKEN_12345',
        provider: 'Torrentio',
        streamUrl: sensitiveUrl,
        details: 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.sensitive_payload_data.xyz',
      );

      final events = StreamingLogger.instance.events;
      expect(events.length, 1);

      final entry = events.first;
      expect(entry.streamUrl, isNot(contains('SUPER_SECRET_RD_API_TOKEN_12345')));
      expect(entry.streamUrl, contains('realdebrid=[REDACTED]'));
      expect(entry.message, isNot(contains('SUPER_SECRET_RD_API_TOKEN_12345')));
      expect(entry.details, isNot(contains('eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.sensitive_payload_data.xyz')));
      expect(entry.details, contains('Bearer [REDACTED]'));
    });
  });

  group('SourceError Diagnostic Modeling', () {
    test('captures detailed technical context and human readable messages', () {
      final error = SourceError(
        provider: 'Torrentio',
        stage: ErrorStage.streamResolution,
        category: ErrorCategory.networkTimeout,
        message: 'Stream provider took too long to respond.',
        technicalDetails: 'ConnectTimeout [10000ms] connecting to https://torrentio.strem.fun',
      );

      expect(error.provider, 'Torrentio');
      expect(error.stage, ErrorStage.streamResolution);
      expect(error.category, ErrorCategory.networkTimeout);
      expect(error.message, contains('too long to respond'));
      expect(error.technicalDetails, contains('ConnectTimeout'));
      expect(error.toString(), contains('Torrentio'));
    });
  });
}
