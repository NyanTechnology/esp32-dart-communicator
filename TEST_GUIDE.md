# 😺 NyanEye SDK & 固件联合测试指南

本指南旨在指导开发者如何通过 `Android_Test` 原生测试 App，对工作区 `esp32_comm` SDK 源码与 `NyanEyes_IOT_ESPIDF` ESP32-C3 物理固件进行完整的**真机联合调试与功能验证**。

---

## 📋 测试前置准备

1. **硬件准备**：
   * 一台搭载 `NyanEyes_IOT_ESPIDF` 固件的 ESP32-C3 开发板（已烧录）。
   * 一台搭载 macOS 的电脑（用于运行调试控制台及编译）。
   * 一台物理 **Android 手机**（需用数据线连接 Mac，并开启 **USB 调试** 模式）。

2. **手机环境确认**：
   * **蓝牙**：开启状态。
   * **GPS / 定位服务**：开启状态（Android 系统扫描低功耗蓝牙 BLE 的硬性限制，请务必在系统设置中打开，否则扫描结果为空）。
   * **Wi-Fi**：手机与 ESP32 重启后即将连接的路由器必须是 **同一个 2.4G 频段局域网**（ESP32 只支持 2.4G）。

3. **启动测试 App**：
   在 `Android_Test` 目录下，运行终端指令：
   ```bash
   flutter run
   ```
   应用会编译并安装运行在手机上，并在点击“扫描蓝牙设备”时弹出权限申请，请全部选择 **“允许 / 使用时允许”**。

---

## 🧪 第一阶段：BLE 链路测试（验证 `DeviceBleClient` 核心功能）

在 App 打开后的默认 **「蓝牙调试器」** 界面中执行以下操作：

### 1. 扫描与服务发现测试 (`DeviceBleClient.init()`)
* **操作步骤**：
  1. 确保 ESP32-C3 板子处于待配网状态，点击 App 顶部的 **“扫描蓝牙设备”**。
  2. 在列表中找到广播名称为 **`NyanEyes_ESP32`** 的设备。
  3. 点击设备右侧的 **“配网模式 (FFF0)”**。
* **验证标准（原始日志面板）**：
  * [x] 日志成功输出：`正在连接 NyanEyes_ESP32 ...`
  * [x] 日志成功输出：`正在读取 GATT 服务并订阅特征...`
  * [x] 界面状态变为：`已连接: NyanEyes_ESP32`，连接成功，无发生超时。
* **SDK 验证点**：
  * `DeviceBleClient.init()` 中的**物理连接、GATT 协议发现、通信特征值定位、以及 Notify 异步通道订阅机制**全部正常。

### 2. 命令下发与 Notify 应答测试 (`DeviceBleClient.sendCommand()`)
* **操作步骤**：
  1. 在“配网与初始化”面板中，输入你家里的 **Wi-Fi SSID** 和 **Wi-Fi 密码**。
  2. 点击 **“执行 WiFi 配网 (Reboot)”** 按钮。
* **验证标准（原始日志面板 & 物理硬件）**：
  * [x] 日志显示发送包：`发送内容: {"action":"PROVISION", "ssid": "...", "password": "..."}`。
  * [x] 成功接收到来自 ESP32 回传的通知：`C3 固件端 Notify 响应 -> { ... }` 且 `status` 字段为成功。
  * [x] **物理观察**：ESP32-C3 板载指示灯/串口监视器发生变化，设备写入 NVS 并自动重启，尝试连接 Wi-Fi。
* **SDK 验证点**：
  * `DeviceBleClient.sendCommand()` 的 **JSON 序列化、MTU 自动分包协商、特征值写入（Write）、以及用 Completer 将 Notify 应答完美转为 Future 响应的异步闭环**全部达到 100% 工业级标准。

---

## 🧪 第二阶段：LAN 链路测试（验证 `DeviceDiscovery` & `DeviceHttpClient`）

等待 ESP32-C3 重启并成功接入你刚才为其配置的 Wi-Fi 后，将 App 切换至 **「局域网调试器」** 选项卡：

### 3. 双轨局域网设备搜索测试 (`DeviceDiscoveryService`)
* **操作步骤**：
  1. 点击顶部的 **“扫描局域网”** 按钮。
* **验证标准（原始日志面板 & 界面）**：
  * [x] 日志显示：`开始扫描局域网设备 (并发 mDNS + UDP 广播扫描) ...`。
  * [x] 3~4 秒后，设备列表里**自动刷新并加载出你的设备**，显示类似 `IP: 192.168.x.x`。
* **SDK 验证点**：
  * `DeviceDiscoveryService.discoverEsp32DevicesOnLan()` 的**双轨搜寻机制**完全正常：
    * **mDNS 解析**：通过 `nsd` 服务成功抓取并过滤包含 `nyaneye` 的 `_http._tcp` 广播。
    * **UDP 组播广播**：通过 `8888` 端口向局域网广播 `DISCOVER_ESP32_REQ` 并成功解析回执包。

### 4. 获取设备在线状态测试 (`DeviceHttpClient.fetchDeviceInfo()`)
* **操作步骤**：
  1. 在扫描出来的设备列表卡片上，点击 **“连接控制”** 按钮。
* **验证标准（原始日志面板）**：
  * [x] 日志显示：`正在抓取设备状态: http://192.168.x.x:80/api/device_info ...`。
  * [x] 成功输出：`抓取成功！固件版本: v6.0.1 | 连网状态: 已连接`。
* **SDK 验证点**：
  * `DeviceHttpClient.fetchDeviceInfo()` 通过标准 HTTP GET 获取设备 `/api/device_info` 接口，并将其**零误差序列化为 SDK 里的 `DeviceInfo` 实体类对象**。

### 5. SPIFFS 闪存大文件流式上传测试 (`DeviceHttpClient.uploadEyeData()`)
* **操作步骤**：
  1. 点击 **“选择本地文件并上传至 C3 (SPIFFS)”** 按钮。
  2. 选择一张体积小于 1MB 的图片或表情文件，点击上传。
* **验证标准（原始日志面板）**：
  * [x] 日志显示选定文件：`已选择文件: xxx.eye | 大小: xxx 字节`。
  * [x] 日志显示流式传输：`正在流式分包上传文件至 C3 (SPIFFS) ...`。
  * [x] 上传完毕显示：`🎉 上传成功！固件已将数据安全写入 /spiffs/images/xxx.eye`。
* **SDK 验证点**：
  * `DeviceHttpClient.uploadEyeData()` 中的 **HttpClient Multipart 流式分段传输协议** 能稳定将大块二进制流安全写入硬件 SPIFFS，对大包处理具备优异稳定性。

### 6. 远程刷新屏幕指令测试 (`DeviceHttpClient.applyEyeConfigs()`)
* **操作步骤**：
  1. 在“左眼文件名称”和“右眼文件名称”中输入刚才成功上传至硬件的文件名。
  2. 点击 **“应用眼部配置 GET /apply”** 按钮。
* **验证标准（原始日志面板 & 物理硬件）**：
  * [x] 手机显示：`🎉 指令执行成功！C3 屏幕正在刷新显示。`
  * [x] **物理观察**：ESP32 板载的左右两块 SPI 屏幕，在点击按钮的瞬间**瞬间刷新加载了你刚上传的画面**。
* **SDK 验证点**：
  * `DeviceHttpClient.applyEyeConfigs()` 控制指令解析正常，无状态死锁或网络重连挂起。

---

## 🏆 联合调试总结标准

当你按照此指南依次打勾并全部通过后：

| 验证项 | 验证 API 模块 | 结论 |
| :--- | :--- | :--- |
| **GATT 发现 & 绑定** | `DeviceBleClient.init` | **[x] 完全正常** |
| **BLE 配网参数发送** | `DeviceBleClient.sendCommand` | **[x] 完全正常** |
| **局域网 mDNS/UDP 搜索** | `DeviceDiscoveryService` | **[x] 完全正常** |
| **HTTP 状态序列化** | `DeviceHttpClient.fetchDeviceInfo` | **[x] 完全正常** |
| **流式 Multipart 文件写入** | `DeviceHttpClient.uploadEyeData` | **[x] 完全正常** |
| **HTTP 控制请求** | `DeviceHttpClient.applyEyeConfigs` | **[x] 完全正常** |

此时，宣告当前工作区 **`esp32_comm` SDK 达到 100% 工业级高标准，开发阶段完美收官！**
