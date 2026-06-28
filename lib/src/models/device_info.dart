class DeviceInfo {
  DeviceInfo({
    required this.firmware,
    required this.mode,
    required this.apSsid,
    required this.apIp,
    required this.apClients,
    required this.staConnected,
    required this.isManager,
    this.staSsid,
    this.staIp,
    this.mdnsHost,
    this.mdnsUrl,
    this.managerHost,
    this.managerUrl,
    this.batteryLevel,
    this.powerSavingMode,
    this.mac,
  });

  final String firmware;
  final String mode;
  final String apSsid;
  final String apIp;
  final int apClients;
  final String? staSsid;
  final bool staConnected;
  final String? staIp;
  final String? mdnsHost;
  final String? mdnsUrl;
  final String? managerHost;
  final String? managerUrl;
  final bool isManager;
  final int? batteryLevel;
  final bool? powerSavingMode;
  final String? mac;

  DeviceInfo copyWith({
    String? firmware,
    String? mode,
    String? apSsid,
    String? apIp,
    int? apClients,
    String? staSsid,
    bool? staConnected,
    String? staIp,
    String? mdnsHost,
    String? mdnsUrl,
    String? managerHost,
    String? managerUrl,
    bool? isManager,
    int? batteryLevel,
    bool? powerSavingMode,
    String? mac,
  }) {
    return DeviceInfo(
      firmware: firmware ?? this.firmware,
      mode: mode ?? this.mode,
      apSsid: apSsid ?? this.apSsid,
      apIp: apIp ?? this.apIp,
      apClients: apClients ?? this.apClients,
      staSsid: staSsid ?? this.staSsid,
      staConnected: staConnected ?? this.staConnected,
      staIp: staIp ?? this.staIp,
      mdnsHost: mdnsHost ?? this.mdnsHost,
      mdnsUrl: mdnsUrl ?? this.mdnsUrl,
      managerHost: managerHost ?? this.managerHost,
      managerUrl: managerUrl ?? this.managerUrl,
      isManager: isManager ?? this.isManager,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      powerSavingMode: powerSavingMode ?? this.powerSavingMode,
      mac: mac ?? this.mac,
    );
  }

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value) {
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    return DeviceInfo(
      firmware: (json['firmware'] ?? json['fw_version']) as String? ?? '',
      mode: json['mode'] as String? ?? '',
      apSsid: (json['apSsid'] ?? json['ap_ssid']) as String? ?? '',
      apIp: (json['apIp'] ?? json['ap_ip']) as String? ?? '',
      apClients: parseInt(json['apClients'] ?? json['ap_clients']),
      staSsid: (json['staSsid'] ?? json['sta_ssid']) as String?,
      staConnected: (json['staConnected'] ?? json['sta_connected']) == true,
      staIp: (json['staIp'] ?? json['sta_ip']) as String?,
      mdnsHost: (json['mdnsHost'] ?? json['mdns_host']) as String?,
      mdnsUrl: (json['mdnsUrl'] ?? json['mdns_url']) as String?,
      managerHost: (json['managerHost'] ?? json['manager_host']) as String?,
      managerUrl: (json['managerUrl'] ?? json['manager_url']) as String?,
      isManager: (json['isManager'] ?? json['is_manager']) == true,
      batteryLevel: json['battery_level'] != null ? parseInt(json['battery_level']) : null,
      powerSavingMode: json['power_saving_mode'] as bool?,
      mac: (json['mac'] ?? json['mac_address']) as String?,
    );
  }
}
