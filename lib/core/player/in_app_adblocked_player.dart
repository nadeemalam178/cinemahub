import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../theme/cinemahub_colors.dart';
import 'adblock_engine.dart';

/// In-App Web Player with built-in uBlock Origin ad-blocking rules & popup shields.
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
  bool _loading = true;
  double _progress = 0;
  bool _isFullScreen = false;

  @override
  void initState() {
    super.initState();
    // Default to landscape for cinematic video experience if desired, or user can toggle
  }

  @override
  void dispose() {
    // Restore orientations and system overlays on exit
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: !_isFullScreen,
        bottom: !_isFullScreen,
        child: Stack(
          children: [
            // 1. InAppWebView with uBlock Origin blockers & UserScript
            InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(widget.url)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                useHybridComposition: true,
                supportMultipleWindows: false, // Drop popup windows
                javaScriptCanOpenWindowsAutomatically: false, // Drop window.open ads
                contentBlockers: AdBlockEngine.getContentBlockers(),
                userAgent:
                    'Mozilla/5.0 (Linux; Android 13; Pixel 7 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
              ),
              onWebViewCreated: (controller) {},
              onProgressChanged: (controller, progress) {
                setState(() {
                  _progress = progress / 100;
                  if (progress >= 95) _loading = false;
                });
              },
              onLoadStop: (controller, url) async {
                setState(() => _loading = false);
                // Inject uBlock Origin anti-ad/anti-popup script
                await controller.evaluateJavascript(source: AdBlockEngine.antiAdScript);
              },
              onCreateWindow: (controller, createWindowAction) async {
                // Drop all popup windows created by video providers
                return false;
              },
              shouldOverrideUrlLoading: (controller, navigationAction) async {
                final uri = navigationAction.request.url;
                if (uri == null) return NavigationActionPolicy.CANCEL;

                final urlString = uri.toString().toLowerCase();

                // Drop malicious schemes
                if (!urlString.startsWith('http://') && !urlString.startsWith('https://')) {
                  return NavigationActionPolicy.CANCEL;
                }

                // Check against uBlock ad domains
                for (final pattern in AdBlockEngine.blockedDomainPatterns) {
                  if (RegExp(pattern).hasMatch(urlString)) {
                    debugPrint('[uBlock Blocked Ad Navigation]: $urlString');
                    return NavigationActionPolicy.CANCEL;
                  }
                }

                return NavigationActionPolicy.ALLOW;
              },
            ),

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
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: CinemahubColors.primary),
                    SizedBox(height: 12),
                    Text(
                      'Filtering ads & preparing stream...',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],

            // 3. Top Cinematic Floating Header (Back & Fullscreen controls)
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
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
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.shield_rounded, color: Colors.greenAccent, size: 16),
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
                          const Text(
                            'uBlock Shield',
                            style: TextStyle(
                              color: Colors.greenAccent,
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
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
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
