import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'stremio_catalog_service.dart';
import 'tmdb_service.dart';

/// Unified catalogue service for movies and TV series.
class CatalogueService extends ChangeNotifier {
  CatalogueService({
    required this._tmdb,
    StremioAddonCatalog? stremio,
    FirebaseFirestore? firestore,
  })  : _stremio = stremio ?? StremioAddonCatalog(),
        _firestoreInstance = firestore;

  final TmdbService _tmdb;
  final StremioAddonCatalog _stremio;
  final FirebaseFirestore? _firestoreInstance;
  FirebaseFirestore get _firestore => _firestoreInstance ?? FirebaseFirestore.instance;
  FirebaseFirestore get firestore => _firestore;

  final Map<String, Timer> _debounce = {};
  final Map<String, dynamic> _cache = {};

  /// Async search across movies and series (supports race-safe callers).
  Future<({List<Map<String, dynamic>> movies, List<Map<String, dynamic>> series})>
      searchAsync(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return (movies: <Map<String, dynamic>>[], series: <Map<String, dynamic>>[]);
    }

    final results = await Future.wait([
      _tmdb.searchMovies(trimmed, rethrowErrors: true),
      _tmdb.searchSeries(trimmed, rethrowErrors: true),
    ]);

    final movies = results[0].map((m) {
      final item = Map<String, dynamic>.from(m);
      item['title'] ??= item['name'];
      return _normalizeContent(item);
    }).toList();

    final series = results[1].map((s) {
      final item = Map<String, dynamic>.from(s);
      item['name'] ??= item['title'];
      return _normalizeContent(item);
    }).toList();

    _cache['search:$trimmed'] = [...movies, ...series];
    return (movies: movies, series: series);
  }

  /// Legacy debounced callback search wrapper.
  void search({
    required String query,
    required Function(List<Map<String, dynamic>>) onMovies,
    required Function(List<Map<String, dynamic>>) onSeries,
  }) {
    _debounce['search']?.cancel();
    _debounce['search'] = Timer(const Duration(milliseconds: 400), () async {
      try {
        final result = await searchAsync(query);
        onMovies(result.movies);
        onSeries(result.series);
      } catch (e) {
        debugPrint('CatalogueService search failed: $e');
        onMovies([]);
        onSeries([]);
      }
    });
  }

  /// Get trending content across movies and series.
  Future<List<Map<String, dynamic>>> getTrending() async {
    final cached = _cache['trending'];
    if (cached != null) return cached as List<Map<String, dynamic>>;

    final items = await _tmdb.getTrendingAll(rethrowErrors: true);
    final content = items.map(_normalizeContent).toList();

    _cache['trending'] = content;
    return content;
  }

  /// Get top rated movies.
  Future<List<Map<String, dynamic>>> getTopRatedMovies() async {
    final cached = _cache['top_rated:movies'];
    if (cached != null) return cached as List<Map<String, dynamic>>;

    final movies = await _tmdb.getTopRatedMovies(rethrowErrors: true);
    final content = movies.map(_normalizeContent).toList();

    _cache['top_rated:movies'] = content;
    return content;
  }

  /// Get popular movies.
  Future<List<Map<String, dynamic>>> getPopularMovies() async {
    final cached = _cache['popular:movies'];
    if (cached != null) return cached as List<Map<String, dynamic>>;

    final movies = await _tmdb.getPopularMovies(rethrowErrors: true);
    final content = movies.map(_normalizeContent).toList();

    _cache['popular:movies'] = content;
    return content;
  }

  /// Get popular series.
  Future<List<Map<String, dynamic>>> getPopularSeries() async {
    final cached = _cache['popular:series'];
    if (cached != null) return cached as List<Map<String, dynamic>>;

    final series = await _tmdb.getPopularSeries(rethrowErrors: true);
    final content = series.map(_normalizeContent).toList();

    _cache['popular:series'] = content;
    return content;
  }

  /// Get Stremio community addon shelves.
  Future<List<StremioShelf>> getStremioShelves() async {
    const cacheKey = 'stremio:shelves';
    final cached = _cache[cacheKey];
    if (cached != null) return cached as List<StremioShelf>;

    final shelves = await _stremio.fetchAllShelves();
    _cache[cacheKey] = shelves;
    return shelves;
  }

  /// Get content by genre.
  Future<List<Map<String, dynamic>>> getByGenre(int genreId) async {
    final key = 'genre:$genreId';
    final cached = _cache[key];
    if (cached != null) return cached as List<Map<String, dynamic>>;

    final movies = await _tmdb.getMoviesByGenre(genreId, rethrowErrors: true);
    final content = movies.map(_normalizeContent).toList();

    _cache[key] = content;
    return content;
  }

  /// Get detailed content information.
  Future<Map<String, dynamic>?> getContentDetails(String type, int id) async {
    final key = 'details:$type:$id';
    final cached = _cache[key];
    if (cached != null) return cached as Map<String, dynamic>;

    Map<String, dynamic>? details;
    if (type == 'movie') {
      details = await _tmdb.getMovieDetails(id);
    } else if (type == 'series') {
      details = await _tmdb.getSeriesDetails(id);
    }

    if (details != null) {
      final normalized = _normalizeContent(details);
      _cache[key] = normalized;
      return normalized;
    }
    return null;
  }

  /// Get episodes for a season.
  Future<List<Map<String, dynamic>>> getSeasonEpisodes(
    int seriesId,
    int seasonNumber,
  ) async {
    final key = 'episodes:$seriesId:$seasonNumber';
    final cached = _cache[key];
    if (cached != null) return cached as List<Map<String, dynamic>>;

    final episodes = await _tmdb.getSeasonEpisodes(seriesId, seasonNumber);
    final content = episodes.toList();

    _cache[key] = content;
    return content;
  }

  /// Normalize TMDB response to our internal format.
  Map<String, dynamic> _normalizeContent(Map<String, dynamic> tmdbData) {
    final mediaType = tmdbData['media_type'] as String?;
    final type = mediaType == 'tv' || mediaType == 'series'
        ? 'series'
        : (tmdbData['title'] != null ? 'movie' : 'series');
    final id = tmdbData['id'];
    final title = tmdbData['title'] ?? tmdbData['name'];
    final posterPath = tmdbData['poster_path'];
    final backdropPath = tmdbData['backdrop_path'];
    final overview = tmdbData['overview'];
    final releaseDate = tmdbData['release_date'] ?? tmdbData['first_air_date'];
    final rating = (tmdbData['vote_average'] as num?)?.toDouble() ?? 0.0;
    final genreIds = (tmdbData['genre_ids'] as List?)
            ?.map((e) => (e as num).toInt())
            .toList() ??
        (tmdbData['genres'] as List?)
            ?.whereType<Map>()
            .map((g) => (g['id'] as num?)?.toInt())
            .whereType<int>()
            .toList() ??
        <int>[];

    return {
      'id': 'tmdb:$type:$id',
      'type': type,
      'title': title,
      'posterUrl': posterPath != null
          ? 'https://image.tmdb.org/t/p/w500$posterPath'
          : null,
      'backdropUrl': backdropPath != null
          ? 'https://image.tmdb.org/t/p/w780$backdropPath'
          : null,
      'overview': overview,
      'releaseDate': releaseDate,
      'rating': rating,
      'genreIds': genreIds,
      'tmdbData': tmdbData,
    };
  }

  /// Clear all cached data.
  void clearCache() {
    _cache.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    for (final timer in _debounce.values) {
      timer.cancel();
    }
    super.dispose();
  }
}
