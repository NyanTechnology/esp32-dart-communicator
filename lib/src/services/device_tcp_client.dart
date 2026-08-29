import 'dart:io';
import 'dart:async';
import 'dart:convert';
import '../models/nyan_eyes_protocol.dart';
import '../models/wifi_scan_network.dart';

/// A secure TCP Socket client for communicating with ESP32 NyanEye devices on LAN (port 8080).
///
/// Automatically performs challenge-response HMAC-SHA256 zero-trust authentication upon connection.
class DeviceTcpClient {
  final String ip;
  final int port;
  Socket? _socket;
  StreamSubscription<String>? _subscription;
  String _receiveBuffer = '';

  Completer<Map<String, dynamic>>? _responseCompleter;
  bool _isAuthenticated = false;
  final StreamController<Map<String, dynamic>> _notificationController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Creates a new [DeviceTcpClient] for the given [ip].
  DeviceTcpClient(this.ip, {this.port = 8080});

  /// Whether the socket is connected and authenticated.
  bool get isConnected => _socket != null && _isAuthenticated;

  /// Connects to the device and authenticates using the [localKey] via zero-trust challenge-response.
  Future<void> connect(String localKey) async {
    close();
    _isAuthenticated = false;

    try {
      // 1. Establish raw TCP Socket connection
      _socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(seconds: 5),
      );
      _receiveBuffer = '';
      _subscription = _socket!
          .cast<List<int>>()
          .transform(utf8.decoder)
          .listen(
            _handleSocketData,
            onError: (Object error, StackTrace stackTrace) {
              final completer = _responseCompleter;
              if (completer != null && !completer.isCompleted) {
                completer.completeError(error, stackTrace);
              }
              close();
            },
            onDone: close,
          );
      _socket!.write('\n'); // Clear buffer
      await _socket!.flush();

      // 2. Step One: Get Challenge (nonce)
      final challengePayload =
          jsonDecode(NyanEyesProtocol.getChallenge()) as Map<String, dynamic>;
      final challengeRes = await _sendAndWait(challengePayload, timeoutSec: 4);

      if (!challengeRes.containsKey('nonce')) {
        throw Exception(
          'Failed to fetch challenge nonce: ${challengeRes['message'] ?? 'Nonce key not found'}',
        );
      }

      final nonce = challengeRes['nonce'].toString();

      // 3. Step Two: Calculate HMAC-SHA256 Hash
      final hash = NyanEyesProtocol.calculateAuthHash(nonce, localKey);

      // 4. Step Three: Submit Authentication Hash
      final authPayload =
          jsonDecode(NyanEyesProtocol.auth(hash)) as Map<String, dynamic>;
      final authRes = await _sendAndWait(authPayload, timeoutSec: 4);

      final isSuccess =
          authRes['status'] == 'success' ||
          authRes['status'] == 'authenticated' ||
          authRes['message'] == 'authenticated';

      if (isSuccess) {
        _isAuthenticated = true;
      } else {
        throw Exception(
          'HMAC challenge authentication failed: ${authRes['message']}',
        );
      }
    } catch (e) {
      close();
      rethrow;
    }
  }

  void _handleSocketData(String data) {
    _receiveBuffer += data;
    while (_receiveBuffer.contains('\n')) {
      final delimiterIndex = _receiveBuffer.indexOf('\n');
      final line = _receiveBuffer.substring(0, delimiterIndex).trim();
      _receiveBuffer = _receiveBuffer.substring(delimiterIndex + 1);
      if (line.isEmpty) continue;

      try {
        final response = jsonDecode(line) as Map<String, dynamic>;
        _notificationController.add(response);
        final completer = _responseCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.complete(response);
        }
      } on FormatException {
        // Ignore malformed frames and continue processing later JSON lines.
      }
    }
  }

  Future<Map<String, dynamic>> _sendAndWait(
    Map<String, dynamic> payload, {
    required int timeoutSec,
  }) async {
    final socket = _socket;
    if (socket == null) throw Exception('Socket disconnected');
    if (_responseCompleter != null) {
      throw StateError('Another TCP command is already waiting for a response');
    }

    final completer = Completer<Map<String, dynamic>>();
    _responseCompleter = completer;
    try {
      socket.write('${jsonEncode(payload)}\n');
      await socket.flush();
      return await completer.future.timeout(Duration(seconds: timeoutSec));
    } finally {
      if (identical(_responseCompleter, completer)) {
        _responseCompleter = null;
      }
    }
  }

  /// Sends a command over the authenticated TCP socket.
  Future<Map<String, dynamic>> sendCommand(
    Map<String, dynamic> payload, {
    int timeoutSec = 5,
  }) async {
    if (_socket == null || !_isAuthenticated) {
      throw Exception('TCP Client is not connected or authenticated');
    }

    return _sendAndWait(payload, timeoutSec: timeoutSec);
  }

  /// Scans nearby Wi-Fi networks over the authenticated TCP control link.
  Future<List<WifiScanNetwork>> scanWifiNetworks({int timeoutSec = 20}) async {
    final networksBySsid = <String, WifiScanNetwork>{};
    final completer = Completer<List<WifiScanNetwork>>();
    int? scanId;

    late final StreamSubscription<Map<String, dynamic>> subscription;
    subscription = _notificationController.stream.listen(
      (data) {
        final message = data['message']?.toString();
        final frameScanId = (data['scan_id'] as num?)?.toInt();
        if (message == 'wifi_scan_started') {
          scanId = frameScanId;
          return;
        }
        if (scanId != null && frameScanId != scanId) return;

        if (message == 'wifi_ap') {
          final network = WifiScanNetwork.fromJson(data);
          if (network.ssid.isNotEmpty &&
              network.supported &&
              network.channel >= 1 &&
              network.channel <= 14) {
            final existing = networksBySsid[network.ssid];
            if (existing == null || network.rssi > existing.rssi) {
              networksBySsid[network.ssid] = network;
            }
          }
        } else if (message == 'wifi_scan_complete' && !completer.isCompleted) {
          final networks = networksBySsid.values.toList()
            ..sort((a, b) => b.rssi.compareTo(a.rssi));
          completer.complete(networks);
        } else if (message == 'wifi_scan_failed' && !completer.isCompleted) {
          completer.completeError(
            Exception('Wi-Fi scan failed: ${data['reason'] ?? 'unknown'}'),
          );
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );

    try {
      final started = await sendCommand(
        jsonDecode(NyanEyesProtocol.scanWiFi()) as Map<String, dynamic>,
        timeoutSec: 8,
      );
      if (started['message'] != 'wifi_scan_started') {
        throw Exception(
          'Device rejected Wi-Fi scan: ${started['message'] ?? started['status']}',
        );
      }
      scanId = (started['scan_id'] as num?)?.toInt() ?? scanId;
      return await completer.future.timeout(Duration(seconds: timeoutSec));
    } finally {
      await subscription.cancel();
    }
  }

  /// Closes the connection and cancels active subscriptions.
  void close() {
    _subscription?.cancel();
    _subscription = null;
    _receiveBuffer = '';
    _socket?.destroy();
    _socket = null;
    _isAuthenticated = false;
    if (_responseCompleter != null && !_responseCompleter!.isCompleted) {
      _responseCompleter!.completeError(Exception('TCP Socket closed'));
    }
    _responseCompleter = null;
  }
}
