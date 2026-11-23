import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../streaming/diagnostics/streaming_logger.dart';

/// Represents one stream returned by a Stremio-compatible provider.
class StreamResult {
  const StreamResult({
    required this.name,
    required this.url,
    required this.type,
    this.hash,
    this.size,
    this.fileIndex,
    this.description,
    this.behaviorHints,
    this.subtitles = const [],
  });

  /// Display name for this stream (e.g. "Torrentio\n1080p").
  final String name;

  /// Direct playable URL (http/https) or magnet URI.
  final String url;

  /// MIME hint such as "video/mp4" or "application/x-bittorrent".
  final String type;

  /// Hash used for P2P-based delivery (e.g. BitTorrent info hash).
  final String? hash;

  /// File size in bytes, if advertised.
  final int? size;

  /// Index of the target media file inside a multi-file torrent.
  final int? fileIndex;

  /// Detailed release title / description if separate from name.
  final String? description;

  final Map<String, dynamic>? behaviorHints;

  final List<Map<String, dynamic>> subtitles;

  bool get isVideo =>
      type.startsWith('video/') || type.contains('mp4') || type.contains('mkv');

  factory StreamResult.fromJson(Map<String, dynamic> json) {
    final rawUrl = json['url'] as String? ?? json['externalUrl'] as String? ?? '';
    final infoHash = json['infoHash'] as String? ?? json['hash'] as String?;
    final fileIdx = json['fileIdx'] as int? ?? json['fileIndex'] as int?;
    final rawTitle = json['title'] as String? ?? json['name'] as String? ?? '';
    final rawName = json['name'] as String? ?? '';

    String finalUrl = rawUrl;
    if (finalUrl.isEmpty && infoHash != null && infoHash.isNotEmpty) {
      // Build magnet URI with clean display name and trackers
      final cleanTitle = rawTitle.split('\n').first.replaceAll(RegExp(r'[^a-zA-Z0-9\.\-\_\s]'), '').trim();
      final buffer = StringBuffer('magnet:?xt=urn:btih:$infoHash');
      if (cleanTitle.isNotEmpty) {
        buffer.write('&dn=${Uri.encodeComponent(cleanTitle)}');
      }
      if (json['sources'] is List) {
        for (final src in (json['sources'] as List)) {
          final srcStr = src.toString();
          if (srcStr.startsWith('tracker:')) {
            buffer.write('&tr=${Uri.encodeComponent(srcStr.substring('tracker:'.length))}');
          }
        }
      }
      finalUrl = buffer.toString();
    }

    final hints = json['behaviorHints'] is Map
        ? Map<String, dynamic>.from(json['behaviorHints'] as Map)
        : <String, dynamic>{};
    if (fileIdx != null && !hints.containsKey('fileIndex')) {
      hints['fileIndex'] = fileIdx;
    }

    return StreamResult(
      name: rawName.isNotEmpty ? rawName : rawTitle,
      url: finalUrl,
      type: json['type'] as String? ?? (finalUrl.startsWith('magnet:?') ? 'application/x-bittorrent' : 'video/mp4'),
      hash: infoHash,
      size: json['size']?.toInt(),
      fileIndex: fileIdx,
      description: rawTitle.isNotEmpty ? rawTitle : null,
      behaviorHints: hints,
      subtitles: ((json['behaviorHints'] as Map?)?['defaultSubtitle'] as List<dynamic>?)
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

/// A parsed resource entry from an addon manifest.
/// Supports both simple string declarations ("stream") and resource objects:
///   {"name": "stream", "types": ["movie", "series"], "idPrefixes": ["tt", "kitsu"]}
class ManifestResource {
  const ManifestResource({
    required this.name,
    this.types = const [],
    this.idPrefixes = const [],
  });

  final String name;
  final List<String> types;
  final List<String> idPrefixes;

  factory ManifestResource.fromDynamic(dynamic raw) {
    if (raw is String) {
      return ManifestResource(name: raw);
    }
    if (raw is Map) {
      final name = raw['name'] as String? ?? '';

      final rawTypes = raw['types'];
      List<String> types = const [];
      if (rawTypes is List) {
        types = rawTypes.map((t) => t.toString()).toList();
      } else if (rawTypes is String) {
        types = rawTypes.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
      }

      final rawPrefixes = raw['idPrefixes'];
      List<String> prefixes = const [];
      if (rawPrefixes is List) {
        prefixes = rawPrefixes.map((p) => p.toString()).toList();
      } else if (rawPrefixes is String) {
        prefixes = rawPrefixes.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
      }

      return ManifestResource(
        name: name,
        types: types,
        idPrefixes: prefixes,
      );
    }
    return ManifestResource(name: raw.toString());
  }
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
    this.logo,
    this.background,
    this.idPrefixes = const [],
    this.parsedResources = const [],
  });

  final String id;
  final String version;
  final String name;
  final String description;
  final List<String> resources;
  final List<String> types;
  final List<Map<String, dynamic>> catalogs;
  final Map<String, dynamic>? behaviorHints;
  final String? logo;
  final String? background;
  final List<String> idPrefixes;
  final List<ManifestResource> parsedResources;

  /// Whether the addon declares support for the given resource (e.g. 'stream', 'catalog', 'meta').
  bool supportsResource(String resourceName) {
    if (resources.contains(resourceName)) return true;
    return parsedResources.any((r) => r.name == resourceName);
  }

  /// Whether the addon advertises support for content type (e.g. 'movie', 'series').
  bool supportsType(String type) {
    if (types.contains(type)) return true;
    for (final r in parsedResources) {
      if (r.types.contains(type)) return true;
    }
    return false;
  }

  /// Verifies whether the addon explicitly supports stream resolution for the given content type and ID.
  bool supportsStreamFor(String type, {String? id}) {
    final streamRes = parsedResources.where((r) => r.name == 'stream').toList();
    if (streamRes.isNotEmpty) {
      final res = streamRes.first;
      if (res.types.isNotEmpty && !res.types.contains(type)) {
        return false;
      }
      if (id != null && res.idPrefixes.isNotEmpty) {
        final matchesPrefix = res.idPrefixes.any((prefix) => id.startsWith(prefix));
        if (!matchesPrefix) return false;
      }
      return true;
    }
    // Fallback to top-level manifest flags
    if (!supportsResource('stream')) return false;
    if (types.isNotEmpty && !types.contains(type)) return false;
    if (id != null && idPrefixes.isNotEmpty) {
      return idPrefixes.any((prefix) => id.startsWith(prefix));
    }
    return true;
  }

  factory AddonManifest.fromJson(Map<String, dynamic> json) {
    final rawResources = (json['resources'] as List<dynamic>?) ?? [];
    final parsed = rawResources.map(ManifestResource.fromDynamic).toList();
    final stringResources = parsed.map((r) => r.name).toList();

    final rawTypes = json['types'];
    List<String> types = [];
    if (rawTypes is List) {
      types = rawTypes.map((t) => t.toString()).toList();
    } else if (rawTypes is String) {
      types = rawTypes.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    }

    final rawPrefixes = json['idPrefixes'];
    List<String> prefixes = [];
    if (rawPrefixes is List) {
      prefixes = rawPrefixes.map((p) => p.toString()).toList();
    } else if (rawPrefixes is String) {
      prefixes = rawPrefixes.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    }

    return AddonManifest(
      id: json['id'] as String? ?? '',
      version: json['version'] as String? ?? '0.0.0',
      name: json['name'] as String? ?? 'Unknown Addon',
      description: json['description'] as String? ?? '',
      resources: stringResources,
      types: types,
      catalogs: (json['catalogs'] as List?)?.cast<Map<String, dynamic>>() ?? const [],
      behaviorHints: json['behaviorHints'] is Map
          ? Map<String, dynamic>.from(json['behaviorHints'] as Map)
          : null,
      logo: json['logo'] as String?,
      background: json['background'] as String?,
      idPrefixes: prefixes,
      parsedResources: parsed,
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
    'logo': logo,
    'background': background,
  };
}

/// Parses addon responses conforming to the Stremio add-on protocol.
class StremioAdapter {
  StremioAdapter({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 12),
              followRedirects: true,
              maxRedirects: 5,
            ));

  final Dio _dio;

  /// Fetch and parse the provider manifest. Returns null on error.
  Future<AddonManifest?> fetchManifest(String baseUrl) async {
    final cleanBase = baseUrl.endsWith('/manifest.json')
        ? baseUrl.substring(0, baseUrl.length - '/manifest.json'.length)
        : (baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl);

    final url = '$cleanBase/manifest.json';
    try {
      final resp = await _dio.get(
        url,
        options: Options(
          responseType: ResponseType.json,
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (resp.statusCode != 200 || resp.data is! Map) {
        StreamingLogger.instance.logManifestResult(
          cleanBase,
          url,
          success: false,
          statusCode: resp.statusCode,
          error: 'Invalid response status or non-JSON data',
        );
        return null;
      }

      final manifest = AddonManifest.fromJson(resp.data as Map<String, dynamic>);
      StreamingLogger.instance.logManifestResult(
        manifest.name,
        url,
        success: true,
        statusCode: resp.statusCode,
      );
      return manifest;
    } catch (e) {
      StreamingLogger.instance.logManifestResult(
        cleanBase,
        url,
        success: false,
        error: e.toString(),
      );
      return null;
    }
  }

  /// Request available streams for a piece of content.
  ///
  /// Conforms to Stremio Addon Protocol specification:
  /// For movies: /stream/{type}/{id}.json
  /// For series: /stream/{type}/{id}:{season}:{episode}.json
  Future<List<StreamResult>> fetchStreams({
    required String baseUrl,
    required String type,
    required String id,
    int? season,
    int? episode,
    String? addonName,
  }) async {
    final cleanBase = baseUrl.endsWith('/manifest.json')
        ? baseUrl.substring(0, baseUrl.length - '/manifest.json'.length)
        : (baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl);

    final name = addonName ?? cleanBase;
    final streamId = (type == 'series' && season != null && episode != null)
        ? '$id:$season:$episode'
        : id;
    final url = '$cleanBase/stream/$type/$streamId.json';

    try {
      final resp = await _dio.get(
        url,
        options: Options(
          responseType: ResponseType.json,
          sendTimeout: const Duration(seconds: 6),
          receiveTimeout: const Duration(seconds: 8),
          validateStatus: (status) => status != null && status < 600,
        ),
      );

      final status = resp.statusCode ?? 0;

      if (status != 200) {
        String errDetail = 'HTTP status $status';
        if (status == 429) {
          errDetail = 'Rate Limited (HTTP 429)';
        } else if (status == 403) {
          errDetail = 'Access Forbidden / Blocked (HTTP 403)';
        } else if (status == 404) {
          errDetail = 'Resource Not Found (HTTP 404)';
        } else if (status >= 500) {
          errDetail = 'Server Error (HTTP $status)';
        }

        StreamingLogger.instance.logStreamRequest(
          name,
          url,
          statusCode: status,
          streamCount: 0,
          error: errDetail,
        );
        return [];
      }

      if (resp.data is! Map) {
        StreamingLogger.instance.logStreamRequest(
          name,
          url,
          statusCode: status,
          streamCount: 0,
          error: 'Response body is not a JSON object',
        );
        return [];
      }

      final data = resp.data as Map<String, dynamic>;
      final streams = data['streams'];
      if (streams == null || streams is! List) {
        StreamingLogger.instance.logStreamRequest(
          name,
          url,
          statusCode: status,
          streamCount: 0,
        );
        return [];
      }

      final results = streams
          .whereType<Map<String, dynamic>>()
          .map((raw) {
            final res = StreamResult.fromJson(raw);
            final hints = Map<String, dynamic>.from(res.behaviorHints ?? const {});
            hints.putIfAbsent('addon', () => name);
            hints.putIfAbsent('provider', () => name);
            hints.putIfAbsent('category', () => 'stremio');
            return StreamResult(
              name: res.name.isNotEmpty ? res.name : name,
              url: res.url,
              type: res.type,
              hash: res.hash,
              size: res.size,
              fileIndex: res.fileIndex,
              description: res.description,
              behaviorHints: hints,
              subtitles: res.subtitles,
            );
          })
          .toList();

      StreamingLogger.instance.logStreamRequest(
        name,
        url,
        statusCode: status,
        streamCount: results.length,
      );

      return results;
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      final errMsg = e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.receiveTimeout
          ? 'Network Timeout (${e.type.name})'
          : e.message ?? e.toString();

      StreamingLogger.instance.logStreamRequest(
        name,
        url,
        statusCode: status,
        streamCount: 0,
        error: errMsg,
      );
      return [];
    } catch (e) {
      StreamingLogger.instance.logStreamRequest(
        name,
        url,
        statusCode: 0,
        streamCount: 0,
        error: e.toString(),
      );
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
      final cleanBase = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      final resp = await _dio.get('$cleanBase/meta/$type/$id.json');
      if (resp.statusCode != 200 || resp.data is! Map) return null;
      return resp.data['meta'] as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('StremioAdapter: meta fetch failed: $e');
      return null;
    }
  }
}
