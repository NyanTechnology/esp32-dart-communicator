import 'dart:typed_data';
import 'package:esp32_comm/esp32_comm.dart';

/// A practical example of how to integrate with an ESP32 device
/// using both HTTP and BLE services.
void main() async {
  print('--- ESP32 Communication Integration Example ---');

  // 1. Initialize HTTP Client
  final httpClient = DeviceHttpClient();
  final deviceUrl = 'http://192.168.4.1'; // Default IP when in AP mode

  print('Checking device info via HTTP...');
  final info = await httpClient.fetchDeviceInfo(deviceUrl);

  if (info != null) {
    print('Device Found!');
    print('Firmware: ${info.firmware}');
    print('Mode: ${info.mode}');
    print('STA Connected: ${info.staConnected}');
    print('STA IP: ${info.staIp ?? "N/A"}');
  } else {
    print('Could not connect to device at $deviceUrl');
  }

  // 2. Example: Uploading asset and applying config
  print('\nAttempting to upload and apply eye configuration...');
  final mockData = Uint8List.fromList([0, 1, 2, 3, 4]); // Mock binary data
  final uploadSuccess = await httpClient.uploadEyeData(deviceUrl, mockData, 'eye_test.bin');
  
  if (uploadSuccess) {
    print('Upload successful. Applying configuration...');
    final applySuccess = await httpClient.applyEyeConfigs(
      deviceUrl,
      'eye_test.bin',
      'eye_test.bin',
      leftMirror: true,
    );
    print('Apply Configuration: ${applySuccess ? "SUCCESS" : "FAILED"}');
  }

  // 3. BLE Integration Example (Provisioning/Command)
  print('\n--- BLE Command Example ---');
  // In a real application, you would use FlutterBluePlus to scan and find the device:
  // List<ScanResult> results = await FlutterBluePlus.startScan(timeout: Duration(seconds: 4));
  // BluetoothDevice device = results.first.device;
  
  /*
  final bleClient = DeviceBleClient(device);
  try {
    print('Initializing BLE Client...');
    await bleClient.init();
    
    print('Sending Wi-Fi Provisioning Command...');
    final response = await bleClient.sendCommand({
      'cmd': 'provision',
      'ssid': 'MyHomeWiFi',
      'password': 'secret_password',
    });
    
    print('BLE Response: $response');
  } catch (e) {
    print('BLE Error: $e');
  } finally {
    bleClient.dispose();
  }
  */
  
  print('\nFor a full discovery example, refer to DeviceDiscoveryService usage.');
}
