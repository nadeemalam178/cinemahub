import 'package:dio/dio.dart';
import 'subtitle_model.dart';
import 'subtitle_parser.dart';

/// Service for discovering, downloading, parsing, and caching subtitle tracks
/// from Stremio OpenSubtitles addons.
class SubtitleService {
  SubtitleService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 10),
            ));

  final Dio _dio;

  /// Cache of loaded cues keyed by track URL
  final Map<String, List<CinemaSubtitleCue>> _cuesCache = {};

  /// Public Stremio subtitle addon endpoints
  static const List<String> _subtitleAddons = [
    'https://opensubtitles-v3.strem.io',
    'https://opensubtitles.strem.io',
  ];

  /// Fetch available subtitle tracks for given media identifiers
  Future<List<CinemaSubtitleTrack>> fetchTracks({
    required String type, // "movie" or "series"
    required String? imdbId,
    int? season,
    int? episode,
    List<CinemaSubtitleTrack>? embeddedTracks,
  }) async {
    final results = <CinemaSubtitleTrack>[];

    if (embeddedTracks != null && embeddedTracks.isNotEmpty) {
      results.addAll(embeddedTracks);
    }

    if (imdbId == null || imdbId.isEmpty) return results;

    final targetId = (type == 'series' && season != null && episode != null)
        ? '$imdbId:$season:$episode'
        : imdbId;

    await Future.wait(
      _subtitleAddons.map((addonBase) async {
        try {
          final url = '$addonBase/subtitles/$type/$targetId.json';
          final response = await _dio.get(url);

          if (response.statusCode == 200 && response.data is Map) {
            final subs = response.data['subtitles'] as List?;
            if (subs != null) {
              final sourceName = addonBase.contains('opensubtitles-v3')
                  ? 'OpenSubtitles v3'
                  : 'OpenSubtitles';
              for (int i = 0; i < subs.length; i++) {
                final item = subs[i];
                if (item is Map && item['url'] != null) {
                  final subUrl = item['url'] as String;
                  final lang = item['lang'] as String? ?? 'en';
                  final label = item['name'] as String? ??
                      _getLanguageLabel(lang) ??
                      'Subtitle ${i + 1}';

                  results.add(CinemaSubtitleTrack(
                    id: 'stremio_${lang}_${subUrl.hashCode}',
                    label: '$label ($sourceName)',
                    languageCode: lang,
                    url: subUrl,
                    source: sourceName,
                  ));
                }
              }
            }
          }
        } catch (_) {
          // Skip failing subtitle addon
        }
      }),
    );

    final unique = <String, CinemaSubtitleTrack>{};
    for (final track in results) {
      unique[track.url] = track;
    }

    return unique.values.toList();
  }

  /// Download and parse subtitle cues for selected track
  Future<List<CinemaSubtitleCue>> loadCues(CinemaSubtitleTrack track) async {
    if (_cuesCache.containsKey(track.url)) {
      return _cuesCache[track.url]!;
    }

    try {
      final response = await _dio.get<String>(
        track.url,
        options: Options(responseType: ResponseType.plain),
      );

      final content = response.data ?? '';
      final cues = SubtitleParser.parse(content);
      _cuesCache[track.url] = cues;
      return cues;
    } catch (_) {
      return const [];
    }
  }

  void clearCache() {
    _cuesCache.clear();
  }

  static String? _getLanguageLabel(String code) {
    switch (code.toLowerCase()) {
      case 'en':
      case 'eng':
        return 'English';
      case 'es':
      case 'spa':
        return 'Spanish';
      case 'fr':
      case 'fre':
        return 'French';
      case 'de':
      case 'ger':
        return 'German';
      case 'it':
      case 'ita':
        return 'Italian';
      case 'ru':
      case 'rus':
        return 'Russian';
      case 'hi':
      case 'hin':
        return 'Hindi';
      default:
        return code.toUpperCase();
    }
  }
}
