enum ErrorStage {
  discovery,
  manifest,
  streamResolution,
  urlExtraction,
  playerRouting,
  playerInitialization,
  playbackRuntime,
}

enum ErrorCategory {
  networkTimeout,
  httpError,
  invalidManifest,
  drmProtected,
  unsupportedCodec,
  unsupportedProtocol,
  geoBlocked,
  hosterOffline,
  emptyResponse,
  unknown,
}

/// Structured technical error for stream discovery, resolution, and playback.
class SourceError {
  SourceError({
    required this.provider,
    required this.stage,
    required this.category,
    required this.message,
    this.technicalDetails,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final String provider;
  final ErrorStage stage;
  final ErrorCategory category;
  final String message;
  final String? technicalDetails;
  final DateTime timestamp;

  @override
  String toString() =>
      'SourceError(stage: $stage, category: $category, provider: $provider, msg: $message, details: $technicalDetails)';
}
