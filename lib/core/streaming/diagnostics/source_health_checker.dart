import 'package:dio/dio.dart';
import 'streaming_logger.dart';

/// Health status states for streaming servers and embed mirrors
enum HealthStatus {
  unknown,      // Not yet probed
  probing,      // Probe in progress
  pageLoaded,   // Web page returned HTTP 200/300, but video element not yet verified
  videoPlaying, // Confirmed HTML5 video playback active with advancing time
  timeout,      // Network request timed out
  blocked,      // Cloudflare / anti-bot challenge or 403 Forbidden
  dnsError,     // Hostname could not be resolved
  httpError,    // HTTP 4xx / 5xx error
}

/// Comprehensive health record for a single streaming source domain or URL
class SourceHealthRecord {
  SourceHealthRecord({
    required this.target,
    required this.domain,
    this.status = HealthStatus.unknown,
    this.consecutiveFailures = 0,
    this.consecutiveSuccesses = 0,
    this.lastStatusCode,
    this.responseTimeMs = 0,
    DateTime? lastCheck,
    this.errorMessage,
    this.hasVerifiedPlayback = false,
  }) : lastCheck = lastCheck ?? DateTime.now();

  final String target;
  final String domain;
  final HealthStatus status;
  final int consecutiveFailures;
  final int consecutiveSuccesses;
  final int? lastStatusCode;
  final int responseTimeMs;
  final DateTime lastCheck;
  final String? errorMessage;
  final bool hasVerifiedPlayback;

  /// A source is usable unless it has experienced 3+ consecutive persistent failures
  bool get isUsable => consecutiveFailures < 3;

  /// Whether the page is currently in a healthy reachable state
  bool get isHealthy =>
      status == HealthStatus.pageLoaded || status == HealthStatus.videoPlaying;

  SourceHealthRecord copyWith({
    HealthStatus? status,
    int? consecutiveFailures,
    int? consecutiveSuccesses,
    int? lastStatusCode,
    int? responseTimeMs,
    DateTime? lastCheck,
    String? errorMessage,
    bool? hasVerifiedPlayback,
  }) {
    return SourceHealthRecord(
      target: target,
      domain: domain,
      status: status ?? this.status,
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
      consecutiveSuccesses: consecutiveSuccesses ?? this.consecutiveSuccesses,
      lastStatusCode: lastStatusCode ?? this.lastStatusCode,
      responseTimeMs: responseTimeMs ?? this.responseTimeMs,
      lastCheck: lastCheck ?? this.lastCheck,
      errorMessage: errorMessage ?? this.errorMessage,
      hasVerifiedPlayback: hasVerifiedPlayback ?? this.hasVerifiedPlayback,
    );
  }

  @override
  String toString() =>
      '$domain: [${status.name}] (fails: $consecutiveFailures, success: $consecutiveSuccesses, ${responseTimeMs}ms)';
}

/// Result of an individual probe execution
class HealthCheckResult {
  const HealthCheckResult({
    required this.target,
    required this.isReachable,
    required this.status,
    required this.statusCode,
    required this.responseTimeMs,
    this.errorMessage,
  });

  final String target;
  final bool isReachable;
  final HealthStatus status;
  final int statusCode;
  final int responseTimeMs;
  final String? errorMessage;

  @override
  String toString() =>
      '$target: ${isReachable ? 'REACHABLE [${status.name}] (${responseTimeMs}ms)' : 'FAILED ($errorMessage)'}';
}

/// Centralized health monitor and latency tracker for streaming servers and web embeds.
/// Distinguishes page-load from confirmed video playback, tracks progressive failure states,
/// avoids permanently blacklisting temporary glitches, and redacts sensitive credentials.
class SourceHealthChecker {
  SourceHealthChecker({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 6),
              followRedirects: true,
              maxRedirects: 5,
            ));

  final Dio _dio;
  final Map<String, SourceHealthRecord> _records = {};

  static final SourceHealthChecker instance = SourceHealthChecker();

  /// Retrieve current record or generate default record for target URL
  SourceHealthRecord getRecord(String url) {
    final domain = _extractDomain(url);
    return _records[domain] ??
        SourceHealthRecord(
          target: url,
          domain: domain,
          status: HealthStatus.unknown,
        );
  }

  /// Record verified successful page load or video playback event
  void recordSuccess(
    String url, {
    bool isVideoPlaying = false,
    int? responseTimeMs,
  }) {
    final domain = _extractDomain(url);
    final current = getRecord(url);

    final updated = current.copyWith(
      status: isVideoPlaying ? HealthStatus.videoPlaying : HealthStatus.pageLoaded,
      consecutiveFailures: 0,
      consecutiveSuccesses: current.consecutiveSuccesses + 1,
      hasVerifiedPlayback: isVideoPlaying || current.hasVerifiedPlayback,
      responseTimeMs: responseTimeMs ?? current.responseTimeMs,
      lastCheck: DateTime.now(),
      errorMessage: null,
    );

    _records[domain] = updated;

    StreamingLogger.instance.log(
      stage: 'SourceHealth',
      message: isVideoPlaying
          ? 'Source verified playing: $domain'
          : 'Source page loaded: $domain',
      provider: domain,
      streamUrl: url,
      details: 'Success count: ${updated.consecutiveSuccesses}',
    );
  }

  /// Record failure with specific failure category
  void recordFailure(
    String url, {
    required HealthStatus failureType,
    int? statusCode,
    String? error,
  }) {
    final domain = _extractDomain(url);
    final current = getRecord(url);
    final cleanError = error != null ? StreamingLogger.redactSensitive(error) : null;

    final updated = current.copyWith(
      status: failureType,
      consecutiveFailures: current.consecutiveFailures + 1,
      consecutiveSuccesses: 0,
      lastStatusCode: statusCode,
      lastCheck: DateTime.now(),
      errorMessage: cleanError,
    );

    _records[domain] = updated;

    StreamingLogger.instance.log(
      stage: 'SourceHealth',
      message: 'Source failed (${failureType.name}): $domain',
      provider: domain,
      streamUrl: url,
      severity: updated.isUsable ? LogSeverity.warning : LogSeverity.error,
      details: 'Failures: ${updated.consecutiveFailures}. $cleanError',
    );
  }

  /// Execute an active network probe against a server endpoint
  Future<HealthCheckResult> probe(String url, {Map<String, String>? headers}) async {
    final domain = _extractDomain(url);
    final sw = Stopwatch()..start();

    try {
      final requestHeaders = <String, String>{
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13; Pixel 7 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        'Referer': 'https://$domain/',
        'Origin': 'https://$domain',
        ...?headers,
      };

      final res = await _dio.get(
        url,
        options: Options(
          validateStatus: (status) => status != null && status < 600,
          headers: requestHeaders,
        ),
      );
      sw.stop();

      final code = res.statusCode ?? 0;
      HealthStatus status;
      bool isReachable;
      String? errorMsg;

      if (code >= 200 && code < 400) {
        status = HealthStatus.pageLoaded;
        isReachable = true;
      } else if (code == 403 || code == 429) {
        status = HealthStatus.blocked;
        isReachable = false;
        errorMsg = 'Host blocked request (HTTP $code)';
      } else {
        status = HealthStatus.httpError;
        isReachable = false;
        errorMsg = 'HTTP status $code';
      }

      final result = HealthCheckResult(
        target: url,
        isReachable: isReachable,
        status: status,
        statusCode: code,
        responseTimeMs: sw.elapsedMilliseconds,
        errorMessage: errorMsg,
      );

      if (isReachable) {
        recordSuccess(url, responseTimeMs: sw.elapsedMilliseconds);
      } else {
        recordFailure(url, failureType: status, statusCode: code, error: errorMsg);
      }

      return result;
    } on DioException catch (dioErr) {
      sw.stop();
      HealthStatus failureStatus;
      if (dioErr.type == DioExceptionType.connectionTimeout ||
          dioErr.type == DioExceptionType.receiveTimeout) {
        failureStatus = HealthStatus.timeout;
      } else if (dioErr.message != null &&
          (dioErr.message!.contains('Failed host lookup') ||
              dioErr.message!.contains('SocketException'))) {
        failureStatus = HealthStatus.dnsError;
      } else {
        failureStatus = HealthStatus.httpError;
      }

      final errorMsg = StreamingLogger.redactSensitive(dioErr.message ?? dioErr.toString());
      recordFailure(url, failureType: failureStatus, error: errorMsg);

      return HealthCheckResult(
        target: url,
        isReachable: false,
        status: failureStatus,
        statusCode: dioErr.response?.statusCode ?? 0,
        responseTimeMs: sw.elapsedMilliseconds,
        errorMessage: errorMsg,
      );
    } catch (e) {
      sw.stop();
      final errorMsg = StreamingLogger.redactSensitive(e.toString());
      recordFailure(url, failureType: HealthStatus.httpError, error: errorMsg);

      return HealthCheckResult(
        target: url,
        isReachable: false,
        status: HealthStatus.httpError,
        statusCode: 0,
        responseTimeMs: sw.elapsedMilliseconds,
        errorMessage: errorMsg,
      );
    }
  }

  void reset(String url) {
    _records.remove(_extractDomain(url));
  }

  void clearAll() {
    _records.clear();
  }

  static String _extractDomain(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.host.isNotEmpty) {
        return uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
      }
    } catch (_) {}
    return url;
  }
}
