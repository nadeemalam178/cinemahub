import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';

import 'provider_model.dart';

/// Health and latency tracking for a single provider.
enum HealthStatus { unknown, healthy, degraded, down }

/// Health monitor for a single provider.
class ProviderHealth {
  ProviderHealth({
    required this.provider,
    required this._dio,
  });

  final ProviderModel provider;
  final Dio _dio;

  HealthStatus _status = HealthStatus.unknown;
  int? _latencyMs;
  String? _lastError;
  DateTime? _lastCheck;
  Timer? _timer;

  HealthStatus get status => _status;
  int? get latencyMs => _latencyMs;
  String? get lastError => _lastError;
  DateTime? get lastCheck => _lastCheck;

  /// Whether the provider is usable right now.
  bool get usable =>
      _status == HealthStatus.healthy || _status == HealthStatus.degraded;

  /// Start periodic health checks every [interval].
  void start({Duration interval = const Duration(minutes: 5)}) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => check());
    check();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Run a single health probe against the provider manifest URL.
  Future<void> check() async {
    final url = provider.manifestUrl;
    if (url == null) {
      _status = HealthStatus.unknown;
      _lastError = 'No manifest URL';
      _lastCheck = DateTime.now();
      return;
    }

    final start = DateTime.now();
    try {
      final response = await _dio.get(
        url,
        queryParameters: {'format': 'json'},
        options: Options(
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
        ),
      );
      _latencyMs = DateTime.now().difference(start).inMilliseconds;

      if (response.statusCode == 200) {
        _status = _latencyMs! < 1500
            ? HealthStatus.healthy
            : HealthStatus.degraded;
        _lastError = null;
      } else {
        _status = HealthStatus.down;
        _lastError = 'HTTP ${response.statusCode}';
      }
    } catch (e) {
      _status = HealthStatus.down;
      _latencyMs = null;
      _lastError = e.toString();
    }
    _lastCheck = DateTime.now();
  }

  /// Persist the latest health snapshot to Firestore.
  Future<void> publish(FirebaseFirestore firestore) async {
    await firestore
        .collection('providers')
        .doc(provider.id)
        .collection('health')
        .add({
      'status': _status.name,
      'latencyMs': _latencyMs,
      'lastError': _lastError,
      'checkedAt': FieldValue.serverTimestamp(),
    });
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}