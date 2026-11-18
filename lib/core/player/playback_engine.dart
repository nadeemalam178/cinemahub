import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../providers/provider_health.dart';
import '../providers/provider_model.dart';
import '../providers/provider_registry.dart';
import '../providers/stremio_adapter.dart';

/// Result produced by the playback engine after evaluating all providers.
class PlaybackResult {
  const PlaybackResult({
    required this.streams,
    this.meta,
    this.errors = const [],
    this.providerFallbacks = const [],
  });

  /// Streams, ordered from highest-priority provider to lowest.
  final List<StreamResult> streams;

  /// Provider metadata (overview, genres, poster URLs).
  final Map<String, dynamic>? meta;

  /// Errors encountered per-provider so callers can surface them gracefully.
  final List<String> errors;

  /// Which provider was tried before failing, for diagnostic UI.
  final List<String> providerFallbacks;
}

/// Multi-provider playback engine with fallback logic.
///
/// Responsibilities:
///  * Walk through the enable-list of providers ordered by priority.
///  * For each provider, check health before use.
///  * Fetch streams via [StremioAdapter] and aggregate results.
///  * Return the first viable stream when [requireOne] is true.
class PlaybackEngine extends ChangeNotifier {
  PlaybackEngine({required StremioAdapter adapter}) : _adapter = adapter;

  final StremioAdapter _adapter;

  List<StreamResult> _currentStreams = [];
  List<StreamResult> get currentStreams => _currentStreams;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  /// Fetch playable streams for the given content across all enabled providers.
  ///
  /// If [providerId] is supplied only that provider is queried; otherwise every
  /// enabled provider is tried in priority order until at least one stream is
  /// found.
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

    final targets = providerId != null
        ? registry.enabled.where((p) => p.id == providerId).toList()
        : registry.enabled;

    if (targets.isEmpty) {
      _error = 'No authorised providers available.';
      _loading = false;
      notifyListeners();
      return;
    }

    final allStreams = <StreamResult>[];
    final errors = <String>[];
    final fallbacks = <String>[];

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
      final streams = await _adapter.fetchStreams(
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
