/// uBlock Origin filter & anti-redirect rule engine for in-app video streams.
class AdBlockEngine {
  AdBlockEngine._();

  /// Known high-frequency advertising, tracking, popup, and malware redirect domains
  static const List<String> blockedDomainPatterns = [
    r'.*doubleclick\.net.*',
    r'.*googlesyndication\.com.*',
    r'.*google-analytics\.com.*',
    r'.*adservice\.google\..*',
    r'.*popads\.net.*',
    r'.*popcash\.net.*',
    r'.*propellerads\.com.*',
    r'.*adsterra\.com.*',
    r'.*exoclick\.com.*',
    r'.*trafficjunky\..*',
    r'.*betting.*',
    r'.*casino.*',
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
    r'.*vmg\.host.*',
    r'.*delivery.*ad.*',
    r'.*banner.*ad.*',
    r'.*tracking.*',
    r'.*whos\.amung\.us.*',
    r'.*counter\.yadro\.ru.*',
  ];

  /// Checks if a navigation URL should be blocked
  static bool shouldBlockUrl(String url) {
    final lower = url.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return true;
    }
    for (final pattern in blockedDomainPatterns) {
      if (RegExp(pattern).hasMatch(lower)) {
        return true;
      }
    }
    return false;
  }

  /// uBlock Origin style UserScript to neutralize aggressive popups, window.open, and malicious redirects
  /// without accidentally deleting the actual video player iframes or controls.
  static const String antiAdScript = '''
(function() {
  // 1. Prevent aggressive window.open popups & new tab hijacking
  try {
    window.open = function(url, target, features) {
      console.log('[CinemaHub Shield] Blocked window.open popup to:', url);
      return null;
    };
  } catch(e) {}

  // 2. Neutralize unsolicited tab hijacking on outbound ad links
  document.addEventListener('click', function(e) {
    var target = e.target;
    while (target && target.tagName !== 'A' && target.parentElement) {
      target = target.parentElement;
    }
    if (target && target.tagName === 'A') {
      var href = target.getAttribute('href') || '';
      var targetAttr = target.getAttribute('target');

      // Do NOT interfere with internal anchors, player actions or relative paths
      if (href === '#' || href === '' || href.startsWith('javascript:') || href.startsWith('/') || href.startsWith('?')) {
        if (targetAttr === '_blank') {
          target.removeAttribute('target');
        }
        return;
      }

      // Check if genuine outbound third-party domain
      try {
        var linkHost = target.hostname || '';
        if (linkHost && linkHost !== window.location.hostname && !linkHost.endsWith('.' + window.location.hostname)) {
          e.preventDefault();
          e.stopPropagation();
          console.log('[CinemaHub Shield] Blocked outbound ad link click:', href);
        } else if (targetAttr === '_blank') {
          target.removeAttribute('target');
        }
      } catch(err) {}
    }
  }, true);

  // 3. Neutralize alert / confirm / prompt spam
  try {
    window.alert = function() {};
    window.confirm = function() { return false; };
    window.prompt = function() { return null; };
  } catch(e) {}

  // 4. CSS inject to hide ads, banners, and click-jack overlays safely
  try {
    var style = document.createElement('style');
    style.innerHTML = '.ad, .ads, .advert, .advertisement, [id*="banner"], [class*="banner"], [id*="popads"], [class*="popads"], .popunder, [id*="adsterra"] { display: none !important; }';
    document.head.appendChild(style);
  } catch(e) {}

  // 5. Ensure video player frames and elements have pointer events and fullscreen enabled
  try {
    var iframes = document.querySelectorAll('iframe');
    for (var i = 0; i < iframes.length; i++) {
      var ifr = iframes[i];
      ifr.style.pointerEvents = 'auto';
      ifr.setAttribute('allowfullscreen', 'true');
    }
  } catch(e) {}
})();
''';
}
