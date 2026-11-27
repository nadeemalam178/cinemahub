import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// TMDB API client for fetching movie and series metadata.
///
/// Usage: Pass --dart-define=TMDB_API_KEY=your_key
class TmdbService {
  TmdbService({String? apiKey, Dio? dio})
      : _apiKey = apiKey ??
            const String.fromEnvironment(
              'TMDB_API_KEY',
              defaultValue: '44c6bd7c4e0a48045794d64bf03d982a',
            ),
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://api.themoviedb.org/3',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
            ));

  final String _apiKey;
  final Dio _dio;

  /// Returns true if a valid TMDB API key is configured.
  bool get isConfigured =>
      _apiKey != 'YOUR_TMDB_API_KEY_HERE' && _apiKey.isNotEmpty;

  /// Search for movies by query.
  Future<List<Map<String, dynamic>>> searchMovies(
    String query, {
    bool rethrowErrors = false,
  }) async {
    try {
      final response = await _dio.get('/search/movie', queryParameters: {
        'query': query,
        'api_key': _apiKey,
        'language': 'en-US',
        'page': 1,
      });
      return (response.data['results'] as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('TMDB search movies failed: $e');
      if (rethrowErrors) rethrow;
      return [];
    }
  }

  /// Search for TV series by query.
  Future<List<Map<String, dynamic>>> searchSeries(
    String query, {
    bool rethrowErrors = false,
  }) async {
    try {
      final response = await _dio.get('/search/tv', queryParameters: {
        'query': query,
        'api_key': _apiKey,
        'language': 'en-US',
        'page': 1,
      });
      return (response.data['results'] as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('TMDB search series failed: $e');
      if (rethrowErrors) rethrow;
      return [];
    }
  }

  /// Get detailed movie information.
  Future<Map<String, dynamic>?> getMovieDetails(int id) async {
    try {
      final response = await _dio.get('/movie/$id', queryParameters: {
        'api_key': _apiKey,
        'language': 'en-US',
        'append_to_response': 'credits,similar,external_ids',
      });
      return response.data as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('TMDB movie details failed: $e');
      return null;
    }
  }

  /// Get detailed TV series information.
  Future<Map<String, dynamic>?> getSeriesDetails(int id) async {
    try {
      final response = await _dio.get('/tv/$id', queryParameters: {
        'api_key': _apiKey,
        'language': 'en-US',
        'append_to_response': 'credits,similar,seasons,external_ids',
      });
      return response.data as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('TMDB series details failed: $e');
      return null;
    }
  }

  /// Find content by external IMDb ID.
  Future<Map<String, dynamic>?> findByImdbId(String imdbId) async {
    try {
      final response = await _dio.get('/find/$imdbId', queryParameters: {
        'api_key': _apiKey,
        'external_source': 'imdb_id',
        'language': 'en-US',
      });
      final data = response.data as Map<String, dynamic>;
      final movieResults = data['movie_results'] as List?;
      if (movieResults != null && movieResults.isNotEmpty) {
        final movie = Map<String, dynamic>.from(movieResults.first as Map);
        movie['media_type'] = 'movie';
        return movie;
      }
      final tvResults = data['tv_results'] as List?;
      if (tvResults != null && tvResults.isNotEmpty) {
        final tv = Map<String, dynamic>.from(tvResults.first as Map);
        tv['media_type'] = 'series';
        return tv;
      }
      return null;
    } catch (e) {
      debugPrint('TMDB findByImdbId failed: $e');
      return null;
    }
  }

  /// Get episodes for a specific season.
  Future<List<Map<String, dynamic>>> getSeasonEpisodes(
    int seriesId,
    int seasonNumber,
  ) async {
    try {
      final response = await _dio.get(
        '/tv/$seriesId/season/$seasonNumber',
        queryParameters: {
          'api_key': _apiKey,
          'language': 'en-US',
        },
      );
      return (response.data['episodes'] as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('TMDB season episodes failed: $e');
      return [];
    }
  }

  /// Get trending movies.
  Future<List<Map<String, dynamic>>> getTrendingMovies({
    bool rethrowErrors = false,
  }) async {
    try {
      final response = await _dio.get('/trending/movie/day', queryParameters: {
        'api_key': _apiKey,
        'language': 'en-US',
      });
      return (response.data['results'] as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('TMDB trending movies failed: $e');
      if (rethrowErrors) rethrow;
      return [];
    }
  }

  /// Get popular movies.
  Future<List<Map<String, dynamic>>> getPopularMovies({
    bool rethrowErrors = false,
  }) async {
    try {
      final response = await _dio.get('/movie/popular', queryParameters: {
        'api_key': _apiKey,
        'language': 'en-US',
        'page': 1,
      });
      return (response.data['results'] as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('TMDB popular movies failed: $e');
      if (rethrowErrors) rethrow;
      return [];
    }
  }

  /// Get popular TV series.
  Future<List<Map<String, dynamic>>> getPopularSeries({
    bool rethrowErrors = false,
  }) async {
    try {
      final response = await _dio.get('/tv/popular', queryParameters: {
        'api_key': _apiKey,
        'language': 'en-US',
        'page': 1,
      });
      return (response.data['results'] as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('TMDB popular series failed: $e');
      if (rethrowErrors) rethrow;
      return [];
    }
  }

  /// Get top rated movies.
  Future<List<Map<String, dynamic>>> getTopRatedMovies({
    bool rethrowErrors = false,
  }) async {
    try {
      final response = await _dio.get('/movie/top_rated', queryParameters: {
        'api_key': _apiKey,
        'language': 'en-US',
        'page': 1,
      });
      return (response.data['results'] as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('TMDB top rated movies failed: $e');
      if (rethrowErrors) rethrow;
      return [];
    }
  }

  /// Get trending all (movies + series) for hero carousel.
  Future<List<Map<String, dynamic>>> getTrendingAll({
    bool rethrowErrors = false,
  }) async {
    try {
      final response = await _dio.get('/trending/all/day', queryParameters: {
        'api_key': _apiKey,
        'language': 'en-US',
      });
      return (response.data['results'] as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('TMDB trending all failed: $e');
      if (rethrowErrors) rethrow;
      return [];
    }
  }

  /// Get movies by genre.
  Future<List<Map<String, dynamic>>> getMoviesByGenre(
    int genreId, {
    bool rethrowErrors = false,
  }) async {
    try {
      final response = await _dio.get(
        '/discover/movie',
        queryParameters: {
          'api_key': _apiKey,
          'language': 'en-US',
          'sort_by': 'popularity.desc',
          'with_genres': genreId,
          'page': 1,
        },
      );
      return (response.data['results'] as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('TMDB movies by genre failed: $e');
      if (rethrowErrors) rethrow;
      return [];
    }
  }
}
