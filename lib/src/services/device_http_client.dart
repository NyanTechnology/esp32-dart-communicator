import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/device_info.dart';

/// Client for communicating with ESP32 devices via HTTP REST API.
class DeviceHttpClient {
  /// Fetches device information from a specific [baseUrl].
  /// 
  /// Returns [DeviceInfo] if successful, otherwise null.
  Future<DeviceInfo?> fetchDeviceInfo(
    String baseUrl, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    try {
      final resp = await http.get(
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
    } catch (_) {}
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
      final response = await req.send().timeout(const Duration(seconds: 60));
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
      final resp = await http.get(applyUri).timeout(const Duration(seconds: 30));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
