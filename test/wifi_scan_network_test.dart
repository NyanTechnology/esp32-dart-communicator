import 'package:flutter_test/flutter_test.dart';
import 'package:esp32_comm/src/models/wifi_scan_network.dart';

void main() {
  test('parses a secured device-side Wi-Fi scan result', () {
    final network = WifiScanNetwork.fromJson({
      'ssid': 'Home WiFi',
      'rssi': -48,
      'channel': 6,
      'auth': 'WPA2_PSK',
      'password_required': true,
      'supported': true,
    });

    expect(network.ssid, 'Home WiFi');
    expect(network.rssi, -48);
    expect(network.channel, 6);
    expect(network.requiresPassword, isTrue);
    expect(network.supported, isTrue);
    expect(network.signalLabel, '信号优秀');
  });

  test('parses an open network without requiring a password', () {
    final network = WifiScanNetwork.fromJson({
      'ssid': 'Guest',
      'rssi': -70,
      'channel': 11,
      'auth': 'OPEN',
      'password_required': false,
      'supported': true,
    });

    expect(network.requiresPassword, isFalse);
    expect(network.signalLabel, '信号一般');
  });
}
