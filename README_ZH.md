# esp32_comm

[English Version](./README.md)

一个用于与基于 ESP32 的 NyanEye 设备进行通信的 Flutter 软件包，支持 BLE、局域网 (mDNS/UDP) 和 HTTP 协议。

## 功能特性

- **BLE 配网 (Provisioning)**: 通过蓝牙低功耗设置设备的 Wi-Fi 凭据和运行模式。
- **局域网发现**: 使用 mDNS 和 UDP 广播自动发现本地网络中的设备。
- **HTTP 控制**: 
  - 获取详细的设备信息。
  - 上传眼睛素材（.eye 文件）。
  - 实时应用眼睛配置。
- **统一模型**: 为设备信息、Wi-Fi 凭据和连接模式提供一致的数据结构。

## 安装

在你的 `pubspec.yaml` 中添加以下内容：

```yaml
dependencies:
  esp32_comm:
    path: packages/esp32_comm
```

## 使用方法

### 设备发现

```dart
final discoveryService = DeviceDiscoveryService();
final devices = await discoveryService.discoverEsp32DevicesOnLan();
for (var device in devices) {
  print('发现设备: ${device.staIp}');
}
```

### HTTP 控制

```dart
final client = DeviceHttpClient();
final success = await client.applyEyeConfigs(
  'http://192.168.1.100', 
  'left_eye.png', 
  'right_eye.png'
);
```

### BLE 配网

```dart
final bleClient = DeviceBleClient(bluetoothDevice);
await bleClient.init();
final response = await bleClient.sendCommand({
  "action": "set_credentials",
  "ssid": "MyWiFi",
  "pwd": "password"
});
```

## 集成与调试

有关如何结合 HTTP 和 BLE 服务进行设备集成的完整示例，请参阅 [example/main.dart](example/main.dart)。

```dart
// 运行示例
flutter run example/main.dart
```

## 测试

该项目包含核心模型和逻辑的单元测试。

```bash
# 运行所有测试
flutter test
```

当前覆盖范围：
- `DeviceInfo` JSON 解析（支持驼峰式和蛇形式）。
- `WifiCredentials` 序列化和 QR 码字符串解析。

## 给固件开发者（独立调试工具）

如果你正在开发 ESP32 固件，并希望在不运行完整 Flutter 应用的情况下测试 API 兼容性，可以使用我们的独立命令行工具。

**前提条件：** 已安装 [Dart SDK](https://dart.dev/get-dart)。

```bash
# 查看帮助和所有可用的测试选项
dart tools/debug_device.dart --help

# 测试特定功能（例如：只测试设备信息和上传）
dart tools/debug_device.dart <你的设备IP> --info --upload
```

可用选项：`--info`, `--upload`, `--apply`, `--negative`, `--all`。

该工具将验证你实现的 `/api/device_info`、`/api/upload` 和 `/api/eyes/apply` 是否正确符合本软件包的要求。

## 许可证

本项目采用 MIT 许可证。
