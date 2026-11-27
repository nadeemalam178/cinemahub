import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// uBlock Origin filter, anti-redirect, and media stream sniffer engine for in-app web embeds.
class AdBlockEngine {
  AdBlockEngine._();

  /// Known high-frequency advertising, tracking, popup, VAST, and malware redirect domains.
  /// Scoped to real ad/tracker hosts so legitimate CDN/video URLs are never false-positived.
  static const List<String> blockedDomainPatterns = [
    r'.*doubleclick\.net.*',
    r'.*googlesyndication\.com.*',
    r'.*google-analytics\.com.*',
    r'.*googletagmanager\.com.*',
    r'.*adservice\.google\..*',
    r'.*popads\.net.*',
    r'.*popcash\.net.*',
    r'.*propellerads\.com.*',
    r'.*adsterra\.com.*',
    r'.*profitablegatecpm\.com.*',
    r'.*highperformanceformat\.com.*',
    r'.*effectivegatecpm\.com.*',
    r'.*exoclick\.com.*',
    r'.*trafficjunky\..*',
    r'.*1xbet.*',
    r'.*monetag\.com.*',
    r'.*adnxs\.com.*',
    r'.*criteo\.com.*',
    r'.*scorecardresearch\.com.*',
    r'.*quantserve\.com.*',
    r'.*outbrain\.com.*',
    r'.*taboola\.com.*',
    r'.*mgid\.com.*',
    r'.*revcontent\.com.*',
    r'.*disqus\.com.*',
    r'.*chatango\.com.*',
    r'.*histats\.com.*',
    r'.*onclickperformance\.com.*',
    r'.*syndication\.exdynsrv\.com.*',
    r'.*a-ads\.com.*',
    r'.*coin-hive\.com.*',
    r'.*crypto-loot\.com.*',
    r'.*onclickads\.net.*',
    r'.*juicyads\.com.*',
    r'.*ero-advertising\.com.*',
    r'.*adkeeper\.co.*',
    r'.*adtrue\.com.*',
    r'.*hilltopads\.net.*',
    r'.*richaudience\.com.*',
    r'.*whos\.amung\.us.*',
    r'.*counter\.yadro\.ru.*',
    r'.*acscdn\.com.*',
    r'.*alwingulla\.com.*',
    r'.*bidswitch\.net.*',
    r'.*dtscout\.com.*',
    r'.*magsrv\.com.*',
    r'.*pubfuture\.com.*',
    r'.*realsrv\.com.*',
    r'.*rtmark\.net.*',
    r'.*tapioni\.com.*',
    r'.*tsyndicate\.com.*',
    r'.*/vast[/?].*',
    r'.*yandex\.ru/metrika.*',
  ];

  static final List<RegExp> _compiledBlockedPatterns =
      blockedDomainPatterns.map((p) => RegExp(p, caseSensitive: false)).toList();

  /// Checks if a navigation or resource URL should be blocked.
  static bool shouldBlockUrl(String url) {
    final lower = url.trim().toLowerCase();
    if (lower.isEmpty) return true;
    if (lower.startsWith('blob:') || lower == 'about:blank') return false;
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return true;
    }
    for (final regex in _compiledBlockedPatterns) {
      if (regex.hasMatch(lower)) {
        return true;
      }
    }
    return false;
  }

  /// Build native WebView ContentBlockers for `flutter_inappwebview`.
  /// Blocks third-party ad/tracker network requests at the WebView engine layer
  /// and hides intrusive overlay/banner selectors cleanly.
  static List<ContentBlocker> buildInAppContentBlockers() {
    final blockers = <ContentBlocker>[
      for (final pattern in blockedDomainPatterns)
        ContentBlocker(
          trigger: ContentBlockerTrigger(urlFilter: pattern),
          action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
        ),
      ContentBlocker(
        trigger: ContentBlockerTrigger(urlFilter: '.*'),
        action: ContentBlockerAction(
          type: ContentBlockerActionType.CSS_DISPLAY_NONE,
          selector:
              '.ad, .ads, .advert, .advertisement, .ad-overlay, .popunder, '
              '[id*="popads"], [class*="popads"], [id*="adsterra"], '
              '[id*="propeller"], ins.adsbygoogle',
        ),
      ),
    ];
    return blockers;
  }

  /// Multi-frame AT_DOCUMENT_START UserScript that:
  /// 1. Neutralizes window.open popups & popunders (returning a dummy window proxy)
  /// 2. Removes transparent full-screen clickjack overlays before clicks reach them
  /// 3. Intercepts anchor clicks & HTMLAnchorElement.prototype.click redirects
  /// 4. Sniffs real .m3u8 / .mpd / .mp4 media URLs from fetch, XHR, and <video> tags
  static const String antiAdScript = r'''
(function() {
  if (window.__cinemahubShieldInstalled) return;
  window.__cinemahubShieldInstalled = true;

  var STREAM_RE = /\.(m3u8|mpd|mp4|mkv|webm)(\?|$|#)/i;
  var BLOCKED_RE = /(doubleclick|googlesyndication|google-analytics|googletagmanager|popads|popcash|propellerads|adsterra|profitablegatecpm|highperformanceformat|effectivegatecpm|exoclick|trafficjunky|monetag|adnxs|criteo|outbrain|taboola|mgid|revcontent|onclickads|juicyads|hilltopads|acscdn|tsyndicate|realsrv|magsrv|\/vast[/?])/i;
  var reportedUrls = Object.create(null);

  function reportStream(rawUrl, source) {
    try {
      if (!rawUrl || typeof rawUrl !== 'string') return;
      var u = rawUrl.trim();
      if (u.indexOf('http') !== 0 && u.indexOf('//') !== 0) return;
      if (u.indexOf('//') === 0) u = window.location.protocol + u;
      if (BLOCKED_RE.test(u)) return;
      if (!STREAM_RE.test(u)) return;
      if (reportedUrls[u]) return;
      reportedUrls[u] = true;
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler('CinemaHubStreamSniffer', {
          url: u,
          source: source || 'dom',
          pageUrl: window.location.href
        });
      }
    } catch (_) {}
  }

  // 1. Dummy window proxy so scripts calling window.open(...) don't fallback to top-frame redirect
  function createFakeWindow() {
    var noop = function() {};
    return {
      closed: false,
      focus: noop,
      blur: noop,
      close: noop,
      postMessage: noop,
      document: { write: noop, open: noop, close: noop },
      location: { href: 'about:blank', replace: noop, assign: noop }
    };
  }

  try {
    Object.defineProperty(window, 'open', {
      value: function(url) {
        console.log('[CinemaHub Shield] Blocked window.open:', url);
        return createFakeWindow();
      },
      writable: false,
      configurable: true
    });
  } catch (_) {
    try {
      window.open = function() { return createFakeWindow(); };
    } catch (__) {}
  }

  // 2. Neutralize programmatic anchor.click() popunders to third-party domains
  try {
    var origAnchorClick = HTMLAnchorElement.prototype.click;
    HTMLAnchorElement.prototype.click = function() {
      try {
        var href = this.getAttribute('href') || '';
        var host = this.hostname || '';
        if (BLOCKED_RE.test(href) ||
            (host && host !== window.location.hostname && !host.endsWith('.' + window.location.hostname))) {
          console.log('[CinemaHub Shield] Blocked programmatic anchor click:', href);
          return;
        }
      } catch (_) {}
      return origAnchorClick.apply(this, arguments);
    };
  } catch (_) {}

  // 3. Neutralize clickjack overlays & popunder triggers before user gestures bubble
  function isClickjackOverlay(el) {
    try {
      if (!el || el === document.body || el === document.documentElement) return false;
      if (el.tagName === 'VIDEO' || el.tagName === 'IFRAME') return false;
      if (el.querySelector && el.querySelector('video')) return false;
      var style = window.getComputedStyle(el);
      if (!style) return false;
      var pos = style.position;
      var z = parseInt(style.zIndex || '0', 10);
      var opacity = parseFloat(style.opacity || '1');
      var rect = el.getBoundingClientRect();
      var coversMost = rect.width >= window.innerWidth * 0.65 && rect.height >= window.innerHeight * 0.55;
      if ((pos === 'fixed' || pos === 'absolute') && coversMost && (opacity <= 0.1 || z >= 9999)) {
        // Check if it looks like an invisible ad trap (empty or single anchor/div without player controls)
        var textLen = (el.innerText || '').trim().length;
        if (opacity <= 0.1 || textLen === 0) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  function shieldPointerEvent(e) {
    try {
      var target = e.target;
      if (isClickjackOverlay(target)) {
        e.preventDefault();
        e.stopImmediatePropagation();
        target.style.pointerEvents = 'none';
        target.style.display = 'none';
        console.log('[CinemaHub Shield] Removed invisible overlay trap');
        return;
      }

      var cur = target;
      while (cur && cur.tagName !== 'A' && cur.parentElement) {
        cur = cur.parentElement;
      }
      if (cur && cur.tagName === 'A') {
        var href = cur.getAttribute('href') || '';
        var targetAttr = cur.getAttribute('target');
        if (href === '#' || href === '' || href.indexOf('javascript:') === 0 ||
            href.indexOf('/') === 0 || href.indexOf('?') === 0) {
          if (targetAttr === '_blank') cur.removeAttribute('target');
          return;
        }
        var linkHost = cur.hostname || '';
        if (BLOCKED_RE.test(href) ||
            (linkHost && linkHost !== window.location.hostname && !linkHost.endsWith('.' + window.location.hostname))) {
          e.preventDefault();
          e.stopImmediatePropagation();
          console.log('[CinemaHub Shield] Blocked outbound ad click:', href);
        } else if (targetAttr === '_blank') {
          cur.removeAttribute('target');
        }
      }
    } catch (_) {}
  }

  document.addEventListener('pointerdown', shieldPointerEvent, true);
  document.addEventListener('touchstart', shieldPointerEvent, true);
  document.addEventListener('mousedown', shieldPointerEvent, true);
  document.addEventListener('click', shieldPointerEvent, true);

  // 4. Neutralize alert / confirm / prompt / beforeunload spam
  try {
    window.alert = function() {};
    window.confirm = function() { return false; };
    window.prompt = function() { return null; };
    window.onbeforeunload = null;
  } catch (_) {}

  // 5. Inject safe CSS rules to collapse ad banners without hiding players
  function injectShieldCss() {
    try {
      var root = document.head || document.documentElement;
      if (!root || document.getElementById('__cinemahub_shield_css')) return;
      var style = document.createElement('style');
      style.id = '__cinemahub_shield_css';
      style.textContent =
        '.ad, .ads, .advert, .advertisement, .ad-overlay, .popunder, ' +
        '[id*="popads"], [class*="popads"], [id*="adsterra"], [id*="propeller"], ins.adsbygoogle ' +
        '{ display: none !important; pointer-events: none !important; }';
      root.appendChild(style);
    } catch (_) {}
  }
  injectShieldCss();
  document.addEventListener('DOMContentLoaded', injectShieldCss);

  // 6. Sniff fetch / XHR / <video> streams to upgrade embeds into NativeVideoPlayer
  try {
    if (window.fetch) {
      var origFetch = window.fetch;
      window.fetch = function(input) {
        try {
          var u = typeof input === 'string' ? input : (input && input.url);
          if (u) reportStream(u, 'fetch');
        } catch (_) {}
        return origFetch.apply(this, arguments);
      };
    }
  } catch (_) {}

  try {
    var origXhrOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url) {
      try {
        if (url) reportStream(url.toString(), 'xhr');
      } catch (_) {}
      return origXhrOpen.apply(this, arguments);
    };
  } catch (_) {}

  function scanMediaNodes() {
    try {
      var videos = document.querySelectorAll('video, source');
      for (var i = 0; i < videos.length; i++) {
        var el = videos[i];
        var src = el.currentSrc || el.src || el.getAttribute('src');
        if (src) reportStream(src, 'video');
      }
      var iframes = document.querySelectorAll('iframe');
      for (var j = 0; j < iframes.length; j++) {
        iframes[j].style.pointerEvents = 'auto';
        iframes[j].setAttribute('allowfullscreen', 'true');
      }
    } catch (_) {}
  }
  document.addEventListener('DOMContentLoaded', scanMediaNodes);
  setInterval(scanMediaNodes, 1500);
})();
''';
}
