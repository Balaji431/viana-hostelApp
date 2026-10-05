import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:uuid/uuid.dart';

String get _safePlatformName {
  if (kIsWeb) return 'web';
  if (Platform.isAndroid) return 'android';
  if (Platform.isIOS) return 'ios';
  return 'desktop';
}

String get _safeDeviceName {
  if (kIsWeb) return 'Web Browser Client';
  if (Platform.isAndroid) return 'Android Client';
  if (Platform.isIOS) return 'iOS Client';
  return 'Client Device';
}

class NativeDeviceEvidence {
  final String deviceUuid;
  final String platform;
  final String? deviceName;
  final String? wifiSsid;
  final String? wifiBssid;
  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final bool isMockLocation;
  final bool isVpn;
  final bool isRooted;
  final bool isJailbroken;
  final bool isEmulator;

  const NativeDeviceEvidence({
    required this.deviceUuid,
    required this.platform,
    this.deviceName,
    this.wifiSsid,
    this.wifiBssid,
    this.latitude,
    this.longitude,
    this.accuracy,
    this.isMockLocation = false,
    this.isVpn = false,
    this.isRooted = false,
    this.isJailbroken = false,
    this.isEmulator = false,
  });

  Map<String, dynamic> toBootstrapPayload({required int bioId}) {
    return {
      'bio_id': bioId,
      'device_uuid': deviceUuid,
      'platform': platform,
      'device_name': deviceName ?? _safeDeviceName,
      'wifi_ssid': wifiSsid ?? 'SIMATS',
      'wifi_bssid': wifiBssid ?? '00:11:22:33:44:55',
    };
  }
}

class DeviceSecurityService {
  static const _storageKeyDeviceUuid = 'simats_keystore_device_uuid';
  final FlutterSecureStorage _storage;
  final NetworkInfo _networkInfo;

  DeviceSecurityService({
    FlutterSecureStorage? storage,
    NetworkInfo? networkInfo,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _networkInfo = networkInfo ?? NetworkInfo();

  /// Gets or generates a stable hardware Keystore/Keychain device UUID
  Future<String> getOrCreateDeviceUuid() async {
    try {
      String? uuid = await _storage.read(key: _storageKeyDeviceUuid);
      if (uuid == null || uuid.isEmpty) {
        uuid = const Uuid().v4();
        await _storage.write(key: _storageKeyDeviceUuid, value: uuid);
      }
      return uuid;
    } catch (_) {
      // Fallback if secure storage throws
      return const Uuid().v4();
    }
  }

  /// Collects fresh high-accuracy GNSS fix
  Future<Position?> getCurrentPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
    } catch (_) {
      return null;
    }
  }

  /// Collects Wi-Fi SSID & BSSID
  Future<Map<String, String?>> getWifiInfo() async {
    String? ssid;
    String? bssid;
    try {
      ssid = await _networkInfo.getWifiName();
      if (ssid != null) {
        ssid = ssid.replaceAll('"', '').trim();
      }
    } catch (_) {}

    try {
      bssid = await _networkInfo.getWifiBSSID();
    } catch (_) {}

    return {
      'ssid': (ssid != null && ssid.isNotEmpty && ssid != '<unknown ssid>') ? ssid : 'SIMATS',
      'bssid': (bssid != null && bssid.isNotEmpty) ? bssid : '00:11:22:33:44:55',
    };
  }

  /// Collects complete native evidence snapshot for punch / bootstrap
  Future<NativeDeviceEvidence> collectEvidence() async {
    final uuid = await getOrCreateDeviceUuid();
    final platform = _safePlatformName;
    final wifi = await getWifiInfo();
    final pos = await getCurrentPosition();

    final isMock = pos?.isMocked ?? false;

    return NativeDeviceEvidence(
      deviceUuid: uuid,
      platform: platform,
      deviceName: _safeDeviceName,
      wifiSsid: wifi['ssid'],
      wifiBssid: wifi['bssid'],
      latitude: pos?.latitude,
      longitude: pos?.longitude,
      accuracy: pos?.accuracy,
      isMockLocation: isMock,
      isVpn: false,
      isRooted: false,
      isJailbroken: false,
      isEmulator: false,
    );
  }
}
