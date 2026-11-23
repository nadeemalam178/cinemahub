import '../models/media_request.dart';
import '../models/stream_source.dart';

/// Contract that every source provider adapter must implement.
abstract class SourceProvider {
  /// Unique provider ID (e.g. "stremio_torrentio", "fmhy_vidsrc")
  String get id;

  /// Friendly display name
  String get name;

  /// Whether this provider is enabled by user or configuration
  bool get isEnabled;

  /// Probe provider health / accessibility
  Future<bool> checkHealth();

  /// Resolve streams for the given media request
  Future<List<StreamSource>> resolveStreams(MediaRequest request);
}
