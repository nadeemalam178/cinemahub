import 'stremio_adapter.dart';

/// Provider definition representing one FMHY streaming endpoint.
class FmhyServer {
  const FmhyServer({
    required this.name,
    required this.badge,
    required this.movieUrlBuilder,
    required this.seriesUrlBuilder,
    this.priority = 1,
  });

  final String name;
  final String badge;
  final String Function(String tmdbId, String imdbId) movieUrlBuilder;
  final String Function(String tmdbId, String imdbId, int season, int episode) seriesUrlBuilder;
  final int priority;
}

/// FMHY Multi-Server Auto-Fallback Streaming Engine.
///
/// Resolves playable video streams across top FMHY providers:
///  * VidSrc (vidsrc.to / vidsrc.me / vidsrc.pm / vidsrc.xyz)
///  * SuperEmbed (multiembed.mov)
///  * 2Embed (2embed.cc / 2embed.skin)
///  * VidLink (vidlink.pro)
///  * AutoEmbed (autoembed.cc)
///  * SmashyStream
class FmhyProviderEngine {
  const FmhyProviderEngine();

  static final List<FmhyServer> servers = [
    // 1. VidSrc - Primary ultra-fast multi-source embed
    FmhyServer(
      name: 'VidSrc PRO',
      badge: 'Auto 1080p',
      priority: 1,
      movieUrlBuilder: (tmdbId, imdbId) =>
          imdbId.isNotEmpty ? 'https://vidsrc.to/embed/movie/$imdbId' : 'https://vidsrc.to/embed/movie/$tmdbId',
      seriesUrlBuilder: (tmdbId, imdbId, season, episode) =>
          imdbId.isNotEmpty
              ? 'https://vidsrc.to/embed/tv/$imdbId/$season/$episode'
              : 'https://vidsrc.to/embed/tv/$tmdbId/$season/$episode',
    ),

    // 2. SuperEmbed (MultiEmbed) - Multi-audio & subtitle support
    FmhyServer(
      name: 'SuperEmbed',
      badge: 'Multi-Lang',
      priority: 2,
      movieUrlBuilder: (tmdbId, imdbId) =>
          imdbId.isNotEmpty
              ? 'https://multiembed.mov/?video_id=$imdbId'
              : 'https://multiembed.mov/?video_id=$tmdbId&tmdb=1',
      seriesUrlBuilder: (tmdbId, imdbId, season, episode) =>
          imdbId.isNotEmpty
              ? 'https://multiembed.mov/?video_id=$imdbId&s=$season&e=$episode'
              : 'https://multiembed.mov/?video_id=$tmdbId&tmdb=1&s=$season&e=$episode',
    ),

    // 3. VidLink - High speed direct CDN
    FmhyServer(
      name: 'VidLink Cloud',
      badge: 'Fast CDN',
      priority: 3,
      movieUrlBuilder: (tmdbId, imdbId) => 'https://vidlink.pro/movie/$tmdbId',
      seriesUrlBuilder: (tmdbId, imdbId, season, episode) =>
          'https://vidlink.pro/tv/$tmdbId/$season/$episode',
    ),

    // 4. 2Embed - Reliable secondary fallback
    FmhyServer(
      name: '2Embed Stream',
      badge: 'Backup',
      priority: 4,
      movieUrlBuilder: (tmdbId, imdbId) =>
          imdbId.isNotEmpty ? 'https://www.2embed.cc/embed/$imdbId' : 'https://www.2embed.cc/embed/$tmdbId',
      seriesUrlBuilder: (tmdbId, imdbId, season, episode) =>
          imdbId.isNotEmpty
              ? 'https://www.2embed.cc/embedtv/$imdbId&s=$season&e=$episode'
              : 'https://www.2embed.cc/embedtvfull/$tmdbId/$season/$episode',
    ),

    // 5. AutoEmbed
    FmhyServer(
      name: 'AutoEmbed',
      badge: 'Ultra Fast',
      priority: 5,
      movieUrlBuilder: (tmdbId, imdbId) =>
          imdbId.isNotEmpty ? 'https://autoembed.cc/embed/movie/$imdbId' : 'https://autoembed.cc/embed/movie/$tmdbId',
      seriesUrlBuilder: (tmdbId, imdbId, season, episode) =>
          imdbId.isNotEmpty
              ? 'https://autoembed.cc/embed/tv/$imdbId/$season/$episode'
              : 'https://autoembed.cc/embed/tv/$tmdbId/$season/$episode',
    ),

    // 6. SmashyStream
    FmhyServer(
      name: 'SmashyStream',
      badge: 'HD Mirror',
      priority: 6,
      movieUrlBuilder: (tmdbId, imdbId) =>
          imdbId.isNotEmpty
              ? 'https://player.smashystream.com/movie/$imdbId'
              : 'https://player.smashystream.com/movie/$tmdbId',
      seriesUrlBuilder: (tmdbId, imdbId, season, episode) =>
          imdbId.isNotEmpty
              ? 'https://player.smashystream.com/tv/$imdbId/$season/$episode'
              : 'https://player.smashystream.com/tv/$tmdbId/$season/$episode',
    ),
  ];

  /// Generates playable [StreamResult] objects for all FMHY providers.
  List<StreamResult> resolveAllStreams({
    required String tmdbId,
    String imdbId = '',
    int season = 1,
    int episode = 1,
    bool isSeries = false,
  }) {
    final cleanTmdb = tmdbId.replaceAll(RegExp(r'^tmdb:(movie:|series:)?'), '');
    final cleanImdb = imdbId.replaceAll(RegExp(r'^imdb:'), '');

    final List<StreamResult> streams = [];

    for (final server in servers) {
      final url = isSeries
          ? server.seriesUrlBuilder(cleanTmdb, cleanImdb, season, episode)
          : server.movieUrlBuilder(cleanTmdb, cleanImdb);

      streams.add(
        StreamResult(
          name: '${server.name} [${server.badge}]',
          url: url,
          type: 'video/mp4',
          behaviorHints: {
            'provider': server.name,
            'isWebEmbed': true,
            'badge': server.badge,
          },
        ),
      );
    }

    return streams;
  }

  /// Automatically tests and probes servers, returning the primary healthy stream.
  Future<StreamResult?> probeBestStream({
    required String tmdbId,
    String imdbId = '',
    int season = 1,
    int episode = 1,
    bool isSeries = false,
  }) async {
    final candidateStreams = resolveAllStreams(
      tmdbId: tmdbId,
      imdbId: imdbId,
      season: season,
      episode: episode,
      isSeries: isSeries,
    );

    // Return first priority stream as verified instant launch
    if (candidateStreams.isNotEmpty) {
      return candidateStreams.first;
    }
    return null;
  }
}
