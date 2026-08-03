import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:esp32_comm/src/models/nyan_eyes_protocol.dart';

void main() {
  group('NyanEyesProtocol.setMode', () {
    test('should build SET_MODE HOME payload', () {
      final payload = jsonDecode(NyanEyesProtocol.setMode('HOME')) as Map<String, dynamic>;
      expect(payload['action'], 'SET_MODE');
      expect(payload['mode'], 'HOME');
    });

    test('should build SET_MODE OUTDOOR payload', () {
      final payload = jsonDecode(NyanEyesProtocol.setMode('OUTDOOR')) as Map<String, dynamic>;
      expect(payload['action'], 'SET_MODE');
      expect(payload['mode'], 'OUTDOOR');
    });

    test('should normalize lowercase mode to uppercase', () {
      final payload = jsonDecode(NyanEyesProtocol.setMode('home')) as Map<String, dynamic>;
      expect(payload['mode'], 'HOME');
    });
  });

  group('NyanEyesProtocol.switchWiFi', () {
    test('should omit bind_token when not provided', () {
      final payload = jsonDecode(NyanEyesProtocol.switchWiFi('MyWiFi', 'password123')) as Map<String, dynamic>;
      expect(payload['action'], 'SWITCH_WIFI');
      expect(payload['ssid'], 'MyWiFi');
      expect(payload['password'], 'password123');
      expect(payload.containsKey('bind_token'), isFalse);
    });

    test('should include bind_token when provided', () {
      final payload = jsonDecode(NyanEyesProtocol.switchWiFi('MyWiFi', 'password123', bindToken: 'token_abc')) as Map<String, dynamic>;
      expect(payload['bind_token'], 'token_abc');
    });
  });

  group('NyanEyesProtocol.setPowerSaving', () {
    test('should build enabled payload', () {
      final payload = jsonDecode(NyanEyesProtocol.setPowerSaving(true)) as Map<String, dynamic>;
      expect(payload, {'action': 'SET_POWER_SAVING', 'enabled': true});
    });

    test('should build disabled payload', () {
      final payload = jsonDecode(NyanEyesProtocol.setPowerSaving(false)) as Map<String, dynamic>;
      expect(payload, {'action': 'SET_POWER_SAVING', 'enabled': false});
    });
  });
}
