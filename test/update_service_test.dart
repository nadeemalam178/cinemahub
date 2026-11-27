import 'package:cinemahub/core/update/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UpdateService.pickApkAsset', () {
    final releaseAssets = [
      {
        'name': 'app-armeabi-v7a-release.apk',
        'browser_download_url': 'https://example.com/arm32.apk',
        'size': 25000000,
      },
      {
        'name': 'app-arm64-v8a-release.apk',
        'browser_download_url': 'https://example.com/arm64.apk',
        'size': 28000000,
      },
      {
        'name': 'app-x86_64-release.apk',
        'browser_download_url': 'https://example.com/x86_64.apk',
        'size': 30000000,
      },
    ];

    test('selects matching ABI in preference order', () {
      final arm64 = UpdateService.pickApkAsset(
        releaseAssets,
        ['arm64-v8a', 'armeabi-v7a'],
      );
      expect(arm64?['name'], 'app-arm64-v8a-release.apk');

      final arm32 = UpdateService.pickApkAsset(
        releaseAssets,
        ['armeabi-v7a', 'armeabi'],
      );
      expect(arm32?['name'], 'app-armeabi-v7a-release.apk');
    });

    test('falls back to universal or first APK when ABI not matched', () {
      final assetsWithUniversal = [
        ...releaseAssets,
        {'name': 'app-universal-release.apk', 'size': 45000000},
      ];
      final universal = UpdateService.pickApkAsset(assetsWithUniversal, ['riscv64']);
      expect(universal?['name'], 'app-universal-release.apk');

      final fallback = UpdateService.pickApkAsset(releaseAssets, ['riscv64']);
      expect(fallback?['name'], 'app-armeabi-v7a-release.apk');
    });

    test('returns null when no .apk assets exist', () {
      final none = UpdateService.pickApkAsset(
        [{'name': 'checksums.txt'}],
        ['arm64-v8a'],
      );
      expect(none, isNull);
    });
  });

  group('UpdateService.isNewer', () {
    final service = UpdateService();

    test('compares semantic versions and build numbers', () {
      expect(service.isNewer('v1.2.0', '1.1.0+2'), isTrue);
      expect(service.isNewer('1.1.0+3', '1.1.0+2'), isTrue);
      expect(service.isNewer('1.1.0+2', '1.1.0+2'), isFalse);
      expect(service.isNewer('1.0.9', '1.1.0+2'), isFalse);
    });
  });
}
