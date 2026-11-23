import 'package:flutter/foundation.dart';

enum LogSeverity { info, warning, error }

class DiagnosticEvent {
  DiagnosticEvent({
    required this.stage,
    required this.message,
    this.provider,
    this.streamUrl,
    this.severity = LogSeverity.info,
    this.details,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final String stage;
  final String message;
  final String? provider;
  final String? streamUrl;
  final LogSeverity severity;
  final String? details;
  final DateTime timestamp;

  @override
  String toString() {
    final prov = provider != null ? ' [$provider]' : '';
    return '[${timestamp.toIso8601String().substring(11, 19)}][$stage]$prov $message ${details != null ? '($details)' : ''}';
  }
}

/// Central streaming diagnostics recorder with strict secret redaction.
class StreamingLogger {
  StreamingLogger._();
  static final StreamingLogger instance = StreamingLogger._();

  final List<DiagnosticEvent> _events = [];
  List<DiagnosticEvent> get events => List.unmodifiable(_events);

  /// Maximum events retained in memory
  static const int maxEvents = 200;

  void log({
    required String stage,
    required String message,
    String? provider,
    String? streamUrl,
    LogSeverity severity = LogSeverity.info,
    String? details,
  }) {
    final cleanMessage = redactSensitive(message);
    final cleanDetails = details != null ? redactSensitive(details) : null;
    final cleanUrl = streamUrl != null ? redactSensitive(streamUrl) : null;

    final event = DiagnosticEvent(
      stage: stage,
      message: cleanMessage,
      provider: provider,
      streamUrl: cleanUrl,
      severity: severity,
      details: cleanDetails,
    );

    if (_events.length >= maxEvents) {
      _events.removeAt(0);
    }
    _events.add(event);

    if (kDebugMode) {
      debugPrint('[CinemaHub Streaming Diagnostics] $event');
    }
  }

  void clear() {
    _events.clear();
  }

  /// Redacts API keys, tokens, and authorization parameters from URLs and headers
  static String redactSensitive(String input) {
    if (input.isEmpty) return input;
    return input
        .replaceAllMapped(
          RegExp(r'(/realdebrid=)([^&/\s]+)', caseSensitive: false),
          (m) => '${m[1]}[REDACTED]',
        )
        .replaceAllMapped(
          RegExp(r'(https?://)([^:]+):([^@]+)@', caseSensitive: false),
          (m) => '${m[1]}[USER]:[REDACTED]@',
        )
        .replaceAllMapped(
          RegExp(r'(api_key|apikey|token|key|realdebrid|secret|auth|password)(\s*[:=]\s*)([^\s&/]+)', caseSensitive: false),
          (m) => '${m[1]}${m[2]}[REDACTED]',
        )
        .replaceAllMapped(
          RegExp(r'(Bearer\s+)[A-Za-z0-9_\-\.]+', caseSensitive: false),
          (m) => '${m[1]}[REDACTED]',
        );
  }

  /// Specific helper for Stremio addon manifest diagnostics
  void logManifestResult(
    String addonName,
    String manifestUrl, {
    required bool success,
    int? statusCode,
    String? error,
  }) {
    log(
      stage: 'AddonManifest',
      message: success
          ? 'Manifest loaded successfully (${statusCode ?? 200})'
          : 'Manifest fetch failed (${statusCode ?? 'ERR'})',
      provider: addonName,
      streamUrl: manifestUrl,
      severity: success ? LogSeverity.info : LogSeverity.warning,
      details: error,
    );
  }

  /// Specific helper for Stremio stream query diagnostics
  void logStreamRequest(
    String addonName,
    String endpointUrl, {
    required int statusCode,
    required int streamCount,
    String? error,
  }) {
    log(
      stage: 'StreamResolution',
      message: statusCode == 200
          ? 'Retrieved $streamCount stream(s)'
          : 'Stream query failed ($statusCode)',
      provider: addonName,
      streamUrl: endpointUrl,
      severity: statusCode == 200
          ? (streamCount > 0 ? LogSeverity.info : LogSeverity.warning)
          : LogSeverity.error,
      details: error ?? 'Streams: $streamCount',
    );
  }

  /// Specific helper for StreamSource classification diagnostics
  void logClassification(
    String provider,
    String url,
    String detectedType, {
    String? reason,
  }) {
    log(
      stage: 'StreamClassification',
      message: 'Classified as $detectedType',
      provider: provider,
      streamUrl: url,
      details: reason,
    );
  }

  /// Specific helper for Player routing decisions
  void logPlayerRouting(
    String streamType,
    String selectedPlayer, {
    String? provider,
    String? url,
    String? reason,
  }) {
    log(
      stage: 'PlayerRouter',
      message: 'Routed $streamType to $selectedPlayer',
      provider: provider,
      streamUrl: url,
      details: reason,
    );
  }

  /// Specific helper for playback failures
  void logPlaybackFailure(
    String player,
    String errorMessage, {
    String? underlyingCause,
    String? provider,
    String? url,
  }) {
    log(
      stage: 'PlaybackFailure',
      message: '[$player] Playback failed: $errorMessage',
      provider: provider,
      streamUrl: url,
      severity: LogSeverity.error,
      details: underlyingCause,
    );
  }

  /// Formatted copyable diagnostics log export
  String exportFormattedLogs() {
    final buffer = StringBuffer();
    buffer.writeln('=== CinemaHub 2.0 Streaming Diagnostics Log ===');
    buffer.writeln('Generated: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Total Events: ${_events.length}');
    buffer.writeln('------------------------------------------------');
    for (final e in _events) {
      buffer.writeln(e.toString());
    }
    buffer.writeln('================================================');
    return buffer.toString();
  }
}
