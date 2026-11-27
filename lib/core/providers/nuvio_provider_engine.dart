import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'stremio_adapter.dart';

/// Nuvio Plugin provider engine (nuvioplugin.com).
/// Queries community Nuvio plugins in parallel for direct and embedded streams.
class NuvioProviderEngine {
  NuvioProviderEngine({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 8),
            ));

  final Dio _dio;

  /// Verified Nuvio plugin streams and scrapers
  static const List<Map<String, String>> nuvioPlugins = [
    {
      'id': 'nuvio_stream_core',
      'name': 'Nuvio Stream Core',
      'baseUrl': 'https://stream.nuvioplugin.com',
    },
    {
      'id': 'nuvio_cinemax',
      'name': 'Nuvio CineMax',
      'baseUrl': 'https://cinemax.nuvioplugin.com',
    },
    {
      'id': 'nuvio_flix',
      'name': 'Nuvio Flix Gateway',
      'baseUrl': 'https://flix.nuvioplugin.com',
    },
  ];

  /// Fetch streams from Nuvio plugins using IMDb ID and/or TMDB ID.
  Future<List<StreamResult>> fetchStreams({
    required bool isMovie,
    required String imdbId,
    required String tmdbId,
    int? season,
    int? episode,
  }) async {
    final queryId = imdbId.isNotEmpty ? imdbId : tmdbId;
    if (queryId.isEmpty) return [];

    final s = season ?? 1;
    final ep = episode ?? 1;
    final path = isMovie
        ? '/api/stream/movie/$queryId'
        : '/api/stream/series/$queryId/$s/$ep';

    final results = <StreamResult>[];
    await Future.wait(
      nuvioPlugins.map((plugin) async {
        try {
          final res = await _dio.get('${plugin['baseUrl']}$path');
          if (res.statusCode == 200 && res.data is Map) {
            final streams = res.data['streams'] as List?;
            if (streams != null) {
              for (final item in streams) {
                if (item is Map && item['url'] != null) {
                  final url = item['url'] as String;
                  final name = item['name'] as String? ?? plugin['name']!;
                  final quality = item['quality'] as String? ?? '1080p';
                  final lower = url.toLowerCase();
                  final isHls = lower.contains('.m3u8');
                  final isMp4 = lower.contains('.mp4');

                  results.add(StreamResult(
                    url: url,
                    name: '$name • $quality',
                    type: isHls
                        ? 'application/x-mpegURL'
                        : (isMp4 ? 'video/mp4' : 'text/html'),
                    behaviorHints: {
                      'isWebEmbed': !isHls && !isMp4,
                      'isDirectHttp': isHls || isMp4,
                      'title': 'Nuvio Stream ($quality)',
                      'quality': quality,
                      'category': 'nuvio',
                      'categoryLabel': 'Nuvio Plugins',
                      'provider': plugin['name']!,
                    },
                  ));
                }
              }
            }
          }
        } catch (e) {
          debugPrint('Nuvio plugin ${plugin['id']} error: $e');
        }
      }),
    );

    return results;
  }
}
