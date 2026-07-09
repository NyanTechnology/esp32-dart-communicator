import 'dart:io';
import 'dart:async';
import 'dart:convert';
import '../models/nyan_eyes_protocol.dart';

/// A secure TCP Socket client for communicating with ESP32 NyanEye devices on LAN (port 8080).
/// 
/// Automatically performs challenge-response HMAC-SHA256 zero-trust authentication upon connection.
class DeviceTcpClient {
  final String ip;
  final int port;
  Socket? _socket;
  StreamSubscription? _subscription;
  
  Completer<Map<String, dynamic>>? _responseCompleter;
  bool _isAuthenticated = false;

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
      _socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 5));
      _socket!.write('\n'); // Clear buffer
      await _socket!.flush();

      final responseController = StreamController<String>();
      
      // Accumulate raw data and split on newline delimiters (since commands are JSON lines)
      String buffer = "";
      _subscription = _socket!.cast<List<int>>().transform(utf8.decoder).listen((data) {
        buffer += data;
        while (buffer.contains('\n')) {
          final idx = buffer.indexOf('\n');
          final line = buffer.substring(0, idx).trim();
          buffer = buffer.substring(idx + 1);
          if (line.isNotEmpty) {
            responseController.add(line);
          }
        }
      }, onError: (e) {
        close();
      }, onDone: () {
        close();
      });

      final responseStream = responseController.stream.asBroadcastStream();

      // Helper function to send and await a JSON response on the raw stream
      Future<Map<String, dynamic>> sendRaw(Map<String, dynamic> payload, {int timeoutSec = 5}) async {
        if (_socket == null) throw Exception('Socket disconnected');
        final jsonStr = jsonEncode(payload) + '\n';
        
        final completer = Completer<Map<String, dynamic>>();
        late StreamSubscription sub;
        
        sub = responseStream.listen((line) {
          try {
            final map = jsonDecode(line) as Map<String, dynamic>;
            if (!completer.isCompleted) {
              completer.complete(map);
            }
          } catch (_) {}
        }, onError: (e) {
          if (!completer.isCompleted) completer.completeError(e);
        });

        _socket!.write(jsonStr);
        await _socket!.flush();

        try {
          return await completer.future.timeout(Duration(seconds: timeoutSec));
        } finally {
          await sub.cancel();
        }
      }

      // 2. Step One: Get Challenge (nonce)
      final challengePayload = jsonDecode(NyanEyesProtocol.getChallenge()) as Map<String, dynamic>;
      final challengeRes = await sendRaw(challengePayload).timeout(const Duration(seconds: 4));
      
      if (!challengeRes.containsKey('nonce')) {
        throw Exception('Failed to fetch challenge nonce: ${challengeRes['message'] ?? 'Nonce key not found'}');
      }

      final nonce = challengeRes['nonce'].toString();

      // 3. Step Two: Calculate HMAC-SHA256 Hash
      final hash = NyanEyesProtocol.calculateAuthHash(nonce, localKey);

      // 4. Step Three: Submit Authentication Hash
      final authPayload = jsonDecode(NyanEyesProtocol.auth(hash)) as Map<String, dynamic>;
      final authRes = await sendRaw(authPayload).timeout(const Duration(seconds: 4));

      final isSuccess = authRes['status'] == 'success' || 
                        authRes['status'] == 'authenticated' || 
                        authRes['message'] == 'authenticated';

      if (isSuccess) {
        _isAuthenticated = true;
        
        // Setup persistent listening for subsequent custom commands after authentication
        _subscription?.cancel(); // Cancel setup subscription
        _subscription = responseStream.listen((line) {
          try {
            final map = jsonDecode(line) as Map<String, dynamic>;
            if (_responseCompleter != null && !_responseCompleter!.isCompleted) {
              _responseCompleter!.complete(map);
            }
          } catch (_) {}
        }, onError: (e) {
          close();
        }, onDone: () {
          close();
        });
      } else {
        throw Exception('HMAC challenge authentication failed: ${authRes['message']}');
      }
    } catch (e) {
      close();
      rethrow;
    }
  }

  /// Sends a command over the authenticated TCP socket.
  Future<Map<String, dynamic>> sendCommand(Map<String, dynamic> payload, {int timeoutSec = 5}) async {
    if (_socket == null || !_isAuthenticated) {
      throw Exception('TCP Client is not connected or authenticated');
    }
    
    _responseCompleter = Completer<Map<String, dynamic>>();
    final jsonStr = jsonEncode(payload) + '\n';
    
    _socket!.write(jsonStr);
    await _socket!.flush();

    try {
      return await _responseCompleter!.future.timeout(Duration(seconds: timeoutSec));
    } finally {
      _responseCompleter = null;
    }
  }

  /// Closes the connection and cancels active subscriptions.
  void close() {
    _subscription?.cancel();
    _subscription = null;
    _socket?.destroy();
    _socket = null;
    _isAuthenticated = false;
    if (_responseCompleter != null && !_responseCompleter!.isCompleted) {
      _responseCompleter!.completeError(Exception('TCP Socket closed'));
    }
    _responseCompleter = null;
  }
}
