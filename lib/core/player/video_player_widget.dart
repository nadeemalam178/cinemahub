import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:torrent_streamer/torrent_streamer.dart';

import '../../core/providers/stremio_adapter.dart';
import '../../core/theme/cinemahub_colors.dart';
import '../../core/theme/cinemahub_tokens.dart';
import 'in_app_adblocked_player.dart';
import 'm3u8_interceptor.dart';

class CinemaPlayer extends StatefulWidget {
  const CinemaPlayer({
    super.key,
    required this.stream,
    this.allowExternalPlayer = true,
    this.onEnded,
    this.onPlayStarted,
    this.errorBuilder,
  });

  final StreamResult stream;
  final bool allowExternalPlayer;
  final VoidCallback? onEnded;
  final VoidCallback? onPlayStarted;
  final Widget Function(Exception error)? errorBuilder;

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
  bool _fallbackToEmbed = false;
  String? _statusText;

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
    String url = widget.stream.url;
    Uri? uri = Uri.tryParse(url);
    if (url.isEmpty || uri == null || !uri.hasScheme) {
      if (mounted) {
        setState(() {
          _errored = true;
          _lastError = Exception('Invalid or empty stream URL.');
        });
      }
      return;
    }

    final isWebEmbed = widget.stream.behaviorHints?['isWebEmbed'] == true;
    final isMagnet = widget.stream.type == 'application/x-bittorrent' || widget.stream.behaviorHints?['isTorrent'] == true || url.startsWith('magnet:');

    try {
      final rawHeaders = widget.stream.behaviorHints?['headers'];
      final headers = <String, String>{};
      if (rawHeaders is Map) {
        for (final entry in rawHeaders.entries) {
          headers[entry.key.toString()] = entry.value.toString();
        }
      }

      if (isMagnet) {
        if (mounted) setState(() => _statusText = 'Starting Torrent Streamer...');

        await TorrentStreamer.init();
        await TorrentStreamer.start(url);

        final completer = Completer<String>();
        TorrentStreamer.addEventListener('ready', (_) async {
           if (!completer.isCompleted) {
             final streamUrl = await TorrentStreamer.getStreamUrl();
             completer.complete(streamUrl);
           }
        });
        TorrentStreamer.addEventListener('error', (err) {
           if (!completer.isCompleted) completer.completeError(Exception('Torrent failed: $err'));
        });

        // Wait up to 30 seconds for buffering
        url = await completer.future.timeout(const Duration(seconds: 30));
        uri = Uri.parse(url);

      } else if (isWebEmbed) {
        if (mounted) setState(() => _statusText = 'Bypassing Ads & Extracting Video...');
        final extractedUrl = await M3u8Interceptor.extract(url, headers: headers);
        if (extractedUrl != null && extractedUrl.isNotEmpty) {
          url = extractedUrl;
          uri = Uri.parse(url);
        } else {
          // Fallback to web embed
          if (mounted) {
            setState(() {
              _fallbackToEmbed = true;
              _ready = true;
            });
          }
          return;
        }
      }

      if (mounted) setState(() => _statusText = 'Connecting to Video Stream...');

      final controller = VideoPlayerController.networkUrl(
        uri,
        httpHeaders: headers,
      );
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
    final isMagnet = widget.stream.type == 'application/x-bittorrent' || widget.stream.behaviorHints?['isTorrent'] == true || widget.stream.url.startsWith('magnet:');
    if (isMagnet && TorrentStreamer.isInitialised) {
       try {
         TorrentStreamer.stop();
         TorrentStreamer.dispose();
       } catch (_) {}
    }
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
    if (_fallbackToEmbed && isWebEmbed) {
      return InAppAdBlockedPlayer(
        url: widget.stream.url,
        title: widget.stream.name,
        onClose: () => Navigator.of(context).pop(),
      );
    }

    if (!_ready || _chewieController == null) {
      return Container(
        color: CinemahubColors.background(Brightness.dark),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                color: CinemahubColors.primary,
              ),
              const SizedBox(height: 16),
              Text(
                _statusText ?? 'Loading stream...',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    return FadeTransition(
      opacity: _fadeController,
      child: Chewie(
        controller: _chewieController!,
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
                'Playback Failed',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: CinemahubSpacing.sm),
              Text(
                error,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                    ),
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              if (allowExternal) ...[
                const SizedBox(height: CinemahubSpacing.xl),
                FilledButton.icon(
                  onPressed: onOpenExternal,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Open External Player'),
                  style: FilledButton.styleFrom(
                    backgroundColor: CinemahubColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
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
