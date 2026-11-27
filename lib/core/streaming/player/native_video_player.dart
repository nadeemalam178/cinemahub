import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../player/subtitles/subtitle_model.dart';
import '../../player/subtitles/subtitle_overlay.dart';
import '../../player/subtitles/subtitle_picker_sheet.dart';
import '../../player/subtitles/subtitle_service.dart';
import '../../sync/sync_service.dart';
import '../diagnostics/streaming_logger.dart';
import '../models/stream_source.dart';
import 'torrent_channel.dart';

/// Native video player backed by ExoPlayer (`video_player` + `chewie`) and our
/// native Android `libtorrent4j` HTTP range proxy for P2P magnets.
class NativeVideoPlayer extends StatefulWidget {
  const NativeVideoPlayer({
    super.key,
    required this.source,
    this.title,
    this.onFirstFrameRendered,
  });

  final StreamSource source;
  final String? title;
  final VoidCallback? onFirstFrameRendered;

  @override
  State<NativeVideoPlayer> createState() => _NativeVideoPlayerState();
}

class _NativeVideoPlayerState extends State<NativeVideoPlayer> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;

  final SubtitleService _subtitleService = SubtitleService();
  List<CinemaSubtitleTrack> _availableSubtitleTracks = [];
  CinemaSubtitleTrack? _selectedSubtitleTrack;
  List<CinemaSubtitleCue> _activeSubtitleCues = [];
  Duration _subtitleSyncDelay = Duration.zero;
  CinemaSubtitleStyle _subtitleStyle = const CinemaSubtitleStyle();

  StreamSubscription<TorrentProgress>? _torrentSub;
  TorrentProgress? _torrentProgress;
  bool _isTorrentStream = false;

  bool _isInitializing = true;
  bool _hasFirstFrame = false;
  String? _errorMessage;
  int _retryCount = 0;
  DateTime _lastProgressSyncAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    setState(() {
      _isInitializing = true;
      _errorMessage = null;
      _torrentProgress = null;
    });

    String url = widget.source.url ?? '';
    final isMagnet = widget.source.type == StreamType.magnet ||
        url.toLowerCase().startsWith('magnet:?') ||
        (widget.source.infoHash != null && widget.source.infoHash!.isNotEmpty && url.isEmpty);
    _isTorrentStream = isMagnet;

    if (isMagnet) {
      if (url.isEmpty && widget.source.infoHash != null) {
        url = StreamSource.ensureTrackers(
          'magnet:?xt=urn:btih:${widget.source.infoHash}',
        );
      } else {
        url = StreamSource.ensureTrackers(url);
      }

      try {
        final readyCompleter = Completer<void>();
        await _torrentSub?.cancel();
        _torrentSub = TorrentChannel.progressStream.listen((progress) {
          if (!mounted) return;
          setState(() => _torrentProgress = progress);

          if (progress.state == 'error' && !readyCompleter.isCompleted) {
            readyCompleter.completeError(
              Exception(progress.error ?? 'Torrent engine reported an error'),
            );
          } else if (progress.readyForPlayback && !readyCompleter.isCompleted) {
            readyCompleter.complete();
          }
        });

        final startResult = await TorrentChannel.startStream(
          url,
          fileIndex: widget.source.fileIndex,
        );
        url = startResult.streamUrl;

        // Wait for header pieces so ExoPlayer receives immediate HTTP bytes without read-timeouts
        final snapshot = await TorrentChannel.getStatus();
        if (snapshot?.readyForPlayback != true && !readyCompleter.isCompleted) {
          await readyCompleter.future.timeout(
            const Duration(seconds: 90),
            onTimeout: () {
              throw TimeoutException(
                'Timed out waiting for torrent pieces (peers: ${_torrentProgress?.peers ?? 0}).',
              );
            },
          );
        }
      } catch (e) {
        await TorrentChannel.stopStream();
        if (mounted) {
          setState(() {
            _isInitializing = false;
            _errorMessage = 'Torrent playback error: $e';
          });
        }
        return;
      }
    }

    if (!mounted) return;
    final uri = Uri.tryParse(url);

    if (url.isEmpty || uri == null || !uri.hasScheme) {
      final err = 'Invalid or empty video URL: $url';
      StreamingLogger.instance.log(
        stage: 'PlayerInit',
        message: err,
        provider: widget.source.provider,
        severity: LogSeverity.error,
      );
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = err;
        });
      }
      return;
    }

    StreamingLogger.instance.log(
      stage: 'PlayerInit',
      message: 'Initializing ExoPlayer for ${widget.source.type.name}',
      provider: widget.source.provider,
      streamUrl: url,
      details: 'Headers: ${widget.source.headers.keys.toList()}',
    );

    try {
      VideoFormat? formatHint;
      final lowerUrl = url.toLowerCase();
      final lowerMime = (widget.source.mimeType ?? '').toLowerCase();

      if (widget.source.type == StreamType.hls ||
          lowerUrl.contains('.m3u8') ||
          lowerMime.contains('mpegurl') ||
          lowerMime.contains('hls')) {
        formatHint = VideoFormat.hls;
      } else if (widget.source.type == StreamType.dash ||
          lowerUrl.contains('.mpd') ||
          lowerMime.contains('dash')) {
        formatHint = VideoFormat.dash;
      } else if (widget.source.type == StreamType.directHttp ||
          isMagnet ||
          lowerUrl.contains('.mp4') ||
          lowerUrl.contains('.mkv') ||
          lowerMime.contains('video/')) {
        formatHint = VideoFormat.other;
      }

      final cleanHeaders = <String, String>{};
      if (!isMagnet) {
        widget.source.headers.forEach((key, value) {
          if (key.trim().isNotEmpty && value.trim().isNotEmpty) {
            cleanHeaders[key.trim()] = value.trim();
          }
        });
      }

      final controller = VideoPlayerController.networkUrl(
        uri,
        formatHint: formatHint,
        httpHeaders: cleanHeaders,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );

      _videoPlayerController = controller;
      await controller.initialize();

      if (!mounted) {
        controller.dispose();
        return;
      }

      final aspectRatio = controller.value.aspectRatio;
      _chewieController = ChewieController(
        videoPlayerController: controller,
        autoPlay: true,
        looping: false,
        aspectRatio: aspectRatio > 0 ? aspectRatio : 16 / 9,
        allowFullScreen: true,
        allowMuting: true,
        allowPlaybackSpeedChanging: true,
        deviceOrientationsAfterFullScreen: const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
        deviceOrientationsOnEnterFullScreen: const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
        placeholder: Container(color: Colors.black),
        errorBuilder: (context, errorMessage) => _buildErrorWidget(errorMessage),
      );

      controller.addListener(_videoListener);
      unawaited(_fetchSubtitles());

      if (mounted) {
        setState(() => _isInitializing = false);
      }
    } catch (e) {
      StreamingLogger.instance.log(
        stage: 'PlayerInit',
        message: 'Native playback initialization failed',
        provider: widget.source.provider,
        streamUrl: url,
        severity: LogSeverity.error,
        details: e.toString(),
      );

      if (mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = 'Failed to load video stream: $e';
        });
      }
    }
  }

  Future<void> _fetchSubtitles() async {
    try {
      final imdbId = widget.source.metadata['imdb_id'] as String? ??
          widget.source.metadata['imdbId'] as String?;

      final tracks = await _subtitleService.fetchTracks(
        type: widget.source.metadata['type'] as String? ?? 'movie',
        imdbId: imdbId,
        season: widget.source.metadata['season'] as int?,
        episode: widget.source.metadata['episode'] as int?,
      );

      if (mounted) {
        setState(() => _availableSubtitleTracks = tracks);

        final englishTrack = tracks.cast<CinemaSubtitleTrack?>().firstWhere(
              (t) =>
                  t?.languageCode.toLowerCase() == 'en' ||
                  t?.languageCode.toLowerCase() == 'eng',
              orElse: () => tracks.isNotEmpty ? tracks.first : null,
            );

        if (englishTrack != null) {
          _selectSubtitleTrack(englishTrack);
        }
      }
    } catch (_) {}
  }

  Future<void> _selectSubtitleTrack(CinemaSubtitleTrack? track) async {
    if (track == null) {
      if (mounted) {
        setState(() {
          _selectedSubtitleTrack = null;
          _activeSubtitleCues = [];
        });
      }
      return;
    }

    final cues = await _subtitleService.loadCues(track);
    if (mounted) {
      setState(() {
        _selectedSubtitleTrack = track;
        _activeSubtitleCues = cues;
      });
    }
  }

  void _openSubtitlePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => SubtitlePickerSheet(
        tracks: _availableSubtitleTracks,
        selectedTrack: _selectedSubtitleTrack,
        onTrackSelected: _selectSubtitleTrack,
        syncDelay: _subtitleSyncDelay,
        onSyncDelayChanged: (delay) {
          setState(() => _subtitleSyncDelay = delay);
        },
        style: _subtitleStyle,
        onStyleChanged: (style) {
          setState(() => _subtitleStyle = style);
        },
      ),
    );
  }

  void _videoListener() {
    final c = _videoPlayerController;
    if (c == null) return;

    final hasValidSize = c.value.size.width > 0 && c.value.size.height > 0;
    if (!_hasFirstFrame &&
        c.value.isInitialized &&
        !c.value.isBuffering &&
        (c.value.position > Duration.zero || (c.value.isPlaying && hasValidSize))) {
      _hasFirstFrame = true;
      StreamingLogger.instance.log(
        stage: 'FirstFrame',
        message:
            'First video frame rendered (${c.value.size.width.toInt()}x${c.value.size.height.toInt()})',
        provider: widget.source.provider,
        streamUrl: widget.source.url,
      );
      widget.onFirstFrameRendered?.call();
    }

    // Periodically sync playback progress to Firestore via SyncService
    if (c.value.isInitialized && c.value.duration > Duration.zero && c.value.isPlaying) {
      final now = DateTime.now();
      if (now.difference(_lastProgressSyncAt).inSeconds >= 3) {
        _lastProgressSyncAt = now;
        final contentId = widget.source.metadata['contentId'] as String?;
        if (contentId != null && contentId.isNotEmpty) {
          try {
            final sync = context.read<SyncService>();
            final season = widget.source.metadata['season'] as int?;
            final episode = widget.source.metadata['episode'] as int?;
            sync.scheduleProgress(
              contentId: contentId,
              positionSeconds: c.value.position.inSeconds.toDouble(),
              durationSeconds: c.value.duration.inSeconds.toDouble(),
              episodeId: (season != null && episode != null) ? 'S${season}E$episode' : null,
              title: widget.title,
              type: widget.source.metadata['type'] as String?,
              posterUrl: widget.source.metadata['posterUrl'] as String?,
              releaseDate: widget.source.metadata['releaseDate'] as String?,
              rating: (widget.source.metadata['rating'] as num?)?.toDouble(),
            );
          } catch (_) {
            // SyncService not mounted in diagnostics-only widget tree
          }
        }
      }
    }

    if (c.value.hasError && mounted) {
      final err = c.value.errorDescription ?? 'Unknown ExoPlayer error.';
      StreamingLogger.instance.log(
        stage: 'PlaybackRuntime',
        message: 'ExoPlayer runtime error',
        provider: widget.source.provider,
        streamUrl: widget.source.url,
        severity: LogSeverity.error,
        details: err,
      );
      setState(() => _errorMessage = err);
    }
  }

  void _retry() {
    _disposeControllers();
    _retryCount++;
    StreamingLogger.instance.log(
      stage: 'PlayerRetry',
      message: 'Retrying playback (Attempt #$_retryCount)',
      provider: widget.source.provider,
      streamUrl: widget.source.url,
    );
    _initializePlayer();
  }

  void _disposeControllers() {
    _videoPlayerController?.removeListener(_videoListener);
    try {
      _chewieController?.pause();
      _videoPlayerController?.pause();
    } catch (_) {}
    _chewieController?.dispose();
    _chewieController = null;

    _videoPlayerController?.dispose();
    _videoPlayerController = null;
  }

  @override
  void dispose() {
    _torrentSub?.cancel();
    _disposeControllers();
    if (_isTorrentStream) {
      unawaited(TorrentChannel.stopStream());
    }
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return _buildErrorWidget(_errorMessage!);
    }

    if (_isInitializing || _chewieController == null) {
      return _buildLoadingWidget();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Chewie(controller: _chewieController!),

            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: _videoPlayerController!,
              builder: (context, value, _) {
                return SubtitleOverlay(
                  cues: _activeSubtitleCues,
                  position: value.position,
                  syncDelay: _subtitleSyncDelay,
                  style: _subtitleStyle,
                );
              },
            ),

            // Live P2P Torrent Telemetry Pill
            if (_isTorrentStream && _torrentProgress != null)
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    'P2P ${_torrentProgress!.bufferPercent.toStringAsFixed(0)}% • '
                    '${_torrentProgress!.formattedDownloadSpeed} • '
                    '${_torrentProgress!.peers} peers',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

            // Subtitles CC Quick Access
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(
                    _selectedSubtitleTrack != null
                        ? Icons.subtitles_rounded
                        : Icons.subtitles_outlined,
                    color: _selectedSubtitleTrack != null
                        ? const Color(0xFFE50914)
                        : Colors.white70,
                    size: 22,
                  ),
                  tooltip: 'Subtitles & Captions',
                  onPressed: _openSubtitlePicker,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingWidget() {
    final p = _torrentProgress;
    String statusText = 'Provider: ${widget.source.provider} • ${widget.source.quality ?? "HD"}';
    if (_isTorrentStream) {
      if (p == null || p.state == 'resolving_metadata') {
        statusText = 'Connecting to DHT & Trackers for magnet metadata…';
      } else {
        statusText =
            'Buffering P2P • ${p.bufferPercent.toStringAsFixed(1)}% • '
            '${p.formattedDownloadSpeed} • ${p.peers} peers (${p.seeds} seeds)';
      }
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Color(0xFFE50914),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              widget.title ?? 'Connecting to media stream…',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              statusText,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            if (_isTorrentStream && p != null && p.fileName.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                p.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
            if (_isTorrentStream) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: 220,
                child: LinearProgressIndicator(
                  value: (p != null && p.bufferPercent > 0)
                      ? (p.bufferPercent / 100.0).clamp(0.0, 1.0)
                      : null,
                  color: const Color(0xFF8B5CF6),
                  backgroundColor: Colors.white12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget(String error) {
    final rawUrl = widget.source.url ?? '';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline_rounded, size: 48, color: Colors.redAccent),
            ),
            const SizedBox(height: 18),
            const Text(
              'Playback Failed',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.3),
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Back to Sources'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white30),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry'),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE50914)),
                ),
                if (rawUrl.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () async {
                      final uri = Uri.tryParse(rawUrl);
                      if (uri != null) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Open in External App'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
