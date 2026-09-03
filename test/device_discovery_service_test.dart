import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:esp32_comm/src/services/device_discovery_service.dart';
import 'package:nsd/nsd.dart' as nsd;

void main() {
  group('DeviceDiscoveryService platform policy', () {
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test('uses mDNS only on iOS by default', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      expect(DeviceDiscoveryService().enableUdpDiscovery, isFalse);
    });

    test('keeps UDP discovery enabled on Android by default', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      expect(DeviceDiscoveryService().enableUdpDiscovery, isTrue);
    });

    test('allows UDP discovery policy to be overridden explicitly', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      expect(
        DeviceDiscoveryService(enableUdpDiscovery: true).enableUdpDiscovery,
        isTrue,
      );
    });
  });

  group('DeviceDiscoveryService MAC Extraction Tests', () {
    final discoveryService = DeviceDiscoveryService();

    test('extractMacFromHostOrName should return null for null input', () {
      expect(discoveryService.extractMacFromHostOrName(null), isNull);
    });

    test(
      'extractMacFromHostOrName should return null for non-matching input',
      () {
        expect(
          discoveryService.extractMacFromHostOrName('some-other-host.local'),
          isNull,
        );
        expect(
          discoveryService.extractMacFromHostOrName('192.168.1.100'),
          isNull,
        );
      },
    );

    test(
      'extractMacFromHostOrName should correctly extract and format MAC from hostname',
      () {
        expect(
          discoveryService.extractMacFromHostOrName(
            'nyaneye-70af09137c50.local',
          ),
          equals('70:AF:09:13:7C:50'),
        );
      },
    );

    test(
      'extractMacFromHostOrName should support uppercase and lowercase variations',
      () {
        expect(
          discoveryService.extractMacFromHostOrName(
            'NYANEYE-70AF09137C50.local',
          ),
          equals('70:AF:09:13:7C:50'),
        );
      },
    );

    test(
      'extractMacFromHostOrName should extract MAC from deep inside url strings',
      () {
        expect(
          discoveryService.extractMacFromHostOrName(
            'http://nyaneye-70af09137c50.local:8080/path',
          ),
          equals('70:AF:09:13:7C:50'),
        );
      },
    );
  });

  group('DeviceDiscoveryService address normalization', () {
    final discoveryService = DeviceDiscoveryService();

    test('prefers a resolved numeric IPv4 address over the mDNS host', () {
      final service = nsd.Service(
        host: 'nyaneye-68ee8f217d70.local.',
        addresses: [
          InternetAddress('fe80::1'),
          InternetAddress('192.168.0.41'),
        ],
      );

      expect(discoveryService.preferredIpv4Address(service), '192.168.0.41');
    });

    test('normalizes Bonjour trailing dot without changing the host', () {
      expect(
        discoveryService.normalizeMdnsHost('nyaneye-68ee8f217d70.local.'),
        'nyaneye-68ee8f217d70.local',
      );
    });

    test('does not classify an mDNS hostname as an IPv4 address', () {
      expect(
        discoveryService.isIpv4Address('nyaneye-68ee8f217d70.local'),
        isFalse,
      );
      expect(discoveryService.isIpv4Address('192.168.0.41'), isTrue);
    });
  });
}
