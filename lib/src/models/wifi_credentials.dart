import 'package:wifi_iot/wifi_iot.dart';
import 'connect_mode.dart';

class WifiCredentials {
  WifiCredentials({
    required this.ssid,
    required this.password,
    required this.type,
    required this.hidden,
    this.nickname,
    this.managerUrl,
    this.mdnsUrl,
    this.lanReachable = false,
    this.lanIp,
    this.connectMode = ConnectMode.home,
    this.imagePath,
    this.makeupImagePath,
    this.isBound = true,
  });

  final String ssid;
  final String password;
  final String? type;
  final bool hidden;
  final String? nickname;
  final String? managerUrl;
  final String? mdnsUrl;
  final bool lanReachable;
  final String? lanIp;
  final ConnectMode connectMode;
  final String? imagePath;
  final String? makeupImagePath;
  final bool isBound;

  Map<String, dynamic> toJson() => {
        'ssid': ssid,
        'password': password,
        'type': type,
        'hidden': hidden,
        'nickname': nickname,
        'managerUrl': managerUrl,
        'mdnsUrl': mdnsUrl,
        'lanReachable': lanReachable,
        'lanIp': lanIp,
        'connectMode': connectMode.name,
        'imagePath': imagePath,
        'makeupImagePath': makeupImagePath,
        'isBound': isBound,
      };

  factory WifiCredentials.fromJson(Map<String, dynamic> json) {
    ConnectMode parseMode(String? raw) {
      return ConnectMode.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => ConnectMode.home,
      );
    }

    return WifiCredentials(
      ssid: json['ssid'] as String? ?? '',
      password: json['password'] as String? ?? '',
      type: json['type'] as String?,
      hidden: json['hidden'] == true,
      nickname: json['nickname'] as String?,
      managerUrl: json['managerUrl'] as String?,
      mdnsUrl: json['mdnsUrl'] as String?,
      lanReachable: json['lanReachable'] as bool? ?? false,
      lanIp: json['lanIp'] as String?,
      connectMode: parseMode(json['connectMode'] as String?),
      imagePath: json['imagePath'] as String?,
      makeupImagePath: json['makeupImagePath'] as String?,
      isBound: json['isBound'] as bool? ?? true,
    );
  }

  NetworkSecurity get security {
    switch (type?.toUpperCase()) {
      case 'WPA':
      case 'WPA2':
      case 'WPA/WPA2':
        return NetworkSecurity.WPA;
      case 'WEP':
        return NetworkSecurity.WEP;
      case 'NOPASS':
        return NetworkSecurity.NONE;
      default:
        return NetworkSecurity.WPA;
    }
  }

  static WifiCredentials? tryParse(String raw) {
    if (!raw.startsWith('WIFI:')) return null;
    final content = raw.substring(5);
    final parts = content.split(';');

    String? ssid;
    String? password;
    String? type;
    bool hidden = false;

    for (final part in parts) {
      final idx = part.indexOf(':');
      if (idx <= 0) continue;
      final key = part.substring(0, idx);
      final value = part.substring(idx + 1);
      switch (key) {
        case 'S':
          ssid = value;
          break;
        case 'P':
          password = value;
          break;
        case 'T':
          type = value;
          break;
        case 'H':
          hidden = value.toLowerCase() == 'true';
          break;
      }
    }

    if (ssid == null || password == null) return null;
    return WifiCredentials(
      ssid: ssid,
      password: password,
      type: type,
      hidden: hidden,
    );
  }
}
