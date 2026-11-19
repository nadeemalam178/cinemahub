import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'tmdb_service.dart';

/// Unified catalogue service for movies and TV series.
///
/// Responsibilities:
/// * Fetch and cache metadata from TMDB
/// * Store in Firestore for offline access
/// * Provide stable content IDs
/// * Handle pagination and search
/// * Support local caching for performance
class CatalogueService extends ChangeNotifier {
  CatalogueService({
    required this._tmdb,
    FirebaseFirestore? firestore,
  }) : _firestoreInstance = firestore;

  final TmdbService _tmdb;
  final FirebaseFirestore? _firestoreInstance;
  FirebaseFirestore get _firestore => _firestoreInstance ?? FirebaseFirestore.instance;
  FirebaseFirestore get firestore => _firestore;

  final Map<String, Timer> _debounce = {};
  final Map<String, dynamic> _cache = {};

  /// Search across movies and series with debouncing.
  void search({
    required String query,
    required Function(List<Map<String, dynamic>>) onMovies,
    required Function(List<Map<String, dynamic>>) onSeries,
  }) {
    _debounce['search']?.cancel();
    _debounce['search'] = Timer(const Duration(milliseconds: 500), () async {
      final movies = await _tmdb.searchMovies(query);
      final series = await _tmdb.searchSeries(query);

      _cache['search:$query'] = [...movies, ...series];
      onMovies(movies);
      onSeries(series);
    });
  }

  /// Get trending content.
  Future<List<Map<String, dynamic>>> getTrending() async {
    final cached = _cache['trending'];
    if (cached != null) return cached;

    final movies = await _tmdb.getTrendingMovies();
    final content = movies.map(_normalizeContent).toList();

    _cache['trending'] = content;
    return content;
  }

  /// Get popular movies.
  Future<List<Map<String, dynamic>>> getPopularMovies() async {
    final cached = _cache['popular:movies'];
    if (cached != null) return cached;

    final movies = await _tmdb.getPopularMovies();
    final content = movies.map(_normalizeContent).toList();

    _cache['popular:movies'] = content;
    return content;
  }

  /// Get popular series.
  Future<List<Map<String, dynamic>>> getPopularSeries() async {
    final cached = _cache['popular:series'];
    if (cached != null) return cached;

    final series = await _tmdb.getPopularSeries();
    final content = series.map(_normalizeContent).toList();

    _cache['popular:series'] = content;
    return content;
  }

  /// Get content by genre.
  Future<List<Map<String, dynamic>>> getByGenre(int genreId) async {
    final key = 'genre:$genreId';
    final cached = _cache[key];
    if (cached != null) return cached;

    final movies = await _tmdb.getMoviesByGenre(genreId);
    final content = movies.map(_normalizeContent).toList();

    _cache[key] = content;
    return content;
  }

  /// Get detailed content information.
  Future<Map<String, dynamic>?> getContentDetails(String type, int id) async {
    final key = 'details:$type:$id';
    final cached = _cache[key];
    if (cached != null) return cached;

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
    if (cached != null) return cached;

    final episodes = await _tmdb.getSeasonEpisodes(seriesId, seasonNumber);
    final content = episodes.map((e) => _normalizeContent(e)).toList();

    _cache[key] = content;
    return content;
  }

  /// Normalize TMDB response to our internal format.
  Map<String, dynamic> _normalizeContent(Map<String, dynamic> tmdbData) {
    final type = tmdbData['title'] != null ? 'movie' : 'series';
    final id = tmdbData['id'];
    final title = tmdbData['title'] ?? tmdbData['name'];
    final posterPath = tmdbData['poster_path'];
    final backdropPath = tmdbData['backdrop_path'];
    final overview = tmdbData['overview'];
    final releaseDate = tmdbData['release_date'] ?? tmdbData['first_air_date'];
    final rating = tmdbData['vote_average']?.toDouble() ?? 0.0;
    final genreIds = (tmdbData['genre_ids'] as List?)?.cast<int>() ?? [];

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