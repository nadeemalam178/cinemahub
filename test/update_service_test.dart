import 'package:flutter_test/flutter_test.dart';
import 'package:cinemahub/core/update/update_service.dart';

void main() {
  group('UpdateService Version Comparison', () {
    final updateService = UpdateService();

    test('correctly identifies newer versions', () {
      expect(updateService.isNewer('1.1.0', '1.0.0'), isTrue);
      expect(updateService.isNewer('1.0.1', '1.0.0'), isTrue);
      expect(updateService.isNewer('2.0.0', '1.9.9'), isTrue);
      expect(updateService.isNewer('v1.1.0', 'v1.0.0'), isTrue);
      expect(updateService.isNewer('1.1.0+2', '1.1.0+1'), isTrue);
    });

    test('correctly identifies equal or older versions', () {
      expect(updateService.isNewer('1.0.0', '1.0.0'), isFalse);
      expect(updateService.isNewer('1.0.0', '1.1.0'), isFalse);
      expect(updateService.isNewer('1.0.0+1', '1.0.0+2'), isFalse);
      expect(updateService.isNewer('0.9.0', '1.0.0'), isFalse);
    });

    test('handles tag prefixes cleanly', () {
      expect(UpdateService.cleanVersion('v1.2.3'), equals('1.2.3'));
      expect(UpdateService.cleanVersion('v1.2.3+4'), equals('1.2.3+4'));
    });
  });
}
