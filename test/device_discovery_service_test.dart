import 'package:flutter_test/flutter_test.dart';
import 'package:esp32_comm/src/services/device_discovery_service.dart';

void main() {
  group('DeviceDiscoveryService MAC Extraction Tests', () {
    final discoveryService = DeviceDiscoveryService();

    test('extractMacFromHostOrName should return null for null input', () {
      expect(discoveryService.extractMacFromHostOrName(null), isNull);
    });

    test('extractMacFromHostOrName should return null for non-matching input', () {
      expect(discoveryService.extractMacFromHostOrName('some-other-host.local'), isNull);
      expect(discoveryService.extractMacFromHostOrName('192.168.1.100'), isNull);
    });

    test('extractMacFromHostOrName should correctly extract and format MAC from hostname', () {
      expect(
        discoveryService.extractMacFromHostOrName('nyaneye-70af09137c50.local'),
        equals('70:AF:09:13:7C:50'),
      );
    });

    test('extractMacFromHostOrName should support uppercase and lowercase variations', () {
      expect(
        discoveryService.extractMacFromHostOrName('NYANEYE-70AF09137C50.local'),
        equals('70:AF:09:13:7C:50'),
      );
    });

    test('extractMacFromHostOrName should extract MAC from deep inside url strings', () {
      expect(
        discoveryService.extractMacFromHostOrName('http://nyaneye-70af09137c50.local:8080/path'),
        equals('70:AF:09:13:7C:50'),
      );
    });
  });
}
