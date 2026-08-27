/// A nearby Wi-Fi access point reported by the NyanEyes device.
class WifiScanNetwork {
  const WifiScanNetwork({
    required this.ssid,
    required this.rssi,
    required this.channel,
    required this.auth,
    required this.requiresPassword,
    required this.supported,
  });

  final String ssid;
  final int rssi;
  final int channel;
  final String auth;
  final bool requiresPassword;
  final bool supported;

  factory WifiScanNetwork.fromJson(Map<String, dynamic> json) {
    return WifiScanNetwork(
      ssid: json['ssid']?.toString() ?? '',
      rssi: (json['rssi'] as num?)?.toInt() ?? -100,
      channel: (json['channel'] as num?)?.toInt() ?? 0,
      auth: json['auth']?.toString() ?? 'UNKNOWN',
      requiresPassword: json.containsKey('password_required')
          ? json['password_required'] != false
          : json['requires_password'] != false,
      supported: json['supported'] != false,
    );
  }

  String get signalLabel {
    if (rssi >= -55) return '信号优秀';
    if (rssi >= -67) return '信号良好';
    if (rssi >= -75) return '信号一般';
    return '信号较弱';
  }
}
