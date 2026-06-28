import 'package:flutter_test/flutter_test.dart';
import 'package:esp32_comm/src/models/device_info.dart';

void main() {
  group('DeviceInfo', () {
    test('fromJson should parse camelCase keys', () {
      final json = {
        'firmware': '1.0.0',
        'mode': 'AP',
        'apSsid': 'ESP32_AP',
        'apIp': '192.168.4.1',
        'apClients': 1,
        'staSsid': 'MyWiFi',
        'staConnected': true,
        'staIp': '192.168.1.10',
        'mdnsHost': 'esp32.local',
        'mdnsUrl': 'http://esp32.local',
        'managerHost': 'manager.local',
        'managerUrl': 'http://manager.local',
        'isManager': true,
      };

      final deviceInfo = DeviceInfo.fromJson(json);

      expect(deviceInfo.firmware, '1.0.0');
      expect(deviceInfo.mode, 'AP');
      expect(deviceInfo.apSsid, 'ESP32_AP');
      expect(deviceInfo.apIp, '192.168.4.1');
      expect(deviceInfo.apClients, 1);
      expect(deviceInfo.staSsid, 'MyWiFi');
      expect(deviceInfo.staConnected, true);
      expect(deviceInfo.staIp, '192.168.1.10');
      expect(deviceInfo.mdnsHost, 'esp32.local');
      expect(deviceInfo.mdnsUrl, 'http://esp32.local');
      expect(deviceInfo.managerHost, 'manager.local');
      expect(deviceInfo.managerUrl, 'http://manager.local');
      expect(deviceInfo.isManager, true);
    });

    test('fromJson should parse snake_case keys (fallback)', () {
      final json = {
        'fw_version': '1.1.0',
        'mode': 'STA',
        'ap_ssid': 'ESP32_AP_TEST',
        'ap_ip': '192.168.4.2',
        'ap_clients': '2',
        'sta_ssid': 'GuestWiFi',
        'sta_connected': false,
        'sta_ip': null,
        'mdns_host': null,
        'mdns_url': null,
        'manager_host': null,
        'manager_url': null,
        'is_manager': false,
      };

      final deviceInfo = DeviceInfo.fromJson(json);

      expect(deviceInfo.firmware, '1.1.0');
      expect(deviceInfo.mode, 'STA');
      expect(deviceInfo.apSsid, 'ESP32_AP_TEST');
      expect(deviceInfo.apIp, '192.168.4.2');
      expect(deviceInfo.apClients, 2);
      expect(deviceInfo.staSsid, 'GuestWiFi');
      expect(deviceInfo.staConnected, false);
      expect(deviceInfo.staIp, null);
      expect(deviceInfo.mdnsHost, null);
      expect(deviceInfo.isManager, false);
    });

    test('fromJson should handle type coercion for apClients', () {
      final json = {
        'firmware': '1.0.0',
        'mode': 'AP',
        'apSsid': 'ESP32',
        'apIp': '192.168.4.1',
        'apClients': '5', // String instead of int
        'staConnected': false,
        'isManager': false,
      };

      final deviceInfo = DeviceInfo.fromJson(json);
      expect(deviceInfo.apClients, 5);
    });

    test('fromJson should provide default values for missing fields', () {
      final json = {
        'mode': 'AP',
      };

      final deviceInfo = DeviceInfo.fromJson(json);
      expect(deviceInfo.firmware, '');
      expect(deviceInfo.apSsid, '');
      expect(deviceInfo.apIp, '');
      expect(deviceInfo.apClients, 0);
      expect(deviceInfo.staConnected, false);
      expect(deviceInfo.isManager, false);
    });

    test('fromJson should parse mac address', () {
      final json = {
        'mode': 'AP',
        'mac': '00:11:22:33:44:55',
      };

      final deviceInfo = DeviceInfo.fromJson(json);
      expect(deviceInfo.mac, '00:11:22:33:44:55');
    });

    test('copyWith should override specific fields', () {
      final deviceInfo = DeviceInfo(
        firmware: '1.0.0',
        mode: 'AP',
        apSsid: 'ESP32',
        apIp: '192.168.4.1',
        apClients: 0,
        staConnected: false,
        isManager: false,
        mac: '00:11:22:33:44:55',
      );

      final updated = deviceInfo.copyWith(mac: '66:77:88:99:aa:bb', mode: 'STA');
      expect(updated.mac, '66:77:88:99:aa:bb');
      expect(updated.mode, 'STA');
      expect(updated.firmware, '1.0.0');
    });
  });
}
