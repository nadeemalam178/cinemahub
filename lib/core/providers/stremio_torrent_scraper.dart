import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'stremio_adapter.dart';

/// Scrapes Stremio community torrent addons (Torrentio, MediaFusion, Comet, KnightCrawler)
/// and extracts direct stream information and torrent hashes with seeder/quality ranking.
class StremioTorrentScraper {
  StremioTorrentScraper({Dio? dio}) : _dio = dio ?? Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 10),
  ));

  final Dio _dio;

  /// Verified public Stremio & Nuvioplugin torrent manifests
  static const List<Map<String, String>> communityAddons = [
    {
      'id': 'torrentio',
      'name': 'Torrentio',
      'baseUrl': 'https://torrentio.strem.fun',
    },
    {
      'id': 'mediafusion',
      'name': 'MediaFusion',
      'baseUrl': 'https://mediafusion.elfhosted.com',
    },
    {
      'id': 'comet',
      'name': 'Comet',
      'baseUrl': 'https://comet.elfhosted.com',
    },
    {
      'id': 'knightcrawler',
      'name': 'KnightCrawler',
      'baseUrl': 'https://knightcrawler.elfhosted.com',
    },
  ];

  /// Fetch torrent streams for movie or TV show across community addons.
  Future<List<StreamResult>> fetchAllTorrentStreams({
    required String type, // 'movie' or 'series'
    required String imdbId,
    int? season,
    int? episode,
  }) async {
    final streamId = season != null && episode != null
        ? '$imdbId:$season:$episode'
        : imdbId;

    final results = <StreamResult>[];

    await Future.wait(
      communityAddons.map((addon) async {
        try {
          final url = '${addon['baseUrl']}/stream/$type/$streamId.json';
          final response = await _dio.get(url);

          if (response.statusCode == 200 && response.data is Map) {
            final streams = response.data['streams'] as List?;
            if (streams != null) {
              for (final raw in streams) {
                if (raw is Map) {
                  final title = raw['title'] as String? ?? raw['name'] as String? ?? '';
                  final infoHash = raw['infoHash'] as String?;
                  final fileIdx = raw['fileIdx'];
                  final directUrl = raw['url'] as String?;

                  // Determine stream target (direct HTTP or P2P WebTorrent bridge)
                  String streamUrl = '';
                  if (directUrl != null && directUrl.isNotEmpty) {
                    streamUrl = directUrl;
                  } else if (infoHash != null && infoHash.isNotEmpty) {
                    // Route via standard P2P WebTorrent / Torrent-to-HTTP bridge endpoint
                    final idxParam = fileIdx != null ? '&idx=$fileIdx' : '';
                    streamUrl = 'https://torrent-stream.online/stream?ih=$infoHash$idxParam';
                  }

                  if (streamUrl.isNotEmpty) {
                    final quality = _extractQuality(title);
                    final seeders = _extractSeeders(title);

                    results.add(StreamResult(
                      url: streamUrl,
                      name: '${addon['name']} • $quality',
                      type: 'application/x-bittorrent',
                      behaviorHints: {
                        'title': '$title\n⚡ Seeders: $seeders',
                        'isTorrent': true,
                        'infoHash': infoHash,
                        'seeders': seeders,
                        'quality': quality,
                        'addon': addon['id'],
                      },
                    ));
                  }
                }
              }
            }
          }
        } catch (e) {
          debugPrint('Error scraping Stremio addon ${addon['id']}: $e');
        }
      }),
    );

    // Rank streams: 4K first, then 1080p, then highest seeders
    results.sort((a, b) {
      final seedersA = a.behaviorHints?['seeders'] as int? ?? 0;
      final seedersB = b.behaviorHints?['seeders'] as int? ?? 0;
      final qualityScoreA = _qualityScore(a.name);
      final qualityScoreB = _qualityScore(b.name);

      if (qualityScoreA != qualityScoreB) {
        return qualityScoreB.compareTo(qualityScoreA);
      }
      return seedersB.compareTo(seedersA);
    });

    return results;
  }

  static String _extractQuality(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('4k') || lower.contains('2160p')) return '4K UHD';
    if (lower.contains('1080p')) return '1080p Full HD';
    if (lower.contains('720p')) return '720p HD';
    return 'HD';
  }

  static int _qualityScore(String name) {
    if (name.contains('4K')) return 4;
    if (name.contains('1080p')) return 3;
    if (name.contains('720p')) return 2;
    return 1;
  }

  static int _extractSeeders(String text) {
    final match = RegExp(r'(?:👤|⚡|seeders?:?\s*)(\d+)', caseSensitive: false).firstMatch(text);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '0') ?? 0;
    }
    return 0;
  }
}
