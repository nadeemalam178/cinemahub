import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'tmdb_service.dart';

/// Resolved content identifiers ensuring compatibility across all provider engines.
class ResolvedIds {
  const ResolvedIds({
    required this.tmdbId,
    required this.imdbId,
    required this.rawId,
    this.title = '',
  });

  /// Bare numeric TMDB ID (e.g. "550")
  final String tmdbId;

  /// Full IMDb ID (e.g. "tt0137523")
  final String imdbId;

  /// Original raw ID passed in
  final String rawId;

  /// Resolved title if available
  final String title;

  bool get hasTmdb => tmdbId.isNotEmpty;
  bool get hasImdb => imdbId.isNotEmpty && imdbId.startsWith('tt');

  @override
  String toString() =>
      'ResolvedIds(tmdb: $tmdbId, imdb: $imdbId, raw: $rawId, title: $title)';
}

/// Bi-directional ID resolver between TMDB and IMDb formats.
/// Ensures FMHY, Stremio, Nuvio, and CloudStream engines all receive
/// valid, properly-formatted IDs.
class IdResolver {
  IdResolver({
    this.tmdb,
    Dio? dio,
  })  : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
            ));

  final TmdbService? tmdb;
  final Dio _dio;

  // In-memory cache for ID pairs
  final Map<String, ResolvedIds> _cache = {};

  /// Synchronously extract whatever IDs can be parsed directly from the ID string.
  ResolvedIds parseImmediate(String rawId, {String? metaImdbId, int? metaTmdbId, String? title}) {
    String cleanTmdb = '';
    String cleanImdb = '';

    // If explicit meta provided
    if (metaTmdbId != null && metaTmdbId > 0) {
      cleanTmdb = metaTmdbId.toString();
    }
    if (metaImdbId != null && metaImdbId.startsWith('tt')) {
      cleanImdb = metaImdbId;
    }

    // Inspect rawId structure
    // Patterns:
    // tmdb:movie:550
    // tmdb:series:1399
    // stremio:imdb:tt0137523
    // tt0137523
    // 550
    final parts = rawId.split(':');
    final lastPart = parts.last;

    if (lastPart.startsWith('tt')) {
      cleanImdb = lastPart;
    } else if (int.tryParse(lastPart) != null) {
      cleanTmdb = lastPart;
    }

    for (final part in parts) {
      if (part.startsWith('tt') && cleanImdb.isEmpty) {
        cleanImdb = part;
      }
    }

    return ResolvedIds(
      tmdbId: cleanTmdb,
      imdbId: cleanImdb,
      rawId: rawId,
      title: title ?? '',
    );
  }

  /// Asynchronously resolve both TMDB and IMDb IDs using TMDB or Cinemeta.
  Future<ResolvedIds> resolve({
    required String rawId,
    required bool isMovie,
    String? metaImdbId,
    int? metaTmdbId,
    String? title,
  }) async {
    final cacheKey = '$rawId:$isMovie';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    var current = parseImmediate(
      rawId,
      metaImdbId: metaImdbId,
      metaTmdbId: metaTmdbId,
      title: title,
    );

    // Case 1: Both IDs already known
    if (current.hasTmdb && current.hasImdb) {
      _cache[cacheKey] = current;
      return current;
    }

    // Case 2: We have TMDB ID, need IMDb ID
    if (current.hasTmdb && !current.hasImdb) {
      final tmdbInt = int.tryParse(current.tmdbId);
      if (tmdbInt != null && tmdb != null) {
        try {
          final details = isMovie
              ? await tmdb!.getMovieDetails(tmdbInt)
              : await tmdb!.getSeriesDetails(tmdbInt);

          if (details != null) {
            String foundImdb = details['imdb_id'] as String? ?? '';
            if (foundImdb.isEmpty && details['external_ids'] is Map) {
              foundImdb = details['external_ids']['imdb_id'] as String? ?? '';
            }
            if (foundImdb.startsWith('tt')) {
              current = ResolvedIds(
                tmdbId: current.tmdbId,
                imdbId: foundImdb,
                rawId: rawId,
                title: details['title'] ?? details['name'] ?? current.title,
              );
            }
          }
        } catch (e) {
          debugPrint('IdResolver TMDB lookup failed: $e');
        }
      }
    }

    // Case 3: We have IMDb ID, need TMDB ID
    if (current.hasImdb && !current.hasTmdb) {
      // Try TMDB /find endpoint
      if (tmdb != null && tmdb!.isConfigured) {
        try {
          final match = await tmdb!.findByImdbId(current.imdbId);
          if (match != null && match['id'] != null) {
            current = ResolvedIds(
              tmdbId: match['id'].toString(),
              imdbId: current.imdbId,
              rawId: rawId,
              title: match['title'] ?? match['name'] ?? current.title,
            );
          }
        } catch (e) {
          debugPrint('IdResolver reverse lookup failed: $e');
        }
      }

      // Fallback: Query Cinemeta public meta endpoint to get title/details
      if (!current.hasTmdb) {
        try {
          final typeStr = isMovie ? 'movie' : 'series';
          final res = await _dio.get(
            'https://v3-cinemeta.strem.io/meta/$typeStr/${current.imdbId}.json',
          );
          if (res.statusCode == 200 && res.data is Map && res.data['meta'] is Map) {
            final meta = res.data['meta'] as Map<String, dynamic>;
            final metaName = meta['name'] as String? ?? '';
            final moviedbId = meta['moviedb_id']?.toString() ?? '';
            current = ResolvedIds(
              tmdbId: moviedbId,
              imdbId: current.imdbId,
              rawId: rawId,
              title: metaName.isNotEmpty ? metaName : current.title,
            );
          }
        } catch (_) {}
      }
    }

    _cache[cacheKey] = current;
    return current;
  }
}
