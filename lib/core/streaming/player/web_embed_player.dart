import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../player/adblock_engine.dart';
import '../diagnostics/source_health_checker.dart';
import '../diagnostics/streaming_logger.dart';
import '../models/stream_source.dart';
import 'native_video_player.dart';

/// In-App WebView player for FMHY and web embeds backed by `flutter_inappwebview`.
///
/// Ad-free enforcement layers:
/// 1. Native `ContentBlocker`s blocking third-party ad/tracker requests & hiding overlays
/// 2. Multi-frame `AT_DOCUMENT_START` `UserScript` blocking `window.open`, popunders,
///    clickjack overlays, and third-party anchor redirects across all iframes
/// 3. `supportMultipleWindows: true` + `onCreateWindow => false` cancelling popups natively
/// 4. Top-frame redirect guard in `shouldOverrideUrlLoading`
/// 5. Network + JS stream sniffer detecting `.m3u8` / `.mpd` / `.mp4` media URLs so users
///    can upgrade directly into the ad-free `NativeVideoPlayer` with captured headers.
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
  InAppWebViewController? _controller;
  bool _isLoading = true;
  double _progress = 0;
  bool _isFullScreen = false;
  bool _hasDetectedVideo = false;
  bool _isVideoPlaying = false;
  double _playbackSeconds = 0;
  int _blockedCount = 0;
  String? _errorMessage;
  String? _sniffedStreamUrl;
  String? _sniffedStreamType;

  late final InAppWebViewSettings _webViewSettings;
  late final UnmodifiableListView<UserScript> _userScripts;

  static const String _defaultUserAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7 Pro) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  @override
  void initState() {
    super.initState();
    final ua = widget.source.headers['User-Agent'] ?? _defaultUserAgent;

    _webViewSettings = InAppWebViewSettings(
      javaScriptEnabled: true,
      javaScriptCanOpenWindowsAutomatically: false,
      supportMultipleWindows: true,
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      useOnLoadResource: true,
      useShouldOverrideUrlLoading: true,
      contentBlockers: AdBlockEngine.buildInAppContentBlockers(),
      userAgent: ua,
      thirdPartyCookiesEnabled: true,
      domStorageEnabled: true,
      databaseEnabled: true,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
      supportZoom: false,
    );

    _userScripts = UnmodifiableListView<UserScript>([
      UserScript(
        source: AdBlockEngine.antiAdScript,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: false,
      ),
      UserScript(
        source: _html5VideoMonitorScript,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
        forMainFrameOnly: false,
      ),
    ]);

    StreamingLogger.instance.log(
      stage: 'WebPlayerInit',
      message: 'Initializing InAppWebView shield for: ${widget.source.provider}',
      provider: widget.source.provider,
      streamUrl: widget.source.url,
    );
  }

  Map<String, String> _buildRequestHeaders() {
    final targetUrl = widget.source.url ?? '';
    final uri = Uri.tryParse(targetUrl);
    final headers = Map<String, String>.from(widget.source.headers);
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
      headers.putIfAbsent('Referer', () => '${uri.scheme}://${uri.host}/');
      headers.putIfAbsent('Origin', () => '${uri.scheme}://${uri.host}');
    }
    headers.putIfAbsent('User-Agent', () => _defaultUserAgent);
    return headers;
  }

  void _maybeCaptureMediaUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return;
    if (AdBlockEngine.shouldBlockUrl(trimmed)) return;

    final lower = trimmed.toLowerCase();
    // Ignore short ad/thumbnail/sprite paths
    if (lower.contains('favicon') || lower.contains('.vtt') || lower.contains('.srt')) {
      return;
    }

    String? detectedType;
    if (RegExp(r'\.m3u8(\?|$|#)', caseSensitive: false).hasMatch(lower)) {
      detectedType = 'HLS';
    } else if (RegExp(r'\.mpd(\?|$|#)', caseSensitive: false).hasMatch(lower)) {
      detectedType = 'DASH';
    } else if (RegExp(r'\.(mp4|mkv|webm)(\?|$|#)', caseSensitive: false).hasMatch(lower)) {
      detectedType = 'MP4';
    }

    if (detectedType == null) return;
    if (_sniffedStreamUrl == trimmed) return;

    // Prefer HLS/DASH master streams over bare MP4 fallbacks
    if (_sniffedStreamUrl != null &&
        (_sniffedStreamType == 'HLS' || _sniffedStreamType == 'DASH') &&
        detectedType == 'MP4') {
      return;
    }

    StreamingLogger.instance.log(
      stage: 'StreamSniffer',
      message: 'Captured native $detectedType stream from embed',
      provider: widget.source.provider,
      streamUrl: trimmed,
    );

    if (mounted) {
      setState(() {
        _sniffedStreamUrl = trimmed;
        _sniffedStreamType = detectedType;
      });
    }
  }

  Future<void> _upgradeToNativePlayer() async {
    final streamUrl = _sniffedStreamUrl;
    if (streamUrl == null || streamUrl.isEmpty) return;

    // Pause embedded WebView video before handing over to ExoPlayer
    try {
      await _controller?.evaluateJavascript(source: '''
        try {
          var els = document.querySelectorAll('video, audio');
          for (var i = 0; i < els.length; i++) { els[i].pause(); }
        } catch(_) {}
      ''');
    } catch (_) {}

    final streamType = _sniffedStreamType == 'HLS'
        ? StreamType.hls
        : (_sniffedStreamType == 'DASH' ? StreamType.dash : StreamType.directHttp);

    final headers = _buildRequestHeaders();
    final currentWebUrl = await _controller?.getUrl();
    if (currentWebUrl != null && currentWebUrl.host.isNotEmpty) {
      headers['Referer'] = '${currentWebUrl.scheme}://${currentWebUrl.host}/';
      headers['Origin'] = '${currentWebUrl.scheme}://${currentWebUrl.host}';
    }

    final nativeSource = widget.source.copyWith(
      url: streamUrl,
      type: streamType,
      mimeType: streamType == StreamType.hls
          ? 'application/x-mpegURL'
          : (streamType == StreamType.dash ? 'application/dash+xml' : 'video/mp4'),
      headers: headers,
      metadata: {
        ...widget.source.metadata,
        'isWebEmbed': false,
        'isDirectHttp': true,
      },
    );

    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          body: NativeVideoPlayer(
            source: nativeSource,
            title: widget.title,
            onFirstFrameRendered: widget.onFirstFrameRendered,
          ),
        ),
      ),
    );
  }

  void _handlePlaybackTelemetry(dynamic rawMessage) {
    try {
      final Map<String, dynamic> data;
      if (rawMessage is String) {
        data = jsonDecode(rawMessage) as Map<String, dynamic>;
      } else if (rawMessage is Map) {
        data = Map<String, dynamic>.from(rawMessage);
      } else {
        return;
      }

      final event = data['event'] as String?;

      if (event == 'playing') {
        final currentTime = (data['currentTime'] as num?)?.toDouble() ?? 0.0;
        final duration = (data['duration'] as num?)?.toDouble() ?? 0.0;
        final width = (data['width'] as num?)?.toInt() ?? 0;
        final height = (data['height'] as num?)?.toInt() ?? 0;

        if (!_hasDetectedVideo) {
          _hasDetectedVideo = true;
          widget.onVideoPlaybackStarted?.call();
          widget.onFirstFrameRendered?.call();

          SourceHealthChecker.instance.recordSuccess(
            widget.source.url ?? '',
            isVideoPlaying: true,
          );

          StreamingLogger.instance.log(
            stage: 'HTML5VideoDetected',
            message:
                'HTML5 video active (${width}x$height, ${currentTime.toStringAsFixed(1)}s / ${duration.toStringAsFixed(1)}s)',
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

  void _reloadEmbed() {
    final targetUrl = widget.source.url ?? '';
    setState(() {
      _errorMessage = null;
      _isLoading = true;
      _hasDetectedVideo = false;
      _isVideoPlaying = false;
      _sniffedStreamUrl = null;
      _sniffedStreamType = null;
    });
    if (targetUrl.isNotEmpty) {
      _controller?.loadUrl(
        urlRequest: URLRequest(
          url: WebUri(targetUrl),
          headers: _buildRequestHeaders(),
        ),
      );
    }
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    try {
      _controller?.evaluateJavascript(source: '''
        try {
          if (window.__cinemahubMonitorTimer) {
            clearInterval(window.__cinemahubMonitorTimer);
          }
          var els = document.querySelectorAll('video, audio');
          for (var i = 0; i < els.length; i++) {
            els[i].pause();
            els[i].src = '';
            els[i].load();
          }
        } catch(_) {}
      ''');
      _controller?.loadUrl(urlRequest: URLRequest(url: WebUri('about:blank')));
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final targetUrl = widget.source.url ?? '';
    final targetUri = Uri.tryParse(targetUrl);

    if (targetUri == null || !targetUri.hasScheme) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: _buildErrorView(overrideMessage: 'Invalid embed stream URL.'),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: !_isFullScreen,
        bottom: !_isFullScreen,
        child: Stack(
          children: [
            // 1. Ad-Blocked InAppWebView Viewport
            if (_errorMessage == null)
              InAppWebView(
                initialUrlRequest: URLRequest(
                  url: WebUri(targetUrl),
                  headers: _buildRequestHeaders(),
                ),
                initialSettings: _webViewSettings,
                initialUserScripts: _userScripts,
                onWebViewCreated: (controller) {
                  _controller = controller;
                  controller.addJavaScriptHandler(
                    handlerName: 'CinemaHubPlayback',
                    callback: (args) {
                      if (args.isNotEmpty) {
                        _handlePlaybackTelemetry(args.first);
                      }
                    },
                  );
                  controller.addJavaScriptHandler(
                    handlerName: 'CinemaHubStreamSniffer',
                    callback: (args) {
                      if (args.isNotEmpty && args.first is Map) {
                        final map = args.first as Map;
                        final sniffed = map['url'] as String?;
                        if (sniffed != null) {
                          _maybeCaptureMediaUrl(sniffed);
                        }
                      }
                    },
                  );
                },
                onProgressChanged: (controller, progress) {
                  if (mounted) {
                    setState(() {
                      _progress = progress / 100.0;
                      if (progress >= 90) _isLoading = false;
                    });
                  }
                },
                onLoadStop: (controller, url) async {
                  if (mounted) {
                    setState(() => _isLoading = false);
                  }
                  StreamingLogger.instance.log(
                    stage: 'WebPageLoaded',
                    message: 'Embed container finished loading',
                    provider: widget.source.provider,
                    streamUrl: url?.toString(),
                  );
                  SourceHealthChecker.instance.recordSuccess(
                    targetUrl,
                    isVideoPlaying: _isVideoPlaying,
                  );
                },
                onLoadResource: (controller, resource) {
                  final resUrl = resource.url?.toString();
                  if (resUrl != null) {
                    _maybeCaptureMediaUrl(resUrl);
                  }
                },
                onCreateWindow: (controller, createWindowAction) async {
                  final popupUrl = createWindowAction.request.url?.toString() ?? 'popup';
                  if (mounted) {
                    setState(() => _blockedCount++);
                  }
                  StreamingLogger.instance.log(
                    stage: 'PopupBlocked',
                    message: 'Cancelled new window / popunder attempt',
                    provider: widget.source.provider,
                    streamUrl: popupUrl,
                  );
                  return false;
                },
                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  final reqUrl = navigationAction.request.url?.toString() ?? '';
                  if (reqUrl.isEmpty || reqUrl == targetUrl) {
                    return NavigationActionPolicy.ALLOW;
                  }

                  if (AdBlockEngine.shouldBlockUrl(reqUrl)) {
                    if (mounted) {
                      setState(() => _blockedCount++);
                    }
                    StreamingLogger.instance.log(
                      stage: 'AdBlocked',
                      message: 'Blocked ad/tracker navigation',
                      provider: widget.source.provider,
                      streamUrl: reqUrl,
                    );
                    return NavigationActionPolicy.CANCEL;
                  }

                  // Prevent main-frame hijacks onto unrelated third-party domains
                  if (navigationAction.isForMainFrame) {
                    final reqHost = navigationAction.request.url?.host.toLowerCase() ?? '';
                    final baseHost = targetUri.host.toLowerCase().replaceFirst('www.', '');
                    final sameSite = reqHost == baseHost ||
                        reqHost.endsWith('.$baseHost') ||
                        baseHost.endsWith('.$reqHost');
                    if (!sameSite) {
                      if (mounted) {
                        setState(() => _blockedCount++);
                      }
                      StreamingLogger.instance.log(
                        stage: 'RedirectBlocked',
                        message: 'Blocked top-frame redirect to $reqHost',
                        provider: widget.source.provider,
                        streamUrl: reqUrl,
                      );
                      return NavigationActionPolicy.CANCEL;
                    }
                  }

                  return NavigationActionPolicy.ALLOW;
                },
                onReceivedError: (controller, request, error) {
                  if (request.isForMainFrame ?? true) {
                    StreamingLogger.instance.log(
                      stage: 'WebResourceError',
                      message: 'WebView error: ${error.description}',
                      provider: widget.source.provider,
                      streamUrl: request.url.toString(),
                      severity: LogSeverity.warning,
                      details: 'Type: ${error.type}',
                    );
                    final isDns = error.description.contains('NAME_NOT_RESOLVED') ||
                        error.type == WebResourceErrorType.HOST_LOOKUP;
                    SourceHealthChecker.instance.recordFailure(
                      targetUrl,
                      failureType: isDns ? HealthStatus.dnsError : HealthStatus.httpError,
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
                onEnterFullscreen: (controller) {
                  if (mounted) setState(() => _isFullScreen = true);
                  SystemChrome.setPreferredOrientations([
                    DeviceOrientation.landscapeLeft,
                    DeviceOrientation.landscapeRight,
                  ]);
                  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
                },
                onExitFullscreen: (controller) {
                  if (mounted) setState(() => _isFullScreen = false);
                  SystemChrome.setPreferredOrientations([
                    DeviceOrientation.portraitUp,
                    DeviceOrientation.portraitDown,
                    DeviceOrientation.landscapeLeft,
                    DeviceOrientation.landscapeRight,
                  ]);
                  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
                },
              )
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

            // 3. Compact Top Control Overlay (Hidden in fullscreen)
            if (!_isFullScreen)
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withValues(alpha: 0.72),
                        Colors.black.withValues(alpha: 0.35),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 4),
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
                                Flexible(
                                  child: Text(
                                    '${widget.source.provider} • Shield${_blockedCount > 0 ? " ($_blockedCount blocked)" : " Active"}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                                  ),
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
                                      'PLAYING ${_playbackSeconds.toStringAsFixed(0)}s',
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
                      if (_sniffedStreamUrl != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: FilledButton.icon(
                            onPressed: _upgradeToNativePlayer,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(Icons.hd_rounded, size: 15),
                            label: Text(
                              'Native $_sniffedStreamType',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
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
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView({String? overrideMessage}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.signal_wifi_connected_no_internet_4_rounded,
                size: 48, color: Colors.redAccent),
            const SizedBox(height: 16),
            const Text(
              'Embed Server Unavailable',
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              overrideMessage ?? _errorMessage ?? 'Unable to reach the embedded player host.',
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
                  onPressed: _reloadEmbed,
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

  static const String _html5VideoMonitorScript = r'''
(function() {
  if (window.__cinemahubMonitorInstalled) return;
  window.__cinemahubMonitorInstalled = true;

  function sendTelemetry(payload) {
    try {
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler('CinemaHubPlayback', payload);
      }
    } catch (_) {}
  }

  function scanAndMonitorVideos() {
    try {
      var videos = document.querySelectorAll('video');
      for (var i = 0; i < videos.length; i++) {
        var v = videos[i];
        if (!v._cinemahub_monitored) {
          v._cinemahub_monitored = true;
          (function(videoEl) {
            function reportState() {
              if (videoEl.currentTime > 0 && !videoEl.paused && !videoEl.ended) {
                sendTelemetry({
                  event: 'playing',
                  currentTime: videoEl.currentTime,
                  duration: videoEl.duration || 0,
                  width: videoEl.videoWidth || 0,
                  height: videoEl.videoHeight || 0
                });
              }
            }
            videoEl.addEventListener('playing', reportState);
            videoEl.addEventListener('timeupdate', reportState);
            videoEl.addEventListener('canplay', reportState);
          })(v);
        }

        if (v.currentTime > 0 && !v.paused && !v.ended) {
          sendTelemetry({
            event: 'playing',
            currentTime: v.currentTime,
            duration: v.duration || 0,
            width: v.videoWidth || 0,
            height: v.videoHeight || 0
          });
        }
      }

      var title = document.title || '';
      var body = document.body ? document.body.innerText : '';
      if (title.indexOf('Just a moment...') !== -1 ||
          body.indexOf('Verify you are human') !== -1 ||
          body.indexOf('Cloudflare Ray ID') !== -1) {
        sendTelemetry({
          event: 'blocked',
          reason: 'Cloudflare / Anti-bot verification challenge'
        });
      }
    } catch (_) {}
  }

  scanAndMonitorVideos();
  window.__cinemahubMonitorTimer = setInterval(scanAndMonitorVideos, 1500);
})();
''';
}
