import 'package:flutter_test/flutter_test.dart';
import 'package:esp32_comm/src/models/wifi_credentials.dart';
import 'package:esp32_comm/src/models/connect_mode.dart';

void main() {
  group('WifiCredentials', () {
    test('toJson and fromJson should be symmetric', () {
      final credentials = WifiCredentials(
        ssid: 'MyWiFi',
        password: 'password123',
        type: 'WPA2',
        hidden: false,
        lanReachable: true,
        lanIp: '192.168.1.50',
        connectMode: ConnectMode.away,
      );

      final json = credentials.toJson();
      final fromJson = WifiCredentials.fromJson(json);

      expect(fromJson.ssid, credentials.ssid);
      expect(fromJson.password, credentials.password);
      expect(fromJson.type, credentials.type);
      expect(fromJson.hidden, credentials.hidden);
      expect(fromJson.lanReachable, credentials.lanReachable);
      expect(fromJson.lanIp, credentials.lanIp);
      expect(fromJson.connectMode, credentials.connectMode);
    });

    test('tryParse should correctly parse WIFI: format strings', () {
      const raw = 'WIFI:S:MyWiFi;P:password123;T:WPA;H:false;';
      final credentials = WifiCredentials.tryParse(raw);

      expect(credentials, isNotNull);
      expect(credentials!.ssid, 'MyWiFi');
      expect(credentials.password, 'password123');
      expect(credentials.type, 'WPA');
      expect(credentials.hidden, false);
    });

    test('tryParse should return null for invalid format', () {
      expect(WifiCredentials.tryParse('INVALID:S:SSID;P:PASS;'), isNull);
      expect(WifiCredentials.tryParse('WIFI:S:SSID;'), isNull); // Missing password
    });
  });
}
