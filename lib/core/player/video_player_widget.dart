import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';

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
  VideoPlayerController? _controller;
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
    final uri = Uri.tryParse(url);
    if (url.isEmpty || uri == null || !uri.hasScheme) {
      if (mounted) {
        setState(() {
          _errored = true;
          _lastError = Exception('Invalid or empty stream URL.');
        });
      }
      return;
    }

    // If stream is marked as an FMHY Web Embed or external viewer, launch immediately
    final isWebEmbed = widget.stream.behaviorHints?['isWebEmbed'] == true;
    if (isWebEmbed) {
      if (mounted) {
        setState(() {
          _ready = true;
        });
      }
      return;
    }

    try {
      final controller = VideoPlayerController.networkUrl(uri);
      _controller = controller;
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }

      final ratio = controller.value.aspectRatio;
      _chewieController = ChewieController(
        videoPlayerController: controller,
        autoPlay: true,
        looping: false,
        aspectRatio: ratio > 0 ? ratio : 16 / 9,
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

      controller.addListener(_onVideoChanged);
      controller.setLooping(false);
      if (mounted) {
        setState(() {
          _ready = true;
        });
      }
      widget.onPlayStarted?.call();
      _fadeController.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errored = true;
        _lastError = e is Exception ? e : Exception(e.toString());
      });
    }
  }

  void _onVideoChanged() {
    final c = _controller;
    if (c != null && c.value.hasError) {
      if (mounted) setState(() => _errored = true);
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onVideoChanged);
    _controller?.dispose();
    _chewieController?.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_errored) {
      final builder =
          widget.errorBuilder ??
          (e) => _ErrorFallback(
                error: e.toString(),
                stream: widget.stream,
                allowExternal: widget.allowExternalPlayer,
                onOpenExternal: _openExternal,
              );
      return builder(_lastError ?? Exception('Playback failed.'));
    }

    final isWebEmbed = widget.stream.behaviorHints?['isWebEmbed'] == true;
    if (isWebEmbed) {
      return Container(
        color: CinemahubColors.darkBackground,
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: CinemahubColors.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_circle_fill_rounded,
                  size: 64,
                  color: CinemahubColors.primary,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                widget.title ?? 'Watch Content',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: CinemahubColors.gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: CinemahubColors.gold.withValues(alpha: 0.4)),
                ),
                child: Text(
                  widget.stream.name,
                  style: const TextStyle(
                    color: CinemahubColors.gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: CinemahubColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _openExternal,
                icon: const Icon(Icons.open_in_browser_rounded, size: 20),
                label: const Text(
                  'Launch Stream Player',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      );
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
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('CinemaPlayer: external player launch failed: $e');
    }
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
  const _ErrorFallback({
    required this.error,
    required this.stream,
    this.allowExternal = false,
    this.onOpenExternal,
  });

  final String error;
  final StreamResult stream;
  final bool allowExternal;
  final VoidCallback? onOpenExternal;

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
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
              if (allowExternal && stream.url.isNotEmpty) ...[
                const SizedBox(height: CinemahubSpacing.lg),
                FilledButton.tonalIcon(
                  onPressed: onOpenExternal,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Try opening externally'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
