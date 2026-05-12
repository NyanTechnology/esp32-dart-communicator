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

  /// Creates a new [DeviceDiscoveryService].
  /// 
  /// An optional [httpClient] can be provided for fetching device info after discovery.
  DeviceDiscoveryService({DeviceHttpClient? httpClient})
      : _httpClient = httpClient ?? DeviceHttpClient();

  /// Scans the local network for ESP32 devices.
  /// 
  /// Returns a list of [DeviceInfo] for all discovered and verified devices.
  /// [timeout] defines how long to wait for discovery responses.
  Future<List<DeviceInfo>> discoverEsp32DevicesOnLan({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final discoveredUrls = <String>{};

    Future<void> runMDNS() async {
      try {
        final discovery = await nsd.startDiscovery('_http._tcp');
        await Future.delayed(timeout);
        for (final service in discovery.services) {
          if (service.name != null && service.name!.toLowerCase().contains('nyaneye')) {
            try {
              final resolvedService = await nsd.resolve(service);
              final host = resolvedService.host;
              final port = resolvedService.port;
              if (host != null) {
                final displayHost = host.contains(':') ? '[$host]' : host;
                discoveredUrls.add('http://$displayHost:$port');
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
        final data = utf8.encode('DISCOVER_ESP32_REQ');

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
                  if (ip != null) {
                    discoveredUrls.add('http://$ip:$port');
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
      final info = await _httpClient.fetchDeviceInfo(baseUrl, timeout: timeout);
      if (info != null) {
        discoveredDevices.add(info);
      }
    }
    return discoveredDevices;
  }
}
