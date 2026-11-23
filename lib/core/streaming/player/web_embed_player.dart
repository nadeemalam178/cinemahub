import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../player/adblock_engine.dart';
import '../diagnostics/source_health_checker.dart';
import '../diagnostics/streaming_logger.dart';
import '../models/stream_source.dart';

/// Upgraded In-App WebView player for video embeds.
/// Features hardware-accelerated playback, true HTML5 video element detection,
/// ad-shield isolation, orientation/fullscreen synchronization, watchdog timeout,
/// and comprehensive diagnostic health telemetry.
class WebEmbedPlayer extends StatefulWidget {
  const WebEmbedPlayer({
    super.key,
    required this.source,
    required this.title,
    this.onFirstFrameRendered,
    this.onVideoPlaybackStarted,
  });

  final StreamSource source;
  final String title;
  final VoidCallback? onFirstFrameRendered;
  final VoidCallback? onVideoPlaybackStarted;

  @override
  State<WebEmbedPlayer> createState() => _WebEmbedPlayerState();
}

class _WebEmbedPlayerState extends State<WebEmbedPlayer> {
  late final WebViewController _controller;
  bool _isLoading = true;
  double _progress = 0;
  bool _isFullScreen = false;
  bool _hasDetectedVideo = false;
  bool _isVideoPlaying = false;
  double _playbackSeconds = 0;
  String? _errorMessage;
  Timer? _watchdogTimer;

  static const int _watchdogTimeoutSeconds = 20;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _startWatchdogTimer() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer(const Duration(seconds: _watchdogTimeoutSeconds), () {
      if (mounted && !_hasDetectedVideo && _errorMessage == null) {
        final targetUrl = widget.source.url ?? '';
        SourceHealthChecker.instance.recordFailure(
          targetUrl,
          failureType: HealthStatus.timeout,
          error: 'Playback initialization timed out after ${_watchdogTimeoutSeconds}s without video output',
        );
        setState(() {
          _errorMessage =
              'Server took too long to start video playback. The embed source may be temporarily unavailable, restricted, or blocked.';
          _isLoading = false;
        });
      }
    });
  }

  void _initWebView() {
    final targetUrl = widget.source.url ?? '';
    StreamingLogger.instance.log(
      stage: 'WebPlayerInit',
      message: 'Initializing WebView for embed: ${widget.source.provider}',
      provider: widget.source.provider,
      streamUrl: targetUrl,
    );

    _startWatchdogTimer();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        widget.source.headers['User-Agent'] ??
            'Mozilla/5.0 (Linux; Android 13; Pixel 7 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      )
      ..addJavaScriptChannel(
        'CinemaHubPlayback',
        onMessageReceived: (JavaScriptMessage message) {
          _handlePlaybackTelemetry(message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) {
              setState(() {
                _progress = p / 100;
                if (p >= 90) _isLoading = false;
              });
            }
          },
          onPageFinished: (url) async {
            if (mounted) {
              setState(() => _isLoading = false);
            }
            StreamingLogger.instance.log(
              stage: 'WebPageLoaded',
              message: 'Embed container page finished loading',
              provider: widget.source.provider,
              streamUrl: url,
            );

            // Record successful document load
            SourceHealthChecker.instance.recordSuccess(
              widget.source.url ?? '',
              isVideoPlaying: false,
            );

            // Inject ad-blocker and video detection monitor
            try {
              await _controller.runJavaScript(AdBlockEngine.antiAdScript);
              await _controller.runJavaScript(_html5VideoMonitorScript);
            } catch (_) {}
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? true) {
              StreamingLogger.instance.log(
                stage: 'WebResourceError',
                message: 'WebView error: ${error.description}',
                provider: widget.source.provider,
                streamUrl: error.url,
                severity: LogSeverity.warning,
                details: 'Code: ${error.errorCode}',
              );

              final isDns = error.errorCode == -2 || error.description.contains('NAME_NOT_RESOLVED');
              final failureStatus = isDns ? HealthStatus.dnsError : HealthStatus.httpError;

              SourceHealthChecker.instance.recordFailure(
                widget.source.url ?? '',
                failureType: failureStatus,
                error: error.description,
              );

              if (mounted) {
                setState(() {
                  _errorMessage = 'Failed to load player (${error.description})';
                  _isLoading = false;
                });
              }
            }
          },
          onNavigationRequest: (request) {
            final reqUrl = request.url;
            if (reqUrl == targetUrl) {
              return NavigationDecision.navigate;
            }

            // Block ad network requests and popup redirects
            if (AdBlockEngine.shouldBlockUrl(reqUrl)) {
              StreamingLogger.instance.log(
                stage: 'AdBlocked',
                message: 'Blocked outbound popup/redirect request',
                provider: widget.source.provider,
                streamUrl: reqUrl,
              );
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      );

    // Platform-specific settings for Android WebView
    if (_controller.platform is AndroidWebViewController) {
      final androidController = _controller.platform as AndroidWebViewController;
      androidController.setMediaPlaybackRequiresUserGesture(false);
      androidController.setOnConsoleMessage((message) {
        if (message.level == JavaScriptLogLevel.error) {
          StreamingLogger.instance.log(
            stage: 'WebConsoleError',
            message: message.message,
            provider: widget.source.provider,
            severity: LogSeverity.warning,
          );
        }
      });
      androidController.setCustomWidgetCallbacks(
        onShowCustomWidget: (Widget customWidget, OnHideCustomWidgetCallback onHideCustomWidget) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (BuildContext context) => Scaffold(
                backgroundColor: Colors.black,
                body: customWidget,
              ),
              fullscreenDialog: true,
            ),
          );
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
        },
        onHideCustomWidget: () {
          Navigator.of(context).pop();
          if (!_isFullScreen) {
            SystemChrome.setPreferredOrientations([
              DeviceOrientation.portraitUp,
              DeviceOrientation.portraitDown,
            ]);
          }
        },
      );
    }

    _loadRequest();
  }

  void _loadRequest() {
    final targetUrl = widget.source.url ?? '';
    final uri = Uri.tryParse(targetUrl);
    if (uri == null || !uri.hasScheme) {
      setState(() {
        _errorMessage = 'Invalid embed stream URL.';
        _isLoading = false;
      });
      return;
    }

    final headers = Map<String, String>.from(widget.source.headers);
    if (!headers.containsKey('Referer')) {
      headers['Referer'] = '${uri.scheme}://${uri.host}/';
    }
    if (!headers.containsKey('Origin')) {
      headers['Origin'] = '${uri.scheme}://${uri.host}';
    }
    if (!headers.containsKey('User-Agent')) {
      headers['User-Agent'] =
          'Mozilla/5.0 (Linux; Android 13; Pixel 7 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
    }

    _controller.loadRequest(uri, headers: headers);
  }

  void _handlePlaybackTelemetry(String rawJson) {
    try {
      final data = jsonDecode(rawJson) as Map<String, dynamic>;
      final event = data['event'] as String?;

      if (event == 'playing') {
        final currentTime = (data['currentTime'] as num?)?.toDouble() ?? 0.0;
        final duration = (data['duration'] as num?)?.toDouble() ?? 0.0;
        final width = data['width'] as int? ?? 0;
        final height = data['height'] as int? ?? 0;

        if (!_hasDetectedVideo) {
          _hasDetectedVideo = true;
          _watchdogTimer?.cancel();

          // Genuine playback confirmation
          widget.onVideoPlaybackStarted?.call();
          widget.onFirstFrameRendered?.call();

          SourceHealthChecker.instance.recordSuccess(
            widget.source.url ?? '',
            isVideoPlaying: true,
          );

          StreamingLogger.instance.log(
            stage: 'HTML5VideoDetected',
            message: 'HTML5 video element active ($width x $height, ${currentTime.toStringAsFixed(1)}s / ${duration.toStringAsFixed(1)}s)',
            provider: widget.source.provider,
            streamUrl: widget.source.url,
          );
        }

        if (mounted) {
          setState(() {
            _isVideoPlaying = true;
            _playbackSeconds = currentTime;
          });
        }
      } else if (event == 'blocked') {
        final reason = data['reason'] as String? ?? 'Anti-bot challenge detected';
        _watchdogTimer?.cancel();
        SourceHealthChecker.instance.recordFailure(
          widget.source.url ?? '',
          failureType: HealthStatus.blocked,
          error: reason,
        );
        if (mounted) {
          setState(() {
            _errorMessage = 'Embed host blocked playback: $reason';
            _isLoading = false;
          });
        }
      }
    } catch (_) {}
  }

  void _toggleFullScreen() {
    setState(() => _isFullScreen = !_isFullScreen);
    if (_isFullScreen) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  void dispose() {
    _watchdogTimer?.cancel();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    try {
      // Force pause all HTML5 audio/video elements before unloading WebView to prevent background audio leaks
      _controller.runJavaScript('''
        try {
          var els = document.querySelectorAll('video, audio');
          for (var i = 0; i < els.length; i++) {
            els[i].pause();
            els[i].src = '';
            els[i].load();
          }
        } catch(_) {}
      ''');
      _controller.loadRequest(Uri.parse('about:blank'));
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: !_isFullScreen,
        bottom: !_isFullScreen,
        child: Stack(
          children: [
            // 1. WebView Viewport
            if (_errorMessage == null)
              WebViewWidget(controller: _controller)
            else
              _buildErrorView(),

            // 2. Loading Progress Bar
            if (_isLoading && _errorMessage == null)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  backgroundColor: Colors.transparent,
                  color: const Color(0xFFE50914),
                  minHeight: 3,
                ),
              ),

            // 3. Compact Top Control Overlay (Fade out when in full screen)
            if (!_isFullScreen)
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                '${widget.source.provider} • Shield Active',
                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                              if (_isVideoPlaying) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.greenAccent.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'PLAYING ${(_playbackSeconds).toStringAsFixed(0)}s',
                                    style: const TextStyle(
                                      color: Colors.greenAccent,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Toggle Fullscreen',
                      icon: const Icon(Icons.fullscreen_rounded, color: Colors.white),
                      onPressed: _toggleFullScreen,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.signal_wifi_connected_no_internet_4_rounded, size: 48, color: Colors.redAccent),
            const SizedBox(height: 16),
            const Text(
              'Embed Server Unavailable',
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Unable to reach the embedded player host.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                  child: const Text('Back to Servers'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _errorMessage = null;
                      _isLoading = true;
                      _hasDetectedVideo = false;
                      _isVideoPlaying = false;
                    });
                    _startWatchdogTimer();
                    _loadRequest();
                  },
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE50914)),
                  child: const Text('Retry Server'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// JavaScript script injected into embed web document to monitor genuine HTML5 video events
  static const String _html5VideoMonitorScript = '''
(function() {
  function scanAndMonitorVideos() {
    try {
      var videos = document.querySelectorAll('video');
      for (var i = 0; i < videos.length; i++) {
        var v = videos[i];
        if (!v._cinemahub_monitored) {
          v._cinemahub_monitored = true;

          function reportState() {
            if (v.currentTime > 0 && !v.paused && !v.ended) {
              CinemaHubPlayback.postMessage(JSON.stringify({
                event: 'playing',
                currentTime: v.currentTime,
                duration: v.duration || 0,
                width: v.videoWidth || 0,
                height: v.videoHeight || 0
              }));
            }
          }

          v.addEventListener('playing', reportState);
          v.addEventListener('timeupdate', reportState);
          v.addEventListener('canplay', reportState);
        }

        if (v.currentTime > 0 && !v.paused && !v.ended) {
          CinemaHubPlayback.postMessage(JSON.stringify({
            event: 'playing',
            currentTime: v.currentTime,
            duration: v.duration || 0,
            width: v.videoWidth || 0,
            height: v.videoHeight || 0
          }));
        }
      }

      // Check for Cloudflare / anti-bot challenge signatures
      var title = document.title || '';
      var body = document.body ? document.body.innerText : '';
      if (title.indexOf('Just a moment...') !== -1 ||
          body.indexOf('Verify you are human') !== -1 ||
          body.indexOf('Cloudflare Ray ID') !== -1) {
        CinemaHubPlayback.postMessage(JSON.stringify({
          event: 'blocked',
          reason: 'Cloudflare / Anti-bot verification challenge'
        }));
      }
    } catch(err) {}
  }

  scanAndMonitorVideos();
  setInterval(scanAndMonitorVideos, 1500);
})();
''';
}
