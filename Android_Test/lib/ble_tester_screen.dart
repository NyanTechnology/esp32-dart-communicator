import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:esp32_comm/esp32_comm.dart';

class BleTesterScreen extends StatefulWidget {
  const BleTesterScreen({super.key});

  @override
  State<BleTesterScreen> createState() => _BleTesterScreenState();
}

class _BleTesterScreenState extends State<BleTesterScreen> {
  final List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  BluetoothDevice? _selectedDevice;
  DeviceBleClient? _bleClient;
  bool _isConnected = false;

  // UUID Configs
  final String _provServiceUuid = '4fafc201-1fb5-459e-8bcc-c5c9c331914b';
  final String _provCharUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';
  final String _outdoorServiceUuid = '4fafc201-1fb5-459e-8bcc-c5c9c331914c';
  final String _outdoorCharUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26a9';

  // Input Controllers
  final _ssidController = TextEditingController(text: 'My_Home_WiFi');
  final _passController = TextEditingController(text: 'My_Password_123');
  final _tokenController = TextEditingController(text: 'token_xyz');
  final _localKeyController = TextEditingController(text: 'my_secure_key_321');
  final _bleEyeController = TextEditingController(text: 'test_anim.gif');
  bool _relayState = false;

  // Console Logs
  final List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _log('系统就绪。请开启设备蓝牙，开始扫描。');
  }

  void _log(String msg) {
    if (!mounted) return;
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    setState(() {
      _logs.insert(0, '[$timeStr] $msg');
    });
  }

  void _startScan() async {
    setState(() {
      _scanResults.clear();
      _isScanning = true;
    });
    _log('正在搜寻 NyanEyes C3 设备...');

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 4),
      );
      
      FlutterBluePlus.scanResults.listen((results) {
        if (!mounted) return;
        for (ScanResult r in results) {
          // Filter by name or UUID
          final name = r.device.platformName;
          if (name.contains('NyanEyes') || name.contains('ESP32')) {
            if (!_scanResults.any((element) => element.device.remoteId == r.device.remoteId)) {
              setState(() {
                _scanResults.add(r);
              });
              _log('发现设备: $name (${r.device.remoteId})');
            }
          }
        }
      });

      await Future.delayed(const Duration(seconds: 4));
    } catch (e) {
      _log('扫描异常: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
        _log('扫描结束。共发现 ${_scanResults.length} 个备选设备。');
      }
    }
  }

  void _connect(BluetoothDevice device, bool isOutdoor) async {
    _log('正在连接 ${device.platformName} ...');
    setState(() {
      _selectedDevice = device;
      _isConnected = false;
    });

    try {
      await device.connect(autoConnect: false, license: License.nonprofit).timeout(const Duration(seconds: 8));
      
      final serviceUuid = isOutdoor ? _outdoorServiceUuid : _provServiceUuid;
      final charUuid = isOutdoor ? _outdoorCharUuid : _provCharUuid;

      _bleClient = DeviceBleClient(
        device,
        serviceUuid: serviceUuid,
        charUuid: charUuid,
      );

      _log('正在读取 GATT 服务并订阅特征...');
      await _bleClient!.init();
      
      if (!mounted) return;
      setState(() {
        _isConnected = true;
      });
      _log('连接成功！通信通道已打通。模式: ${isOutdoor ? "户外控制" : "极速配网"}');
    } catch (e) {
      _log('连接失败: $e');
      if (mounted) {
        setState(() {
          _selectedDevice = null;
        });
      }
    }
  }

  void _disconnect() async {
    if (_selectedDevice != null) {
      _log('断开蓝牙连接...');
      await _selectedDevice!.disconnect();
    }
    _bleClient?.dispose();
    setState(() {
      _selectedDevice = null;
      _bleClient = null;
      _isConnected = false;
    });
    _log('连接已断开。');
  }

  void _sendProvision() async {
    if (_bleClient == null) return;
    final ssid = _ssidController.text.trim();
    final pass = _passController.text.trim();
    final token = _tokenController.text.trim();

    final payload = {
      'action': 'PROVISION',
      'ssid': ssid,
      'password': pass,
      if (token.isNotEmpty) 'bind_token': token,
    };

    _log('发送 Wi-Fi 配网参数 -> SSID: $ssid');
    _log('发送内容: ${jsonEncode(payload)}');

    try {
      // 开启 Notify 异步应答等待 (timeout 设定为 10 秒)
      final response = await _bleClient!.sendCommand(payload, timeoutSec: 10);
      _log('C3 固件端 Notify 响应 -> $response');
    } catch (e) {
      _log('配网错误或超时: $e');
    }
  }

  void _sendOutdoorInit() async {
    if (_bleClient == null) return;
    final key = _localKeyController.text.trim();

    final payload = {
      'action': 'OUTDOOR_INIT',
      'local_key': key,
    };

    _log('发送户外模式初始化，密钥: $key');
    try {
      final response = await _bleClient!.sendCommand(payload, timeoutSec: 10);
      _log('C3 固件端 Notify 响应 -> $response');
    } catch (e) {
      _log('命令发送失败: $e');
    }
  }

  void _sendAuth() async {
    if (_bleClient == null) return;
    final key = _localKeyController.text.trim();

    final payload = {
      'action': 'AUTH',
      'local_key': key,
    };

    _log('开始安全鉴权握手 (AUTH) ...');
    try {
      final response = await _bleClient!.sendCommand(payload, timeoutSec: 10);
      _log('鉴权结果 -> $response');
    } catch (e) {
      _log('鉴权超时或异常: $e');
    }
  }

  void _sendToggleRelay() async {
    if (_bleClient == null) return;
    final newState = !_relayState;

    final payload = {
      'action': 'TOGGLE_RELAY',
      'state': newState ? 1 : 0,
    };

    _log('发送开关继电器指令 -> 目标状态: ${newState ? "开" : "关"}');
    try {
      final response = await _bleClient!.sendCommand(payload, timeoutSec: 10);
      _log('C3 响应 -> $response');
      if (response['status'] == 'success') {
        setState(() {
          _relayState = newState;
        });
      }
    } catch (e) {
      _log('控制失败: $e');
    }
  }

  void _sendBleApplyEyes() async {
    if (_bleClient == null) return;
    final filename = _bleEyeController.text.trim();
    if (filename.isEmpty) return;

    final payload = {
      'action': 'APPLY_EYES',
      'left': filename,
    };

    _log('蓝牙发送切换表情指令 -> $filename');
    try {
      final response = await _bleClient!.sendCommand(payload, timeoutSec: 10);
      _log('C3 蓝牙回复 -> $response');
    } catch (e) {
      _log('命令发送失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Top Action Panel
        Container(
          padding: const EdgeInsets.all(8.0),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              ElevatedButton.icon(
                onPressed: _isScanning ? null : _startScan,
                icon: const Icon(Icons.search),
                label: const Text('扫描蓝牙设备'),
              ),
              const SizedBox(width: 8),
              if (_isScanning) const CircularProgressIndicator(),
              const Spacer(),
              if (_selectedDevice != null)
                TextButton.icon(
                  onPressed: _disconnect,
                  icon: const Icon(Icons.close, color: Colors.redAccent),
                  label: const Text('断开', style: TextStyle(color: Colors.redAccent)),
                ),
            ],
          ),
        ),

        // Device Selection Pane
        if (_selectedDevice == null)
          Expanded(
            flex: 2,
            child: _scanResults.isEmpty
                ? const Center(child: Text('没有扫描到 NyanEyes 设备，请开启蓝牙后重试'))
                : ListView.builder(
                    itemCount: _scanResults.length,
                    itemBuilder: (context, index) {
                      final r = _scanResults[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: ListTile(
                          title: Text(r.device.platformName, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('MAC: ${r.device.remoteId}  |  RSSI: ${r.rssi} dBm'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                onPressed: () => _connect(r.device, false),
                                child: const Text('配网模式 (FFF0)'),
                              ),
                              TextButton(
                                onPressed: () => _connect(r.device, true),
                                child: const Text('户外模式 (FFE0)', style: TextStyle(color: Colors.amber)),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

        // Connected Controllers Pane
        if (_selectedDevice != null && _isConnected)
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12.0),
              child: Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('已连接: ${_selectedDevice!.platformName}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurpleAccent)),
                      const Divider(),
                      
                      // 1. WiFi 配网区域 (如果当前服务是 FFF0)
                      if (_bleClient!.serviceUuid.toLowerCase() == _provServiceUuid.toLowerCase()) ...[
                        const Text('Scenario 1: 配网与初始化', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amberAccent)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _ssidController,
                          decoration: const InputDecoration(labelText: 'WiFi SSID', border: OutlineInputBorder()),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _passController,
                          decoration: const InputDecoration(labelText: 'WiFi 密码', border: OutlineInputBorder()),
                          obscureText: true,
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _tokenController,
                          decoration: const InputDecoration(labelText: '云端绑定 Token (可选)', border: OutlineInputBorder()),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _sendProvision,
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
                                child: const Text('执行 WiFi 配网 (Reboot)'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _sendOutdoorInit,
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                                child: const Text('执行户外初始化 (Reboot)'),
                              ),
                            ),
                          ],
                        ),
                      ],

                      // 2. 户外控制区域 (如果当前服务是 FFE0)
                      if (_bleClient!.serviceUuid.toLowerCase() == _outdoorServiceUuid.toLowerCase()) ...[
                        const Text('Scenario 2: 户外直连控制 (需 AUTH)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amberAccent)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _localKeyController,
                          decoration: const InputDecoration(labelText: '安全密钥 (Local Key)', border: OutlineInputBorder()),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _sendAuth,
                                icon: const Icon(Icons.security),
                                label: const Text('安全鉴权 AUTH'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _sendToggleRelay,
                                icon: Icon(_relayState ? Icons.lightbulb : Icons.lightbulb_outline),
                                label: Text(_relayState ? '关闭指示灯' : '打开指示灯'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _relayState ? Colors.green : Colors.grey[700],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text('3. 蓝牙直连切换表情', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amberAccent)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _bleEyeController,
                                decoration: const InputDecoration(labelText: '表情文件名 (如 test_anim.gif)', border: OutlineInputBorder()),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: _sendBleApplyEyes,
                              icon: const Icon(Icons.play_circle_outline),
                              label: const Text('蓝牙刷新'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber[800],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),

        // Scrollable Console Log View
        Expanded(
          flex: 2,
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.all(8.0),
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(color: Colors.deepPurple, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.terminal, size: 16, color: Colors.green),
                    SizedBox(width: 6),
                    Text('通信原始日志面板', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
                const Divider(color: Colors.green, height: 10),
                Expanded(
                  child: ListView.builder(
                    reverse: false,
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: Text(
                          _logs[index],
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
