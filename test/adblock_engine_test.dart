import 'package:cinemahub/core/player/adblock_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdBlockEngine.shouldBlockUrl', () {
    test('blocks known ad networks, popunders, and VAST paths', () {
      expect(AdBlockEngine.shouldBlockUrl('https://googleads.g.doubleclick.net/pagead/ads'), isTrue);
      expect(AdBlockEngine.shouldBlockUrl('https://serve.popads.net/c?a=1'), isTrue);
      expect(AdBlockEngine.shouldBlockUrl('https://pl12345.adsterra.com/invoke.js'), isTrue);
      expect(AdBlockEngine.shouldBlockUrl('https://cdn.example.com/vast/tag.xml'), isTrue);
    });

    test('blocks non-HTTP dangerous or empty schemes', () {
      expect(AdBlockEngine.shouldBlockUrl(''), isTrue);
      expect(AdBlockEngine.shouldBlockUrl('javascript:alert(1)'), isTrue);
      expect(AdBlockEngine.shouldBlockUrl('intent://open/#Intent;end'), isTrue);
    });

    test('allows legitimate embed hosts, blob media, and CDN streams', () {
      expect(AdBlockEngine.shouldBlockUrl('https://vidsrc.to/embed/movie/550'), isFalse);
      expect(AdBlockEngine.shouldBlockUrl('https://vidlink.pro/movie/550'), isFalse);
      expect(AdBlockEngine.shouldBlockUrl('blob:https://vidlink.pro/1234-5678'), isFalse);
      expect(AdBlockEngine.shouldBlockUrl('about:blank'), isFalse);
      // Must not false-positive on harmless query words like "tracking="
      expect(
        AdBlockEngine.shouldBlockUrl('https://cdn.example.com/master.m3u8?tracking=1'),
        isFalse,
      );
    });
  });
}
