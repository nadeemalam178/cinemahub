import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'stremio_adapter.dart';

/// CloudStream provider engine.
/// Scrapes verified CloudStream public extractor endpoints and API mirrors in parallel
/// for direct video streams (HLS/M3U8/MP4) and ad-blocked embeds.
class CloudStreamProviderEngine {
  CloudStreamProviderEngine({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 8),
            ));

  final Dio _dio;

  /// Verified CloudStream extractor engines & public API mirrors
  static const List<Map<String, String>> cloudStreamEngines = [
    {
      'id': 'sorastream',
      'name': 'SoraStream (CloudStream)',
      'apiUrl': 'https://api.sorastream.top',
      'embedUrl': 'https://sorastream.top/watch',
    },
    {
      'id': 'sudoflix',
      'name': 'Sudo-Flix Direct',
      'apiUrl': 'https://api.sudo-flix.lol',
      'embedUrl': 'https://sudo-flix.lol/watch',
    },
    {
      'id': 'superstream',
      'name': 'SuperStream Fast M3U8',
      'apiUrl': 'https://api.superstream.network',
      'embedUrl': 'https://superstream.network/embed',
    },
    {
      'id': 'hexated_cs',
      'name': 'Hexated Community Stream',
      'apiUrl': 'https://hexated.github.io',
      'embedUrl': 'https://hexated-stream.org/watch',
    },
  ];

  /// Fetch streams from CloudStream sources using TMDB ID or IMDb ID.
  Future<List<StreamResult>> fetchStreams({
    required bool isMovie,
    required String tmdbId,
    required String imdbId,
    int? season,
    int? episode,
  }) async {
    final id = tmdbId.isNotEmpty ? tmdbId : imdbId;
    if (id.isEmpty) return [];

    final s = season ?? 1;
    final ep = episode ?? 1;
    final queryParam = isMovie
        ? '/stream?type=movie&id=$id'
        : '/stream?type=series&id=$id&season=$s&episode=$ep';

    final results = <StreamResult>[];
    await Future.wait(
      cloudStreamEngines.map((engine) async {
        try {
          final res = await _dio.get('${engine['apiUrl']}$queryParam');
          if (res.statusCode == 200 && res.data is Map) {
            final streams = res.data['streams'] as List?;
            if (streams != null) {
              for (final st in streams) {
                if (st is Map && st['url'] != null) {
                  final url = st['url'] as String;
                  final quality = st['quality'] as String? ?? 'HD';
                  final lower = url.toLowerCase();

                  String mimeType = 'text/html';
                  bool isDirect = false;

                  if (lower.contains('.m3u8')) {
                    mimeType = 'application/x-mpegURL';
                    isDirect = true;
                  } else if (lower.contains('.mp4') ||
                      lower.contains('.mkv') ||
                      lower.contains('.webm')) {
                    mimeType = 'video/mp4';
                    isDirect = true;
                  } else if (lower.contains('.mpd')) {
                    mimeType = 'application/dash+xml';
                    isDirect = true;
                  }

                  results.add(StreamResult(
                    url: url,
                    name: '${engine['name']} • $quality',
                    type: mimeType,
                    behaviorHints: {
                      'isWebEmbed': !isDirect,
                      'isDirectHttp': isDirect,
                      'title': '${engine['name']} • $quality',
                      'quality': quality,
                      'category': 'cloudstream',
                      'categoryLabel': 'CloudStream',
                      'provider': engine['name']!,
                    },
                  ));
                }
              }
            }
          }
        } catch (e) {
          debugPrint('CloudStream engine ${engine['id']} error: $e');
        }
      }),
    );

    return results;
  }
}
