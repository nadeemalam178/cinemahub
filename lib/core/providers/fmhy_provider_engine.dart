import 'stremio_adapter.dart';
import '../streaming/diagnostics/source_health_checker.dart';

/// Categorization of FMHY streaming and directory sources
enum FmhyServerCategory {
  htmlEmbed,        // In-app sandboxed video embed iframe (e.g. VidSrc, VidLink, 2Embed)
  directMedia,      // Direct progressive MP4 / HLS / DASH stream
  websiteDirectory, // General external website or directory portal (not an in-app player)
}

/// Represents an accessible FMHY streaming server specification with URL templates.
/// Note: These servers are verified for HTTP reachability and host activity,
/// but video stream playback for any specific title depends on the third-party
/// hoster's catalog, upstream CDN, and anti-bot checks.
class FmhyServerEntry {
  const FmhyServerEntry({
    required this.id,
    required this.name,
    required this.domain,
    required this.movieUrlTemplate,
    required this.tvUrlTemplate,
    this.prefersTmdb = true,
    this.category = FmhyServerCategory.htmlEmbed,
    this.attribution = 'FMHY Directory (https://fmhy.net/video)',
    this.customHeaders = const {},
  });

  final String id;
  final String name;
  final String domain;
  final String movieUrlTemplate;
  final String tvUrlTemplate;
  final bool prefersTmdb;
  final FmhyServerCategory category;
  final String attribution;
  final Map<String, String> customHeaders;

  /// Construct movie stream URL with TMDB or IMDb ID
  String buildMovieUrl({required String tmdbId, String? imdbId}) {
    final id = (prefersTmdb && tmdbId.isNotEmpty)
        ? tmdbId
        : ((imdbId != null && imdbId.isNotEmpty) ? imdbId : tmdbId);
    return movieUrlTemplate.replaceAll('{id}', id);
  }

  /// Construct TV episode stream URL with TMDB or IMDb ID, season, and episode
  String buildTvUrl({
    required String tmdbId,
    String? imdbId,
    required int season,
    required int episode,
  }) {
    final id = (prefersTmdb && tmdbId.isNotEmpty)
        ? tmdbId
        : ((imdbId != null && imdbId.isNotEmpty) ? imdbId : tmdbId);
    return tvUrlTemplate
        .replaceAll('{id}', id)
        .replaceAll('{season}', season.toString())
        .replaceAll('{episode}', episode.toString());
  }

  /// Generate standard browser headers required for embed loading
  Map<String, String> get resolvedHeaders => {
        'Referer': 'https://$domain/',
        'Origin': 'https://$domain',
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13; Pixel 7 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        ...customHeaders,
      };
}

/// Provider engine for verified FMHY streaming servers and web embeds.
/// Standardizes source discovery, removes dead mirrors, deduplicates domains,
/// and eliminates fabricated speed and reliability metrics.
class FmhyProviderEngine {
  const FmhyProviderEngine({this.healthChecker});

  final SourceHealthChecker? healthChecker;

  /// Curated list of accessible, HTTP-verified FMHY embed servers.
  /// Confirmed active via HTTP probe (HTTP 200/302).
  /// Note: HTTP responsiveness confirms host domain reachability; actual video
  /// playback availability varies per title and host upstream CDN.
  /// Filters out dead domains and obsolete mirrors (such as multiembed.mov,
  /// vidsrc.xyz, vidsrc.rip, autoembed.cc, and embed.su).
  static const List<FmhyServerEntry> verifiedServers = [
    FmhyServerEntry(
      id: 'vidsrc_to',
      name: 'VidSrc PRO',
      domain: 'vidsrc.to',
      movieUrlTemplate: 'https://vidsrc.to/embed/movie/{id}',
      tvUrlTemplate: 'https://vidsrc.to/embed/tv/{id}/{season}/{episode}',
      prefersTmdb: true,
    ),
    FmhyServerEntry(
      id: 'vidlink',
      name: 'VidLink Cloud',
      domain: 'vidlink.pro',
      movieUrlTemplate: 'https://vidlink.pro/movie/{id}',
      tvUrlTemplate: 'https://vidlink.pro/tv/{id}/{season}/{episode}',
      prefersTmdb: true,
    ),
    FmhyServerEntry(
      id: 'vidsrc_me',
      name: 'VidSrc Classic (SH)',
      domain: 'vidsrc.me',
      movieUrlTemplate: 'https://vidsrc.me/embed/movie?imdb={id}',
      tvUrlTemplate: 'https://vidsrc.me/embed/tv?imdb={id}&season={season}&episode={episode}',
      prefersTmdb: false,
    ),
    FmhyServerEntry(
      id: 'two_embed',
      name: '2Embed Stream',
      domain: 'www.2embed.cc',
      movieUrlTemplate: 'https://www.2embed.cc/embed/{id}',
      tvUrlTemplate: 'https://www.2embed.cc/embedtv/{id}&s={season}&e={episode}',
      prefersTmdb: true,
    ),
    FmhyServerEntry(
      id: 'frembed',
      name: 'Frembed Multi-Audio',
      domain: 'frembed.live',
      movieUrlTemplate: 'https://frembed.live/api/film.php?id={id}',
      tvUrlTemplate: 'https://frembed.live/api/serie.php?id={id}&s={season}&e={episode}',
      prefersTmdb: true,
    ),
    FmhyServerEntry(
      id: 'nontongo',
      name: 'NontonGo MovieWeb',
      domain: 'www.nontongo.win',
      movieUrlTemplate: 'https://www.NontonGo.win/embed/movie/{id}',
      tvUrlTemplate: 'https://www.NontonGo.win/embed/tv/{id}/{season}/{episode}',
      prefersTmdb: true,
    ),
    FmhyServerEntry(
      id: 'warezcdn',
      name: 'WarezCDN Player',
      domain: 'embed.warezcdn.net',
      movieUrlTemplate: 'https://embed.warezcdn.net/filme/{id}',
      tvUrlTemplate: 'https://embed.warezcdn.net/serie/{id}/{season}/{episode}',
      prefersTmdb: true,
    ),
  ];

  /// Deduplicate servers by canonical base domain to prevent redundant mirrors
  static List<FmhyServerEntry> deduplicateServers(List<FmhyServerEntry> servers) {
    final seen = <String>{};
    final result = <FmhyServerEntry>[];
    for (final s in servers) {
      final canonical = s.domain.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
      if (seen.add(canonical)) {
        result.add(s);
      }
    }
    return result;
  }

  /// Resolves available FMHY streams for given TMDB and/or IMDb ID.
  /// Eliminates fake 1080p speed strings and fabricated reliability scores.
  List<StreamResult> resolveAllStreams({
    required String tmdbId,
    String? imdbId,
    required bool isMovie,
    int? season,
    int? episode,
  }) {
    final s = season ?? 1;
    final ep = episode ?? 1;

    // Clean inputs: strip non-numeric from TMDB and validate IMDb format (tt followed by digits)
    final cleanTmdb = tmdbId.replaceAll(RegExp(r'[^0-9]'), '');
    final imdbMatch = RegExp(r'tt\d+').firstMatch(imdbId ?? '');
    final cleanImdb = imdbMatch != null ? imdbMatch.group(0)! : '';

    if (cleanTmdb.isEmpty && cleanImdb.isEmpty) {
      return [];
    }

    final uniqueServers = deduplicateServers(verifiedServers);
    final streams = <StreamResult>[];

    for (final server in uniqueServers) {
      // Check if server is currently known to be down via health tracker
      if (healthChecker != null) {
        final record = healthChecker!.getRecord('https://${server.domain}');
        if (!record.isUsable) {
          continue; // Skip persistently failing server
        }
      }

      final streamUrl = isMovie
          ? server.buildMovieUrl(tmdbId: cleanTmdb, imdbId: cleanImdb)
          : server.buildTvUrl(tmdbId: cleanTmdb, imdbId: cleanImdb, season: s, episode: ep);

      if (streamUrl.isEmpty) continue;

      final isEmbed = server.category == FmhyServerCategory.htmlEmbed;
      final isOrdinaryWebsite = server.category == FmhyServerCategory.websiteDirectory;

      streams.add(
        StreamResult(
          url: streamUrl,
          name: server.name,
          type: isEmbed ? 'text/html' : (isOrdinaryWebsite ? 'text/plain' : 'video/mp4'),
          behaviorHints: {
            'isWebEmbed': isEmbed,
            'isOrdinaryWebsite': isOrdinaryWebsite,
            'isDirectHttp': !isEmbed && !isOrdinaryWebsite,
            'isTorrent': false,
            'provider': 'FMHY / ${server.name}',
            'serverId': server.id,
            'domain': server.domain,
            'attribution': server.attribution,
            'category': 'fmhy',
            'categoryLabel': isEmbed ? 'FMHY Embed Server' : 'FMHY Web Portal',
            'headers': server.resolvedHeaders,
          },
        ),
      );
    }

    return streams;
  }
}
