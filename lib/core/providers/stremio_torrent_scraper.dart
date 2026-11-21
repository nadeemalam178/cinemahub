import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'stremio_adapter.dart';

/// Scrapes Stremio community torrent addons (Torrentio, MediaFusion, Comet, KnightCrawler)
/// with support for Real-Debrid API keys, custom addons, and season:episode TV series formatting.
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
      'id': 'knightcrawler',
      'name': 'KnightCrawler',
      'baseUrl': 'https://knightcrawler.elfhosted.com',
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
  ];

  /// Fetch torrent streams for movie or TV show across community addons.
  Future<List<StreamResult>> fetchAllTorrentStreams({
    required String type, // 'movie' or 'series'
    required String imdbId,
    int? season,
    int? episode,
    String? realDebridKey,
    List<String>? customAddonUrls,
  }) async {
    // Ensure clean IMDb ID (must start with 'tt')
    final cleanImdb = imdbId.contains('tt')
        ? 'tt${imdbId.split('tt').last.split(RegExp(r'[^0-9]')).first}'
        : '';

    if (cleanImdb.isEmpty) {
      debugPrint('StremioTorrentScraper: No valid IMDb ID found in "$imdbId"');
      return [];
    }

    // Torrentio and Stremio protocol require :season:episode for TV series
    final isSeries = type == 'series';
    final s = season ?? 1;
    final ep = episode ?? 1;
    final streamId = isSeries ? '$cleanImdb:$s:$ep' : cleanImdb;

    final results = <StreamResult>[];
    final rdKey = (realDebridKey != null && realDebridKey.trim().isNotEmpty)
        ? realDebridKey.trim()
        : null;

    // Build list of target addons to query
    final targetAddons = <Map<String, String>>[];

    for (final addon in communityAddons) {
      String base = addon['baseUrl']!;
      // If Torrentio and Real-Debrid configured, inject RD token
      if (addon['id'] == 'torrentio' && rdKey != null) {
        base = 'https://torrentio.strem.fun/realdebrid=$rdKey';
      }
      targetAddons.add({
        'id': addon['id']!,
        'name': addon['name']!,
        'baseUrl': base,
      });
    }

    // Add any user-configured custom addon URLs
    if (customAddonUrls != null) {
      for (int i = 0; i < customAddonUrls.length; i++) {
        final url = customAddonUrls[i].trim();
        if (url.isNotEmpty) {
          final cleanBase = url.endsWith('/manifest.json')
              ? url.substring(0, url.length - '/manifest.json'.length)
              : (url.endsWith('/') ? url.substring(0, url.length - 1) : url);
          targetAddons.add({
            'id': 'custom_$i',
            'name': 'Custom Addon ${i + 1}',
            'baseUrl': cleanBase,
          });
        }
      }
    }

    await Future.wait(
      targetAddons.map((addon) async {
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

                  String streamUrl = '';
                  String magnetUri = '';
                  bool isDirectHttp = false;

                  if (directUrl != null && directUrl.isNotEmpty) {
                    streamUrl = directUrl;
                    isDirectHttp = directUrl.startsWith('http://') || directUrl.startsWith('https://');
                  } else if (infoHash != null && infoHash.isNotEmpty) {
                    magnetUri =
                        'magnet:?xt=urn:btih:$infoHash&dn=${Uri.encodeComponent(title)}';
                    streamUrl = magnetUri;
                  }

                  if (streamUrl.isNotEmpty) {
                    final quality = _extractQuality(title);
                    final seeders = _extractSeeders(title);
                    final isDebrid = rdKey != null && isDirectHttp;

                    results.add(StreamResult(
                      url: streamUrl,
                      name: isDebrid
                          ? '⚡ Real-Debrid • $quality'
                          : '${addon['name']} • $quality',
                      type: isDirectHttp ? 'video/mp4' : 'application/x-bittorrent',
                      behaviorHints: {
                        'title': '$title\n⚡ Seeders: $seeders',
                        'isTorrent': !isDirectHttp,
                        'isDirectHttp': isDirectHttp,
                        'isDebrid': isDebrid,
                        'isWebEmbed': false,
                        'infoHash': infoHash,
                        'magnetUri': magnetUri,
                        'seeders': seeders,
                        'quality': quality,
                        'addon': addon['id'],
                        'category': 'stremio',
                        'categoryLabel': isDebrid ? 'Real-Debrid Direct' : 'Community Torrent',
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

    // Sort: Debrid first, then highest seeders
    results.sort((a, b) {
      final aDebrid = a.behaviorHints?['isDebrid'] == true ? 1 : 0;
      final bDebrid = b.behaviorHints?['isDebrid'] == true ? 1 : 0;
      if (aDebrid != bDebrid) return bDebrid.compareTo(aDebrid);

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
