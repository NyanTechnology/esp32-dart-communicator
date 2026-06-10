# 😺 NyanEye 软硬件合规性审计与后续研发规划书 (Development Plan)

本开发文档依据项目最新的 **`REQUIREMENTS.md`（功能需求与接口规范）**，对当前工作区的 **Flutter SDK / App 源码** 以及外部 **ESP32-C3 IOT 固件源码** 进行了全面的代码合规性比对审计。文档详细列出了已完成的接口、存在的研发缺口（Gap），并为两端开发者制定了下一阶段的**一键通车迭代计划与任务清单（Backlog）**。

---

## 📊 1. 需求达成状态总体审计 (Audit Summary)

目前对 `REQUIREMENTS.md` 中定义的 8 大功能核心需求进行全面盘点，状态分类如下：

*   **🟩 100% 已满足 (Fully Satisfied)**：**3 项**（需求 1、2、4）—— 链路完全通畅，功能验收通过。
*   **🟨 部分满足 (Partially Satisfied)**：**2 项**（需求 3、5）—— 底层通路已通，但需在 JSON 模型中补全键值对。
*   **🟥 当前缺失 (Missing / Backlog)**：**3 项**（需求 6、7、8）—— 属于下一阶段需优先排期并闭环的纯新增接口。

### 📋 需求合规性对照矩阵 (Compliance Matrix)

| 需求 ID | 功能模块描述 | 固件端现状 (ESP32-C3) | SDK/App 端现状 (Flutter) | 合规结论 |
| :--- | :--- | :--- | :--- | :--- |
| **REQ-1** | **蓝牙配对与安全建立** | 已实现广播 `"NyanEyes_ESP32"` 并绑定 128位 UUID，具备 AUTH 鉴权失败断连保护。 | `DeviceBleClient` 已实现 128位 GATT 通道解析与 Notify 监听。 | **🟩 100% 已满足** |
| **REQ-2** | **网络配置信息配置** | `ble_server.c` 成功解析 cJSON 组包，并可安全写入 NVS 重启。 | App 完美封装配网 Payload 结构并支持下发。 | **🟩 100% 已满足** |
| **REQ-3** | **设备基础信息获取** | 已实现 `GET /api/device_info` 接口，包含版本、SSID、IP 和在线状态。 | `DeviceInfo` 模型与 HTTP 请求逻辑已建立，且支持 IP 提取。 | **🟨 部分满足** *(缺电量与节能状态)* |
| **REQ-4** | **眼部显示与文件上传** | 已实现 `POST /api/upload` 写入 SPIFFS，以及 `GET /api/eyes/apply` 屏幕刷新。 | SDK 已封装 Multipart 上传和大图应用，测试 App 工作正常。 | **🟩 100% 已满足** |
| **REQ-5** | **电量数据读取与上报** | 蓝牙端标准电量服务 `0x180F` (GATT 2A19) 已通。 | App 已实现蓝牙读取电量与 Notification 监听。 | **🟨 部分满足** *(缺局域网 HTTP 读取接口)* |
| **REQ-6** | **基础连接性检测 (Ping)** | **未开发。** 缺失 `GET /api/ping` 心跳接口。 | **未开发。** 缺失 `pingDevice` HTTP 检测逻辑。 | **🟥 当前缺失** |
| **REQ-7** | **用户信息与云端绑定** | 固件已集成云端上报任务 `cloud_binding_task`，但无外部 HTTP 写入接口。 | **未开发。** 缺失用户信息绑定 POST API。 | **🟥 当前缺失** |
| **REQ-8** | **节能与睡眠控制指令** | `power_manager.c` 具备睡眠逻辑，但 **未在 HTTP 服务中注册控制路由**。 | **未开发。** 缺失一键关屏休眠控制接口。 | **🟥 当前缺失** |

---

## 🔍 2. 研发缺口深度剖析 (Gap Analysis)

### REQ-3: 设备基础信息获取 ＆ REQ-5: 电量数据局域网通道
*   **Gap 描述**：目前手机在通过 Wi-Fi 控制板子时，主界面通常需要展示“电量图标”、“电量百分比”和“当前节电模式状态”。但目前的固件 `/api/device_info` 回执中**缺失了这两个字段**，导致局域网面板无法展示电池健康度。
*   **修复建议**：
    *   在固件端 `device_info_get_handler()` 中，使用 NVS 读取节能状态并获取电源管理器电池电压，追加 `battery_level` (0-100) 与 `power_saving_mode` (bool) 键值对。
    *   在 Flutter SDK 的 `DeviceInfo` 实体类中，补齐这两个字段的反序列化映射。

### REQ-6: 基础连接性检测 (Ping)
*   **Gap 描述**：App 目前在执行上传大文件或频繁发送控制指令前，无法极速检测连接畅通度，如果连接失效只能等待高时延的网络超时。
*   **研发方案**：在固件端注册一个超轻量路由 `/api/ping`。该处理器不查询 ADC、不读 NVS，只在内存中返回 `{"status":"pong"}`，RTT（往返时延）小于 5ms，专供 App 做低延迟心跳握手。

### REQ-7: 用户信息与绑定配置
*   **Gap 描述**：设备已经具备了强大的 `cloud_binding_task`（云端绑定多任务线），可将配网用户的 Token 上报给云端实现所有权注册，但目前固件和 App 均缺失了“通过 HTTP 写入绑定信息”的 REST 路径。
*   **研发方案**：
    *   在固件端添加 `POST /api/user/bind` 处理器，解析 `user_id` 与 `bind_token` 并存入 NVS，然后通过 FreeRTOS 动态拉起 `cloud_binding_task` 上报线程。
    *   在 SDK 的 `DeviceHttpClient` 中新增 `bindUser(baseUrl, userId, token)`。

### REQ-8: 节能与睡眠控制指令
*   **Gap 描述**：为保护 OLED/LCD 屏幕寿命并极大地延长移动电池续航，用户在 App 中点击“熄屏/一键休眠”时，硬件必须能够断电。目前固件已实现底层低功耗管理，但缺失了暴露在外的控制接口。
*   **研发方案**：
    *   在固件端添加 `POST /api/power/sleep`，接收睡眠时间参数，触发 `display_set_backlight(0)`，调用 GC9D01 的关屏 `Sleep In` 保护，最终调用 ESP-IDF 的 `esp_deep_sleep_start()`。
    *   在 SDK 端封装 `enterSleepMode` 控制接口。

---

## 🛠️ 3. 下一阶段双端开发任务清单 (Backlog)

为了实现两端一键配齐、100% 闭环，双端开发人员需优先认领并执行以下任务：

### 🔌 固件端开发任务 (ESP32-C3 Firmware Backlog)

- [ ] **Task 1: 升级 `device_info` 状态接口**
  * 修改 `main/http_server.c` 中的 `device_info_get_handler()` 接口。
  * 获取电源管理器解算百分比，追加 `cJSON_AddNumberToObject(root, "battery_level", battery_val)` 和 `cJSON_AddBoolToObject(root, "power_saving_mode", is_saving)`。
- [ ] **Task 2: 实现 `/api/ping` 快速握手接口**
  * 在 `main/http_server.c` 中添加 `device_ping_get_handler()`，直接返回 `{"status":"pong"}`。
  * 在 `http_server_start()` 中注册 `/api/ping` 路由。
- [ ] **Task 3: 实现 `/api/user/bind` 本地绑定路由**
  * 在 `main/http_server.c` 中注册 `POST /api/user/bind` 路由及处理器。
  * 解析用户 JSON 信息，写入 NVS 并开启后台 `cloud_binding_task`。
- [ ] **Task 4: 实现 `/api/power/sleep` 软件一键关机/低功耗休眠**
  * 注册 `POST /api/power/sleep` 路由及处理器。
  * 触发 LCD 关机状态，延时 1s 后直接引导芯片进入 `esp_deep_sleep_start()` 深睡眠，实现极致省电。

### 📱 SDK & App 端开发任务 (Flutter SDK & App Backlog)

- [ ] **Task 5: 升级 `DeviceInfo` 数据实体模型**
  * 修改 `lib/src/models/device_info.dart` 类，补齐 `batteryLevel` 和 `powerSavingMode` 两个属性。
  * 升级 `DeviceInfo.fromJson` 映射层，做好空安全与类型容错拦截。
- [ ] **Task 6: 补全 `DeviceHttpClient` 缺失的核心控制方法**
  * 在 `lib/src/services/device_http_client.dart` 类中追加以下方法：
    ```dart
    // REQ-6: 轻量级 RTT 连通性检测
    Future<bool> pingDevice(String baseUrl, {Duration timeout = const Duration(seconds: 2)});
    
    // REQ-7: 远程用户信息与云端账号绑定
    Future<bool> bindUser(String baseUrl, String userId, String token);
    
    // REQ-8: 远程一键熄屏软关机进深睡眠
    Future<bool> enterSleepMode(String baseUrl, {int sleepSeconds = 3600});
    ```
- [ ] **Task 7: 升级 App 局域网控制面板 (UI 升级)**
  * 在 `lan_tester_screen.dart` 中追加“实时电量和节电状态指示”。
  * 增加“用户信息绑定输入面板”和“远程一键低功耗休眠按钮”。
  * 将 `TEST_GUIDE.md` 规范里的测试指标在 App 界面上以图形化 Checklist 完全闭环呈现！
