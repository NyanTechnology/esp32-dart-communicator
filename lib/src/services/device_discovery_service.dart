import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart' as nsd;
import '../models/device_info.dart';
import 'device_http_client.dart';

/// Service for discovering ESP32 devices on the local area network.
/// 
/// Utilizes both mDNS and UDP broadcast for robust discovery.
class DeviceDiscoveryService {
  final DeviceHttpClient _httpClient;
  final String mDnsServiceName;
  final String mDnsSearchString;
  final String udpRequestString;

  /// Creates a new [DeviceDiscoveryService].
  /// 
  /// [mDnsServiceName] is the service type to search for (default: _http._tcp).
  /// [mDnsSearchString] is a substring to match in the discovered service name.
  /// [udpRequestString] is the payload for UDP broadcast discovery.
  DeviceDiscoveryService({
    DeviceHttpClient? httpClient,
    this.mDnsServiceName = '_http._tcp',
    this.mDnsSearchString = 'nyaneye',
    this.udpRequestString = 'DISCOVER_ESP32_REQ',
  }) : _httpClient = httpClient ?? DeviceHttpClient();

  /// Scans the local network for ESP32 devices.
  Future<List<DeviceInfo>> discoverEsp32DevicesOnLan({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final discoveredUrls = <String>{};
    final discoveredMacs = <String, String>{};

    Future<void> runMDNS() async {
      try {
        final discovery = await nsd.startDiscovery(mDnsServiceName);
        await Future.delayed(timeout);
        for (final service in discovery.services) {
          if (service.name != null && service.name!.toLowerCase().contains(mDnsSearchString.toLowerCase())) {
            try {
              final resolvedService = await nsd.resolve(service);
              final host = resolvedService.host;
              final port = resolvedService.port;
              if (host != null) {
                final displayHost = host.contains(':') ? '[$host]' : host;
                final baseUrl = 'http://$displayHost:$port';
                discoveredUrls.add(baseUrl);

                final txtRecords = resolvedService.txt;
                if (txtRecords != null) {
                  final macBytes = txtRecords['mac'];
                  if (macBytes != null) {
                    try {
                      discoveredMacs[baseUrl] = utf8.decode(macBytes);
                    } catch (_) {}
                  }
                }
              }
            } catch (_) {
              if (kDebugMode) { debugPrint('mDNS resolve failed'); }
            }
          }
        }
        await nsd.stopDiscovery(discovery);
      } catch (e) {
        if (kDebugMode) { debugPrint('mDNS Discovery error: $e'); }
      }
    }

    Future<void> runUDP() async {
      try {
        final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        socket.broadcastEnabled = true;
        final data = utf8.encode(udpRequestString);

        final targets = <InternetAddress>{};
        try {
          final interfaces = await NetworkInterface.list(
            type: InternetAddressType.IPv4,
            includeLinkLocal: false,
            includeLoopback: false,
          );
          for (final iface in interfaces) {
            for (final addr in iface.addresses) {
              final parts = addr.address.split('.');
              if (parts.length == 4) {
                final bcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
                targets.add(InternetAddress(bcast));
              }
            }
          }
        } catch (_) {}
        targets.add(InternetAddress('255.255.255.255'));

        final subscription = socket.listen(
          (RawSocketEvent event) {
            if (event == RawSocketEvent.read) {
              final dg = socket.receive();
              if (dg != null) {
                try {
                  final jsonStr = utf8.decode(dg.data);
                  final info = jsonDecode(jsonStr);
                  final ip = info['ip'];
                  final port = info['http_port'] ?? 80;
                  final mac = info['mac'] as String?;
                  if (ip != null) {
                    final baseUrl = 'http://$ip:$port';
                    discoveredUrls.add(baseUrl);
                    if (mac != null) {
                      discoveredMacs[baseUrl] = mac;
                    }
                  }
                } catch (_) {}
              }
            }
          },
          onError: (e, st) {
            if (e is SocketException && e.osError?.errorCode == 65) {
              return;
            }
            if (kDebugMode) { debugPrint('UDP socket error: $e'); }
          },
          cancelOnError: false,
        );

        for (final target in targets) {
          try {
            socket.send(data, target, 8888);
          } catch (e) {
            if (e is SocketException && e.osError?.errorCode == 65) {
              continue;
            }
            if (kDebugMode) { debugPrint('UDP send to ${target.address} failed: $e'); }
          }
        }

        await Future.delayed(timeout);
        await subscription.cancel();
        socket.close();
      } catch (e) {
        if (kDebugMode) { debugPrint('UDP Discovery error: $e'); }
      }
    }

    await Future.wait([runMDNS(), runUDP()]).timeout(
      timeout + const Duration(seconds: 1),
      onTimeout: () {
        if (kDebugMode) { debugPrint('Discovery timeout'); }
        return <void>[];
      },
    );

    final discoveredDevices = <DeviceInfo>[];
    for (final baseUrl in discoveredUrls) {
      var info = await _httpClient.fetchDeviceInfo(baseUrl, timeout: timeout);
      if (info != null) {
        final mac = discoveredMacs[baseUrl];
        if (mac != null && (info.mac == null || info.mac!.isEmpty)) {
          info = info.copyWith(mac: mac);
        }
        discoveredDevices.add(info);
      } else {
        // Fallback: If HTTP check fails/times out, construct a skeleton DeviceInfo
        // from resolved mDNS or received UDP broadcast to ensure the device's dynamic IP is still updated.
        final mac = discoveredMacs[baseUrl];
        if (mac != null) {
          final uri = Uri.parse(baseUrl);
          final ip = uri.host;
          discoveredDevices.add(DeviceInfo(
            firmware: 'Unknown',
            mode: 'STA',
            apSsid: '',
            apIp: '',
            apClients: 0,
            staConnected: true,
            isManager: false,
            staIp: ip,
            mac: mac,
            mdnsHost: uri.host.endsWith('.local') ? uri.host : null,
            mdnsUrl: baseUrl,
          ));
        }
      }
    }
    return discoveredDevices;
  }
}
