import 'package:flutter/foundation.dart';
import '../models/media_request.dart';
import '../models/source_error.dart';
import '../models/stream_source.dart';

/// Abstract playback engine interface.
abstract class IPlaybackEngine extends ChangeNotifier {
  List<StreamSource> get sources;
  bool get isLoading;
  SourceError? get lastError;

  Future<void> fetchSources(MediaRequest request);
  void clear();
}
