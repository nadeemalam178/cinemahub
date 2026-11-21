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

/// Multi-provider playback engine: FMHY 28+ Servers + Stremio Addons + Nuvio Plugins + CloudStream.
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

  // Categorized stream accessors
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

  /// Update cached Real-Debrid and community addons
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

    // Load any saved Real-Debrid API key from SharedPreferences if not provided explicitly
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
      // Category 1: FMHY Video Servers (28+ verified embeds)
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
        } catch (e) {
          debugPrint('FMHY resolution error: $e');
        }
      }),

      // Category 2: Stremio Addons (Torrentio, MediaFusion, Comet, KnightCrawler)
      Future(() async {
        if (cleanImdb.isNotEmpty) {
          try {
            final torrents = await _torrentScraper.fetchAllTorrentStreams(
              type: isMovie ? 'movie' : 'series',
              imdbId: cleanImdb,
              season: season,
              episode: episode,
              realDebridKey: effectiveRdKey,
              customAddonUrls: effectiveCustomAddons,
            );
            allStreams.addAll(torrents);
          } catch (e) {
            debugPrint('Stremio Addon scraper error: $e');
          }
        }
      }),

      // Category 3: Nuvio Plugins (nuvioplugin.com)
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

    // 3. Fallback to registered custom providers if provided
    if (registry != null) {
      final enabledProviders = registry.enabled;
      for (final provider in enabledProviders) {
        final streams = await _tryProvider(
          provider: provider,
          type: type,
          id: id,
          season: season,
          episode: episode,
          errors: errors,
        );
        if (streams.isNotEmpty) {
          allStreams.addAll(streams);
        }
      }
    }

    if (allStreams.isEmpty && errors.isNotEmpty) {
      _error = errors.last;
    }

    _currentStreams = allStreams;
    _loading = false;
    notifyListeners();
  }

  Future<List<StreamResult>> _tryProvider({
    required ProviderModel provider,
    required ContentType type,
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
        type: type.name,
        id: id,
        season: season,
        episode: episode,
      );
      return streams;
    } catch (e) {
      errors.add('${provider.id}: ${e.toString()}');
      return [];
    }
  }
}
