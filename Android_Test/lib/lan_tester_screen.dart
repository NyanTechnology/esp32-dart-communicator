import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:esp32_comm/esp32_comm.dart';

class LanTesterScreen extends StatefulWidget {
  const LanTesterScreen({super.key});

  @override
  State<LanTesterScreen> createState() => _LanTesterScreenState();
}

class _LanTesterScreenState extends State<LanTesterScreen> {
  final DeviceDiscoveryService _discoveryService = DeviceDiscoveryService();
  final DeviceHttpClient _httpClient = DeviceHttpClient();

  List<DeviceInfo> _discoveredDevices = [];
  bool _isDiscovering = false;
  DeviceInfo? _selectedDevice;
  String? _selectedBaseUrl;
  int? _displayDurationSeconds;

  // Controllers
  final _manualIpController = TextEditingController(text: '10.20.0.163');
  final _userIdController = TextEditingController(text: 'usr_94883199');
  final _bindTokenController = TextEditingController(text: 'token_abcdefg_9988');
  final _leftFilenameController = TextEditingController(text: 'test_anim.gif');
  final _rightFilenameController = TextEditingController(text: 'test_anim.gif');
  bool _leftMirror = false;
  bool _rightMirror = false;
  bool _autoApplyAfterUpload = true; // 上传成功后自动应用到双眼显示

  // Console Logs
  final List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _log('系统就绪。将 ESP32-C3 连接至家庭 Wi-Fi，手机接入同一局域网后，开始检索设备。');
  }

  void _log(String msg) {
    // 同时也输出到 IDE (如 VS Code) 的调试控制台
    debugPrint('📱 [LAN] $msg');
    if (!mounted) return;
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    setState(() {
      _logs.insert(0, '[$timeStr] $msg');
    });
  }

  void _discoverDevices() async {
    setState(() {
      _isDiscovering = true;
      _discoveredDevices.clear();
    });
    _log('开始扫描局域网设备 (并发 mDNS + UDP 广播扫描) ...');

    try {
      // 扫描 4 秒，确保设备响应
      final devices = await _discoveryService.discoverEsp32DevicesOnLan(
        timeout: const Duration(seconds: 4),
      );

      if (!mounted) return;

      setState(() {
        _discoveredDevices = devices;
      });
      _log('扫描完成。共发现 ${devices.length} 个搭载 NyanEye 固件的活动设备。');
      for (var d in devices) {
        _log('发现设备 IP: ${d.staIp} | mDNS Host: ${d.mdnsHost} | 固件: ${d.firmware}');
      }
    } catch (e) {
      _log('发现接口异常: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isDiscovering = false;
        });
      }
    }
  }

  void _fetchDeviceInfo(String baseUrl) async {
    _log('正在抓取设备状态: $baseUrl/api/device_info ...');
    try {
      final info = await _httpClient.fetchDeviceInfo(baseUrl);
      if (info != null) {
        if (!mounted) return;
        setState(() {
          _selectedDevice = info;
          _selectedBaseUrl = baseUrl;
          _displayDurationSeconds = null;
        });
        _log('抓取成功！固件版本: ${info.firmware} | 连网状态: ${info.staConnected ? "已连接" : "未连接"}');

        // Auto fetch screen active duration
        final duration = await _httpClient.fetchDisplayDuration(baseUrl);
        if (mounted && duration != null) {
          setState(() {
            _displayDurationSeconds = duration;
          });
          _log('🎉 累计亮屏时间已同步: ${_formatDuration(duration)}');
        }
      } else {
        _log('抓取失败，HTTP 返回非 200 或网络不可达。');
      }
    } catch (e) {
      _log('HTTP 获取错误: $e');
    }
  }

  void _pickAndUploadFile() async {
    if (_selectedBaseUrl == null) return;

    _log('正在打开系统文件选择器...');
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );

      if (result != null && result.files.single.bytes != null) {
        final fileBytes = result.files.single.bytes!;
        final originalName = result.files.single.name;

        // Apply SPIFFS filename limit sanitization!
        final dotIndex = originalName.lastIndexOf('.');
        final ext = dotIndex != -1 ? originalName.substring(dotIndex) : '';
        final filename = sanitizeSpiffsFilename(originalName, ext);

        _log('已选择文件: $originalName | 净化并适配 SPIFFS 文件名: $filename | 大小: ${fileBytes.length} 字节');
        _log('正在流式分包上传文件至 C3 (SPIFFS) ...');

        final success = await _httpClient.uploadEyeData(
          _selectedBaseUrl!,
          Uint8List.fromList(fileBytes),
          filename,
        );

        if (success) {
          _log('🎉 上传成功！固件已将数据安全写入 /spiffs/images/$filename');
          setState(() {
            _leftFilenameController.text = filename;
            _rightFilenameController.text = filename;
          });
          if (_autoApplyAfterUpload) {
            _log('🔄 检测到“自动应用”已开启，正在向 C3 发送画面切换指令...');
            _applyEyes();
          }
        } else {
          _log('❌ 上传失败。可能由于 C3 闪存空间不足或网络中断。');
        }
      } else {
        _log('取消选择文件。');
      }
    } catch (e) {
      _log('文件上传异常: $e');
    }
  }

  void _applyEyes() async {
    if (_selectedBaseUrl == null) return;
    final leftFile = _leftFilenameController.text.trim();
    final rightFile = _rightFilenameController.text.trim();

    _log('请求应用显示 -> 左眼: $leftFile, 右眼: $rightFile, 镜像: $_leftMirror/$_rightMirror');
    
    try {
      final success = await _httpClient.applyEyeConfigs(
        _selectedBaseUrl!,
        leftFile,
        rightFile,
        leftMirror: _leftMirror,
        rightMirror: _rightMirror,
      );

      if (success) {
        _log('🎉 指令执行成功！C3 屏幕正在刷新显示。');
      } else {
        _log('❌ 固件端应用失败，可能目标文件不存在。');
      }
    } catch (e) {
      _log('HTTP 提交错误: $e');
    }
  }

  void _resetDevice() async {
    if (_selectedBaseUrl == null) return;

    _log('⚠️ 正在向 C3 发送远程软复位/重新配网指令...');
    try {
      final success = await _httpClient.resetDevice(_selectedBaseUrl!);
      if (!mounted) return;
      if (success) {
        _log('🎉 远程软复位成功！固件正在擦除所有 Wi-Fi 配置，并即刻重启进入蓝牙配网模式！');
        setState(() {
          _selectedDevice = null;
          _selectedBaseUrl = null;
        });
      } else {
        _log('❌ 软复位请求失败，可能设备未响应。');
      }
    } catch (e) {
      _log('软复位异常: $e');
    }
  }

  void _refreshBattery() async {
    if (_selectedBaseUrl == null) return;
    _log('正在通过局域网独立获取电量 /api/battery ...');
    try {
      final val = await _httpClient.fetchBatteryLevel(_selectedBaseUrl!);
      if (!mounted) return;
      if (val != null) {
        _log('🎉 独立电量抓取成功: $val%');
        setState(() {
          _selectedDevice = DeviceInfo(
            firmware: _selectedDevice!.firmware,
            mode: _selectedDevice!.mode,
            apSsid: _selectedDevice!.apSsid,
            apIp: _selectedDevice!.apIp,
            apClients: _selectedDevice!.apClients,
            staConnected: _selectedDevice!.staConnected,
            isManager: _selectedDevice!.isManager,
            staSsid: _selectedDevice!.staSsid,
            staIp: _selectedDevice!.staIp,
            mdnsHost: _selectedDevice!.mdnsHost,
            mdnsUrl: _selectedDevice!.mdnsUrl,
            managerHost: _selectedDevice!.managerHost,
            managerUrl: _selectedDevice!.managerUrl,
            batteryLevel: val,
            powerSavingMode: _selectedDevice!.powerSavingMode,
          );
        });
      } else {
        _log('❌ 独立电量抓取失败。');
      }
    } catch (e) {
      _log('电量抓取异常: $e');
    }
  }

  void _pingDevice() async {
    if (_selectedBaseUrl == null) return;
    _log('正在向 C3 发送网络检测请求 (HTTP Ping) ...');
    try {
      final rtt = await _httpClient.pingDevice(_selectedBaseUrl!);
      if (!mounted) return;
      if (rtt != null) {
        _log('🎉 网络正常！Ping 成功，往返时延 RTT: $rtt ms | 状态: pong');
      } else {
        _log('❌ 网络异常或超时！C3 无响应。');
      }
    } catch (e) {
      _log('网络检测异常: $e');
    }
  }

  void _bindUser() async {
    if (_selectedBaseUrl == null) return;
    final userId = _userIdController.text.trim();
    final token = _bindTokenController.text.trim();

    if (userId.isEmpty || token.isEmpty) {
      _log('❌ 绑定失败: 用户 ID 或 Token 不能为空');
      return;
    }

    _log('正在向 C3 发送云端绑定请求...');
    try {
      final success = await _httpClient.bindUser(_selectedBaseUrl!, userId, token);
      if (!mounted) return;
      if (success) {
        _log('🎉 绑定成功！C3 已接收到用户信息，正在后台启动云端注册上报 (cloud_binding_task) ...');
      } else {
        _log('❌ 绑定失败，可能接口未响应。');
      }
    } catch (e) {
      _log('绑定异常: $e');
    }
  }

  void _enterSleepMode() async {
    if (_selectedBaseUrl == null) return;

    _log('⚠️ 正在向 C3 发送一键进入低功耗待机命令...');
    try {
      final success = await _httpClient.enterSleepMode(_selectedBaseUrl!);
      if (!mounted) return;
      if (success) {
        _log('🎉 远程待机命令成功！C3 屏幕已硬熄灭，系统射频进入低电量轻休眠监听状态。');
        _log('💡 提示：在 App 中重新点击任意“应用眼部配置”指令，设备即可瞬间自动唤醒！');
        setState(() {
          _selectedDevice = DeviceInfo(
            firmware: _selectedDevice!.firmware,
            mode: _selectedDevice!.mode,
            apSsid: _selectedDevice!.apSsid,
            apIp: _selectedDevice!.apIp,
            apClients: _selectedDevice!.apClients,
            staConnected: _selectedDevice!.staConnected,
            isManager: _selectedDevice!.isManager,
            staSsid: _selectedDevice!.staSsid,
            staIp: _selectedDevice!.staIp,
            mdnsHost: _selectedDevice!.mdnsHost,
            mdnsUrl: _selectedDevice!.mdnsUrl,
            managerHost: _selectedDevice!.managerHost,
            managerUrl: _selectedDevice!.managerUrl,
            batteryLevel: _selectedDevice!.batteryLevel,
            powerSavingMode: true,
          );
        });
      } else {
        _log('❌ 待机命令发送失败。');
      }
    } catch (e) {
      _log('待机发生异常: $e');
    }
  }

  String _formatDuration(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    final hStr = hours > 0 ? '$hours小时' : '';
    final mStr = minutes > 0 ? '$minutes分' : '';
    return '$hStr$mStr$seconds秒';
  }

  void _refreshDuration() async {
    if (_selectedBaseUrl == null) return;
    _log('正在向 C3 抓取亮屏累计时间 /api/display/duration ...');
    try {
      final seconds = await _httpClient.fetchDisplayDuration(_selectedBaseUrl!);
      if (!mounted) return;
      if (seconds != null) {
        _log('🎉 今日累计亮屏时间: ${_formatDuration(seconds)}');
        setState(() {
          _displayDurationSeconds = seconds;
        });
      } else {
        _log('❌ 亮屏时间抓取失败。');
      }
    } catch (e) {
      _log('时间抓取异常: $e');
    }
  }

  void _syncTime() async {
    if (_selectedBaseUrl == null) return;
    _log('正在向 C3 发送网络时间同步指令...');
    try {
      final timeStr = await _httpClient.syncDeviceTime(_selectedBaseUrl!);
      if (!mounted) return;
      if (timeStr != null) {
        _log('🎉 时间同步成功！C3 内部 RTC 时钟已校准为: $timeStr');
      } else {
        _log('❌ 时间同步失败，可能设备未响应。');
      }
    } catch (e) {
      _log('时间同步异常: $e');
    }
  }

  void _runTripleUploadAndApplyTest() async {
    if (_selectedBaseUrl == null) {
      _log('❌ 错误：请先连接一个局域网设备');
      return;
    }

    _log('🧪 [压力测试] 启动固件“上传+显示”三次断链漏洞检测...');
    _log('步骤 1: 正在打开系统文件选择器，请选择用于测试的图片/GIF文件...');

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );

      if (result == null || result.files.single.bytes == null) {
        _log('⚠️ 测试取消：未选择任何文件。');
        return;
      }

      final fileBytes = result.files.single.bytes!;
      final filename = result.files.single.name;

      _log('📂 已选择测试文件: $filename | 大小: ${fileBytes.length} 字节');
      _log('🚀 开始连续 3 轮“上传并显示”循环测试，每轮间隔 2.5 秒...');

      bool testPassed = true;
      int failedRound = 0;
      String failureReason = '';

      for (int i = 1; i <= 3; i++) {
        _log('========================================');
        _log('🧪 [第 $i / 3 轮] 开始测试');
        _log('========================================');

        // 1. 上传文件
        _log('第 $i 轮 -> 正在上传文件至 C3 (SPIFFS)...');
        final uploadSw = Stopwatch()..start();
        final uploadSuccess = await _httpClient.uploadEyeData(
          _selectedBaseUrl!,
          Uint8List.fromList(fileBytes),
          filename,
        );
        uploadSw.stop();

        if (!uploadSuccess) {
          testPassed = false;
          failedRound = i;
          failureReason = '第 $i 轮文件上传失败 (HTTP 错误或超时)';
          _log('❌ $failureReason');
          break;
        }
        _log('第 $i 轮 -> ✅ 文件上传成功！耗时: ${uploadSw.elapsedMilliseconds} ms');

        // 2. 应用显示
        _log('第 $i 轮 -> 正在发送应用显示指令...');
        final applySw = Stopwatch()..start();
        final applySuccess = await _httpClient.applyEyeConfigs(
          _selectedBaseUrl!,
          filename,
          filename,
          leftMirror: _leftMirror,
          rightMirror: _rightMirror,
        );
        applySw.stop();

        if (!applySuccess) {
          testPassed = false;
          failedRound = i;
          failureReason = '第 $i 轮应用显示指令执行失败';
          _log('❌ $failureReason');
          break;
        }
        _log('第 $i 轮 -> ✅ 应用指令执行成功！耗时: ${applySw.elapsedMilliseconds} ms');

        // 3. 稳定等待
        _log('第 $i 轮 -> 正在等待 2.5 秒以确保固件完成文件解压、渲染和画面切换...');
        await Future.delayed(const Duration(milliseconds: 2500));

        // 4. 连通性测试 (Ping)
        _log('第 $i 轮 -> 正在测试设备连通性 (Ping)...');
        final pingSw = Stopwatch()..start();
        final rtt = await _httpClient.pingDevice(_selectedBaseUrl!);
        pingSw.stop();

        if (rtt == null) {
          testPassed = false;
          failedRound = i;
          failureReason = '第 $i 轮连通性测试 (Ping) 失败，设备已断线/无响应！';
          _log('❌ $failureReason');
          break;
        }
        _log('第 $i 轮 -> ✅ 连通性正常！往返时延 RTT: $rtt ms');
      }

      _log('========================================');
      if (testPassed) {
        _log('🎉🎉🎉 [测试完成] 连续 3 轮“上传并显示”压力测试顺利通过！');
        _log('✅ 结论: 当前固件已成功解决“上传显示图像三次后导致设备断链”的问题！');
        
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 28),
                SizedBox(width: 10),
                Text('🎉 测试完美通过！'),
              ],
            ),
            content: const Text(
              '在连续 3 轮高强度的“文件上传 -> 刷新显示 -> 网络探测”测试中，ESP32-C3 设备稳定运行，未出现任何崩溃、断链或无响应现象！\n\n'
              '结论：您的固件已成功解决“上传显示图像3次后断线”的核心 Bug！',
              style: TextStyle(fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      } else {
        _log('🚨🚨🚨 [测试失败] 压力测试异常中断！');
        _log('❌ 失败原因: $failureReason');
        _log('💡 结论: 固件仍存在断链或崩溃问题，请检查固件端的 SPIFFS 写冲突、网络协议栈或内存泄漏（Out of Memory）！');

        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error, color: Colors.red, size: 28),
                SizedBox(width: 10),
                Text('❌ 测试未通过！'),
              ],
            ),
            content: Text(
              '压力测试在第 $failedRound 轮检测到异常中断：\n\n'
              '具体表现为：$failureReason\n\n'
              '结论：固件“上传并显示 3 次后导致断链”的问题可能仍未完全解决。请结合 C3 串口日志（Serial Monitor）排查内存溢出或 SPIFFS 文件系统写保护问题。',
              style: const TextStyle(fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('去排查'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _log('💥 测试运行异常: $e');
    }
  }

  Future<Uint8List?> _convertImageToRgb565(Uint8List originalBytes) async {
    try {
      _log('🎨 [转换引擎] 正在解码并重采样图像为 160x160...');
      
      // 使用 Flutter built-in dart:ui 解码并重采样到 160x160
      final codec = await ui.instantiateImageCodec(
        originalBytes,
        targetWidth: 160,
        targetHeight: 160,
        allowUpscaling: true,
      );
      final frameInfo = await codec.getNextFrame();
      final image = frameInfo.image;
      
      _log('🎨 [转换引擎] 获取原始 RGBA8888 像素数据...');
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) {
        _log('❌ [转换引擎] 错误: 无法提取像素数据');
        return null;
      }
      
      final rgbaBytes = byteData.buffer.asUint8List();
      final rgb565Bytes = Uint8List(160 * 160 * 2); // 恰好 51200 字节
      
      _log('🎨 [转换引擎] 正在将 RGBA8888 转换为 RGB565 Big Endian Byte Array...');
      int offset = 0;
      for (int i = 0; i < rgbaBytes.length; i += 4) {
        final r = rgbaBytes[i];
        final g = rgbaBytes[i + 1];
        final b = rgbaBytes[i + 2];
        // Alpha 通道忽略，直接对 RGB 进行 16位 RGB565 重构
        final r5 = (r >> 3) & 0x1F;
        final g6 = (g >> 2) & 0x3F;
        final b5 = (b >> 3) & 0x1F;
        final rgb565 = (r5 << 11) | (g6 << 5) | b5;
        
        // 存储为 Big Endian（大端序：高8位在前，低8位在后）
        rgb565Bytes[offset++] = (rgb565 >> 8) & 0xFF;
        rgb565Bytes[offset++] = rgb565 & 0xFF;
      }
      
      _log('🎨 [转换引擎] 转换完成！输出大小: ${rgb565Bytes.length} 字节 (.eye 格式标准大小)');
      return rgb565Bytes;
    } catch (e) {
      _log('❌ [转换引擎] 转换异常: $e');
      return null;
    }
  }

  void _pickConvertAndUploadImage() async {
    if (_selectedBaseUrl == null) {
      _log('❌ 错误：请先连接局域网设备');
      return;
    }

    _log('📂 [智能转换及上传] 正在打开文件选择器选择图片 (PNG/JPG/WEBP/GIF)...');
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
        withData: true,
      );

      if (result == null || result.files.single.bytes == null) {
        _log('⚠️ 操作取消：未选择任何图片文件。');
        return;
      }

      final originalBytes = result.files.single.bytes!;
      final originalName = result.files.single.name;
      _log('📂 已选择源图片: $originalName | 大小: ${originalBytes.length} 字节');

      final isGif = originalName.toLowerCase().endsWith('.gif');
      final targetExtension = isGif ? '.gif' : '.eye';
      final targetFilename = sanitizeSpiffsFilename(originalName, targetExtension);

      Uint8List? convertedBytes;

      if (isGif) {
        _log('🎬 检测到动画 GIF，启动多帧智能重采样缩放引擎 (Isolate)...');
        convertedBytes = await compute(_resizeGifTo160InIsolate, originalBytes);
      } else {
        _log('🖼️ 检测到静态图像 (PNG/JPG/WEBP)，启动硬件加速无损 RGB565 转换引擎...');
        convertedBytes = await _convertImageToRgb565(originalBytes);
      }

      if (convertedBytes == null) {
        _log('❌ 格式转换/重采样处理失败，中止上传。');
        return;
      }

      _log('🚀 正在将处理完成的 $targetFilename (${convertedBytes.length} 字节) 串行流式上传至 C3 (SPIFFS)...');
      final success = await _httpClient.uploadEyeData(
        _selectedBaseUrl!,
        convertedBytes,
        targetFilename,
      );

      if (success) {
        _log('🎉 智能转换并上传成功！目标文件已安全写入 /spiffs/images/$targetFilename');
        setState(() {
          _leftFilenameController.text = targetFilename;
          _rightFilenameController.text = targetFilename;
        });
        if (_autoApplyAfterUpload) {
          _log('🔄 检测到“自动应用”已开启，正在向 C3 发送画面切换指令...');
          _applyEyes();
        }
      } else {
        _log('❌ 上传已转换的文件失败。可能由于 C3 闪存空间不足、SPIFFS 损坏或网络中断。');
      }
    } catch (e) {
      _log('💥 智能转换及上传处理异常: $e');
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
                onPressed: _isDiscovering ? null : _discoverDevices,
                icon: const Icon(Icons.travel_explore),
                label: const Text('扫描局域网'),
              ),
              const SizedBox(width: 8),
              if (_isDiscovering) const CircularProgressIndicator(),
              const Spacer(),
              if (_selectedBaseUrl != null) ...[
                TextButton.icon(
                  onPressed: _pingDevice,
                  icon: const Icon(Icons.network_check, color: Colors.greenAccent),
                  label: const Text('网络检测 (Ping)', style: TextStyle(color: Colors.greenAccent)),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedDevice = null;
                      _selectedBaseUrl = null;
                    });
                    _log('退出当前设备控制。');
                  },
                  icon: const Icon(Icons.close, color: Colors.amber),
                  label: const Text('释放设备', style: TextStyle(color: Colors.amber)),
                ),
              ],
            ],
          ),
        ),

        // Manual IP Direct Connection Pane (Fallback for blocked multicast)
        if (_selectedBaseUrl == null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _manualIpController,
                    decoration: const InputDecoration(
                      labelText: '手动直连 IP (例如: 10.20.0.163)',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    final ip = _manualIpController.text.trim();
                    if (ip.isNotEmpty) {
                      _fetchDeviceInfo('http://$ip:80');
                    }
                  },
                  icon: const Icon(Icons.link),
                  label: const Text('直连'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
        ],

        // Discovered Devices Selection Pane
        if (_selectedBaseUrl == null)
          Expanded(
            flex: 2,
            child: _discoveredDevices.isEmpty
                ? const Center(child: Text('局域网未发现活动设备，请确认 Wi-Fi 及 IP 设置'))
                : ListView.builder(
                    itemCount: _discoveredDevices.length,
                    itemBuilder: (context, index) {
                      final d = _discoveredDevices[index];
                      // Reconstruct active URL (C3 runs web server on standard port 80)
                      final baseUrl = 'http://${d.staIp}:80';
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: ListTile(
                          title: Text('IP: ${d.staIp}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('MDNS: ${d.mdnsHost ?? "nyaneye.local"} | FW: ${d.firmware}'),
                          trailing: ElevatedButton.icon(
                            onPressed: () => _fetchDeviceInfo(baseUrl),
                            icon: const Icon(Icons.power_settings_new),
                            label: const Text('连接控制'),
                          ),
                        ),
                      );
                    },
                  ),
          ),

        // Connected Device Controller Dashboard
        if (_selectedBaseUrl != null && _selectedDevice != null)
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
                      Text('活动控制台: $_selectedBaseUrl', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                      Text('设备 Wi-Fi 网卡: ${_selectedDevice!.staSsid} (IP: ${_selectedDevice!.staIp})', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.battery_charging_full, size: 14, color: Colors.green[400]),
                          const SizedBox(width: 4),
                          Text('电量: ${_selectedDevice!.batteryLevel ?? 100}%', style: TextStyle(fontSize: 12, color: Colors.green[400])),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: _refreshBattery,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.all(2.0),
                              child: Icon(Icons.refresh, size: 12, color: Colors.green[200]),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Icon(Icons.energy_savings_leaf, size: 14, color: _selectedDevice!.powerSavingMode == true ? Colors.amber[400] : Colors.grey[400]),
                          const SizedBox(width: 4),
                          Text('节电模式: ${_selectedDevice!.powerSavingMode == true ? "开启" : "关闭"}', style: TextStyle(fontSize: 12, color: _selectedDevice!.powerSavingMode == true ? Colors.amber[400] : Colors.grey[400])),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.timer, size: 14, color: Colors.blue[300]),
                          const SizedBox(width: 4),
                          Text(
                            '今日累计亮屏: ${_displayDurationSeconds != null ? _formatDuration(_displayDurationSeconds!) : "0秒"}',
                            style: TextStyle(fontSize: 12, color: Colors.blue[300]),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: _refreshDuration,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.all(2.0),
                              child: Icon(Icons.refresh, size: 12, color: Colors.blue[200]),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Icon(Icons.access_time, size: 14, color: Colors.indigoAccent[100]),
                          const SizedBox(width: 4),
                          TextButton(
                            onPressed: _syncTime,
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              '同步系统时间',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.indigoAccent[100],
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(),

                      // 1. HTTP 动图上传区域
                      const Text('1. 上传眼部图像/GIF 动画 (.eye / .gif)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.tealAccent)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _pickAndUploadFile,
                              icon: const Icon(Icons.file_upload),
                              label: const Text('直接上传 .eye/.gif'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal[800],
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _pickConvertAndUploadImage,
                              icon: const Icon(Icons.transform, color: Colors.amberAccent),
                              label: const Text('智能转换 (JPG/PNG/GIF)', style: TextStyle(color: Colors.amberAccent, fontSize: 11)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.cyan[900],
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                        ],
                      ),
                      CheckboxListTile(
                        title: const Text('上传成功后自动设为眼部输出并刷新显示', style: TextStyle(fontSize: 12, color: Colors.tealAccent)),
                        value: _autoApplyAfterUpload,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (val) {
                          setState(() {
                            _autoApplyAfterUpload = val ?? false;
                          });
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      const SizedBox(height: 16),

                      // 2. HTTP 动态眼部应用控制
                      const Text('2. 切换眼部配置文件 & 动画应用', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.tealAccent)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _leftFilenameController,
                              decoration: const InputDecoration(labelText: '左眼文件名称', border: OutlineInputBorder()),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _rightFilenameController,
                              decoration: const InputDecoration(labelText: '右眼文件名称', border: OutlineInputBorder()),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: CheckboxListTile(
                              title: const Text('左眼镜像', style: TextStyle(fontSize: 12)),
                              value: _leftMirror,
                              onChanged: (val) {
                                setState(() {
                                  _leftMirror = val ?? false;
                                });
                              },
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                          ),
                          Expanded(
                            child: CheckboxListTile(
                              title: const Text('右眼镜像', style: TextStyle(fontSize: 12)),
                              value: _rightMirror,
                              onChanged: (val) {
                                setState(() {
                                  _rightMirror = val ?? false;
                                });
                              },
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _applyEyes,
                          icon: const Icon(Icons.play_circle_outline),
                          label: const Text('应用眼部配置 GET /apply'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo[800]),
                        ),
                      ),
                      const Divider(height: 24),

                      // 3. 固件断链漏洞测试 (上传并显示3次)
                      const Text('3. 固件断链漏洞检测 (连续3次上传并显示)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.pinkAccent)),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _runTripleUploadAndApplyTest,
                          icon: const Icon(Icons.bug_report, color: Colors.white),
                          label: const Text('执行 3次 连续上传与应用测试', style: TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.pink[800]),
                        ),
                      ),
                      const Divider(height: 24),
                      
                      // 用户与云端绑定配对
                      const Text('用户与云端绑定配对', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigoAccent)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _userIdController,
                              decoration: const InputDecoration(labelText: '用户 ID', border: OutlineInputBorder()),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _bindTokenController,
                              decoration: const InputDecoration(labelText: '绑定 Token', border: OutlineInputBorder()),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _bindUser,
                          icon: const Icon(Icons.cloud_upload),
                          label: const Text('上传并激活云端绑定 POST /user/bind'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo[800]),
                        ),
                      ),
                      const Divider(height: 24),
                      
                      // 4. 系统维护与模式重置
                      const Text('4. 系统维护与模式重置', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _enterSleepMode,
                              icon: const Icon(Icons.power_settings_new, color: Colors.white),
                              label: const Text('一键休眠待机', style: TextStyle(color: Colors.white)),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber[900]),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _resetDevice,
                              icon: const Icon(Icons.settings_backup_restore, color: Colors.white),
                              label: const Text('恢复出厂设置', style: TextStyle(color: Colors.white)),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red[900]),
                            ),
                          ),
                        ],
                      ),
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
              border: Border.all(color: Colors.teal, width: 1.5),
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

/// Sanitizes a filename to fit the ESP32 SPIFFS filename limit (maximum path length of 32 characters).
/// Given that the directory prefix is '/images/' (8 characters), the baseName + extension can be at most 23 characters.
String sanitizeSpiffsFilename(String originalName, String extension) {
  final dotIndex = originalName.lastIndexOf('.');
  String baseName = dotIndex != -1 ? originalName.substring(0, dotIndex) : originalName;
  
  // Clean baseName of special characters, keep only standard alphanumeric characters or underscores
  baseName = baseName.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '');
  if (baseName.isEmpty) {
    baseName = 'eye_temp';
  }
  
  // Max filename length including extension is 31 - 8 = 23 characters.
  // We limit the baseName length so that baseName + extension is <= 22 characters.
  final maxBaseLength = 22 - extension.length; // e.g. 22 - 4 (.eye or .gif) = 18 characters
  if (baseName.length > maxBaseLength) {
    baseName = baseName.substring(0, maxBaseLength);
  }
  
  return '$baseName$extension';
}

/// Helper function to resize animated GIF using the 'image' package.
/// This runs in a separate Isolate to keep the UI responsive.
Uint8List? _resizeGifTo160InIsolate(Uint8List originalBytes) {
  try {
    final decodedImage = img.decodeGif(originalBytes);
    if (decodedImage == null) return null;

    // Check if resize is actually needed
    if (decodedImage.width == 160 && decodedImage.height == 160) {
      return originalBytes;
    }

    // copyResize resizes all animation frames in image v4.x automatically
    final resized = img.copyResize(
      decodedImage,
      width: 160,
      height: 160,
      interpolation: img.Interpolation.nearest, // Fastest interpolation for pixel efficiency
    );

    final gifBytes = img.encodeGif(resized);
    return Uint8List.fromList(gifBytes);
  } catch (e) {
    debugPrint('Isolate GIF resize error: $e');
    return null;
  }
}
