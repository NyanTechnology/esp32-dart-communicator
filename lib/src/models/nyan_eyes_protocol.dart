import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';

/// NyanEyes 蓝牙通信协议常量及负载构造器 (零信任双轨版)
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

  /// 生成一个符合规范的 16 字节随机安全 LocalKey（仅含英文字母、数字、下划线）
  static String generateSecureKey() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_';
    final rand = math.Random.secure();
    return List.generate(16, (index) => chars[rand.nextInt(chars.length)]).join();
  }

  /// 使用本地保存的该设备 local_key 对 nonce 计算 HMAC-SHA256
  static String calculateAuthHash(String nonce, String localKey) {
    var hmacSha256 = Hmac(sha256, utf8.encode(localKey));
    var digest = hmacSha256.convert(utf8.encode(nonce));
    return digest.toString(); // 返回 16 进制小写字符串
  }

  /// 构造获取挑战码负载
  static String getChallenge() {
    return '{"action":"GET_CHALLENGE"}';
  }

  /// 构造配网（居家在线模式）负载
  static String provision(String ssid, String password, String bindToken) {
    return '{"action":"PROVISION","ssid":"$ssid","password":"$password","bind_token":"$bindToken"}';
  }

  /// 构造近场户外模式初始化负载 (localKey 必须恰好为 16 字节)
  static String outdoorInit(String localKey) {
    assert(localKey.length == 16, "LocalKey must be exactly 16 bytes.");
    return '{"action":"OUTDOOR_INIT","local_key":"$localKey"}';
  }

  /// 构造基于 HMAC-SHA256 哈希的身份鉴权负载
  static String auth(String hash) {
    return '{"action":"AUTH","hash":"$hash"}';
  }

  /// 构造户外切换 Wi-Fi 负载
  static String switchWiFi(String ssid, String password) {
    return '{"action":"SWITCH_WIFI","ssid":"$ssid","password":"$password"}';
  }

  /// 构造控制设备（继电器/LED）开关负载
  static String toggleRelay(bool isOn) {
    return '{"action":"TOGGLE_RELAY","state":${isOn ? 1 : 0}}';
  }

  /// 构造控制双眼应用特定眼片文件（APPLY_EYES）负载
  static String applyEyes(String left, String right, bool leftMirror, bool rightMirror) {
    return '{"action":"APPLY_EYES","left":"$left","right":"$right","leftMirror":$leftMirror,"rightMirror":$rightMirror}';
  }
}
