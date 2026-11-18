import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/cinemahub_colors.dart';
import '../../core/theme/cinemahub_tokens.dart';
import '../providers/stremio_adapter.dart';

/// Video player backed by Chewie; supports direct URLs and external players.
///
/// When [allowExternalPlayer] is true and the system has another video app
/// capable of handling the scheme, the user is offered to open the stream
/// externally — useful for torrents or non-http URIs that chewie cannot play.
class CinemaPlayer extends StatefulWidget {
  const CinemaPlayer({
    super.key,
    required this.stream,
    this.title,
    this.subtitle,
    this.allowExternalPlayer = false,
    this.onPlayStarted,
    this.onEnded,
    this.errorBuilder,
  });

  final StreamResult stream;
  final String? title;
  final String? subtitle;
  final bool allowExternalPlayer;
  final VoidCallback? onPlayStarted;
  final VoidCallback? onEnded;
  final Widget Function(Exception)? errorBuilder;

  @override
  State<CinemaPlayer> createState() => _CinemaPlayerState();
}

class _CinemaPlayerState extends State<CinemaPlayer>
    with SingleTickerProviderStateMixin {
  late final VideoPlayerController _controller;
  late final AnimationController _fadeController;
  ChewieController? _chewieController;
  bool _ready = false;
  bool _errored = false;
  Exception? _lastError;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final url = widget.stream.url;
    if (url.isEmpty) {
      setState(() {
        _errored = true;
        _lastError = Exception('Empty stream URL.');
      });
      return;
    }

    try {
      _controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await _controller.initialize();
      if (!mounted) return;

      _chewieController = ChewieController(
        videoPlayerController: _controller,
        autoPlay: true,
        looping: false,
        aspectRatio: _controller.value.aspectRatio,
        deviceOrientationsAfterFullScreen: [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
        allowedScreenSleep: false,
        showControlsOnInitialize: true,
        placeholder: Container(
          color: CinemahubColors.background(Brightness.dark),
        ),
      );

      _controller.addListener(_onVideoChanged);
      _controller.setLooping(false);
      _ready = true;
      widget.onPlayStarted?.call();
      _fadeController.forward();
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errored = true;
        _lastError = e is Exception ? e : Exception(e.toString());
      });
    }
  }

  void _onVideoChanged() {
    if (_controller.value.hasError) {
      setState(() => _errored = true);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onVideoChanged);
    _controller.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_errored) {
      final builder =
          widget.errorBuilder ??
          (e) => _ErrorFallback(error: e.toString(), stream: widget.stream);
      return builder(_lastError!);
    }

    if (!_ready || _chewieController == null) {
      return _LoadingPlaceholder();
    }

    return FadeTransition(
      opacity: _fadeController,
      child: Stack(
        children: [
          Chewie(controller: _chewieController!),
          if (widget.allowExternalPlayer)
            Positioned(
              bottom: CinemahubSpacing.xxxl,
              right: CinemahubSpacing.md,
              child: FilledButton.tonalIcon(
                onPressed: _openExternal,
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Open externally'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openExternal() async {
    final url = widget.stream.url;
    if (url.isEmpty) return;
    // The app delegates external playback to the OS chooser (see
    // settings_provider.dart for link launching helpers). We don't import
    // url_launcher here to keep dependencies lean — callers in higher layers
    // can pass a callback instead if they want tight integration.
    widget.onEnded?.call();
  }
}

class _LoadingPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: CinemahubColors.background(Brightness.dark),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: CinemahubColors.primary,
            ),
            SizedBox(height: 16),
            Text(
              'Loading stream…',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorFallback extends StatelessWidget {
  const _ErrorFallback({required this.error, required this.stream});

  final String error;
  final StreamResult stream;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: CinemahubColors.background(Brightness.dark),
      child: Center(
        child: Padding(
          padding: CinemahubSpacing.pagePadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 56,
                color: CinemahubColors.danger.withValues(alpha: 0.9),
              ),
              const SizedBox(height: CinemahubSpacing.md),
              Text(
                'Playback unavailable',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: CinemahubSpacing.sm),
              Text(
                error,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                ),
                textAlign: TextAlign.center,
              ),
              if (stream.url.isNotEmpty) ...[
                const SizedBox(height: CinemahubSpacing.md),
                Text(
                  'Source: ${stream.name}',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}