# 😺 NyanEye 智能摆件功能需求与接口规范 (Requirements Specification)

本文件详细定义了 NyanEye 智能双屏摆件的**核心功能需求、蓝牙（BLE）与局域网（LAN HTTP）接口技术规范**。开发人员在进行客户端 SDK、App 界面或 ESP32-C3 固件开发时，均须以此规范为准。

---

## 📋 功能需求总览 (Checklist)

- [ ] **1. 蓝牙配对与安全建立** (BLE Connection & Bonding)
- [ ] **2. 网络配置信息配置** (Wi-Fi Credentials Provisioning via POST / BLE)
- [ ] **3. 设备基础信息获取** (Device Status & Info via GET)
- [ ] **4. 眼部动画应用与资产上传** (Eyes Config & SPIFFS File Upload)
- [ ] **5. 电量数据读取与上报** (Battery Level GET)
- [ ] **6. 基础连接性检测 (Ping)** (Connectivity Heartbeat Check)
- [ ] **7. 用户信息/云端绑定配置** (User Profile / Binding Info POST)
- [ ] **8. 节能/休眠控制指令 [已延后]** (Power Saving & Sleep Mode Command - Postponed)
- [ ] **9. 屏幕每日累计显示时长获取 (GET)** (Daily Display Active Duration GET)
- [ ] **10. 系统时间同步功能 (POST)** (System Time Synchronization POST)

---

## 🛠️ 接口技术规范与实现指引

### 1. 蓝牙配对与安全建立
设备通过低功耗蓝牙（BLE）公开广播，App 搜索到设备后建立 GATT 安全连接，并根据需求进行配对/绑定。

*   **广播名称 (Local Name)**：`NyanEyes_ESP32`
*   **服务定义**：
    *   **极速配网服务 (FFF0 段)**：`4fafc201-1fb5-459e-8bcc-c5c9c331914b`
    *   **户外直连控制服务 (FFE0 段)**：`4fafc201-1fb5-459e-8bcc-c5c9c331914c`
*   **安全机制**：
    *   在 **户外直连服务** 下，手机在连接后必须优先下发 `AUTH` 安全握手包（参见第 2 点）。若在 `10秒` 内未通过鉴权，设备端将主动 Terminate 断开蓝牙物理链路，防止恶意控制。

---

### 2. 网络配置信息配置 (POST)
网络配网和密钥初始化配置主要在 **极速配网 (FFF0)** 的特征通道下完成。

*   **BLE 特征 UUID**：`beb5483e-36e1-4688-b7f5-ea07361b26a8`
*   **通信属性**：`WRITE` & `NOTIFY`
*   **控制指令 Payload (JSON格式)**：
    ```json
    {
      "action": "PROVISION",
      "ssid": "My_Home_WiFi_SSID",
      "password": "My_Secure_WiFi_Password_123",
      "bind_token": "token_xyz_from_cloud"  // 选填，云端临时绑定令牌
    }
    ```
*   **设备端 Notify 响应**：
    ```json
    {
      "status": "success",
      "message": "rebooting_to_wifi"
    }
    ```

---

### 3. 设备基础信息获取 (GET)
当设备重启连入 Wi-Fi 后，App 通过标准局域网 HTTP GET 接口抓取设备的系统运行状态、连接情况以及版本信息。

*   **请求路由**：`GET /api/device_info`
*   **请求头部**：`Connection: close`（防止 TCP 连接持续占用导致死锁）
*   **设备端响应 (JSON 200 OK)**：
    ```json
    {
      "firmware": "v6.0.1",
      "running_mode": "wifi_sta",           // 运行模式：wifi_sta / outdoor
      "sta_ssid": "Hikari_IOT",             // 当前连入的路由器 SSID
      "sta_ip": "10.20.0.163",              // 局域网物理 IP
      "sta_connected": true,                 // 连网在线状态
      "battery_level": 98,                  // 电池电量 (0 - 100)
      "power_saving_mode": false            // 节能模式是否开启
    }
    ```

---

### 4. 眼部显示指令与文件上传
包含**文件实体上传**以及**屏幕配置刷新**两部分。

#### A. 表情动图/眼部资产上传 (POST)
*   **请求路由**：`POST /api/upload`
*   **Content-Type**：`multipart/form-data`
*   **数据体**：包含名为 `file` 的二进制文件流，以及 `filename`。
*   **存储路径**：ESP32 接收并安全分包写入 `/spiffs/images/<filename>`。
*   **设备端响应**：`{"status":"success"}`

#### B. 应用眼部显示配置 (GET)
*   **请求路由**：`GET /api/eyes/apply`
*   **请求参数**：
    *   `left`：左眼显示图像的存储路径（例如 `/images/test_anim.gif`）。
    *   `right`：右眼显示图像的存储路径。
    *   `leftMirror`：左眼是否使能水平镜像（`true` / `false`）。
    *   `rightMirror`：右眼是否使能水平镜像（`true` / `false`）。
*   **请求示例**：
    `GET /api/eyes/apply?left=/images/blink.gif&right=/images/blink.gif&leftMirror=true&rightMirror=false`
*   **设备端响应 (JSON 200 OK)**：`{"status":"success"}`

---

### 5. 电量数据获取 (GET)
提供蓝牙和局域网两种读取渠道：

*   **蓝牙渠道（标准 BLE 电池服务）**：
    *   **Service UUID**：`0x180F` (GATT Battery Service)
    *   **Characteristic UUID**：`0x2A19` (Battery Level)
    *   **通信属性**：`READ` & `NOTIFY`（电量变化时，硬件主动通知手机更新）
    *   **数据格式**：`uint8_t` (0 - 100) 表示当前百分比。
*   **局域网渠道（HTTP GET）**：
    *   **请求路由**：`GET /api/device_info` 里的 `battery_level` 字段。
    *   也可以设计独立接口：`GET /api/battery`，返回 `{"battery_level": 95}`。

---

### 6. 基础连接性检测 API (Ping)
类似于局域网 ICMP Ping，手机 App 在启动控制或流式传输大文件前，使用该超轻量级 HTTP GET 请求来极速判定设备是否在线，以及网络往返时延（RTT）。

*   **请求路由**：`GET /api/ping`
*   **设备端响应 (JSON 200 OK)**：
    ```json
    {
      "status": "pong"
    }
    ```
*   **优势**：相较于 `/api/device_info` 路由，该接口免去了查询电池电压 ADC 和 NVS 状态的操作，响应极其轻量（时延在 5ms 以内），可用于高频的心跳保持。

---

### 7. 用户信息与绑定配置 (POST)
用于在配网阶段或局域网绑定阶段，将 App 登录的用户信息（例如用户 ID、云端绑定 Token）写入设备存储。

*   **请求路由**：`POST /api/user/bind`
*   **请求内容 (JSON)**：
    ```json
    {
      "user_id": "usr_94883199",
      "bind_token": "token_abcdefg_9988",
      "app_version": "1.0.0"
    }
    ```
*   **设备端行为**：将用户信息序列化存储到 NVS Active 区，并在后台启动异步云端绑定上报任务 `cloud_binding_task`，完成后 LED 变为常亮。
*   **设备端响应 (JSON 200 OK)**：
    ```json
    {
      "status": "success",
      "message": "user_binding_saved_and_uploading"
    }
    ```

---

### 8. 节能与睡眠控制指令 [已延后]
提供局域网一键关机或控制进入超低功耗节电模式的功能。

*   **请求路由**：`POST /api/power/sleep`
*   **请求内容 (JSON)**：
    ```json
    {
      "action": "ENTER_SLEEP",
      "sleep_seconds": 3600,             // 定时睡眠秒数，0 为无限期睡眠（等按键唤醒）
      "disable_backlight": true          // 立即关闭背光和双屏幕
    }
    ```
*   **设备端行为**：
    1. 立即回复手机 success 应答，断开所有 TCP/HTTP 活动连接。
    2. 关闭两块 GC9D01 的屏幕背光，执行 LCD 面板的 `Sleep In` 关屏保护。
    3. 关闭 Wi-Fi 射频、蓝牙射频和后台所有耗电任务。
    4. 进入 ESP32-C3 的 **Deep Sleep (深睡眠)** 或者是 **Light Sleep (轻睡眠)** 节能模式，等待定时器溢出或通过物理 IO 按键重新唤醒启动。
*   **设备端响应 (JSON 200 OK)**：
    ```json
    {
      "status": "success",
      "message": "entering_sleep_mode"
    }
    ```

---

### 9. 屏幕每日累计显示时长获取 (GET)
用于手机 App 抓取并统计该设备今日累计开启双屏显示的总时长（单位：秒）。

*   **请求路由**：`GET /api/display/duration`
*   **设备端行为**：设备端会自开机起，以及通过 RTC 记录每日的显示模块工作时长，并累加返回。
*   **设备端响应 (JSON 200 OK)**：
    ```json
    {
      "daily_duration_seconds": 18200   // 累计今日亮屏使用时间（5小时3分20秒）
    }
    ```

---

### 10. 系统时间同步功能 (POST)
用于使设备内部的硬件 RTC 时钟与手机当前的高精度时间进行同步（包含时间戳和时区偏移）。

*   **请求路由**：`POST /api/time/sync`
*   **请求内容 (JSON)**：
    ```json
    {
      "timestamp": 1781084775,           // 手机当前 Unix 时间戳
      "timezone_offset_hours": 8         // 手机当前的本地时区偏移量（如北京时间 +8）
    }
    ```
*   **设备端行为**：接收并解调时间参数，通过 ESP-IDF 的 `settimeofday` 设置系统底层 RTC，实现离线高精度时钟对齐。
*   **设备端响应 (JSON 200 OK)**：
    ```json
    {
      "status": "success",
      "message": "time_synchronized",
      "synchronized_time": "2026-06-10 17:15:00" // 同步后的设备本地可视化时间
    }
    ```
