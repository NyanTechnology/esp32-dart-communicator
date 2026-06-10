# 😺 NyanEye SDK (`esp32_comm`) 双通道对称 API 开发者文档

本设计与集成文档旨在帮助移动端开发人员（Flutter/Dart 开发者）快速上手使用 `esp32_comm` SDK，实现与 NyanEye ESP32-C3 物理设备进行低功耗蓝牙（BLE）与 Wi-Fi 局域网（HTTP）的双通道对称控制、高精度配网、安全鉴权、离线表情刷新、系统级一键待机休眠、高精度 RTC 时间对齐、累计亮屏工作时间获取及网络时延检测。

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
1.  **`DeviceBleClient`**：负责低功耗蓝牙连接、双通道命令下发、安全鉴权及配网。
2.  **`DeviceDiscoveryService`**：负责局域网双轨（mDNS + UDP）设备搜索。
3.  **`DeviceHttpClient`**：负责局域网内所有基于 HTTP REST 的设备状态控制、大资产文件传输。

---

### 🟢 组件 A：`DeviceBleClient`（低功耗蓝牙控制客户端）

用于在无网环境（户外模式）或出厂配网状态下，与设备建立物理蓝牙链路并进行全对称指令下发。

#### 1. 构造函数与广播对齐
开发板在蓝牙广播中**同时开启配网服务（FFF0）与户外直连控制服务（FFE0）**。App 连接对应的特征值句柄后即可直接下发指令。
```dart
DeviceBleClient(
  BluetoothDevice device, {
  String serviceUuid = defaultServiceUuid, // 默认 FFF0 / FFE0 段服务 UUID
  String charUuid = defaultCharUuid,       // 默认 FFF0 / FFE0 段特征 UUID
})
```

#### 2. `init()` —— 建立连接与 Notify 特征值订阅
```dart
Future<void> init()
```
*   **功能**：对传入的蓝牙物理设备执行 GATT 发现、提取目标服务与通信特征值，并**自动建立 Notify 双工监听通道**。

#### 3. `sendCommand()` —— 蓝牙下发 JSON 命令（含自动 MTU 扩容与异步等待）
```dart
Future<Map<String, dynamic>> sendCommand(
  Map<String, dynamic> payload, {
  int timeoutSec = 10,
})
```
*   **功能**：向设备发送 JSON 命令包，SDK 自动完成 **GATT 分包传输及 Notify 异步 Completer 转 Future 转换**。
*   **返回值**：设备 Notify 回传的统一 JSON 字典（含 `status` 状态和 `message` 内容）。

#### 💡 4. 蓝牙控制特征全对称 8 大 API 指令载荷与调用示例：

负责 App 蓝牙模块的同事，可以直接复制以下载荷模板在业务层通过 `sendCommand` 极速调用：

##### ① 🔑 安全鉴权 (AUTH)
任何户外/直连蓝牙指令（除配网外）执行前，必须下发鉴权。固件支持 **出厂及空配置强健容错机制**，若没有设定过密钥，使用默认密钥 `"my_secure_key_321"` 即可解锁。
```dart
final response = await bleClient.sendCommand({
  "action": "AUTH",
  "local_key": "my_secure_key_321" // NVS 内保存的密钥，默认 my_secure_key_321
});
// 成功回执: { "status": "success", "message": "authenticated" }
```

##### ② 🎨 表情包动画秒切刷新 (APPLY_EYES —— 🆕 支持休眠自动唤醒)
App 在户外直接通过蓝牙让屏幕切换播放躺在 SPIFFS 中的动图文件。**注：若设备正处于休眠关屏状态，发送此蓝牙命令会自动瞬间拉起背光、自动唤醒设备，实现极客级即时眨眼！**
```dart
final response = await bleClient.sendCommand({
  "action": "APPLY_EYES",
  "left": "test_anim.gif" // 存储在开发板 /spiffs/images/ 中的动图文件名
});
// 成功回执: { "status": "success", "message": "eyes_applied" }
```

##### ③ 🕒 RTC 硬件时间高精度对齐 (SYNC_TIME —— 🆕 对称功能)
将手机的高精度本地时钟通过蓝牙一键写入开发板，直接用 C 语言 `settimeofday` 校准硬件 RTC，即使离线断网，设备时间也绝对精确。
```dart
final response = await bleClient.sendCommand({
  "action": "SYNC_TIME",
  "timestamp": DateTime.now().millisecondsSinceEpoch ~/ 1000,
  "timezone_offset_hours": DateTime.now().timeZoneOffset.inHours,
});
// 成功回执: { "status": "success", "message": "2026-06-11 00:15:30" } （回显校准后的可视化本地时间）
```

##### ④ ⏳ 每日累计开屏亮屏时间获取 (GET_DURATION —— 🆕 对称功能)
向硬件读取今日（自开机起）双屏背光拉高工作的累计秒数。
```dart
final response = await bleClient.sendCommand({
  "action": "GET_DURATION"
});
// 成功回执: { "status": "success", "message": "3932" } （今日累计工作的秒数，APP 端可友好解算）
```

##### ⑤ 😴 软熄屏超低功耗一键待机 (ENTER_SLEEP —— 🆕 对称功能)
让设备瞬间熄屏、关停多线程 GIF 解码、并进入分时超低功耗慢待机广播。
```dart
final response = await bleClient.sendCommand({
  "action": "ENTER_SLEEP"
});
// 成功回执: { "status": "success", "message": "entering_sleep_mode" }
```

##### ⑥ ⚡ 蓝牙往返 RTT 连通性心跳探测 (PING —— 🆕 对称功能)
App 通过蓝牙发送超轻量 PING 包，在业务层解算蓝牙链路往返时延（RTT）。
```dart
final stopwatch = Stopwatch()..start();
final response = await bleClient.sendCommand({
  "action": "PING"
});
stopwatch.stop();
print('蓝牙链路往返时延 RTT: ${stopwatch.elapsedMilliseconds} ms');
// 成功回执: { "status": "success", "message": "pong" }
```

##### ⑦ 🔗 用户云端配对与序列化绑定 (BIND_USER —— 🆕 对称功能)
直接将用户 ID 和云端 Token 通过蓝牙下发，固件写入 NVS 永久区，并激发 C3 在联网后自动向云端拉起 `cloud_binding_task`。
```dart
final response = await bleClient.sendCommand({
  "action": "BIND_USER",
  "bind_token": "token_abcdefg_9988"
});
// 成功回执: { "status": "success", "message": "user_binding_saved_and_uploading" }
```

##### ⑧ 💡 指示灯物理外设开关 (TOGGLE_RELAY)
控制开发板载 LED 指示灯或继电器的开关状态。
```dart
final response = await bleClient.sendCommand({
  "action": "TOGGLE_RELAY",
  "state": 1 // 1 为打开指示灯，0 为关闭
});
// 成功回执: { "status": "success", "message": "relay_toggled" }
```

---

### 🟡 组件 B：`DeviceDiscoveryService`（局域网双轨设备搜索器）

用于在局域网下搜寻已连网在线的设备实体。

#### 1. `discoverEsp32DevicesOnLan()` —— 双轨并发搜索
```dart
Future<List<DeviceInfo>> discoverEsp32DevicesOnLan({
  Duration timeout = const Duration(seconds: 4),
})
```
*   **功能**：拉起 mDNS 与 UDP 组播双轨并发检索线程，去重并返回全量的 `DeviceInfo` 实体列表。

---

### 🔵 组件 C：`DeviceHttpClient`（局域网 HTTP REST 控制客户端）

用于局域网内对设备执行状态监测、控制，以及高频大表情包资产（GIF）的上传传输。

#### 1. `fetchDeviceInfo()` —— 获取整机信息状态 (含电量及节能)
```dart
Future<DeviceInfo?> fetchDeviceInfo(String baseUrl, {Duration timeout})
```
*   **返回值**：`DeviceInfo`，包含了 `batteryLevel`（0-100% 实时电量）和 `powerSavingMode`（是否休眠待机标志）。

#### 2. `uploadEyeData()` —— 流式分包上传动图大文件
```dart
Future<bool> uploadEyeData(String baseUrl, Uint8List data, String filename)
```
*   **功能**：流式切片分包将手机端表情大文件传输写入 C3 的物理闪存。**（注：此项功能由于蓝牙速率瓶颈，必须在局域网 Wi-Fi 下通过本 API 进行！）**

#### 3. `applyEyeConfigs()` —— 远程显示刷新（支持休眠自唤醒）
```dart
Future<bool> applyEyeConfigs(String baseUrl, String leftFilename, String rightFilename, {bool leftMirror, bool rightMirror})
```

#### 4. `fetchBatteryLevel()` —— 极速、独立电量获取通道
```dart
Future<int?> fetchBatteryLevel(String baseUrl, {Duration timeout})
```

#### 5. `pingDevice()` —— 局域网 RTT 网络延迟检测
```dart
Future<int?> pingDevice(String baseUrl, {Duration timeout})
```
*   **功能**：极速向 HTTP 服务发送 PING，并以高保真返回本次连接往返解算的时延（ms）。

#### 6. `bindUser()` —— 用户登录状态绑定
```dart
Future<bool> bindUser(String baseUrl, String userId, String bindToken, {Duration timeout})
```

#### 7. `enterSleepMode()` —— 一键熄屏节能待机状态控制
```dart
Future<bool> enterSleepMode(String baseUrl, {int sleepSeconds, Duration timeout})
```

#### 8. `fetchDisplayDuration()` —— 今日累计亮屏显示时长获取
```dart
Future<int?> fetchDisplayDuration(String baseUrl, {Duration timeout})
```

#### 9. `syncDeviceTime()` —— RTC 硬件时钟高精度同步
```dart
Future<String?> syncDeviceTime(String baseUrl, {Duration timeout})
```

---

## 📊 3. 统一实体模型参考

### `DeviceInfo` 设备状态字典
```dart
class DeviceInfo {
  final String firmware;         // 固件版本
  final String mode;             // 运作模式 ("STA" 或 "AP")
  final String apSsid;           // 板载自广播 AP 热点 SSID
  final String apIp;             // AP 热点网卡 IP
  final int apClients;           // 当前连入板载 AP 的手机数
  final String? staSsid;         // 连入的外部路由器 SSID
  final bool staConnected;       // 路由器连网状态指示
  final String? staIp;           // 路由器网卡 IP (局域网 IP)
  final String? mdnsHost;        // mDNS 广播主机名
  final bool isManager;          // 是否为群组主控制器
  final int? batteryLevel;       // 实时电池电量百分比 (0-100)
  final bool? powerSavingMode;   // 休眠节电模式状态指示 (true 为处于熄屏待机)
}
```
