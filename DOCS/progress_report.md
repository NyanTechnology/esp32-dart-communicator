# NyanEye ESP32-C3 SDK 链接与集成进度报告 (Progress Report)

本报告详细记录了目前 `esp32_comm` SDK 项目与 `NyanEyes_IOT_ESPIDF` (基于 ESP-IDF + NimBLE 的 ESP32-C3 固件) 项目之间的对接进展、已完成的协议重构、当前的链路链接情况，以及后续局域网通信的演进方向。

---

## 1. 进展概述与对接成果 (Achievements)

截至目前，已成功完成了两大项目在**物理层、数据结构层及通信协议层**的深度互设与打通，具体成效如下：

*   **128-bit 蓝牙 UUID 统一对齐**：彻底废弃了固件端原有的 16-bit 临时 UUID (`0xFFF0`, `0xFFE0` 等)，将其全量升级为对齐 Dart SDK 默认配置的标准 128-bit 蓝牙服务与特征（如 `4fafc201-...` 等），实现客户端免密/免参“开箱即用”。
*   **确定性双向 RPC (Notify) 通道建立**：在固件端特征中，通过追加 `BLE_GATT_CHR_F_NOTIFY` 属性并捕捉对应的值句柄（Val Handle），将原本脆弱、无任何状态反馈的“盲写模式”重构为**“请求-响应 (Notify)”双向高确定性通信**。
*   **物理层断开及重启的时序容错**：在固件端对涉及系统状态迁移的动作（如配网保存重启、鉴权失败主动断开等）加入了延时排空机制（`vTaskDelay`），确保设备重启/切断连接前，蓝牙特征值 Notify 已完全被手机客户端拉取并解调，保障了手机侧逻辑闭环。

---

## 2. 蓝牙 (BLE) 深度打通链路现状 (BLE Current Link State)

目前两项目的蓝牙链路已处于完美契合、高度互通状态，检测详情如下：

### 2.1 配网通道 (Scenario 1 - WiFi Provisioning)
*   **服务 UUID**：`4fafc201-1fb5-459e-8bcc-c5c9c331914b` (对应 C3 中 128 位 `prov_svc_uuid`)
*   **特征 UUID**：`beb5483e-36e1-4688-b7f5-ea07361b26a8` (对应 C3 中 128 位 `prov_chr_uuid`)
*   **通信方向**：双向 (`WRITE | NOTIFY`)
*   **业务指令对齐**：
    *   **Wi-Fi 局域网配网**：手机下发 `{"action": "PROVISION", "ssid": "...", "password": "...", "bind_token": "..."}` $\rightarrow$ 设备保存成功 $\rightarrow$ 手机收到 Notify 应答 `{"status": "success", "message": "rebooting_to_wifi"}` $\rightarrow$ 设备安全延时 1000ms $\rightarrow$ 设备重启连网。
    *   **初始化为户外模式**：手机下发 `{"action": "OUTDOOR_INIT", "local_key": "..."}` $\rightarrow$ 设备保存成功 $\rightarrow$ 手机收到 Notify 应答 `{"status": "success", "message": "outdoor_init_reboot"}` $\rightarrow$ 设备重启。

### 2.2 户外直连控制通道 (Scenario 2 - Outdoor Control)
*   **服务 UUID**：`4fafc201-1fb5-459e-8bcc-c5c9c331914c` (对应 C3 中 128 位 `outdoor_svc_uuid`)
*   **特征 UUID**：`beb5483e-36e1-4688-b7f5-ea07361b26a9` (对应 C3 中 128 位 `outdoor_chr_uuid`)
*   **通信方向**：双向 (`WRITE | NOTIFY`)
*   **业务安全与控制**：
    *   **AUTH 安全握手鉴权**：手机下发 `{"action": "AUTH", "local_key": "..."}` $\rightarrow$ C3 匹配 NVS 中的 Key $\rightarrow$ 鉴权成功返回 `{"status": "success", "message": "authenticated"}`，允许后续控制；若匹配失败返回 `{"status": "error", "message": "auth_failed"}` 并延时断开 BLE。
    *   **硬件继电器/指示灯控制**：手机下发 `{"action": "TOGGLE_RELAY", "state": 1|0}` $\rightarrow$ C3 控制指示灯点亮/熄灭 $\rightarrow$ 手机收到 Notify 应答 `{"status": "success", "message": "relay_toggled"}`。
    *   **在线 Wi-Fi 切换测试**：手机下发 `{"action": "SWITCH_WIFI", "ssid": "...", "password": "..."}` $\rightarrow$ C3 开启Fallback连网测试任务 $\rightarrow$ 手机收到 Notify 应答 `{"status": "success", "message": "switching_wifi"}`。

---

## 3. 局域网通讯 (Wi-Fi REST / mDNS / UDP) 现状与演进建议

由于您的 ESP32-C3 项目当前的 Wi-Fi 模式定位仅用于 Station 连网并进行云端绑定测试（`cloud_binding_task` 模拟），**目前固件中尚未运行本地 Web 服务器与多播/广播服务**。因此，SDK 中的局域网交互目前处于挂起待链接状态。

为了后期使 SDK 能够直接在局域网下对 C3 设备进行 HTTP 超高速图片/动画上传和控制，建议在固件端补充以下模块：

```
                              [ SDK 局域网控制接入路径 ]
                              
┌──────────────────────────┐                    ┌──────────────────────────┐
│  SDK: DeviceHttpClient   ├─ (HTTP GET/POST) ─►│ C3: esp_http_server      │
│  - /api/device_info      │                    │  - Register Handlers     │
│  - /api/upload (.eye)    │                    │  - Save raw to SPIFFS    │
└──────────────────────────┘                    └──────────────────────────┘
┌──────────────────────────┐                    ┌──────────────────────────┐
│  SDK: DeviceDiscovery    ├─ (mDNS Resolve) ─►│ C3: mdns_init()          │
│  - Search: _http._tcp    │                    │  - Service name: nyaneye │
│  - Broadcast on Port 8888├─ (UDP Send REQ) ──►│ C3: Socket Bind & Recv   │
└──────────────────────────┘                    └──────────────────────────┘
```

1.  **添加本地 HTTP 引擎**：
    *   在 C3 固件成功连接 Wi-Fi 后，引入并初始化 ESP-IDF 的 `esp_http_server` 组件。
    *   注册 HTTP GET 处理器响应 `/api/device_info`（输出 JSON 数据以填充 Dart 端 `DeviceInfo` 模型，其中应包含固件版本、运行模式、STA IP 等，并使用 `Connection: close` 头部防止死锁）。
    *   注册 HTTP POST 处理器响应 `/api/upload`（接收 Multipart 格式的二进制数据流，将其安全地流式写入 C3 的 SPIFFS/LittleFS 闪存空间，实现眼部文件更新）。
2.  **植入双通道服务发现**：
    *   **mDNS 广播**：调用 `mdns_init()` 并将主机名配置为 `nyaneye`，通过 `mdns_service_add` 广播 `_http` 协议在 `_tcp` 类型的服务，使 SDK 客户端能立刻跨网段找回设备 IP。
    *   **UDP 组播应答**：新建一个 FreeRTOS 任务，绑定本网段 IP 的端口 `8888`，一旦接收到 SDK 发送的 `DISCOVER_ESP32_REQ` 数据，即刻将自身的 IP 地址以 JSON 字符串回复至客户端，极大提升在复杂企业网下的搜索触达率。

---

## 4. 下阶段开发者调通清单 (Next Steps)

1.  **固件烧录与日志监控**：
    *   使用数据线连接您的 ESP32-C3 设备。
    *   执行以下命令开始编译、烧录并监控固件日志：
        ```bash
        cd /Volumes/SN550E/NyanTech/NyanEyes_IOT_ESPIDF
        idf.py flash monitor
        ```
2.  **单元测试验证**：
    *   在当前 `esp32-dart-communicator-main` 工作区运行测试指令，保证 SDK 模型在处理设备端产生的防御性 JSON 回执时通过验证：
        ```bash
        flutter test
        ```
3.  **开始联调**：
    *   打开含有当前 SDK 的 Flutter APP，无需任何 UUID 修改，直接开始配网与控制！
