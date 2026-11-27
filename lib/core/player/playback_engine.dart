import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../catalogue/id_resolver.dart';
import '../providers/cloudstream_provider_engine.dart';
import '../providers/fmhy_provider_engine.dart';
import '../providers/nuvio_provider_engine.dart';
import '../providers/provider_model.dart';
import '../providers/provider_registry.dart';
import '../providers/stremio_adapter.dart';
import '../providers/stremio_torrent_scraper.dart';
import '../streaming/diagnostics/streaming_logger.dart';

/// Multi-provider playback engine: FMHY Servers + Stremio Addons + Nuvio Plugins + CloudStream.
class PlaybackEngine extends ChangeNotifier {
  PlaybackEngine({
    required this.adapter,
    FmhyProviderEngine? fmhyEngine,
    StremioTorrentScraper? torrentScraper,
    NuvioProviderEngine? nuvioEngine,
    CloudStreamProviderEngine? cloudStreamEngine,
    IdResolver? idResolver,
  })  : _fmhyEngine = fmhyEngine ?? const FmhyProviderEngine(),
        _torrentScraper = torrentScraper ?? StremioTorrentScraper(),
        _nuvioEngine = nuvioEngine ?? NuvioProviderEngine(),
        _cloudStreamEngine = cloudStreamEngine ?? CloudStreamProviderEngine(),
        _idResolver = idResolver ?? IdResolver();

  final StremioAdapter adapter;
  final FmhyProviderEngine _fmhyEngine;
  final StremioTorrentScraper _torrentScraper;
  final NuvioProviderEngine _nuvioEngine;
  final CloudStreamProviderEngine _cloudStreamEngine;
  final IdResolver _idResolver;

  List<StreamResult> _currentStreams = [];
  List<StreamResult> get currentStreams => _currentStreams;

  List<StreamResult> get fmhyStreams => _currentStreams
      .where((s) => s.behaviorHints?['category'] == 'fmhy')
      .toList();

  List<StreamResult> get stremioStreams => _currentStreams
      .where((s) => s.behaviorHints?['category'] == 'stremio')
      .toList();

  List<StreamResult> get nuvioStreams => _currentStreams
      .where((s) => s.behaviorHints?['category'] == 'nuvio')
      .toList();

  List<StreamResult> get cloudStreamStreams => _currentStreams
      .where((s) => s.behaviorHints?['category'] == 'cloudstream')
      .toList();

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  String? _cachedRdKey;
  List<String>? _cachedCustomAddons;

  void updateDebridConfig({String? realDebridKey, List<String>? customAddons}) {
    if (realDebridKey != null) _cachedRdKey = realDebridKey;
    if (customAddons != null) _cachedCustomAddons = customAddons;
  }

  /// Fetch playable streams for the given content across all 4 categories.
  Future<void> fetchStreams({
    required ContentType type,
    required String id,
    int? season,
    int? episode,
    String? metaImdbId,
    int? metaTmdbId,
    String? title,
    ProviderRegistry? registry,
    String? realDebridKey,
    List<String>? customAddonUrls,
  }) async {
    _loading = true;
    _error = null;
    _currentStreams = [];
    notifyListeners();

    final allStreams = <StreamResult>[];
    final errors = <String>[];
    final isMovie = type == ContentType.movie;
    final stremioType = isMovie ? 'movie' : 'series';

    String? effectiveRdKey = realDebridKey ?? _cachedRdKey;
    List<String>? effectiveCustomAddons = customAddonUrls ?? _cachedCustomAddons;
    if (effectiveRdKey == null || effectiveCustomAddons == null) {
      try {
        final prefs = await SharedPreferences.getInstance().timeout(
          const Duration(milliseconds: 300),
        );
        effectiveRdKey ??= prefs.getString('real_debrid_key');
        effectiveCustomAddons ??= prefs.getStringList('custom_stremio_addons');
        _cachedRdKey = effectiveRdKey;
        _cachedCustomAddons = effectiveCustomAddons;
      } catch (_) {}
    }

    // 1. Resolve IDs bi-directionally (clean TMDB ID + clean IMDb ID)
    final resolved = await _idResolver.resolve(
      rawId: id,
      isMovie: isMovie,
      metaImdbId: metaImdbId,
      metaTmdbId: metaTmdbId,
      title: title,
    );

    final cleanTmdb = resolved.tmdbId;
    final cleanImdb = resolved.imdbId;

    // 2. Fetch all 4 categories in parallel
    await Future.wait([
      // Category 1: FMHY Video Servers (Verified Embeds)
      Future(() {
        try {
          final fmhy = _fmhyEngine.resolveAllStreams(
            tmdbId: cleanTmdb,
            imdbId: cleanImdb,
            isMovie: isMovie,
            season: season,
            episode: episode,
          );
          allStreams.addAll(fmhy);
          StreamingLogger.instance.log(
            stage: 'FmhyResolution',
            message: 'Resolved ${fmhy.length} verified FMHY embed server(s)',
            provider: 'FMHY',
          );
        } catch (e) {
          StreamingLogger.instance.log(
            stage: 'FmhyResolution',
            message: 'FMHY resolution error: $e',
            provider: 'FMHY',
            severity: LogSeverity.warning,
          );
        }
      }),

      // Category 2: Stremio Addons (Torrentio, MediaFusion, Comet, KnightCrawler)
      Future(() async {
        if (cleanImdb.isNotEmpty) {
          try {
            final torrents = await _torrentScraper.fetchAllTorrentStreams(
              type: stremioType,
              imdbId: cleanImdb,
              season: season,
              episode: episode,
              realDebridKey: effectiveRdKey,
              customAddonUrls: effectiveCustomAddons,
            );
            allStreams.addAll(torrents);
          } catch (e) {
            StreamingLogger.instance.logStreamRequest(
              'StremioScraper',
              cleanImdb,
              statusCode: 0,
              streamCount: 0,
              error: e.toString(),
            );
          }
        } else {
          StreamingLogger.instance.logStreamRequest(
            'PlaybackEngine',
            'stremio_resolve',
            statusCode: 404,
            streamCount: 0,
            error:
                'No IMDb ID resolved for content "$id" (${title ?? 'untitled'}); Stremio querying skipped.',
          );
        }
      }),

      // Category 3: Nuvio Plugins
      Future(() async {
        try {
          final nuvio = await _nuvioEngine.fetchStreams(
            isMovie: isMovie,
            imdbId: cleanImdb,
            tmdbId: cleanTmdb,
            season: season,
            episode: episode,
          );
          allStreams.addAll(nuvio);
        } catch (e) {
          debugPrint('Nuvio Plugin scraper error: $e');
        }
      }),

      // Category 4: CloudStream Sources
      Future(() async {
        try {
          final cs = await _cloudStreamEngine.fetchStreams(
            isMovie: isMovie,
            tmdbId: cleanTmdb,
            imdbId: cleanImdb,
            season: season,
            episode: episode,
          );
          allStreams.addAll(cs);
        } catch (e) {
          debugPrint('CloudStream scraper error: $e');
        }
      }),
    ]);

    // 3. Query registered Firestore providers in parallel with resolved IMDb/TMDB ID
    if (registry != null && registry.enabled.isNotEmpty) {
      final targetId = cleanImdb.isNotEmpty
          ? cleanImdb
          : (cleanTmdb.isNotEmpty ? 'tmdb:$cleanTmdb' : id);
      await Future.wait(
        registry.enabled.map((provider) async {
          final streams = await _tryProvider(
            provider: provider,
            type: stremioType,
            id: targetId,
            season: season,
            episode: episode,
            errors: errors,
          );
          if (streams.isNotEmpty) {
            allStreams.addAll(streams);
          }
        }),
      );
    }

    // 4. Propagate content identifiers to every stream so subtitles & sync always work
    final enriched = allStreams.map((s) {
      final hints = Map<String, dynamic>.from(s.behaviorHints ?? const {});
      if (cleanImdb.isNotEmpty) hints.putIfAbsent('imdb_id', () => cleanImdb);
      if (cleanTmdb.isNotEmpty) hints.putIfAbsent('tmdb_id', () => cleanTmdb);
      hints.putIfAbsent('type', () => stremioType);
      if (season != null) hints.putIfAbsent('season', () => season);
      if (episode != null) hints.putIfAbsent('episode', () => episode);
      return StreamResult(
        name: s.name,
        url: s.url,
        type: s.type,
        hash: s.hash,
        size: s.size,
        fileIndex: s.fileIndex,
        description: s.description,
        behaviorHints: hints,
        subtitles: s.subtitles,
      );
    }).toList();

    if (enriched.isEmpty && errors.isNotEmpty) {
      _error = errors.last;
    }

    _currentStreams = enriched;
    _loading = false;
    notifyListeners();
  }

  Future<List<StreamResult>> _tryProvider({
    required ProviderModel provider,
    required String type,
    required String id,
    int? season,
    int? episode,
    required List<String> errors,
  }) async {
    final baseUrl = provider.manifestUrl;
    if (baseUrl == null) {
      errors.add('${provider.id}: no manifestUrl configured.');
      return [];
    }

    try {
      final streams = await adapter.fetchStreams(
        baseUrl: baseUrl,
        type: type,
        id: id,
        season: season,
        episode: episode,
        addonName: provider.name,
      );
      return streams;
    } catch (e) {
      errors.add('${provider.id}: ${e.toString()}');
      return [];
    }
  }
}
