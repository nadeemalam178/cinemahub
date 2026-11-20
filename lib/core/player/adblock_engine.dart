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
  static const String antiAdScript = '''
(function() {
  // 1. Prevent aggressive window.open popups
  window.open = function(url, target, features) {
    console.log('[CinemaHub uBlock] Blocked window.open popup attempt to:', url);
    return null;
  };

  // 2. Neutralize unsolicited tab hijacking on element clicks
  document.addEventListener('click', function(e) {
    var target = e.target;
    while (target && target.tagName !== 'A' && target.parentElement) {
      target = target.parentElement;
    }
    if (target && target.tagName === 'A') {
      var href = target.getAttribute('href');
      var targetAttr = target.getAttribute('target');
      if (targetAttr === '_blank' || (href && !href.startsWith('javascript:') && !href.includes(window.location.hostname))) {
        e.preventDefault();
        e.stopPropagation();
        console.log('[CinemaHub uBlock] Blocked outbound ad link click:', href);
      }
    }
  }, true);

  // 3. Neutralize alert / confirm / prompt spam
  window.alert = function() {};
  window.confirm = function() { return false; };
  window.prompt = function() { return null; };

  // 4. CSS inject to hide ads and click-jack overlays
  var style = document.createElement('style');
  style.innerHTML = '.ad, .ads, .advert, .advertisement, [id*="banner"], [class*="banner"], [id*="pop"], [class*="pop"], div[style*="z-index: 2147483647"], div[style*="z-index: 999999"] { display: none !important; }';
  document.head.appendChild(style);

  // 5. Periodically remove transparent clickjack overlays
  setInterval(function() {
    var overlays = document.querySelectorAll('div, a, iframe');
    for (var i = 0; i < overlays.length; i++) {
      var el = overlays[i];
      var z = window.getComputedStyle(el).zIndex;
      var pos = window.getComputedStyle(el).position;
      if ((pos === 'fixed' || pos === 'absolute') && parseInt(z, 10) > 1000) {
        if (!el.querySelector('video')) {
          el.remove();
        }
      }
    }
  }, 1000);
})();
''';
}
