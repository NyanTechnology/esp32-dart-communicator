import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Client for communicating with ESP32 devices via Bluetooth Low Energy (BLE).
/// 
/// Supports smart auto-detection of services (provisioning, outdoor direct control, 
/// standard battery service, and backward compatibility with old custom service UUIDs).
class DeviceBleClient {
  /// The legacy default service UUID for NyanEye control.
  static const String defaultServiceUuid = '4fafc201-1fb5-459e-8bcc-c5c9c331914b';
  
  /// The legacy default characteristic UUID for control commands and notifications.
  static const String defaultCharUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';

  final BluetoothDevice device;
  final String serviceUuid;
  final String charUuid;
  
  BluetoothCharacteristic? _controlChar;
  StreamSubscription? _notifySub;
  Completer<Map<String, dynamic>>? _responseCompleter;

  /// Creates a new [DeviceBleClient] for the given [device].
  DeviceBleClient(
    this.device, {
    this.serviceUuid = defaultServiceUuid,
    this.charUuid = defaultCharUuid,
  });

  /// Normalizes and compares BLE UUIDs to support short 16-bit and full 128-bit forms.
  bool _uuidMatches(String uuidStr, String targetShort, String targetLong) {
    final normalized = uuidStr.toLowerCase().replaceAll('-', '');
    final shortNorm = targetShort.toLowerCase().replaceAll('-', '');
    final longNorm = targetLong.toLowerCase().replaceAll('-', '');
    
    return normalized == shortNorm || 
           normalized == longNorm ||
           (normalized.contains(shortNorm) && 
            (normalized.endsWith('00805f9b34fb') || normalized.startsWith('0000' + shortNorm)));
  }

  /// Initializes the client by discovering services and enabling notifications.
  Future<void> init() async {
    await _notifySub?.cancel();
    final services = await device.discoverServices().timeout(const Duration(seconds: 10));

    BluetoothService? matchedService;
    BluetoothCharacteristic? matchedChar;

    // 1. Attempt to detect new standard services first (provisioning or outdoor control)
    for (final s in services) {
      final sUuid = s.uuid.toString();
      
      // Check for FFF0 (Provisioning Service)
      if (_uuidMatches(sUuid, 'fff0', '0000fff0-0000-1000-8000-00805f9b34fb')) {
        for (final c in s.characteristics) {
          final cUuid = c.uuid.toString();
          if (_uuidMatches(cUuid, 'fff1', '0000fff1-0000-1000-8000-00805f9b34fb')) {
            matchedService = s;
            matchedChar = c;
            break;
          }
        }
      }
      // Check for FFE0 (Outdoor Control Service)
      else if (_uuidMatches(sUuid, 'ffe0', '0000ffe0-0000-1000-8000-00805f9b34fb')) {
        for (final c in s.characteristics) {
          final cUuid = c.uuid.toString();
          if (_uuidMatches(cUuid, 'ffe1', '0000ffe1-0000-1000-8000-00805f9b34fb')) {
            matchedService = s;
            matchedChar = c;
            break;
          }
        }
      }
      
      if (matchedChar != null) break;
    }

    // 2. If no new services matched, fallback to specified constructor/legacy parameters
    if (matchedChar == null) {
      for (final s in services) {
        final sUuid = s.uuid.toString().toLowerCase();
        if (sUuid == serviceUuid.toLowerCase() || _uuidMatches(sUuid, serviceUuid, serviceUuid)) {
          for (final c in s.characteristics) {
            final cUuid = c.uuid.toString().toLowerCase();
            if (cUuid == charUuid.toLowerCase() || _uuidMatches(cUuid, charUuid, charUuid)) {
              matchedService = s;
              matchedChar = c;
              break;
            }
          }
        }
        if (matchedChar != null) break;
      }
    }

    _controlChar = matchedChar;

    if (_controlChar != null) {
      await _controlChar!.setNotifyValue(true).timeout(const Duration(seconds: 5));
      _notifySub = _controlChar!.onValueReceived.listen((value) {
        try {
          final jsonStr = utf8.decode(value);
          final data = jsonDecode(jsonStr) as Map<String, dynamic>;
          if (_responseCompleter != null && !_responseCompleter!.isCompleted) {
            _responseCompleter!.complete(data);
          }
        } catch (_) {}
      });
    } else {
      throw Exception(
        'Could not find control service/characteristic (tried FFF0/FFF1, FFE0/FFE1, and legacy $serviceUuid/$charUuid)'
      );
    }
  }

  /// Sends a JSON-encoded command to the device and waits for a response.
  /// 
  /// The device must be [init]ialized before calling this.
  Future<Map<String, dynamic>> sendCommand(
    Map<String, dynamic> payload, {
    int timeoutSec = 15,
    bool waitResponse = true,
  }) async {
    if (_controlChar == null) throw Exception('BleClient not initialized');
    
    final jsonStr = '${jsonEncode(payload)}\n';
    bool withoutResp = _controlChar!.properties.writeWithoutResponse;
    
    if (Platform.isAndroid) {
      try {
        await device.requestMtu(512);
        await Future.delayed(const Duration(milliseconds: 200));
      } catch (_) {}
    }
    
    if (waitResponse) {
      _responseCompleter = Completer<Map<String, dynamic>>();
      await _controlChar!.write(utf8.encode(jsonStr), withoutResponse: withoutResp).timeout(const Duration(seconds: 5));
      try {
        return await _responseCompleter!.future.timeout(Duration(seconds: timeoutSec));
      } finally {
        _responseCompleter = null;
      }
    } else {
      // 💡 [无回复高速写入]：动态使用 characteristic 自身的 properties.writeWithoutResponse 决定写入模式，防范 iOS 因特性越界强行断链
      await _controlChar!.write(utf8.encode(jsonStr), withoutResponse: withoutResp).timeout(const Duration(seconds: 5));
      return const <String, dynamic>{};
    }
  }

  /// Reads the battery level if the standard battery service is available on the device.
  /// 
  /// Returns a percentage value between 0 and 100, or null if not available or reading fails.
  Future<int?> readBatteryLevel() async {
    try {
      final services = await device.discoverServices().timeout(const Duration(seconds: 5));
      for (final s in services) {
        final sUuid = s.uuid.toString();
        if (_uuidMatches(sUuid, '180f', '0000180f-0000-1000-8000-00805f9b34fb')) {
          for (final c in s.characteristics) {
            final cUuid = c.uuid.toString();
            if (_uuidMatches(cUuid, '2a19', '00002a19-0000-1000-8000-00805f9b34fb')) {
              final value = await c.read().timeout(const Duration(seconds: 5));
              if (value.isNotEmpty) {
                return value[0];
              }
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Subscribes to battery level changes.
  /// 
  /// Returns a stream of battery level percentages (0-100).
  Stream<int> monitorBatteryLevel() async* {
    try {
      final services = await device.discoverServices();
      for (final s in services) {
        final sUuid = s.uuid.toString();
        if (_uuidMatches(sUuid, '180f', '0000180f-0000-1000-8000-00805f9b34fb')) {
          for (final c in s.characteristics) {
            final cUuid = c.uuid.toString();
            if (_uuidMatches(cUuid, '2a19', '00002a19-0000-1000-8000-00805f9b34fb')) {
              await c.setNotifyValue(true);
              yield* c.onValueReceived.map((value) => value.isNotEmpty ? value[0] : 0);
            }
          }
        }
      }
    } catch (_) {}
  }

  /// Disposes of the client and cancels active subscriptions.
  void dispose() {
    _notifySub?.cancel();
  }
}
