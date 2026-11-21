import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../theme/cinemahub_colors.dart';
import 'adblock_engine.dart';

/// In-App Web Player using official webview_flutter with uBlock Origin isolation rules & sandboxed iframe shield.
class InAppAdBlockedPlayer extends StatefulWidget {
  const InAppAdBlockedPlayer({
    super.key,
    required this.url,
    required this.title,
    this.onClose,
  });

  final String url;
  final String title;
  final VoidCallback? onClose;

  @override
  State<InAppAdBlockedPlayer> createState() => _InAppAdBlockedPlayerState();
}

class _InAppAdBlockedPlayerState extends State<InAppAdBlockedPlayer> {
  late final WebViewController _controller;
  bool _loading = true;
  double _progress = 0;
  bool _isFullScreen = false;
  bool _useSandboxedShield = false; // Default to direct load so video embeds get true origin, referer & DOM storage

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 13; Pixel 7 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) {
              setState(() {
                _progress = progress / 100;
                if (progress >= 85) _loading = false;
              });
            }
          },
          onPageFinished: (url) async {
            if (mounted) setState(() => _loading = false);
            // Inject anti-ad & popup neutralizing scripts
            try {
              await _controller.runJavaScript(AdBlockEngine.antiAdScript);
            } catch (_) {}
          },
          onNavigationRequest: (request) {
            // Never block initial target URL
            if (request.url == widget.url) {
              return NavigationDecision.navigate;
            }
            if (AdBlockEngine.shouldBlockUrl(request.url)) {
              debugPrint('[CinemaHub Blocked Ad URL]: ${request.url}');
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );

    // Platform-specific optimizations for Android WebView
    if (_controller.platform is AndroidWebViewController) {
      final androidController = _controller.platform as AndroidWebViewController;
      androidController.setMediaPlaybackRequiresUserGesture(false);
    }

    _loadContent();
  }

  void _loadContent() {
    if (_useSandboxedShield) {
      // Sandboxed Iframe fallback if explicitly toggled by user
      final html = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body { width: 100%; height: 100%; background: #000; overflow: hidden; }
    iframe {
      width: 100%;
      height: 100%;
      border: 0;
      position: absolute;
      top: 0; left: 0; right: 0; bottom: 0;
    }
  </style>
</head>
<body>
  <iframe
    src="${widget.url}"
    allow="autoplay; fullscreen; encrypted-media; picture-in-picture"
    allowfullscreen="true"
    sandbox="allow-scripts allow-same-origin allow-forms allow-presentation"
    referrerpolicy="no-referrer-when-downgrade">
  </iframe>
</body>
</html>
''';
      _controller.loadHtmlString(html);
    } else {
      // Direct load gives the embed player legitimate Origin, Referer, and full access to media decoders & DOMStorage
      final uri = Uri.parse(widget.url);
      final referer = '${uri.scheme}://${uri.host}/';
      _controller.loadRequest(
        uri,
        headers: {
          'Referer': referer,
          'Origin': '${uri.scheme}://${uri.host}',
        },
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
    super.dispose();
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

  void _toggleShield() {
    setState(() {
      _useSandboxedShield = !_useSandboxedShield;
      _loading = true;
    });
    _loadContent();
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
            // 1. WebView
            WebViewWidget(controller: _controller),

            // 2. Loading Indicator & Progress Bar
            if (_loading) ...[
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.black54,
                  valueColor: const AlwaysStoppedAnimation<Color>(CinemahubColors.primary),
                  minHeight: 3,
                ),
              ),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: CinemahubColors.primary),
                      SizedBox(height: 12),
                      Text(
                        '🛡️ Isolating ads & streaming...',
                        style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // 3. Top Floating Glass Header
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      onPressed: () {
                        if (widget.onClose != null) {
                          widget.onClose!();
                        } else {
                          Navigator.of(context).pop();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _useSandboxedShield ? Icons.shield_rounded : Icons.shield_outlined,
                            color: _useSandboxedShield ? Colors.greenAccent : Colors.orangeAccent,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _useSandboxedShield ? 'Zero-Ad Shield' : 'Direct Mode',
                            style: TextStyle(
                              color: _useSandboxedShield ? Colors.greenAccent : Colors.orangeAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Shield Mode Toggle
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: IconButton(
                      tooltip: _useSandboxedShield ? 'Shield Active (Zero Ads)' : 'Direct Mode Active',
                      icon: Icon(
                        _useSandboxedShield ? Icons.security_rounded : Icons.security_update_warning_rounded,
                        color: _useSandboxedShield ? Colors.greenAccent : Colors.orangeAccent,
                        size: 20,
                      ),
                      onPressed: _toggleShield,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Fullscreen button
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: IconButton(
                      icon: Icon(
                        _isFullScreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                        color: Colors.white,
                      ),
                      onPressed: _toggleFullScreen,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
