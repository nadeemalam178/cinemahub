import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// TMDB API client for fetching movie and series metadata.
///
/// Responsibilities:
///  * Search movies and series
///  * Fetch detailed information
///  * Get cast and crew
///  * Fetch similar titles
///  * Cache responses locally
///
/// Rate limits: 40 requests/10s (free tier), 100 requests/10s (API key)
///
/// Usage: Pass --dart-define=TMDB_API_KEY=your_key
class TmdbService {
  /// Creates a TMDB service. The API key should be provided via --dart-define.
  /// Falls back to 'YOUR_TMDB_API_KEY_HERE' if not set (shows error in UI).
  TmdbService({String? apiKey, Dio? dio})
      : _apiKey = apiKey ??
            const String.fromEnvironment(
              'TMDB_API_KEY',
              defaultValue: 'YOUR_TMDB_API_KEY_HERE',
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
  Future<List<Map<String, dynamic>>> searchMovies(String query) async {
    try {
      final response = await _dio.get('/search/movie', queryParameters: {
        'query': query,
        'api_key': _apiKey,
        'language': 'en-US',
        'page': 1,
      });
      return (response.data['results'] as List)
          .cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('TMDB search movies failed: $e');
      return [];
    }
  }

  /// Search for TV series by query.
  Future<List<Map<String, dynamic>>> searchSeries(String query) async {
    try {
      final response = await _dio.get('/search/tv', queryParameters: {
        'query': query,
        'api_key': _apiKey,
        'language': 'en-US',
        'page': 1,
      });
      return (response.data['results'] as List)
          .cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('TMDB search series failed: $e');
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
      return response.data;
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
      return response.data;
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
        final movie = movieResults.first as Map<String, dynamic>;
        movie['media_type'] = 'movie';
        return movie;
      }
      final tvResults = data['tv_results'] as List?;
      if (tvResults != null && tvResults.isNotEmpty) {
        final tv = tvResults.first as Map<String, dynamic>;
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
      return (response.data['episodes'] as List)
          .cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('TMDB season episodes failed: $e');
      return [];
    }
  }

  /// Get trending movies.
  Future<List<Map<String, dynamic>>> getTrendingMovies() async {
    try {
      final response = await _dio.get('/trending/movie/day', queryParameters: {
        'api_key': _apiKey,
        'language': 'en-US',
      });
      return (response.data['results'] as List)
          .cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('TMDB trending movies failed: $e');
      return [];
    }
  }

  /// Get popular movies.
  Future<List<Map<String, dynamic>>> getPopularMovies() async {
    try {
      final response = await _dio.get('/movie/popular', queryParameters: {
        'api_key': _apiKey,
        'language': 'en-US',
        'page': 1,
      });
      return (response.data['results'] as List)
          .cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('TMDB popular movies failed: $e');
      return [];
    }
  }

  /// Get popular TV series.
  Future<List<Map<String, dynamic>>> getPopularSeries() async {
    try {
      final response = await _dio.get('/tv/popular', queryParameters: {
        'api_key': _apiKey,
        'language': 'en-US',
        'page': 1,
      });
      return (response.data['results'] as List)
          .cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('TMDB popular series failed: $e');
      return [];
    }
  }

  /// Get top rated movies.
  Future<List<Map<String, dynamic>>> getTopRatedMovies() async {
    try {
      final response = await _dio.get('/movie/top_rated', queryParameters: {
        'api_key': _apiKey,
        'language': 'en-US',
        'page': 1,
      });
      return (response.data['results'] as List)
          .cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('TMDB top rated movies failed: $e');
      return [];
    }
  }

  /// Get trending all (movies + series) for hero carousel.
  Future<List<Map<String, dynamic>>> getTrendingAll() async {
    try {
      final response = await _dio.get('/trending/all/day', queryParameters: {
        'api_key': _apiKey,
        'language': 'en-US',
      });
      return (response.data['results'] as List)
          .cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('TMDB trending all failed: $e');
      return [];
    }
  }

  /// Get movies by genre.
  Future<List<Map<String, dynamic>>> getMoviesByGenre(int genreId) async {
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
      return (response.data['results'] as List)
          .cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('TMDB movies by genre failed: $e');
      return [];
    }
  }
}