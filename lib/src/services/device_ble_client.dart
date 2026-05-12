import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Client for communicating with ESP32 devices via Bluetooth Low Energy (BLE).
/// 
/// Primarily used for initial provisioning and out-of-band control.
class DeviceBleClient {
  /// The default service UUID for NyanEye control.
  static const String defaultServiceUuid = '4fafc201-1fb5-459e-8bcc-c5c9c331914b';
  
  /// The default characteristic UUID for control commands and notifications.
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

  /// Initializes the client by discovering services and enabling notifications.
  Future<void> init() async {
    await _notifySub?.cancel();
    final services = await device.discoverServices().timeout(const Duration(seconds: 10));
    for (final s in services) {
      if (s.uuid.toString().toLowerCase() == serviceUuid.toLowerCase()) {
        for (final c in s.characteristics) {
          if (c.uuid.toString().toLowerCase() == charUuid.toLowerCase()) {
            _controlChar = c;
            break;
          }
        }
      }
    }

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
      throw Exception('Could not find control service/characteristic');
    }
  }

  /// Sends a JSON-encoded command to the device and waits for a response.
  /// 
  /// The device must be [init]ialized before calling this.
  Future<Map<String, dynamic>> sendCommand(Map<String, dynamic> payload, {int timeoutSec = 15}) async {
    if (_controlChar == null) throw Exception('BleClient not initialized');
    _responseCompleter = Completer<Map<String, dynamic>>();
    
    final jsonStr = '${jsonEncode(payload)}\n';
    bool withoutResp = _controlChar!.properties.writeWithoutResponse;
    
    if (Platform.isAndroid) {
      try {
        await device.requestMtu(512);
        await Future.delayed(const Duration(milliseconds: 200));
      } catch (_) {}
    }
    
    await _controlChar!.write(utf8.encode(jsonStr), withoutResponse: withoutResp).timeout(const Duration(seconds: 5));
    
    try {
      return await _responseCompleter!.future.timeout(Duration(seconds: timeoutSec));
    } finally {
      _responseCompleter = null;
    }
  }

  /// Disposes of the client and cancels active subscriptions.
  void dispose() {
    _notifySub?.cancel();
  }
}
