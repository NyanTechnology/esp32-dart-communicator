# esp32_comm

[中文版](./README_ZH.md)

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

## Integration & Debugging

For a complete example of how to combine HTTP and BLE services for device integration, see [example/main.dart](example/main.dart).

```dart
// Run the example
flutter run example/main.dart
```

## Testing

The project includes unit tests for core models and logic.

```bash
# Run all tests
flutter test
```

Currently covered:
- `DeviceInfo` JSON parsing (camelCase and snake_case support).
- `WifiCredentials` serialization and QR-code string parsing.

## For Firmware Developers (Standalone Debugging)

If you are developing the ESP32 firmware and want to test your API compatibility without running the full Flutter app, you can use our standalone CLI tool.

**Prerequisites:** [Dart SDK](https://dart.dev/get-dart) installed.

```bash
# Show help and available test options
dart tools/debug_device.dart --help

# Test specific features (e.g., only Info and Upload)
dart tools/debug_device.dart <your_device_ip> --info --upload
```

Available flags: `--info`, `--upload`, `--apply`, `--negative`, `--all`.

This tool will verify if your implementation of `/api/device_info`, `/api/upload`, and `/api/eyes/apply` correctly matches the requirements of this package.

## License

This project is licensed under the MIT License.
