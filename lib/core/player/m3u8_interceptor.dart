import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class M3u8Interceptor {
  static Future<String?> extract(String embedUrl, {Map<String, String>? headers}) async {
    final completer = Completer<String?>();
    HeadlessInAppWebView? headlessWebView;

    headlessWebView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(
        url: WebUri(embedUrl),
        headers: headers,
      ),
      initialSettings: InAppWebViewSettings(
        userAgent: 'Mozilla/5.0 (Linux; Android 13; Pixel 7 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        mediaPlaybackRequiresUserGesture: false,
        javaScriptEnabled: true,
      ),
      onLoadResource: (controller, resource) {
        final url = resource.url?.toString();
        if (url != null && (url.contains('.m3u8') || url.contains('.mp4'))) {
          // Exclude blank or tracking URLs
          if (url.startsWith('http') && !url.contains('ad') && !url.contains('tracking')) {
            if (!completer.isCompleted) {
              debugPrint('Intercepted direct media link: $url');
              completer.complete(url);
            }
          }
        }
      },
      onLoadStop: (controller, url) async {
        // Wait a few seconds for JS to trigger video load
        await Future.delayed(const Duration(seconds: 4));
        if (!completer.isCompleted) completer.complete(null);
      },
      onReceivedError: (controller, req, error) {
         if (!completer.isCompleted && req.isForMainFrame) {
            completer.complete(null);
         }
      },
      onReceivedHttpError: (controller, req, resp) {
         if (!completer.isCompleted && req.isForMainFrame) {
            completer.complete(null);
         }
      }
    );

    try {
      await headlessWebView.run();
      final result = await completer.future.timeout(const Duration(seconds: 12), onTimeout: () => null);
      await headlessWebView.dispose();
      return result;
    } catch (e) {
      debugPrint('M3u8Interceptor error: $e');
      return null;
    }
  }
}
