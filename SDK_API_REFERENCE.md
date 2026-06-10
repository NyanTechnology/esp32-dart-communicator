# 😺 NyanEye SDK (`esp32_comm`) 开发者 API 接口文档

本设计与集成文档旨在帮助移动端开发人员（Flutter/Dart 开发者）快速上手使用工作区的 `esp32_comm` SDK，实现与 NyanEye ESP32-C3 物理设备进行低功耗蓝牙（BLE）配网、局域网设备搜索、用户信息绑定、心跳检测、独立电量获取、屏幕累计工作时间统计，以及眼部动图资产流式上传与显示的远程控制。

---

## 📦 1. 快速集成与引入

将 `esp32_comm` 包以本地 path 形式添加至你的 Flutter 工程中：

```yaml
# pubspec.yaml
dependencies:
  flutter:
    sdk: flutter
  esp32_comm:
    path: ../esp32-dart-communicator # 指向本地 SDK 根目录
```

在 Dart 代码中统一引入：

```dart
import 'package:esp32_comm/esp32_comm.dart';
```

---

## 📡 2. 核心类与 API 详细参考

`esp32_comm` SDK 由三大核心服务组件和对应的实体数据模型组成：
1.  **`DeviceBleClient`**：负责低功耗蓝牙连接、双模指令下发及配网。
2.  **`DeviceDiscoveryService`**：负责局域网双轨（mDNS + UDP）设备搜索。
3.  **`DeviceHttpClient`**：负责局域网内所有基于 HTTP REST 的高频设备状态控制、大资产文件传输。

---

### 🟢 组件 A：`DeviceBleClient`（低功耗蓝牙控制客户端）

用于在出厂未配网状态或户外蓝牙直连状态下，与设备建立物理蓝牙链路并下发指令。

#### 1. 构造函数
```dart
DeviceBleClient(
  BluetoothDevice device, {
  String serviceUuid = defaultServiceUuid, // 默认 128-bit 极速配网服务 UUID
  String charUuid = defaultCharUuid,       // 默认 128-bit 极速配网特征 UUID
})
```

#### 2. `init()` —— 建立连接与 Notify 特征值订阅
```dart
Future<void> init()
```
*   **功能**：对传入的蓝牙物理设备执行 GATT 发现、提取目标服务与通信特征值，并**自动建立 Notify 双工监听通道**。
*   **异常**：若未发现特征值，会抛出 `Exception('Could not find control service/characteristic')`。

#### 3. `sendCommand()` —— 蓝牙下发 JSON 命令（含自动 MTU 扩容与异步等待）
```dart
Future<Map<String, dynamic>> sendCommand(
  Map<String, dynamic> payload, {
  int timeoutSec = 15,
})
```
*   **功能**：下发一笔控制 JSON。
*   **特性**：
    *   在 Android 端会**自动申请 512 字节的大 MTU 扩容**，防止密码和 Token 被截断。
    *   利用 `Completer` 将底层的异步 Notify 通知转换为标准 Dart `Future` 形式，实现写入 ➡️ 异步等待应答 ➡️ 获取返回值的完整闭环。
*   **调用示例（蓝牙配网）**：
    ```dart
    final bleClient = DeviceBleClient(bluetoothDevice);
    await bleClient.init();
    
    final response = await bleClient.sendCommand({
      "action": "PROVISION",
      "ssid": "My_WiFi_Name",
      "password": "My_WiFi_Password",
      "bind_token": "token_xyz" // 选填
    });
    print('配网结果: ${response["status"]}'); // success
    bleClient.dispose();
    ```

#### 4. `dispose()` —— 销毁与资源释放
```dart
void dispose()
```
*   **功能**：注销内部所有的 Stream 蓝牙监听，释放内存。

---

### 🟡 组件 B：`DeviceDiscoveryService`（局域网双轨设备搜索器）

用于在局域网下搜索已经成功配好网、在线的物理设备。

#### 1. `discoverEsp32DevicesOnLan()` —— 双轨并发搜索
```dart
Future<List<DeviceInfo>> discoverEsp32DevicesOnLan({
  Duration timeout = const Duration(seconds: 4),
})
```
*   **功能**：同时拉起 **mDNS 监听**与 **UDP 组播广播（8888 端口）** 双向线程在局域网内并发寻找设备，去重并返回全量的 `DeviceInfo` 设备实体列表。
*   **调用示例**：
    ```dart
    final discovery = DeviceDiscoveryService();
    final List<DeviceInfo> devices = await discovery.discoverEsp32DevicesOnLan(
      timeout: const Duration(seconds: 4),
    );
    for (var device in devices) {
      print('发现设备 IP: ${device.staIp}, 固件版本: ${device.firmware}');
    }
    ```

---

### 🔵 组件 C：`DeviceHttpClient`（局域网 HTTP REST 控制客户端）

在局域网内对物理设备执行高吞吐量文件传输和低时延的控制交互。

#### 1. `fetchDeviceInfo()` —— 获取设备当前基础信息状态 (REQ-3)
```dart
Future<DeviceInfo?> fetchDeviceInfo(
  String baseUrl, {
  Duration timeout = const Duration(seconds: 4),
})
```
*   **功能**：向板子获取 `/api/device_info` 并将其反序列化。返回值已高标准补齐了 **`batteryLevel` (实时电量)** 与 **`powerSavingMode` (节能模式指示)**。
*   **调用示例**：
    ```dart
    final client = DeviceHttpClient();
    final info = await client.fetchDeviceInfo('http://10.20.0.163:80');
    if (info != null) {
      print('当前电量: ${info.batteryLevel}%');
      print('节电状态: ${info.powerSavingMode == true ? "开启" : "关闭"}');
    }
    ```

#### 2. `uploadEyeData()` —— 流式分包上传表情包大文件
```dart
Future<bool> uploadEyeData(
  String baseUrl, 
  Uint8List data, 
  String filename,
)
```
*   **功能**：将手机本地的 GIF/Eye 二进制表情包文件，通过标准 HttpClient Multipart 流式协议分包传输写入到板子的物理 SPIFFS 闪存 `/spiffs/images/<filename>` 中。

#### 3. `applyEyeConfigs()` —— 远程刷新显示画面
```dart
Future<bool> applyEyeConfigs(
  String baseUrl,
  String leftFilename,  // 写入 SPIFFS 的左眼文件名
  String rightFilename, // 写入 SPIFFS 的右眼文件名
  {
    bool leftMirror = false,
    bool rightMirror = false,
  }
)
```
*   **功能**：控制板子的两块屏幕立刻刷新、并流畅解码播放指定的表情资产（**注：若设备处于低功耗休眠，发送此指令会自动唤醒屏幕并拉起背光！**）。

#### 4. `fetchBatteryLevel()` —— 独立低电量快速获取通道 (REQ-5)
```dart
Future<int?> fetchBatteryLevel(
  String baseUrl, {
  Duration timeout = const Duration(seconds: 4),
})
```
*   **功能**：不调用整机 info，而是极速、独立请求 `/api/battery`，获取当前设备的电池百分比（0-100）。

#### 5. `pingDevice()` —— 轻量级连通性与 RTT 延迟检测 (REQ-6)
```dart
Future<int?> pingDevice(
  String baseUrl, {
  Duration timeout = const Duration(seconds: 2),
})
```
*   **功能**：向设备发送超轻量 `/api/ping`。
*   **返回值**：若连通，高精度计算并返回**本次连接的往返毫秒时延 (Round Trip Time, RTT)**；若断网，返回 `null`。

#### 6. `bindUser()` —— 用户登录状态与云上绑定注册 (REQ-7)
```dart
Future<bool> bindUser(
  String baseUrl,
  String userId,
  String bindToken, {
  Duration timeout = const Duration(seconds: 4),
})
```
*   **功能**：将手机用户的 ID 和云端临时安全 Token 绑定传输写入板子的 NVS 永久区，强制激活开发板后台拉起异步上报上云线程 `cloud_binding_task`。

#### 7. `enterSleepMode()` —— 一键远程强制软熄屏睡眠 (REQ-8)
```dart
Future<bool> enterSleepMode(
  String baseUrl, {
  int sleepSeconds = 3600,
  Duration timeout = const Duration(seconds: 4),
})
```
*   **功能**：向设备下发节电休眠命令。硬件接收到后会回复成功包，并在后台延迟 1.5 秒安全**熄灭双屏背光、停止 GIF 软解码任务释放 CPU、并将 Wi-Fi 芯片切换至超低功耗 Modem 省电模式**。

#### 8. `fetchDisplayDuration()` —— 今日屏幕累计显示工作时间 (REQ-9)
```dart
Future<int?> fetchDisplayDuration(
  String baseUrl, {
  Duration timeout = const Duration(seconds: 4),
})
```
*   **功能**：抓取并获取设备今日双屏背光亮起、进行工作的累计秒数。

#### 9. `syncDeviceTime()` —— RTC 硬件时钟高精度同步 (REQ-10)
```dart
Future<String?> syncDeviceTime(
  String baseUrl, {
  Duration timeout = const Duration(seconds: 4),
})
```
*   **功能**：获取手机当前的高精度 Unix 时间戳和时区偏移（DateTime.now），打包发送给开发板。开发板底层通过 C 语言 `settimeofday` 强制写死校准硬件 RTC，并返回包含已同步的可视化时间字符串（如 `2026-06-10 23:15:00`）。

---

## 📊 3. 实体数据模型参考

### `DeviceInfo` 模型 (解析自 /api/device_info)
```dart
class DeviceInfo {
  final String firmware;         // 固件版本
  final String mode;             // 运作模式
  final String apSsid;           // 板载自广播 AP 热点 SSID
  final String apIp;             // AP 热点网卡 IP
  final int apClients;           // 当前连入板载 AP 的手机数
  final String? staSsid;         // 连入的外部路由器 SSID
  final bool staConnected;       // 路由器连网状态指示
  final String? staIp;           // 路由器网卡 IP (局域网 IP)
  final String? mdnsHost;        // mDNS 广播主机名
  final bool isManager;          // 是否为群组主控制器
  final int? batteryLevel;       // REQ-3: 电池电量百分比 (0-100)
  final bool? powerSavingMode;   // REQ-3: 当前是否处于节电模式
}
```
