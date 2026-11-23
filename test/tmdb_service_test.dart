import 'package:flutter_test/flutter_test.dart';
import 'package:cinemahub/core/catalogue/tmdb_service.dart';

void main() {
  group('TmdbService', () {
    test('creates with explicit API key', () {
      const testKey = 'test_api_key_12345';
      final service = TmdbService(apiKey: testKey);
      expect(service.isConfigured, isTrue);
    });
  });
}
