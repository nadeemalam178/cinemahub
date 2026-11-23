import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:torrent_streamer/torrent_streamer.dart';
import 'dart:async';

import '../diagnostics/streaming_logger.dart';
import '../models/stream_source.dart';

/// Upgraded native video player backed by video_player (ExoPlayer on Android) and Chewie.
/// Fully preserves custom HTTP headers (Referer, Origin, User-Agent), tracks first frame,
/// and handles buffering/retry states gracefully.
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

  bool _isInitializing = true;
  bool _hasFirstFrame = false;
  String? _errorMessage;
  int _retryCount = 0;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    setState(() {
      _isInitializing = true;
      _errorMessage = null;
    });

    String url = widget.source.url ?? '';
    final isMagnet = widget.source.type == StreamType.magnet || url.startsWith('magnet:?');

    if (isMagnet) {
      try {
        if (!TorrentStreamer.isInitialised) {
          await TorrentStreamer.init();
        }
        await TorrentStreamer.start(url);
        final completer = Completer<String>();
        TorrentStreamer.addEventListener('ready', (_) async {
          if (!completer.isCompleted) {
            final streamUrl = await TorrentStreamer.getStreamUrl();
            completer.complete(streamUrl);
          }
        });
        TorrentStreamer.addEventListener('error', (err) {
          if (!completer.isCompleted) {
            completer.completeError(Exception('Torrent failed: $err'));
          }
        });
        url = await completer.future.timeout(const Duration(seconds: 30));
      } catch (e) {
        if (mounted) {
          setState(() {
            _isInitializing = false;
            _errorMessage = 'Torrent streamer error: $e';
          });
        }
        return;
      }
    }

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
      // 1. Map StreamType and URL/MIME hints to explicit VideoFormat for Android Media3/ExoPlayer
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
          lowerUrl.contains('.mp4') ||
          lowerUrl.contains('.mkv') ||
          lowerMime.contains('video/')) {
        formatHint = VideoFormat.other;
      }

      // Sanitize headers map: ensure non-null string keys and values
      final cleanHeaders = <String, String>{};
      widget.source.headers.forEach((key, value) {
        if (key.trim().isNotEmpty && value.trim().isNotEmpty) {
          cleanHeaders[key.trim()] = value.trim();
        }
      });

      // 2. Build controller with forwarded custom HTTP headers and formatHint
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

      // 2. Setup Chewie controller with custom controls
      final aspectRatio = controller.value.aspectRatio;
      _chewieController = ChewieController(
        videoPlayerController: controller,
        autoPlay: true,
        looping: false,
        aspectRatio: aspectRatio > 0 ? aspectRatio : 16 / 9,
        allowFullScreen: true,
        allowMuting: true,
        allowPlaybackSpeedChanging: true,
        deviceOrientationsAfterFullScreen: [
          DeviceOrientation.portraitUp,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
        deviceOrientationsOnEnterFullScreen: [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
        placeholder: Container(color: Colors.black),
        errorBuilder: (context, errorMessage) {
          return _buildErrorWidget(errorMessage);
        },
      );

      controller.addListener(_videoListener);

      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
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

  void _videoListener() {
    final c = _videoPlayerController;
    if (c == null) return;

    // Detect actual first frame rendered: verify decoder has parsed dimensions and started playback
    final hasValidSize = c.value.size.width > 0 && c.value.size.height > 0;
    if (!_hasFirstFrame &&
        c.value.isInitialized &&
        !c.value.isBuffering &&
        (c.value.position > Duration.zero || (c.value.isPlaying && hasValidSize))) {
      _hasFirstFrame = true;
      StreamingLogger.instance.log(
        stage: 'FirstFrame',
        message: 'First video frame rendered successfully (${c.value.size.width.toInt()}x${c.value.size.height.toInt()})',
        provider: widget.source.provider,
        streamUrl: widget.source.url,
      );
      widget.onFirstFrameRendered?.call();
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
      setState(() {
        _errorMessage = err;
      });
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
    _disposeControllers();
    final url = widget.source.url ?? '';
    final isMagnet = widget.source.type == StreamType.magnet || url.startsWith('magnet:?');
    if (isMagnet) {
      try {
        TorrentStreamer.stop();
        TorrentStreamer.dispose();
      } catch (_) {}
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
        child: Chewie(controller: _chewieController!),
      ),
    );
  }

  Widget _buildLoadingWidget() {
    return Center(
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
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Provider: ${widget.source.provider} • ${widget.source.quality ?? "HD"}',
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget(String error) {
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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
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
                const SizedBox(width: 14),
                FilledButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry'),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE50914)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
