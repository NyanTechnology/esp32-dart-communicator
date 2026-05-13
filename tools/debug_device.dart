import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// NyanEye Firmware Compliance Suite (v3.0)
/// 
/// Allows selective testing of ESP32 API features.
void main(List<String> args) async {
  if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
    _printUsage();
    exit(0);
  }

  final target = args[0];
  final baseUrl = target.startsWith('http') ? target : 'http://$target';
  
  // Parse flags
  final bool testAll = args.contains('--all') || args.length == 1;
  final bool doInfo = testAll || args.contains('--info');
  final bool doUpload = testAll || args.contains('--upload');
  final bool doApply = testAll || args.contains('--apply');
  final bool doNegative = testAll || args.contains('--negative');

  print('======================================================');
  print('   NyanEye Firmware Compliance Suite (v3.0)   ');
  print('======================================================');
  print('Target Device: $baseUrl');
  print('Selected Tests: ${[
    if (doInfo) 'Info',
    if (doUpload) 'Upload',
    if (doApply) 'Apply',
    if (doNegative) 'Negative'
  ].join(', ')}\n');

  final client = http.Client();

  try {
    if (doInfo) await _testDeviceInfo(client, baseUrl);
    if (doUpload) await _testUploadRobustness(client, baseUrl);
    if (doApply) await _testApplyLogic(client, baseUrl);
    if (doNegative) await _testErrorHandling(client, baseUrl);
  } finally {
    client.close();
  }

  print('\n------------------------------------------------------');
  print('Compliance check finished.');
}

void _printUsage() {
  print('Usage: dart tools/debug_device.dart <device_ip> [options]');
  print('\nOptions:');
  print('  --all        Run all tests (default if no flags provided)');
  print('  --info       Test GET /api/device_info');
  print('  --upload     Test POST /api/upload (Small & Standard)');
  print('  --apply      Test GET /api/eyes/apply with params');
  print('  --negative   Test error handling (404)');
  print('\nExample:');
  print('  dart tools/debug_device.dart 192.168.4.1 --info --upload');
}

Future<void> _testDeviceInfo(http.Client client, String baseUrl) async {
  print('[STEP] Deep Validation: GET /api/device_info');
  try {
    final response = await client.get(Uri.parse('$baseUrl/api/device_info')).timeout(Duration(seconds: 5));
    if (response.statusCode != 200) {
      print('  ❌ FAIL: HTTP Status ${response.statusCode}');
      return;
    }
    print('  ✅ HTTP 200 OK');
    final Map<String, dynamic> data = json.decode(response.body);
    final mode = data['mode'] ?? '';
    final isAP = mode.toString().toLowerCase().contains('ap');
    
    final fields = {
      'firmware': true,
      'mode': true,
      'staConnected': true,
      'isManager': false, // Optional, defaults to false in app
      'apSsid': isAP,
      'apIp': isAP,
      'apClients': isAP,
    };

    fields.forEach((field, required) {
      if (data.containsKey(field) || data.containsKey(_toSnakeCase(field))) {
        print('  ✅ Field [$field]: ${data[field] ?? data[_toSnakeCase(field)]}');
      } else if (required) {
        print('  ❌ FAIL: Missing required field [$field]');
      } else {
        print('  ℹ️  Optional field [$field] omitted (Mode: $mode)');
      }
    });
  } catch (e) {
    print('  ❌ ERROR: $e');
  }
  print('');
}

String _toSnakeCase(String input) {
  return input.replaceAllMapped(RegExp(r'([A-Z])'), (match) => '_${match.group(1)!.toLowerCase()}');
}

Future<void> _testUploadRobustness(http.Client client, String baseUrl) async {
  print('[STEP] Robustness Test: POST /api/upload');
  await _performUpload(client, baseUrl, 'test_small.eye', 100, 'Small Payload (.eye)');
  await _performUpload(client, baseUrl, 'test_std.eye', 50 * 1024, 'Standard Asset (50KB .eye)');
  print('');
}

Future<void> _performUpload(http.Client client, String baseUrl, String filename, int size, String label) async {
  try {
    print('  Testing $label...');
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/upload'));
    request.files.add(http.MultipartFile.fromBytes('file', Uint8List(size), filename: filename));
    final streamedResponse = await client.send(request).timeout(Duration(seconds: 30));
    final respBody = await streamedResponse.stream.bytesToString();
    if (streamedResponse.statusCode == 200) {
      print('    ✅ Success');
    } else {
      print('    ❌ FAIL: ${streamedResponse.statusCode}');
      if (respBody.isNotEmpty) print('       Msg: $respBody');
    }
  } catch (e) {
    print('    ❌ ERROR: $e');
  }
}

Future<void> _testApplyLogic(http.Client client, String baseUrl) async {
  print('[STEP] Parameter Validation: GET /api/eyes/apply');
  try {
    // Note: We use the files we (hopefully) just uploaded
    final uri = Uri.parse('$baseUrl/api/eyes/apply').replace(queryParameters: {
      'left': '/images/test_small.eye',
      'right': '/images/test_small.eye',
      'leftMirror': 'true',
    });
    print('  Requesting: ${uri.path}${uri.query.isNotEmpty ? '?' + uri.query : ''}');
    final resp = await client.get(uri).timeout(Duration(seconds: 10));
    if (resp.statusCode == 200) {
      print('  ✅ Success');
    } else {
      print('  ❌ FAIL: ${resp.statusCode}');
      if (resp.body.isNotEmpty) print('     Msg: ${resp.body}');
    }
  } catch (e) {
    print('  ❌ ERROR: $e');
  }
  print('');
}

Future<void> _testErrorHandling(http.Client client, String baseUrl) async {
  print('[STEP] Negative Testing: Error Handling');
  try {
    final resp = await client.get(Uri.parse('$baseUrl/api/invalid_path_test'));
    print('  ℹ️  Device returned ${resp.statusCode}.');
  } catch (e) {
    print('  ⚠️  WARNING: Potential crash on invalid path.');
  }
}
