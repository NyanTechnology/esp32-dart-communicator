import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/device_info.dart';

/// Client for communicating with ESP32 devices via HTTP REST API.
class DeviceHttpClient {
  final http.Client _client;

  DeviceHttpClient({http.Client? client}) : _client = client ?? http.Client();

  /// Fetches device information from a specific [baseUrl].
  /// 
  /// Returns [DeviceInfo] if successful, otherwise null.
  Future<DeviceInfo?> fetchDeviceInfo(
    String baseUrl, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    try {
      final resp = await _client.get(
        Uri.parse('$baseUrl/api/device_info'),
        headers: {'Connection': 'close'},
      ).timeout(
        timeout,
        onTimeout: () => http.Response('', 408),
      );
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        // Safely extract IP from baseUrl (e.g., http://192.168.x.x:80) to fallback if firmware drops it
        final RegExp ipRegExp = RegExp(r'http://([0-9\.]+)(:\d+)?');
        final match = ipRegExp.firstMatch(baseUrl);
        if (match != null && data['sta_ip'] == null) {
           data['sta_ip'] = match.group(1);
        }
        return DeviceInfo.fromJson(data);
      }
    } catch (e) {
      if (kDebugMode) { debugPrint('fetchDeviceInfo Error: $e'); }
    }
    return null;
  }

  /// Uploads raw eye asset data to the device.
  /// 
  /// [data] is the binary content of the file.
  /// [filename] is the name to save the file as on the device.
  Future<bool> uploadEyeData(String baseUrl, Uint8List data, String filename) async {
    try {
      final uploadUri = Uri.parse('$baseUrl/api/upload');
      final req = http.MultipartRequest('POST', uploadUri);
      req.files.add(http.MultipartFile.fromBytes('file', data, filename: filename));
      final response = await _client.send(req).timeout(const Duration(seconds: 60));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Commands the device to apply specific eye configurations.
  /// 
  /// [leftFilename] and [rightFilename] refer to assets previously uploaded to the device.
  Future<bool> applyEyeConfigs(
    String baseUrl,
    String leftFilename,
    String rightFilename, {
    bool leftMirror = false,
    bool rightMirror = false,
  }) async {
    try {
      final applyUri = Uri.parse(
        '$baseUrl/api/eyes/apply?left=/images/$leftFilename&right=/images/$rightFilename&leftMirror=$leftMirror&rightMirror=$rightMirror',
      );
      final resp = await _client.get(applyUri).timeout(const Duration(seconds: 30));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Soft resets the device back to Provisioning Mode.
  Future<bool> resetDevice(
    String baseUrl, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    try {
      final resetUri = Uri.parse('$baseUrl/api/reset');
      final resp = await _client.get(resetUri).timeout(timeout);
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Fetches the battery level independently from the device via HTTP.
  /// 
  /// Returns the battery level as a percentage (0-100) if successful, otherwise null.
  Future<int?> fetchBatteryLevel(
    String baseUrl, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    try {
      final batteryUri = Uri.parse('$baseUrl/api/battery');
      final resp = await _client.get(batteryUri).timeout(timeout);
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final val = data['battery_level'];
        if (val is int) return val;
        if (val is String) return int.tryParse(val);
      }
    } catch (_) {}
    return null;
  }

  /// Pings the device via HTTP to test connection and measure latency (RTT).
  /// 
  /// Returns the RTT duration in milliseconds if successful, otherwise null.
  Future<int?> pingDevice(
    String baseUrl, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final pingUri = Uri.parse('$baseUrl/api/ping');
      final resp = await _client.get(pingUri).timeout(timeout);
      stopwatch.stop();
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        if (data['status'] == 'pong') {
          return stopwatch.elapsedMilliseconds;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Sends user binding information to the device over HTTP.
  /// 
  /// Returns true if successful, otherwise false.
  Future<bool> bindUser(
    String baseUrl,
    String userId,
    String bindToken, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    try {
      final bindUri = Uri.parse('$baseUrl/api/user/bind');
      final resp = await _client.post(
        bindUri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'user_id': userId,
          'bind_token': bindToken,
        }),
      ).timeout(timeout);
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Commands the device to enter low power sleep/standby mode.
  /// 
  /// Returns true if successful, otherwise false.
  Future<bool> enterSleepMode(
    String baseUrl, {
    int sleepSeconds = 3600,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    try {
      final sleepUri = Uri.parse('$baseUrl/api/power/sleep');
      final resp = await _client.post(
        sleepUri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'action': 'ENTER_SLEEP',
          'sleep_seconds': sleepSeconds,
          'disable_backlight': true,
        }),
      ).timeout(timeout);
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Fetches the daily accumulated screen active duration (in seconds) from the device via HTTP.
  /// 
  /// Returns the duration in seconds if successful, otherwise null.
  Future<int?> fetchDisplayDuration(
    String baseUrl, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    try {
      final durationUri = Uri.parse('$baseUrl/api/display/duration');
      final resp = await _client.get(durationUri).timeout(timeout);
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final val = data['daily_duration_seconds'];
        if (val is int) return val;
        if (val is String) return int.tryParse(val);
      }
    } catch (_) {}
    return null;
  }

  /// Synchronizes the device's internal RTC clock with the mobile phone's high-precision time.
  /// 
  /// Returns the synchronized local time string if successful, otherwise null.
  Future<String?> syncDeviceTime(
    String baseUrl, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    try {
      final syncUri = Uri.parse('$baseUrl/api/time/sync');
      final now = DateTime.now();
      final timestampSeconds = now.millisecondsSinceEpoch ~/ 1000;
      final timezoneOffsetHours = now.timeZoneOffset.inHours;

      final resp = await _client.post(
        syncUri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'timestamp': timestampSeconds,
          'timezone_offset_hours': timezoneOffsetHours,
        }),
      ).timeout(timeout);

      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        if (data['status'] == 'success') {
          return data['synchronized_time'] as String?;
        }
      }
    } catch (_) {}
    return null;
  }
}
