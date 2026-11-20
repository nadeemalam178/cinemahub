import 'dart:async';
import 'package:flutter/foundation.dart';

import '../providers/fmhy_provider_engine.dart';
import '../providers/provider_model.dart';
import '../providers/provider_registry.dart';
import '../providers/stremio_adapter.dart';
import '../providers/stremio_torrent_scraper.dart';

/// Multi-provider playback engine: FMHY 12+ Servers + Stremio & Nuvioplugin P2P torrents.
class PlaybackEngine extends ChangeNotifier {
  PlaybackEngine({
    required this.adapter,
    FmhyProviderEngine? fmhyEngine,
    StremioTorrentScraper? torrentScraper,
  })  : _fmhyEngine = fmhyEngine ?? const FmhyProviderEngine(),
        _torrentScraper = torrentScraper ?? StremioTorrentScraper();

  final StremioAdapter adapter;
  final FmhyProviderEngine _fmhyEngine;
  final StremioTorrentScraper _torrentScraper;

  List<StreamResult> _currentStreams = [];
  List<StreamResult> get currentStreams => _currentStreams;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  /// Fetch playable streams for the given content across FMHY, Stremio torrents & registered providers.
  Future<void> fetchStreams({
    required ContentType type,
    required String id,
    int? season,
    int? episode,
    ProviderRegistry? registry,
  }) async {
    _loading = true;
    _error = null;
    _currentStreams = [];
    notifyListeners();

    final allStreams = <StreamResult>[];
    final errors = <String>[];

    // Normalize IDs
    String tmdbOrImdb = id;
    if (tmdbOrImdb.startsWith('tmdb:')) {
      tmdbOrImdb = tmdbOrImdb.replaceFirst('tmdb:', '');
    } else if (tmdbOrImdb.startsWith('imdb:')) {
      tmdbOrImdb = tmdbOrImdb.replaceFirst('imdb:', '');
    }

    final isMovie = type == ContentType.movie;

    // 1. Fetch all FMHY Embed Streams (Ad-Blocked In-App Player)
    try {
      final fmhyStreams = _fmhyEngine.resolveAllStreams(
        tmdbId: tmdbOrImdb,
        isMovie: isMovie,
        season: season,
        episode: episode,
      );
      allStreams.addAll(fmhyStreams);
    } catch (e) {
      debugPrint('FMHY Engine resolution error: $e');
    }

    // 2. Fetch Stremio & Nuvioplugin Torrents (Torrentio, MediaFusion, Comet, KnightCrawler)
    try {
      final torrentStreams = await _torrentScraper.fetchAllTorrentStreams(
        type: isMovie ? 'movie' : 'series',
        imdbId: tmdbOrImdb.startsWith('tt') ? tmdbOrImdb : 'tt$tmdbOrImdb',
        season: season,
        episode: episode,
      );
      allStreams.addAll(torrentStreams);
    } catch (e) {
      debugPrint('Torrent Scraper error: $e');
    }

    // 3. Fallback to registered Stremio providers if provided
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
