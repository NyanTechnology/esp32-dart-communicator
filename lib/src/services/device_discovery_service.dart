import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart' as nsd;
import '../models/device_info.dart';

/// Service for discovering ESP32 devices on the local area network.
///
/// Uses mDNS on iOS and combines mDNS with UDP broadcast on other platforms.
class DeviceDiscoveryService {
  final String mDnsServiceName;
  final String mDnsSearchString;
  final String udpRequestString;
  final bool enableUdpDiscovery;

  /// Creates a new [DeviceDiscoveryService].
  ///
  /// [mDnsServiceName] is the service type to search for (default: _nyaneyes._tcp).
  /// [mDnsSearchString] is a substring to match in the discovered service name.
  /// [udpRequestString] is the payload for UDP broadcast discovery.
  /// [enableUdpDiscovery] defaults to false on iOS until the multicast
  /// entitlement is available, and true on other platforms.
  DeviceDiscoveryService({
    this.mDnsServiceName = '_nyaneyes._tcp',
    this.mDnsSearchString = '',
    this.udpRequestString = 'DISCOVER_ESP32_REQ',
    bool? enableUdpDiscovery,
  }) : enableUdpDiscovery =
           enableUdpDiscovery ?? defaultTargetPlatform != TargetPlatform.iOS;

  // Helper method to format debugging output to conform exactly to the main App's framed, emoji-based logger style.
  void _log(String emoji, String tag, String msg, [dynamic error]) {
    if (!kDebugMode) return;
    final now = DateTime.now().toString().substring(0, 23);
    debugPrint(
      '┌───────────────────────────────────────────────────────────────────────────────',
    );
    debugPrint('│ $now');
    debugPrint(
      '├┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄',
    );
    debugPrint('│ $emoji [$tag] $msg');
    if (error != null) {
      debugPrint('│ Error: $error');
    }
    debugPrint(
      '└───────────────────────────────────────────────────────────────────────────────',
    );
  }

  /// Scans the local network for ESP32 devices.
  Future<List<DeviceInfo>> discoverEsp32DevicesOnLan({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final discoveryMode = enableUdpDiscovery ? 'mDNS + UDP' : 'mDNS only';
    _log(
      '🔍',
      'DeviceDiscoveryService',
      'Starting LAN discovery ($discoveryMode) with timeout: ${timeout.inSeconds}s',
    );
    final discoveredUrls = <String>{};
    final discoveredMacs = <String, String>{};
    final discoveredMdnsHosts = <String, String>{};

    Future<void> runMDNS() async {
      nsd.Discovery? discovery;
      try {
        discovery = await nsd.startDiscovery(
          mDnsServiceName,
          autoResolve: true,
          ipLookupType: nsd.IpLookupType.v4,
        );
        await Future.delayed(timeout);
        for (final service in discovery.services) {
          if (service.name != null &&
              service.name!.toLowerCase().contains(
                mDnsSearchString.toLowerCase(),
              )) {
            try {
              var resolvedService = service;
              if (resolvedService.host == null ||
                  resolvedService.port == null) {
                resolvedService = await nsd.resolve(service);
              }

              final mdnsHost = normalizeMdnsHost(resolvedService.host);
              final host = preferredIpv4Address(resolvedService) ?? mdnsHost;
              final port = resolvedService.port;
              if (host != null && port != null) {
                final displayHost = host.contains(':') ? '[$host]' : host;
                final baseUrl = 'http://$displayHost:$port';
                discoveredUrls.add(baseUrl);
                if (mdnsHost != null &&
                    mdnsHost.isNotEmpty &&
                    !isIpv4Address(mdnsHost)) {
                  discoveredMdnsHosts[baseUrl] = mdnsHost;
                }

                final txtRecords = resolvedService.txt;
                if (txtRecords != null) {
                  final macBytes = txtRecords['mac'];
                  if (macBytes != null) {
                    try {
                      final parsedMac = utf8.decode(macBytes);
                      discoveredMacs[baseUrl] = parsedMac;
                      _log(
                        '✅',
                        'DeviceDiscoveryService',
                        'mDNS Hit: $baseUrl (MAC: $parsedMac)',
                      );
                    } catch (_) {}
                  }
                } else {
                  _log(
                    '✅',
                    'DeviceDiscoveryService',
                    'mDNS Hit: $baseUrl (No TXT MAC data)',
                  );
                }
              }
            } catch (e) {
              _log(
                '⚠️',
                'DeviceDiscoveryService',
                'mDNS resolve failed for service: ${service.name}',
                e,
              );
            }
          }
        }
      } catch (e) {
        _log('⛔', 'DeviceDiscoveryService', 'mDNS Discovery critical error', e);
      } finally {
        if (discovery != null) {
          try {
            await nsd.stopDiscovery(discovery);
          } catch (e) {
            _log(
              '⚠️',
              'DeviceDiscoveryService',
              'mDNS discovery cleanup failed',
              e,
            );
          }
        }
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
                String? jsonStr;
                try {
                  jsonStr = utf8.decode(dg.data);
                  final info = jsonDecode(jsonStr);
                  final ip = info['ip'];
                  final port = info['http_port'] ?? info['tcp_port'] ?? 80;
                  final mac = info['mac'] as String?;
                  if (ip != null) {
                    final baseUrl = 'http://$ip:$port';
                    discoveredUrls.add(baseUrl);
                    if (mac != null) {
                      discoveredMacs[baseUrl] = mac;
                      _log(
                        '🚀',
                        'DeviceDiscoveryService',
                        'UDP Hit: $baseUrl (MAC: $mac)',
                      );
                    } else {
                      _log('🚀', 'DeviceDiscoveryService', 'UDP Hit: $baseUrl');
                    }
                  }
                } catch (e) {
                  // 收到了回包但无法按协议解析——打印原文，方便排查固件回包格式不匹配的问题
                  _log(
                    '⚠️',
                    'DeviceDiscoveryService',
                    'UDP reply from ${dg.address.address}:${dg.port} could not be parsed: ${jsonStr ?? dg.data}',
                    e,
                  );
                }
              }
            }
          },
          onError: (e, st) {
            if (e is SocketException && e.osError?.errorCode == 65) {
              return;
            }
            _log('⚠️', 'DeviceDiscoveryService', 'UDP Socket read error', e);
          },
          cancelOnError: false,
        );

        var broadcastBlockedLogged = false;
        for (final target in targets) {
          try {
            socket.send(data, target, 8888);
          } catch (e) {
            if (e is SocketException && e.osError?.errorCode == 65) {
              // errno 65 (EHOSTUNREACH)：iOS 真机缺少 com.apple.developer.networking.multicast
              // entitlement 时广播报文会被系统拦截。只提示一次，发现流程继续依赖 mDNS。
              if (!broadcastBlockedLogged) {
                broadcastBlockedLogged = true;
                _log(
                  '⚠️',
                  'DeviceDiscoveryService',
                  'UDP broadcast blocked by OS (errno 65). On iOS this requires the multicast entitlement; falling back to mDNS only.',
                );
              }
              continue;
            }
            _log(
              '⚠️',
              'DeviceDiscoveryService',
              'UDP send to ${target.address} failed',
              e,
            );
          }
        }

        await Future.delayed(timeout);
        await subscription.cancel();
        socket.close();
      } catch (e) {
        _log('⛔', 'DeviceDiscoveryService', 'UDP Discovery critical error', e);
      }
    }

    try {
      final discoveryTasks = <Future<void>>[runMDNS()];
      if (enableUdpDiscovery) {
        discoveryTasks.add(runUDP());
      }
      await Future.wait(
        discoveryTasks,
      ).timeout(timeout + const Duration(seconds: 1));
    } catch (_) {
      _log(
        '💡',
        'DeviceDiscoveryService',
        'Discovery timeframe completed. Proceeding with ${discoveredUrls.length} found endpoints.',
      );
    }

    final discoveredDevices = <DeviceInfo>[];
    for (final baseUrl in discoveredUrls) {
      final uri = Uri.parse(baseUrl);
      final host = uri.host;
      final ip = isIpv4Address(host) ? host : null;

      // Attempt to get MAC from the mapping, or extract it from host/URL
      var mac = discoveredMacs[baseUrl];
      if (mac == null || mac.isEmpty) {
        mac =
            extractMacFromHostOrName(discoveredMdnsHosts[baseUrl]) ??
            extractMacFromHostOrName(host) ??
            extractMacFromHostOrName(uri.toString());
      }

      // Ensure mdnsHost is formatted canonically: nyaneye-[lowercase_mac].local
      String? mdnsHost;
      if (mac != null) {
        final cleanMac = mac.replaceAll(':', '').toLowerCase();
        mdnsHost = 'nyaneye-$cleanMac.local';
      } else {
        final discoveredHost = discoveredMdnsHosts[baseUrl];
        if (discoveredHost != null && discoveredHost.isNotEmpty) {
          mdnsHost = discoveredHost;
        } else if (host.toLowerCase().endsWith('.local')) {
          mdnsHost = normalizeMdnsHost(host);
        }
      }

      discoveredDevices.add(
        DeviceInfo(
          firmware: 'Unknown',
          mode: 'STA',
          apSsid: '',
          apIp: '',
          apClients: 0,
          staConnected: true,
          isManager: false,
          staIp: ip,
          mac: mac,
          mdnsHost: mdnsHost,
          mdnsUrl: mdnsHost != null ? 'http://$mdnsHost:${uri.port}' : baseUrl,
        ),
      );
    }
    return discoveredDevices;
  }

  /// Returns the first numeric IPv4 address resolved for an mDNS service.
  @visibleForTesting
  String? preferredIpv4Address(nsd.Service service) {
    for (final address in service.addresses ?? const <InternetAddress>[]) {
      if (address.type == InternetAddressType.IPv4) {
        return address.address;
      }
    }
    final host = normalizeMdnsHost(service.host);
    return isIpv4Address(host) ? host : null;
  }

  /// Normalizes Bonjour's fully-qualified trailing dot for URL/cache usage.
  @visibleForTesting
  String? normalizeMdnsHost(String? host) {
    if (host == null || host.isEmpty) return null;
    return host.replaceFirst(RegExp(r'\.+$'), '');
  }

  /// Whether [host] is a numeric IPv4 address rather than an mDNS hostname.
  @visibleForTesting
  bool isIpv4Address(String? host) {
    if (host == null || host.isEmpty) return false;
    final address = InternetAddress.tryParse(host);
    return address != null && address.type == InternetAddressType.IPv4;
  }

  /// Extracts MAC address from a host or service name string.
  /// Matches "nyaneye-" followed by 12 hex characters and formats it as colon-separated uppercase MAC.
  @visibleForTesting
  String? extractMacFromHostOrName(String? input) {
    if (input == null) return null;
    final clean = input.toLowerCase();
    final match = RegExp(r'nyaneye-([0-9a-f]{12})').firstMatch(clean);
    if (match != null) {
      final hex = match.group(1)!;
      final parts = <String>[];
      for (var i = 0; i < 12; i += 2) {
        parts.add(hex.substring(i, i + 2).toUpperCase());
      }
      return parts.join(':');
    }
    return null;
  }
}
