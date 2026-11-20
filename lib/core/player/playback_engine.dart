import 'dart:async';

import 'package:flutter/foundation.dart';

import '../providers/fmhy_provider_engine.dart';
import '../providers/provider_model.dart';
import '../providers/provider_registry.dart';
import '../providers/stremio_adapter.dart';

/// Multi-provider playback engine with FMHY Auto-Fallback logic.
class PlaybackEngine extends ChangeNotifier {
  PlaybackEngine({
    required this.adapter,
    FmhyProviderEngine? fmhyEngine,
  })  : _fmhyEngine = fmhyEngine ?? const FmhyProviderEngine();

  final StremioAdapter adapter;
  final FmhyProviderEngine _fmhyEngine;

  List<StreamResult> _currentStreams = [];
  List<StreamResult> get currentStreams => _currentStreams;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  /// Fetch playable streams for the given content across FMHY servers and enabled providers.
  Future<void> loadStreams({
    required ProviderRegistry registry,
    required ContentType contentType,
    required String id,
    int? season,
    int? episode,
    String? providerId,
  }) async {
    _loading = true;
    _error = null;
    _currentStreams = [];
    notifyListeners();

    final allStreams = <StreamResult>[];
    final errors = <String>[];
    final fallbacks = <String>[];

    // 1. First inject FMHY Multi-Server Scrapers
    try {
      final isSeries = contentType == ContentType.series || contentType == ContentType.episode;
      final fmhyStreams = _fmhyEngine.resolveAllStreams(
        tmdbId: id,
        season: season ?? 1,
        episode: episode ?? 1,
        isSeries: isSeries,
      );
      allStreams.addAll(fmhyStreams);
    } catch (e) {
      debugPrint('FMHY Stream resolution error: $e');
    }

    // 2. Query enabled Stremio Providers as secondary sources
    final targets = providerId != null
        ? registry.enabled.where((p) => p.id == providerId).toList()
        : registry.enabled;

    for (final provider in targets) {
      if (!provider.usable) {
        fallbacks.add(provider.id);
        continue;
      }

      final streams = await _tryProvider(
        provider: provider,
        type: contentType,
        id: id,
        season: season,
        episode: episode,
        errors: errors,
      );
      if (streams.isNotEmpty) {
        allStreams.addAll(streams);
        break; // Stop on first healthy provider with results.
      } else {
        fallbacks.add(provider.id);
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
