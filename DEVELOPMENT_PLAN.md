# 😺 NyanEye 软硬件合规性审计与后续研发规划书 (Development Plan)

本开发文档依据项目最新的 **`REQUIREMENTS.md`（功能需求与接口规范）**，对当前工作区的 **Flutter SDK / App 源码** 以及外部 **ESP32-C3 IOT 固件源码** 进行了全面的代码合规性比对审计。文档详细列出了已完成的接口、存在的研发缺口（Gap），并为两端开发者制定了下一阶段的**一键通车迭代计划与任务清单（Backlog）**。

---

## 📊 1. 需求达成状态总体审计 (Audit Summary)

目前对 `REQUIREMENTS.md` 中定义的 10 大功能核心需求进行全面盘点，状态分类如下：

*   **🟩 100% 已满足 (Fully Satisfied)**：**7 项**（需求 1、2、3、4、5、6、7）—— 链路完全通畅，功能验收通过！
*   **🟪 已延期/挂起 (Postponed)**：**1 项**（需求 8）—— 控制休眠功能，因优先级调整已进行排期挂起。
*   **🟥 当前缺失 (Missing / Backlog)**：**2 项**（需求 9、10）—— 新增屏幕显示时长获取及 RTC 时间同步功能。

### 📋 需求合规性对照矩阵 (Compliance Matrix)

| 需求 ID | 功能模块描述 | 固件端现状 (ESP32-C3) | SDK/App 端现状 (Flutter) | 合规结论 |
| :--- | :--- | :--- | :--- | :--- |
| **REQ-1** | **蓝牙配对与安全建立** | 已实现广播 `"NyanEyes_ESP32"` 并绑定 128位 UUID，具备 AUTH 鉴权失败断连保护。 | `DeviceBleClient` 已实现 128位 GATT 通道解析与 Notify 监听。 | **🟩 100% 已满足** |
| **REQ-2** | **网络配置信息配置** | `ble_server.c` 成功解析 cJSON 组包，并可安全写入 NVS 重启。 | App 完美封装配网 Payload 结构并支持下发。 | **🟩 100% 已满足** |
| **REQ-3** | **设备基础信息获取** | 已完美集成 `battery_level` 和 `power_saving_mode` 字段到 `GET /api/device_info`。 | `DeviceInfo` 实体类、JSON 解析层和局域网控制面板 UI 已全部对齐显示。 | **🟩 100% 已满足** |
| **REQ-4** | **眼部显示与文件上传** | 已实现 `POST /api/upload` 写入 SPIFFS，以及 `GET /api/eyes/apply` 屏幕刷新。 | SDK 已封装 Multipart 上传和大图应用，测试 App 工作正常。 | **🟩 100% 已满足** |
| **REQ-5** | **电量数据读取与上报** | 已实现独立 `GET /api/battery` 局域网电量获取接口。 | SDK 补全 `fetchBatteryLevel` API，UI 新增一键刷新指示。 | **🟩 100% 已满足** |
| **REQ-6** | **基础连接性检测 (Ping)** | 已实现高响应 `/api/ping` GET 心跳探测接口。 | SDK 补全 `pingDevice` API 支持毫秒级 RTT 解析，UI 新增一键检测。 | **🟩 100% 已满足** |
| **REQ-7** | **用户信息与云端绑定** | 已实现 `POST /api/user/bind` 接口，自动存入 NVS 并拉起异步 cloud_binding_task。 | SDK 补全 `bindUser` POST 动作，UI 新增专用绑定控制面板。 | **🟩 100% 已满足** |
| **REQ-8** | **节能与睡眠控制指令** | `power_manager.c` 具备睡眠逻辑，但 **未在 HTTP 服务中注册控制路由**。 | 缺失一键关屏休眠控制接口。 | **🟪 已延期/挂起** |
| **REQ-9** | **累计亮屏时长获取** | 缺失 `GET /api/display/duration` 局域网获取接口。 | 缺失累计亮屏时长获取 Dart 接口与 UI 统计面板。 | **🟥 当前缺失** |
| **REQ-10** | **时间同步功能** | 缺失 `POST /api/time/sync` 局域网硬件 RTC 时间同步接口。 | 缺失同步系统时间到硬件 RTC 的 API 与操作。 | **🟥 当前缺失** |

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

### REQ-8: 节能与睡眠控制指令 [已延期]
*   **Gap 描述**：因项目排期与测试场景优先级调整，该功能已延后挂起。

### REQ-9: 屏幕每日累计显示时长获取
*   **Gap 描述**：App 需要展示设备每日的工作亮屏累计时间做健康度分析。
*   **研发方案**：
    *   在固件端注册 `GET /api/display/duration` 接口，自系统开机起并在后台周期性读取 RTC（或定时器）计算累加工作时间，并返回该秒数。
    *   在 SDK 封装 `fetchDisplayDuration` 接口。

### REQ-10: 系统时间同步功能
*   **Gap 描述**：离线摆件内部时钟经常发生偏差，需要每次连接 App 时自动对齐。
*   **研发方案**：
    *   在固件端注册 `POST /api/time/sync` 接口，解析手机端下发的 Unix 毫秒/秒级时间戳及本地时区，通过 `settimeofday` 重写底层的系统 RTC。
    *   在 SDK 封装 `syncDeviceTime` 接口。

---

## 🛠️ 3. 下一阶段双端开发任务清单 (Backlog)

根据最新需求调整，双端开发人员需认领并执行以下剩余的任务清单：

### 🔌 固件端开发任务 (ESP32-C3 Firmware Backlog)

- [ ] **Task 1: 实现 `/api/display/duration` 亮屏时长获取**
  * 在 `main/http_server.c` 中添加 `device_duration_get_handler()`，返回 `{"daily_duration_seconds": xxx}`（计算今日累计开机工作秒数）。
  * 注册该路由。
- [ ] **Task 2: 实现 `/api/time/sync` 时间同步接口**
  * 在 `main/http_server.c` 中添加 `device_time_sync_post_handler()`。
  * 解析时间戳和时区，调用 `settimeofday` 设置 ESP32 系统时钟，并返回包含 `synchronized_time` 的应答 JSON。
  * 注册该路由。

### 📱 SDK & App 端开发任务 (Flutter SDK & App Backlog)

- [ ] **Task 3: 补全 `DeviceHttpClient` 新增的两个核心控制方法**
  * 在 `lib/src/services/device_http_client.dart` 类中追加以下方法：
    ```dart
    // REQ-9: 获取每日屏幕累计工作时长（秒数）
    Future<int?> fetchDisplayDuration(String baseUrl, {Duration timeout = const Duration(seconds: 4)});
    
    // REQ-10: 将手机本地高精度时间同步到硬件 RTC
    Future<bool> syncDeviceTime(String baseUrl, {Duration timeout = const Duration(seconds: 4)});
    ```
- [ ] **Task 4: 升级 App 局域网控制面板 (UI 升级)**
  * 在 `lan_tester_screen.dart` 中，增设“亮屏累计时间数据看板”。
  * 增设一键“同步手机高精度系统时间到 C3”的精美交互按钮。
