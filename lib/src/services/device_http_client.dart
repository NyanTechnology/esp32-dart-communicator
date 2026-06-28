import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/device_info.dart';

/// Client for communicating with ESP32 devices via HTTP REST API.
class DeviceHttpClient {
  final http.Client _client;
  final bool _isCustomClient;

  DeviceHttpClient({http.Client? client})
      : _client = client ?? http.Client(),
        _isCustomClient = client != null;

  /// Helper to execute an HTTP request with a dedicated client,
  /// closing it immediately in a finally block to avoid TCP connection leaks
  /// and prevent ESP32 TCP socket exhaustion.
  Future<T> _withClient<T>(Future<T> Function(http.Client client) action) async {
    if (_isCustomClient) {
      return await action(_client);
    }
    final client = http.Client();
    try {
      return await action(client);
    } finally {
      client.close();
    }
  }

  // Helper method to format debugging output to conform exactly to the main App's framed, emoji-based logger style.
  void _log(String emoji, String tag, String msg, [dynamic error, StackTrace? stack]) {
    final now = DateTime.now().toString().substring(0, 23);
    debugPrint('┌───────────────────────────────────────────────────────────────────────────────');
    debugPrint('│ $now');
    debugPrint('├┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄');
    debugPrint('│ $emoji [$tag] $msg');
    if (error != null) {
      debugPrint('│ Error: $error');
    }
    if (stack != null) {
      final lines = stack.toString().split('\n');
      for (final line in lines) {
        if (line.trim().isNotEmpty) {
          debugPrint('│ $line');
        }
      }
    }
    debugPrint('└───────────────────────────────────────────────────────────────────────────────');
  }

  /// Fetches device information from a specific [baseUrl].
  /// 
  /// Returns [DeviceInfo] if successful, otherwise null.
  Future<DeviceInfo?> fetchDeviceInfo(
    String baseUrl, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final devInfoUri = Uri.parse('$baseUrl/api/device_info');
    _log('🐛', 'DeviceHttpClient', 'fetchDeviceInfo INITIATED: $devInfoUri');
    try {
      final resp = await _withClient((client) => client.get(
        devInfoUri,
        headers: {'Connection': 'close'},
      ).timeout(
        timeout,
        onTimeout: () => http.Response('', 408),
      ));
      _log('💡', 'DeviceHttpClient', 'fetchDeviceInfo RESPONDED: statusCode: ${resp.statusCode}, body: ${resp.body}');
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
    } catch (e, stack) {
      _log('⛔', 'DeviceHttpClient', 'fetchDeviceInfo EXCEPTION', e, stack);
    }
    return null;
  }

  /// Uploads raw eye asset data to the device.
  /// 
  /// [data] is the binary content of the file.
  /// [filename] is the name to save the file as on the device.
  Future<bool> uploadEyeData(String baseUrl, Uint8List data, String filename) async {
    final uploadUri = Uri.parse('$baseUrl/api/upload');
    _log('🐛', 'DeviceHttpClient', 'uploadEyeData INITIATED: $uploadUri, filename: $filename, bytes: ${data.length}');
    try {
      final req = http.MultipartRequest('POST', uploadUri);
      req.headers['Connection'] = 'close';
      req.files.add(http.MultipartFile.fromBytes('file', data, filename: filename));
      final response = await _withClient((client) => client.send(req).timeout(const Duration(seconds: 60)));
      _log('💡', 'DeviceHttpClient', 'uploadEyeData SUCCESS: statusCode: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e, stack) {
      _log('⛔', 'DeviceHttpClient', 'uploadEyeData EXCEPTION', e, stack);
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
    final applyUri = Uri.parse(
      '$baseUrl/api/eyes/apply?left=$leftFilename&right=$rightFilename&leftMirror=$leftMirror&rightMirror=$rightMirror',
    );
    _log('🐛', 'DeviceHttpClient', 'applyEyeConfigs INITIATED: $applyUri');
    try {
      final resp = await _withClient((client) => client.get(applyUri, headers: {'Connection': 'close'}).timeout(const Duration(seconds: 30)));
      _log('💡', 'DeviceHttpClient', 'applyEyeConfigs SUCCESS: statusCode: ${resp.statusCode}, body: ${resp.body}');
      if (resp.statusCode == 200) {
        try {
          final data = json.decode(resp.body) as Map<String, dynamic>;
          return data['status'] == 'success';
        } catch (_) {
          return true; // Fallback for backward compatibility if body is not JSON or lacks status
        }
      }
      return false;
    } catch (e, stack) {
      _log('⛔', 'DeviceHttpClient', 'applyEyeConfigs EXCEPTION', e, stack);
      return false;
    }
  }

  /// Soft resets the device back to Provisioning Mode.
  Future<bool> resetDevice(
    String baseUrl, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final resetUri = Uri.parse('$baseUrl/api/reset');
    _log('🐛', 'DeviceHttpClient', 'resetDevice INITIATED: $resetUri');
    try {
      final resp = await _withClient((client) => client.get(resetUri, headers: {'Connection': 'close'}).timeout(timeout));
      _log('💡', 'DeviceHttpClient', 'resetDevice SUCCESS: statusCode: ${resp.statusCode}, body: ${resp.body}');
      return resp.statusCode == 200;
    } catch (e, stack) {
      _log('⛔', 'DeviceHttpClient', 'resetDevice EXCEPTION', e, stack);
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
    final batteryUri = Uri.parse('$baseUrl/api/battery');
    _log('🐛', 'DeviceHttpClient', 'fetchBatteryLevel INITIATED: $batteryUri');
    try {
      final resp = await _withClient((client) => client.get(batteryUri, headers: {'Connection': 'close'}).timeout(timeout));
      _log('💡', 'DeviceHttpClient', 'fetchBatteryLevel RESPONDED: statusCode: ${resp.statusCode}, body: ${resp.body}');
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final val = data['battery_level'];
        if (val is int) return val;
        if (val is String) return int.tryParse(val);
      }
    } catch (e, stack) {
      _log('⛔', 'DeviceHttpClient', 'fetchBatteryLevel EXCEPTION', e, stack);
    }
    return null;
  }

  /// Pings the device via HTTP to test connection and measure latency (RTT).
  /// 
  /// Returns the RTT duration in milliseconds if successful, otherwise null.
  Future<int?> pingDevice(
    String baseUrl, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final pingUri = Uri.parse('$baseUrl/api/ping');
    _log('🐛', 'DeviceHttpClient', 'pingDevice INITIATED: $pingUri');
    final stopwatch = Stopwatch()..start();
    try {
      final resp = await _withClient((client) => client.get(pingUri, headers: {'Connection': 'close'}).timeout(timeout));
      stopwatch.stop();
      _log('💡', 'DeviceHttpClient', 'pingDevice RESPONDED: statusCode: ${resp.statusCode}, latency: ${stopwatch.elapsedMilliseconds}ms, body: ${resp.body}');
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        if (data['status'] == 'pong') {
          return stopwatch.elapsedMilliseconds;
        }
      }
    } catch (e, stack) {
      _log('⛔', 'DeviceHttpClient', 'pingDevice EXCEPTION', e, stack);
    }
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
    final bindUri = Uri.parse('$baseUrl/api/user/bind');
    _log('🐛', 'DeviceHttpClient', 'bindUser INITIATED: $bindUri');
    try {
      final resp = await _withClient((client) => client.post(
        bindUri,
        headers: {'Content-Type': 'application/json', 'Connection': 'close'},
        body: json.encode({
          'user_id': userId,
          'bind_token': bindToken,
        }),
      ).timeout(timeout));
      _log('💡', 'DeviceHttpClient', 'bindUser SUCCESS: statusCode: ${resp.statusCode}, body: ${resp.body}');
      return resp.statusCode == 200;
    } catch (e, stack) {
      _log('⛔', 'DeviceHttpClient', 'bindUser EXCEPTION', e, stack);
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
    final sleepUri = Uri.parse('$baseUrl/api/power/sleep');
    _log('🐛', 'DeviceHttpClient', 'enterSleepMode INITIATED: $sleepUri');
    try {
      final resp = await _withClient((client) => client.post(
        sleepUri,
        headers: {'Content-Type': 'application/json', 'Connection': 'close'},
        body: json.encode({
          'action': 'ENTER_SLEEP',
          'sleep_seconds': sleepSeconds,
          'disable_backlight': true,
        }),
      ).timeout(timeout));
      _log('💡', 'DeviceHttpClient', 'enterSleepMode SUCCESS: statusCode: ${resp.statusCode}, body: ${resp.body}');
      return resp.statusCode == 200;
    } catch (e, stack) {
      _log('⛔', 'DeviceHttpClient', 'enterSleepMode EXCEPTION', e, stack);
      return false;
    }
  }

  /// Preserves the daily accumulated screen active duration (in seconds) from the device via HTTP.
  /// 
  /// Returns the duration in seconds if successful, otherwise null.
  Future<int?> fetchDisplayDuration(
    String baseUrl, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final durationUri = Uri.parse('$baseUrl/api/display/duration');
    _log('🐛', 'DeviceHttpClient', 'fetchDisplayDuration INITIATED: $durationUri');
    try {
      final resp = await _withClient((client) => client.get(durationUri, headers: {'Connection': 'close'}).timeout(timeout));
      _log('💡', 'DeviceHttpClient', 'fetchDisplayDuration RESPONDED: statusCode: ${resp.statusCode}, body: ${resp.body}');
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final val = data['daily_duration_seconds'];
        if (val is int) return val;
        if (val is String) return int.tryParse(val);
      }
    } catch (e, stack) {
      _log('⛔', 'DeviceHttpClient', 'fetchDisplayDuration EXCEPTION', e, stack);
    }
    return null;
  }

  /// Synchronizes the device's internal RTC clock with the mobile phone's high-precision time.
  /// 
  /// Returns the synchronized local time string if successful, otherwise null.
  Future<String?> syncDeviceTime(
    String baseUrl, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final syncUri = Uri.parse('$baseUrl/api/time/sync');
    _log('🐛', 'DeviceHttpClient', 'syncDeviceTime INITIATED: $syncUri');
    try {
      final now = DateTime.now();
      final timestampSeconds = now.millisecondsSinceEpoch ~/ 1000;
      final timezoneOffsetHours = now.timeZoneOffset.inHours;

      final resp = await _withClient((client) => client.post(
        syncUri,
        headers: {'Content-Type': 'application/json', 'Connection': 'close'},
        body: json.encode({
          'timestamp': timestampSeconds,
          'timezone_offset_hours': timezoneOffsetHours,
        }),
      ).timeout(timeout));
      _log('💡', 'DeviceHttpClient', 'syncDeviceTime RESPONDED: statusCode: ${resp.statusCode}, body: ${resp.body}');

      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        if (data['status'] == 'success') {
          return data['synchronized_time'] as String?;
        }
      }
    } catch (e, stack) {
      _log('⛔', 'DeviceHttpClient', 'syncDeviceTime EXCEPTION', e, stack);
    }
    return null;
  }
}
