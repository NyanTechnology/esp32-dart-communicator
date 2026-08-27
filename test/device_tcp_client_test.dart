import 'dart:convert';
import 'dart:io';

import 'package:esp32_comm/src/services/device_tcp_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('authenticated TCP scan aggregates valid Wi-Fi frames', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    final serverTask = server.first.then((socket) async {
      addTearDown(socket.destroy);
      var receiveBuffer = '';
      await for (final chunk in socket.cast<List<int>>().transform(
        utf8.decoder,
      )) {
        receiveBuffer += chunk;
        while (receiveBuffer.contains('\n')) {
          final delimiterIndex = receiveBuffer.indexOf('\n');
          final line = receiveBuffer.substring(0, delimiterIndex).trim();
          receiveBuffer = receiveBuffer.substring(delimiterIndex + 1);
          if (line.isEmpty) continue;

          final command = jsonDecode(line) as Map<String, dynamic>;
          switch (command['action']) {
            case 'GET_CHALLENGE':
              socket.writeln(jsonEncode({'nonce': 'test-nonce'}));
              break;
            case 'AUTH':
              socket.writeln(
                jsonEncode({'status': 'success', 'message': 'authenticated'}),
              );
              break;
            case 'SCAN_WIFI':
              socket.write(
                [
                  {
                    'status': 'success',
                    'message': 'wifi_scan_started',
                    'scan_id': 7,
                  },
                  {
                    'message': 'wifi_ap',
                    'scan_id': 7,
                    'ssid': 'Weaker duplicate',
                    'rssi': -75,
                    'channel': 6,
                    'auth': 'WPA2_PSK',
                    'password_required': true,
                    'supported': true,
                  },
                  {
                    'message': 'wifi_ap',
                    'scan_id': 7,
                    'ssid': 'Strong network',
                    'rssi': -42,
                    'channel': 11,
                    'auth': 'OPEN',
                    'password_required': false,
                    'supported': true,
                  },
                  {
                    'message': 'wifi_ap',
                    'scan_id': 7,
                    'ssid': 'Weaker duplicate',
                    'rssi': -58,
                    'channel': 6,
                    'auth': 'WPA2_PSK',
                    'password_required': true,
                    'supported': true,
                  },
                  {
                    'message': 'wifi_ap',
                    'scan_id': 7,
                    'ssid': 'Unsupported network',
                    'rssi': -30,
                    'channel': 1,
                    'auth': 'WPA2_ENTERPRISE',
                    'password_required': true,
                    'supported': false,
                  },
                  {
                    'status': 'success',
                    'message': 'wifi_scan_complete',
                    'scan_id': 7,
                    'count': 4,
                  },
                ].map(jsonEncode).join('\n'),
              );
              socket.write('\n');
              await socket.flush();
              break;
          }
        }
      }
    });
    addTearDown(() async => serverTask.timeout(const Duration(seconds: 1)));

    final client = DeviceTcpClient(
      InternetAddress.loopbackIPv4.address,
      port: server.port,
    );
    addTearDown(client.close);

    await client.connect('test-local-key');
    final networks = await client.scanWifiNetworks(timeoutSec: 2);

    expect(networks.map((network) => network.ssid), [
      'Strong network',
      'Weaker duplicate',
    ]);
    expect(networks.last.rssi, -58);
    expect(networks.first.requiresPassword, isFalse);
  });
}
