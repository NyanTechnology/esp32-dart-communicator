import 'package:esp32_comm/esp32_comm.dart';

void main() async {
  print('Starting ESP32 Discovery...');
  
  final discoveryService = DeviceDiscoveryService();
  
  // Note: This won't work in a pure terminal without a Flutter environment 
  // if the underlying plugins (nsd, flutter_blue_plus) require a platform channel.
  // This serves as a code-level example.
  print('Scanning for 5 seconds...');
  
  final devices = await discoveryService.discoverEsp32DevicesOnLan(
    timeout: Duration(seconds: 5),
  );
  
  print('Found ${devices.length} devices:');
  for (var device in devices) {
    print('- IP: ${device.staIp}, Firmware: ${device.firmware}');
  }
}
