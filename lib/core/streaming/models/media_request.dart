enum MediaType { movie, series }

/// Canonical media request model for resolving streams across any provider.
class MediaRequest {
  const MediaRequest({
    required this.tmdbId,
    this.imdbId,
    required this.type,
    this.season,
    this.episode,
    required this.title,
    this.year,
  });

  /// Canonical TMDB ID (e.g. "550" or "1399")
  final String tmdbId;

  /// Optional IMDb ID (e.g. "tt0137523")
  final String? imdbId;

  /// Movie or Series
  final MediaType type;

  /// Season number for series
  final int? season;

  /// Episode number for series
  final int? episode;

  /// Content title for display and matching
  final String title;

  /// Release year if available
  final int? year;

  bool get isMovie => type == MediaType.movie;
  bool get isSeries => type == MediaType.series;

  /// Produces a canonical cache/query key
  String get canonicalId {
    if (isSeries) {
      final s = season ?? 1;
      final ep = episode ?? 1;
      if (imdbId != null && imdbId!.isNotEmpty && imdbId!.startsWith('tt')) {
        return '$imdbId:$s:$ep';
      }
      return 'tmdb:$tmdbId:$s:$ep';
    }
    if (imdbId != null && imdbId!.isNotEmpty && imdbId!.startsWith('tt')) {
      return imdbId!;
    }
    return 'tmdb:$tmdbId';
  }

  @override
  String toString() =>
      'MediaRequest(title: $title, type: $type, tmdb: $tmdbId, imdb: $imdbId, s: $season, ep: $episode)';
}
