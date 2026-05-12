# esp32_comm

A Flutter package for communicating with ESP32-based NyanEye devices via BLE, LAN (mDNS/UDP), and HTTP.

## Features

- **BLE Provisioning**: Setup device Wi-Fi credentials and operating modes via Bluetooth Low Energy.
- **LAN Discovery**: Automatically discover devices on the local network using mDNS and UDP broadcast.
- **HTTP Control**: 
  - Fetch detailed device information.
  - Upload eye assets (.eye files).
  - Apply eye configurations in real-time.
- **Unified Models**: Consistent data structures for device info, Wi-Fi credentials, and connection modes.

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  esp32_comm:
    path: packages/esp32_comm
```

## Usage

### Device Discovery

```dart
final discoveryService = DeviceDiscoveryService();
final devices = await discoveryService.discoverEsp32DevicesOnLan();
for (var device in devices) {
  print('Found device: ${device.staIp}');
}
```

### HTTP Control

```dart
final client = DeviceHttpClient();
final success = await client.applyEyeConfigs(
  'http://192.168.1.100', 
  'left_eye.png', 
  'right_eye.png'
);
```

### BLE Provisioning

```dart
final bleClient = DeviceBleClient(bluetoothDevice);
await bleClient.init();
final response = await bleClient.sendCommand({
  "action": "set_credentials",
  "ssid": "MyWiFi",
  "pwd": "password"
});
```

## License

This project is licensed under the MIT License.
