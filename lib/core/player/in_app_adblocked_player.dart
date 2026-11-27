import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../theme/cinemahub_colors.dart';
import 'adblock_engine.dart';

/// In-App Web Player backed by `flutter_inappwebview` with native ContentBlockers,
/// multi-frame anti-ad/anti-popunder UserScripts, and optional sandboxed iframe shield.
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
  InAppWebViewController? _controller;
  bool _loading = true;
  double _progress = 0;
  bool _isFullScreen = false;
  bool _useSandboxedShield = false;

  late final InAppWebViewSettings _settings;
  late final UnmodifiableListView<UserScript> _userScripts;

  static const String _defaultUserAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7 Pro) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  @override
  void initState() {
    super.initState();
    _settings = InAppWebViewSettings(
      javaScriptEnabled: true,
      javaScriptCanOpenWindowsAutomatically: false,
      supportMultipleWindows: true,
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      useShouldOverrideUrlLoading: true,
      contentBlockers: AdBlockEngine.buildInAppContentBlockers(),
      userAgent: _defaultUserAgent,
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
    ]);
  }

  Map<String, String> _headersFor(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return const {'User-Agent': _defaultUserAgent};
    }
    return {
      'Referer': '${uri.scheme}://${uri.host}/',
      'Origin': '${uri.scheme}://${uri.host}',
      'User-Agent': _defaultUserAgent,
    };
  }

  void _loadContent() {
    final controller = _controller;
    if (controller == null) return;

    if (_useSandboxedShield) {
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
      controller.loadData(
        data: html,
        baseUrl: WebUri(widget.url),
      );
    } else {
      controller.loadUrl(
        urlRequest: URLRequest(
          url: WebUri(widget.url),
          headers: _headersFor(widget.url),
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
      _controller?.loadUrl(urlRequest: URLRequest(url: WebUri('about:blank')));
    } catch (_) {}
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
    final targetUri = Uri.tryParse(widget.url);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: !_isFullScreen,
        bottom: !_isFullScreen,
        child: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri(widget.url),
                headers: _headersFor(widget.url),
              ),
              initialSettings: _settings,
              initialUserScripts: _userScripts,
              onWebViewCreated: (controller) {
                _controller = controller;
              },
              onProgressChanged: (controller, progress) {
                if (mounted) {
                  setState(() {
                    _progress = progress / 100.0;
                    if (progress >= 85) _loading = false;
                  });
                }
              },
              onLoadStop: (controller, url) {
                if (mounted) setState(() => _loading = false);
              },
              onCreateWindow: (controller, createWindowAction) async {
                return false;
              },
              shouldOverrideUrlLoading: (controller, navigationAction) async {
                final reqUrl = navigationAction.request.url?.toString() ?? '';
                if (reqUrl.isEmpty || reqUrl == widget.url) {
                  return NavigationActionPolicy.ALLOW;
                }
                if (AdBlockEngine.shouldBlockUrl(reqUrl)) {
                  return NavigationActionPolicy.CANCEL;
                }
                if (navigationAction.isForMainFrame && targetUri != null) {
                  final reqHost = navigationAction.request.url?.host.toLowerCase() ?? '';
                  final baseHost = targetUri.host.toLowerCase().replaceFirst('www.', '');
                  final sameSite = reqHost == baseHost ||
                      reqHost.endsWith('.$baseHost') ||
                      baseHost.endsWith('.$reqHost');
                  if (!sameSite) {
                    return NavigationActionPolicy.CANCEL;
                  }
                }
                return NavigationActionPolicy.ALLOW;
              },
            ),

            if (_loading) ...[
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
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
                        'Isolating ads & streaming...',
                        style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],

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
