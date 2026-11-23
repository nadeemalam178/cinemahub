import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Stremio public addon catalog service.
///
/// Fetches catalog rows from well-known public Stremio addons:
///  - Cinemeta  (official metadata + catalog)
///  - Kitsu     (anime)
///  - Community catalogs
///
/// Each addon exposes:
///   GET /{addonBase}/catalog/{type}/{catalogId}.json
///
/// The returned `metas` array has: id (imdb tt-id), type, name, poster,
/// background, description, releaseInfo, genres, imdbRating.
class StremioAddonCatalog {
  StremioAddonCatalog({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 12),
            ));

  final Dio _dio;

  // ---------------------------------------------------------------------------
  // Known public addons
  // ---------------------------------------------------------------------------

  static const String _cinemeta = 'https://v3-cinemeta.strem.io';

  // ---------------------------------------------------------------------------
  // Catalog definitions
  // Key → {base, type, catalogId, label}
  // ---------------------------------------------------------------------------

  static const List<Map<String, String>> _catalogs = [
    // --- Cinemeta movies ---
    {
      'base': _cinemeta,
      'type': 'movie',
      'id': 'top',
      'label': '🎬 Top Global Movies',
      'source': 'Cinemeta',
    },
    {
      'base': _cinemeta,
      'type': 'movie',
      'id': 'featured',
      'label': '⭐ Featured Movies',
      'source': 'Cinemeta',
    },
    // --- Cinemeta series ---
    {
      'base': _cinemeta,
      'type': 'series',
      'id': 'top',
      'label': '📺 Trending Global Series',
      'source': 'Cinemeta',
    },
    {
      'base': _cinemeta,
      'type': 'series',
      'id': 'featured',
      'label': '🌟 Featured Series',
      'source': 'Cinemeta',
    },
    // --- Kitsu anime (Disabled due to dead domain) ---
    // --- Community / RPDB (Disabled due to 404 domain) ---
  ];

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Fetch a single catalog row from a Stremio addon.
  /// Returns normalized content items or empty list on failure.
  Future<StremioShelf> fetchCatalog({
    required String base,
    required String type,
    required String catalogId,
    required String label,
    required String source,
    int skip = 0,
  }) async {
    final url = '$base/catalog/$type/$catalogId.json'
        '${skip > 0 ? '?skip=$skip' : ''}';
    try {
      final response = await _dio.get(url);
      final metas = (response.data['metas'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final items = metas.map(_normalizeMeta).toList();
      return StremioShelf(label: label, source: source, items: items);
    } catch (e) {
      debugPrint('Stremio catalog [$source/$catalogId] failed: $e');
      return StremioShelf(label: label, source: source, items: []);
    }
  }

  /// Fetch all configured catalog shelves in parallel.
  Future<List<StremioShelf>> fetchAllShelves() async {
    final futures = _catalogs.map((c) => fetchCatalog(
          base: c['base']!,
          type: c['type']!,
          catalogId: c['id']!,
          label: c['label']!,
          source: c['source']!,
        ));
    final shelves = await Future.wait(futures);
    // Drop empty shelves so the UI stays clean
    return shelves.where((s) => s.items.isNotEmpty).toList();
  }

  /// Fetch manifest from a Stremio addon URL and return its catalog list.
  /// Useful for user-added addons.
  Future<List<Map<String, dynamic>>> fetchManifestCatalogs(String base) async {
    try {
      final response = await _dio.get('$base/manifest.json');
      final catalogs = (response.data['catalogs'] as List?)
              ?.cast<Map<String, dynamic>>() ??
          [];
      return catalogs;
    } catch (e) {
      debugPrint('Stremio manifest [$base] failed: $e');
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Normalize a Stremio meta preview → CinemaHub content map
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _normalizeMeta(Map<String, dynamic> meta) {
    final id = meta['id'] as String? ?? '';
    final type = meta['type'] as String? ?? 'movie';
    final name = meta['name'] as String? ?? 'Unknown';
    final poster = meta['poster'] as String?;
    final background = meta['background'] as String?;
    final description = meta['description'] as String? ?? '';
    final releaseInfo = meta['releaseInfo'] as String? ?? '';
    final imdbRating = meta['imdbRating'];
    final genres = (meta['genres'] as List?)?.cast<String>() ?? [];

    double rating = 0.0;
    if (imdbRating != null) {
      rating = double.tryParse(imdbRating.toString()) ?? 0.0;
    }

    // Build a stable internal ID: prefer imdb id, else stremio id
    final internalId = id.startsWith('tt') ? 'stremio:imdb:$id' : 'stremio:$type:$id';

    return {
      'id': internalId,
      'stremioId': id, // raw stremio id (may be imdb tt-id or kitsu:xxx)
      'type': _mapType(type),
      'title': name,
      'posterUrl': poster,
      'backdropUrl': background,
      'overview': description,
      'releaseDate': releaseInfo,
      'rating': rating,
      'genres': genres,
      'source': 'stremio',
      // Keep raw meta for the detail screen to use
      'stremioMeta': meta,
    };
  }

  String _mapType(String stremioType) {
    switch (stremioType) {
      case 'movie':
        return 'movie';
      case 'series':
        return 'series';
      case 'anime':
        return 'series'; // treat anime as series in our UI
      default:
        return 'movie';
    }
  }
}

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

class StremioShelf {
  const StremioShelf({
    required this.label,
    required this.source,
    required this.items,
  });

  final String label;
  final String source;
  final List<Map<String, dynamic>> items;

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;
}
