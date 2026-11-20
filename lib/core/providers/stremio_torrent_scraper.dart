import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'stremio_adapter.dart';

/// Scrapes Stremio community torrent addons (Torrentio, MediaFusion, Comet, KnightCrawler)
/// and extracts direct stream information and torrent hashes with seeder/quality ranking.
class StremioTorrentScraper {
  StremioTorrentScraper({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 12),
            ));

  final Dio _dio;

  /// Verified public Stremio torrent addons
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
    // Ensure clean IMDb ID (must start with 'tt')
    final cleanImdb = imdbId.contains('tt')
        ? 'tt${imdbId.split('tt').last.split(RegExp(r'[^0-9]')).first}'
        : '';

    if (cleanImdb.isEmpty) {
      debugPrint('StremioTorrentScraper: No valid IMDb ID found in "$imdbId"');
      return [];
    }

    final streamId = season != null && episode != null
        ? '$cleanImdb:$season:$episode'
        : cleanImdb;

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
                  final title =
                      raw['title'] as String? ?? raw['name'] as String? ?? '';
                  final infoHash = raw['infoHash'] as String?;
                  final directUrl = raw['url'] as String?;

                  // Determine stream target (direct HTTP or streaming gateway)
                  String streamUrl = '';
                  String magnetUri = '';

                  if (directUrl != null && directUrl.isNotEmpty) {
                    streamUrl = directUrl;
                  } else if (infoHash != null && infoHash.isNotEmpty) {
                    magnetUri =
                        'magnet:?xt=urn:btih:$infoHash&dn=${Uri.encodeComponent(title)}';
                    // Webtor / Seedr / WebTorrent in-app streaming gateway
                    streamUrl =
                        'https://webtor.io/show?magnet=${Uri.encodeComponent(magnetUri)}';
                  }

                  if (streamUrl.isNotEmpty) {
                    final quality = _extractQuality(title);
                    final seeders = _extractSeeders(title);

                    final isWebEmbed = streamUrl.contains('webtor.io');

                    results.add(StreamResult(
                      url: streamUrl,
                      name: '${addon['name']} • $quality',
                      type: isWebEmbed ? 'text/html' : 'video/mp4',
                      behaviorHints: {
                        'title': '$title\n⚡ Seeders: $seeders',
                        'isTorrent': true,
                        'isWebEmbed': isWebEmbed,
                        'infoHash': infoHash,
                        'magnetUri': magnetUri,
                        'seeders': seeders,
                        'quality': quality,
                        'addon': addon['id'],
                        'category': 'stremio',
                        'categoryLabel': 'Stremio Addons',
                        'provider': addon['name'],
                      },
                    ));
                  }
                }
              }
            }
          }
        } catch (e) {
          debugPrint('Scraping ${addon['name']} failed: $e');
        }
      }),
    );

    // Sort by seeders descending
    results.sort((a, b) {
      final sA = a.behaviorHints?['seeders'] as int? ?? 0;
      final sB = b.behaviorHints?['seeders'] as int? ?? 0;
      return sB.compareTo(sA);
    });

    return results;
  }

  String _extractQuality(String text) {
    if (text.contains('4K') || text.contains('2160p')) return '4K UHD';
    if (text.contains('1080p')) return '1080p FHD';
    if (text.contains('720p')) return '720p HD';
    if (text.contains('HDR')) return 'HDR';
    return 'HD';
  }

  int _extractSeeders(String text) {
    final match = RegExp(r'👤\s*(\d+)|👥\s*(\d+)|⚡\s*(\d+)|[sS]eeders?:\s*(\d+)')
        .firstMatch(text);
    if (match != null) {
      for (int i = 1; i <= match.groupCount; i++) {
        final val = match.group(i);
        if (val != null) return int.tryParse(val) ?? 0;
      }
    }
    return 10;
  }
}
