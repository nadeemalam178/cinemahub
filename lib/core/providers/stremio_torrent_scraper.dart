import 'dart:async';
import 'package:dio/dio.dart';
import '../streaming/diagnostics/streaming_logger.dart';
import '../streaming/models/stream_source.dart';
import 'stremio_adapter.dart';

/// Scrapes Stremio community torrent addons (Torrentio, MediaFusion, Comet, KnightCrawler)
/// with support for Real-Debrid API keys, custom addons, manifest validation,
/// and strict series (:season:episode) vs movie Stremio protocol routing.
class StremioTorrentScraper {
  StremioTorrentScraper({
    StremioAdapter? adapter,
    Dio? dio,
  }) : _adapter = adapter ?? StremioAdapter(dio: dio);

  final StremioAdapter _adapter;

  // In-memory cache for parsed addon manifests
  final Map<String, AddonManifest> _manifestCache = {};

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
  ///
  /// Conforms strictly to Stremio Addon Protocol specification:
  /// For movies: /stream/movie/{imdbId}.json
  /// For series: /stream/series/{imdbId}:{season}:{episode}.json
  Future<List<StreamResult>> fetchAllTorrentStreams({
    required String type, // 'movie' or 'series'
    required String imdbId,
    int? season,
    int? episode,
    String? realDebridKey,
    List<String>? customAddonUrls,
  }) async {
    // 1. Ensure clean IMDb ID (must match tt followed by digits)
    final imdbMatch = RegExp(r'tt\d+').firstMatch(imdbId);
    final cleanImdb = imdbMatch != null ? imdbMatch.group(0)! : '';

    if (cleanImdb.isEmpty) {
      StreamingLogger.instance.logStreamRequest(
        'StremioScraper',
        'invalid_id',
        statusCode: 400,
        streamCount: 0,
        error: 'No valid IMDb ID found in "$imdbId"',
      );
      return [];
    }

    // 2. Validate series vs movie routing constraints
    final isSeries = type == 'series';
    if (isSeries && (season == null || episode == null)) {
      StreamingLogger.instance.logStreamRequest(
        'StremioScraper',
        'series_missing_episode',
        statusCode: 400,
        streamCount: 0,
        error: 'Series request requires both season and episode numbers for $cleanImdb',
      );
      return [];
    }

    final streamId = isSeries ? '$cleanImdb:$season:$episode' : cleanImdb;
    final results = <StreamResult>[];
    final rdKey = (realDebridKey != null && realDebridKey.trim().isNotEmpty)
        ? realDebridKey.trim()
        : null;

    // 3. Build target addons list
    final targetAddons = <Map<String, dynamic>>[];

    for (final addon in communityAddons) {
      String base = addon['baseUrl']!;
      bool isDebridAddon = false;
      String displayName = addon['name']!;

      if (addon['id'] == 'torrentio' && rdKey != null) {
        base = 'https://torrentio.strem.fun/realdebrid=$rdKey';
        isDebridAddon = true;
        displayName = 'Torrentio (RD)';
      }

      targetAddons.add({
        'id': addon['id']!,
        'name': displayName,
        'baseUrl': base,
        'isDebrid': isDebridAddon,
      });
    }

    // Add user-configured custom addon URLs
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
            'isDebrid': false,
          });
        }
      }
    }

    // 4. Query target addons in parallel with manifest validation
    await Future.wait(
      targetAddons.map((addon) async {
        final base = addon['baseUrl'] as String;
        final addonName = addon['name'] as String;
        final addonId = addon['id'] as String;
        final isDebridTarget = addon['isDebrid'] == true;

        try {
          // Validate addon manifest if not already cached
          AddonManifest? manifest = _manifestCache[base];
          if (manifest == null) {
            manifest = await _adapter.fetchManifest(base);
            if (manifest != null) {
              _manifestCache[base] = manifest;
            }
          }

          // If manifest was successfully fetched, verify resource & type support
          if (manifest != null) {
            final supports = manifest.supportsStreamFor(type, id: streamId);
            if (!supports) {
              StreamingLogger.instance.logStreamRequest(
                addonName,
                '$base/stream/$type/$streamId.json',
                statusCode: 200,
                streamCount: 0,
                error: 'Addon does not support stream for type=$type, id=$streamId',
              );
              return;
            }
          }

          // Fetch streams via StremioAdapter
          final streams = await _adapter.fetchStreams(
            baseUrl: base,
            type: type,
            id: cleanImdb,
            season: season,
            episode: episode,
            addonName: addonName,
          );

          for (final stream in streams) {
            final directUrl = stream.url;
            final isDirectHttp = directUrl.startsWith('http://') || directUrl.startsWith('https://');
            final isDebrid = isDebridTarget ||
                (rdKey != null && isDirectHttp) ||
                directUrl.contains('real-debrid.com') ||
                stream.name.contains('[RD+]');

            final rawText = stream.description ?? stream.name;
            final quality = StreamSource.extractQuality(rawText);
            final seeders = StreamSource.extractSeeders(rawText);
            final language = StreamSource.extractLanguage(rawText);
            final sizeBytes = stream.size ?? StreamSource.extractSizeBytes(rawText);

            final hints = Map<String, dynamic>.from(stream.behaviorHints ?? const {});
            hints['addon'] = addonId;
            hints['provider'] = addonName;
            hints['isTorrent'] = !isDirectHttp;
            hints['isDirectHttp'] = isDirectHttp;
            hints['isDebrid'] = isDebrid;
            hints['isWebEmbed'] = false;
            hints['category'] = 'stremio';
            hints['categoryLabel'] = isDebrid ? 'Real-Debrid Direct' : 'Community Torrent';
            if (quality != null) hints['quality'] = quality;
            if (seeders != null) hints['seeders'] = seeders;
            if (language != null) hints['language'] = language;
            if (sizeBytes != null) hints['sizeBytes'] = sizeBytes;
            if (stream.hash != null) hints['infoHash'] = stream.hash;
            if (stream.fileIndex != null) hints['fileIndex'] = stream.fileIndex;

            // Build clean user-facing title
            final nameBuffer = StringBuffer();
            if (isDebrid) {
              nameBuffer.write('⚡ Real-Debrid');
            } else {
              nameBuffer.write(addonName);
            }
            if (quality != null) {
              nameBuffer.write(' • $quality');
            }

            results.add(StreamResult(
              name: nameBuffer.toString(),
              url: stream.url,
              type: isDirectHttp ? (stream.type.isNotEmpty ? stream.type : 'video/mp4') : 'application/x-bittorrent',
              hash: stream.hash,
              size: sizeBytes,
              fileIndex: stream.fileIndex,
              description: stream.description ?? stream.name,
              behaviorHints: hints,
              subtitles: stream.subtitles,
            ));
          }
        } catch (e) {
          StreamingLogger.instance.logStreamRequest(
            addonName,
            '$base/stream/$type/$streamId.json',
            statusCode: 0,
            streamCount: 0,
            error: e.toString(),
          );
        }
      }),
    );

    // 5. Deduplicate streams by infoHash + fileIndex or clean URL
    final deduplicated = <StreamResult>[];
    final seenKeys = <String>{};

    for (final stream in results) {
      final key = (stream.hash != null && stream.hash!.isNotEmpty)
          ? 'hash_${stream.hash}_${stream.fileIndex ?? 0}'
          : stream.url.trim();
      if (key.isNotEmpty && seenKeys.add(key)) {
        deduplicated.add(stream);
      }
    }

    // 6. Sort: Real-Debrid first, then highest genuine seeders, then Quality, then File Size
    deduplicated.sort((a, b) {
      final aDebrid = a.behaviorHints?['isDebrid'] == true ? 1 : 0;
      final bDebrid = b.behaviorHints?['isDebrid'] == true ? 1 : 0;
      if (aDebrid != bDebrid) return bDebrid.compareTo(aDebrid);

      final sA = a.behaviorHints?['seeders'] as int? ?? 0;
      final sB = b.behaviorHints?['seeders'] as int? ?? 0;
      if (sA != sB) return sB.compareTo(sA);

      final qA = _qualityWeight(a.behaviorHints?['quality'] as String?);
      final qB = _qualityWeight(b.behaviorHints?['quality'] as String?);
      if (qA != qB) return qB.compareTo(qA);

      final sizeA = a.size ?? 0;
      final sizeB = b.size ?? 0;
      return sizeB.compareTo(sizeA);
    });

    return deduplicated;
  }

  static int _qualityWeight(String? quality) {
    if (quality == null) return 0;
    if (quality.contains('4K')) return 4;
    if (quality.contains('1080p')) return 3;
    if (quality.contains('720p')) return 2;
    if (quality.contains('480p')) return 1;
    return 0;
  }
}
