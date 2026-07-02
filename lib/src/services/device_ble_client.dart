import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Client for communicating with ESP32 devices via Bluetooth Low Energy (BLE).
/// 
/// Automatically routes commands to either the Provisioning service or the Outdoor/Control service based on the action.
class DeviceBleClient {
  static const String provServiceUuid = 'fff0';
  static const String provCharUuid = 'fff1';

  static const String outdoorServiceUuid = 'ffe0';
  static const String outdoorCharUuid = 'ffe1';

  static const String batteryServiceUuid = '180f';
  static const String batteryCharUuid = '2a19';

  final BluetoothDevice device;
  
  BluetoothCharacteristic? _provChar;
  BluetoothCharacteristic? _outdoorChar;
  BluetoothCharacteristic? _batteryChar;
  
  StreamSubscription? _provNotifySub;
  StreamSubscription? _outdoorNotifySub;
  StreamSubscription? _batteryNotifySub;
  
  Completer<Map<String, dynamic>>? _responseCompleter;

  /// Creates a new [DeviceBleClient] for the given [device].
  DeviceBleClient(this.device);

  /// Returns the battery level stream if available, otherwise null.
  Stream<int>? get batteryLevelStream => _batteryChar?.onValueReceived.map((val) => val.isNotEmpty ? val[0] : 0);

  /// Initializes the client by discovering services and enabling notifications.
  Future<void> init() async {
    await _provNotifySub?.cancel();
    await _outdoorNotifySub?.cancel();
    await _batteryNotifySub?.cancel();
    
    print('[DeviceBleClient] Discovering services for ${device.remoteId} ...');
    final services = await device.discoverServices().timeout(const Duration(seconds: 10));
    print('[DeviceBleClient] Discovered ${services.length} services.');

    for (final s in services) {
      final sUuid = s.uuid.toString().toLowerCase();
      print('  -> Service: $sUuid');
      // Handle standard 16-bit UUID representations in flutter_blue_plus and fallback to Legacy UUIDs
      if (sUuid.contains(provServiceUuid) || sUuid == '0000$provServiceUuid-0000-1000-8000-00805f9b34fb' || sUuid == '4fafc201-1fb5-459e-8bcc-c5c9c331914b') {
        for (final c in s.characteristics) {
          final cUuid = c.uuid.toString().toLowerCase();
          print('      -> Char: $cUuid (Notify: ${c.properties.notify}, Read: ${c.properties.read}, Write: ${c.properties.write})');
          if (cUuid.contains(provCharUuid) || cUuid == '0000$provCharUuid-0000-1000-8000-00805f9b34fb' || cUuid == 'beb5483e-36e1-4688-b7f5-ea07361b26a8') {
            _provChar = c;
          }
        }
      } else if (sUuid.contains(outdoorServiceUuid) || sUuid == '0000$outdoorServiceUuid-0000-1000-8000-00805f9b34fb' || sUuid == '4fafc201-1fb5-459e-8bcc-c5c9c331914b') {
        for (final c in s.characteristics) {
          final cUuid = c.uuid.toString().toLowerCase();
          print('      -> Char: $cUuid (Notify: ${c.properties.notify}, Read: ${c.properties.read}, Write: ${c.properties.write})');
          if (cUuid.contains(outdoorCharUuid) || cUuid == '0000$outdoorCharUuid-0000-1000-8000-00805f9b34fb' || cUuid == 'beb5483e-36e1-4688-b7f5-ea07361b26a8') {
            _outdoorChar = c;
          }
        }
      } else if (sUuid.contains(batteryServiceUuid) || sUuid == '0000$batteryServiceUuid-0000-1000-8000-00805f9b34fb') {
        for (final c in s.characteristics) {
          final cUuid = c.uuid.toString().toLowerCase();
          print('      -> Char: $cUuid (Notify: ${c.properties.notify}, Read: ${c.properties.read}, Write: ${c.properties.write})');
          if (cUuid.contains(batteryCharUuid) || cUuid == '0000$batteryCharUuid-0000-1000-8000-00805f9b34fb') {
            _batteryChar = c;
          }
        }
      }
    }

    print('[DeviceBleClient] Target Chars - Prov: ${_provChar != null}, Outdoor: ${_outdoorChar != null}, Battery: ${_batteryChar != null}');

    if (_provChar == null && _outdoorChar == null) {
      throw Exception('Could not find any NyanEyes BLE services');
    }

    void handleNotify(List<int> value) {
      try {
        final jsonStr = utf8.decode(value);
        final data = jsonDecode(jsonStr) as Map<String, dynamic>;
        if (_responseCompleter != null && !_responseCompleter!.isCompleted) {
          _responseCompleter!.complete(data);
        }
      } catch (_) {}
    }

    if (_provChar != null) {
      await _provChar!.setNotifyValue(true).timeout(const Duration(seconds: 5));
      _provNotifySub = _provChar!.onValueReceived.listen(handleNotify);
    }
    
    if (_outdoorChar != null) {
      await _outdoorChar!.setNotifyValue(true).timeout(const Duration(seconds: 5));
      _outdoorNotifySub = _outdoorChar!.onValueReceived.listen(handleNotify);
    }
    
    if (_batteryChar != null) {
      if (_batteryChar!.properties.notify) {
        await _batteryChar!.setNotifyValue(true).timeout(const Duration(seconds: 5));
      }
      if (_batteryChar!.properties.read) {
        try {
          await _batteryChar!.read();
        } catch (_) {}
      }
    }
  }

  /// Sends a JSON-encoded command to the device and waits for a response.
  /// 
  /// The device must be [init]ialized before calling this.
  /// Routes 'PROVISION' and 'OUTDOOR_INIT' to the provisioning service,
  /// and all other actions to the outdoor/control service.
  Future<Map<String, dynamic>> sendCommand(
    Map<String, dynamic> payload, {
    int timeoutSec = 15,
    bool waitResponse = true,
  }) async {
    final action = payload['action'] as String?;
    BluetoothCharacteristic? targetChar;
    
    if (action == 'PROVISION' || action == 'OUTDOOR_INIT') {
      targetChar = _provChar;
    } else {
      targetChar = _outdoorChar;
    }

    if (targetChar == null) {
      // Fallback if only one service is found, though protocol states both should be available
      targetChar = _outdoorChar ?? _provChar;
    }
    
    if (targetChar == null) throw Exception('Target BLE characteristic not found');
    
    final jsonStr = '${jsonEncode(payload)}\n';
    bool withoutResp = targetChar.properties.writeWithoutResponse;
    
    if (Platform.isAndroid) {
      try {
        await device.requestMtu(512);
        await Future.delayed(const Duration(milliseconds: 200));
      } catch (_) {}
    }
    
    if (waitResponse) {
      _responseCompleter = Completer<Map<String, dynamic>>();
      await targetChar.write(utf8.encode(jsonStr), withoutResponse: withoutResp).timeout(const Duration(seconds: 5));
      try {
        return await _responseCompleter!.future.timeout(Duration(seconds: timeoutSec));
      } finally {
        _responseCompleter = null;
      }
    } else {
      // 💡 [无回复高速写入]：动态使用 characteristic 自身的 properties.writeWithoutResponse 决定写入模式，防范 iOS 因特性越界强行断链
      await targetChar.write(utf8.encode(jsonStr), withoutResponse: withoutResp).timeout(const Duration(seconds: 5));
      return const <String, dynamic>{};
    }
  }

  /// Disposes of the client and cancels active subscriptions.
  void dispose() {
    _provNotifySub?.cancel();
    _outdoorNotifySub?.cancel();
  }
}
