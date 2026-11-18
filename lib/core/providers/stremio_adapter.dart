import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Represents one stream returned by a Stremio-compatible provider.
class StreamResult {
  const StreamResult({
    required this.name,
    required this.url,
    required this.type,
    this.hash,
    this.size,
    this.behaviorHints,
    this.subtitles = const [],
  });

  /// Display name for this stream.
  final String name;

  /// Direct playable URL (http/https) or magnet URI.
  final String url;

  /// MIME hint such as "video/mp4" or "text/vtt".
  final String type;

  /// Hash used for P2P-based delivery (e.g. BitTorrent info hash).
  final String? hash;

  /// File size in bytes, if advertised.
  final int? size;

  final Map<String, dynamic>? behaviorHints;

  final List<Map<String, dynamic>> subtitles;

  bool get isVideo =>
      type.startsWith('video/') || type.contains('mp4') || type.contains('mkv');

  factory StreamResult.fromJson(Map<String, dynamic> json) {
    return StreamResult(
      name: json['name'] as String? ?? '',
      url: json['url'] as String? ?? '',
      type: json['type'] as String? ?? 'application/octet-stream',
      hash: json['hash'] as String?,
      size: json['size']?.toInt(),
      behaviorHints:
          (json['behaviorHints'] as Map?)?.cast<String, dynamic>(),
      subtitles:
          ((json['behaviorHints'] as Map?)?['defaultSubtitle']
                  as List<dynamic>?)
              ?.map((s) => s as Map<String, dynamic>)
              .toList() ??
          const [],
    );
  }
}

/// Subtitle track associated with a playback session.
class SubtitleTrack {
  const SubtitleTrack({required this.lang, required this.url});

  final String lang;
  final String url;
}

/// A Stremio-compatible add-on manifest, parsed from a JSON response.
class AddonManifest {
  const AddonManifest({
    required this.id,
    required this.version,
    required this.name,
    required this.description,
    required this.resources,
    required this.types,
    this.catalogs = const [],
    this.behaviorHints,
  });

  final String id;
  final String version;
  final String name;
  final String description;
  final List<String> resources;
  final List<String> types;
  final List<Map<String, dynamic>> catalogs;
  final Map<String, dynamic>? behaviorHints;

  factory AddonManifest.fromJson(Map<String, dynamic> json) {
    return AddonManifest(
      id: json['id'] as String? ?? '',
      version: json['version'] as String? ?? '0.0.0',
      name: json['name'] as String? ?? 'Unknown',
      description: json['description'] as String? ?? '',
      resources:
          ((json['resources'] as List<dynamic>?) ?? [])
              .map((r) => r.toString())
              .toList(),
      types:
          ((json['types'] as List<dynamic>?) ?? [])
              .map((t) => t.toString())
              .toList(),
      catalogs:
          (json['catalogs'] as List?)?.cast<Map<String, dynamic>>() ??
              const [],
      behaviorHints:
          (json['behaviorHints'] as Map?)?.cast<String, dynamic>(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'id': id,
    'version': version,
    'name': name,
    'description': description,
    'resources': resources,
    'types': types,
    'catalogs': catalogs,
    'behaviorHints': behaviorHints,
  };
}

/// Parses addon responses conforming to the Stremio add-on protocol.
///
/// The server returns an envelope:
///   {"meta": {...}, "streams": [...]}  for /stream/type/id/id.json
///   {"meta": {...}}                   for /meta/type/id/id.json
///   {"catalogs": [...]}               for /catalog/type/id.json
///
/// All HTTP calls are made to the base URL registered in [ProviderModel].
/// CORS headers must be configured on the provider side; if not, requests
/// will fail and the registry marks the provider [HealthStatus.down].
class StremioAdapter {
  StremioAdapter({required Dio dio}) : _dio = dio;

  final Dio _dio;

  /// Fetch and cache the provider manifest. Returns null on error.
  Future<AddonManifest?> fetchManifest(String baseUrl) async {
    try {
      final uri = Uri.parse(baseUrl);
      final manifestUrl =
          uri.scheme == ''
              ? baseUrl
              : '${uri.hasAbsolutePath ? '' : ''}$baseUrl/manifest.json';

      final resp = await _dio.get('$baseUrl/manifest.json');
      if (resp.statusCode != 200) return null;
      return AddonManifest.fromJson(resp.data as Map<String, dynamic>);
    } catch (e) {
      debugPrint('StremioAdapter: manifest fetch failed: $e');
      return null;
    }
  }

  /// Request available streams for a piece of content.
  ///
  /// Example payload keys: `type`, `id`, `season`, `episode`.
  Future<List<StreamResult>> fetchStreams({
    required String baseUrl,
    required String type,
    required String id,
    int? season,
    int? episode,
  }) async {
    try {
      final uriBuilder = StringBuffer('$baseUrl/stream/$type/$id.json');
      if (season != null) uriBuilder.write('?season=$season');
      if (episode != null) uriBuilder.write('&episode=$episode');

      final resp = await _dio.get(uriBuilder.toString());
      if (resp.statusCode != 200) return [];

      final data = resp.data as Map<String, dynamic>;
      final streams = data['streams'];
      if (streams == null || streams is! List) return [];

      return streams
          .whereType<Map<String, dynamic>>()
          .map(StreamResult.fromJson)
          .toList();
    } catch (e) {
      debugPrint('StremioAdapter: stream fetch failed: $e');
      return [];
    }
  }

  /// Request metadata (synopsis, cast, genres, poster images).
  Future<Map<String, dynamic>?> fetchMeta({
    required String baseUrl,
    required String type,
    required String id,
  }) async {
    try {
      final resp = await _dio.get('$baseUrl/meta/$type/$id.json');
      if (resp.statusCode != 200) return null;
      return resp.data['meta'] as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('StremioAdapter: meta fetch failed: $e');
      return null;
    }
  }
}
