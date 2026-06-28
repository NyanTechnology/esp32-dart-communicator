import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:esp32_comm/src/services/device_http_client.dart';

void main() {
  group('DeviceHttpClient', () {
    test('fetchDeviceInfo returns DeviceInfo on 200', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/device_info') {
          return http.Response(
            json.encode({
              'firmware': '1.0.0',
              'mode': 'AP',
              'apSsid': 'ESP32',
              'apIp': '192.168.4.1',
              'apClients': 0,
              'staConnected': false,
              'isManager': false,
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final client = DeviceHttpClient(client: mockClient);
      final info = await client.fetchDeviceInfo('http://192.168.4.1');

      expect(info, isNotNull);
      expect(info!.firmware, '1.0.0');
      expect(info.mode, 'AP');
    });

    test('fetchDeviceInfo handles missing sta_ip by extracting from baseUrl', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          json.encode({
            'firmware': '1.0.0',
            'mode': 'AP',
            'apSsid': 'ESP32',
            'apIp': '192.168.4.1',
            'apClients': 0,
            'staConnected': false,
            'isManager': false,
            // 'staIp' is missing
          }),
          200,
        );
      });

      final client = DeviceHttpClient(client: mockClient);
      final info = await client.fetchDeviceInfo('http://192.168.1.50');

      expect(info, isNotNull);
      expect(info!.staIp, '192.168.1.50');
    });

    test('uploadEyeData returns true on 200', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/upload');
        return http.Response('', 200);
      });

      final client = DeviceHttpClient(client: mockClient);
      final success = await client.uploadEyeData(
        'http://192.168.4.1',
        Uint8List.fromList([1, 2, 3]),
        'test.bin',
      );

      expect(success, isTrue);
    });

    test('applyEyeConfigs constructs correct URL and returns true on 200', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.queryParameters['left'], 'L.bin');
        expect(request.url.queryParameters['right'], 'R.bin');
        expect(request.url.queryParameters['leftMirror'], 'true');
        return http.Response(json.encode({'status': 'success'}), 200);
      });

      final client = DeviceHttpClient(client: mockClient);
      final success = await client.applyEyeConfigs(
        'http://192.168.4.1',
        'L.bin',
        'R.bin',
        leftMirror: true,
      );

      expect(success, isTrue);
    });

    test('returns null/false on error', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Error', 500);
      });

      final client = DeviceHttpClient(client: mockClient);
      
      expect(await client.fetchDeviceInfo('http://192.168.4.1'), isNull);
      expect(await client.uploadEyeData('http://192.168.4.1', Uint8List(0), 'f'), isFalse);
    });
  });
}
