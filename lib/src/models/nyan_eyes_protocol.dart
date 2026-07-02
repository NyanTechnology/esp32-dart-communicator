/// NyanEyes 蓝牙通信协议常量及负载构造器
class NyanEyesProtocol {
  static const String deviceName = "NyanEyes_ESP32";

  // === GATT 服务 UUID ===
  static const String provServiceUuid = "fff0";
  static const String provCharUuid = "fff1";

  static const String outdoorServiceUuid = "ffe0";
  static const String outdoorCharUuid = "ffe1";

  static const String batteryServiceUuid = "180f";
  static const String batteryCharUuid = "2a19";

  // === JSON 负载构造器 ===

  /// 构造配网（居家在线模式）负载
  static Map<String, dynamic> provision(String ssid, String password, String bindToken) {
    return {
      "action": "PROVISION",
      "ssid": ssid,
      "password": password,
      "bind_token": bindToken
    };
  }

  /// 构造近场户外模式初始化负载 (localKey 必须恰好为 16 字节)
  static Map<String, dynamic> outdoorInit(String localKey) {
    assert(localKey.length == 16, "LocalKey must be exactly 16 bytes.");
    return {
      "action": "OUTDOOR_INIT",
      "local_key": localKey
    };
  }

  /// 构造户外直连身份鉴权负载 (localKey 必须与初始化时的一致)
  static Map<String, dynamic> auth(String localKey) {
    assert(localKey.length == 16, "LocalKey must be exactly 16 bytes.");
    return {
      "action": "AUTH",
      "local_key": localKey
    };
  }

  /// 构造户外切换 Wi-Fi 负载
  static Map<String, dynamic> switchWiFi(String ssid, String password) {
    return {
      "action": "SWITCH_WIFI",
      "ssid": ssid,
      "password": password
    };
  }

  /// 构造控制设备（继电器/LED）开关负载
  static Map<String, dynamic> toggleRelay(bool isOn) {
    return {
      "action": "TOGGLE_RELAY",
      "state": isOn ? 1 : 0
    };
  }

  /// 构造客户端控制模式切换负载
  static Map<String, dynamic> setMode(String mode) {
    return {
      "action": "SET_MODE",
      "mode": mode
    };
  }

  /// 构造客户端控制模式翻转负载
  static Map<String, dynamic> toggleMode() {
    return {
      "action": "TOGGLE_MODE"
    };
  }
}
