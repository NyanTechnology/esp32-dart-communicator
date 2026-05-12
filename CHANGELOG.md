# Changelog

All notable changes to this project will be documented in this file.

## [0.1.0] - 2026-05-12

### Added
- Initial extraction of ESP32 communication logic from the main project.
- `DeviceDiscoveryService` for mDNS and UDP discovery.
- `DeviceHttpClient` for REST API communication.
- `DeviceBleClient` for BLE-based provisioning and control.
- Core models: `DeviceInfo`, `WifiCredentials`, `ConnectMode`, `ProvisionResult`.
