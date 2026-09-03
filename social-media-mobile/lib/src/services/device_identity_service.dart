import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Phase 1 of the device/session architecture plan: a stable per-install
/// identifier plus best-effort platform/OS/app-version metadata, sent on
/// every login/register call so the backend can register a Device row and
/// a revocable UserSession. Generated once and persisted in
/// SharedPreferences (not sensitive — unlike the access token, it doesn't
/// need Keychain/Keystore-grade protection, it's just an install label).
class DeviceIdentityService {
  static const String _deviceIdKey = 'device_identity_id';

  static Future<String> _getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString(_deviceIdKey);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString(_deviceIdKey, id);
    }
    return id;
  }

  /// Shape matches the backend's DeviceInfoRequest DTO exactly — send this
  /// as the `deviceInfo` field on login/register request bodies.
  static Future<Map<String, dynamic>> getDeviceInfoPayload() async {
    final deviceId = await _getOrCreateDeviceId();
    final plugin = DeviceInfoPlugin();

    String? platform;
    String? osName;
    String? osVersion;
    String? deviceModel;
    String? browserName;
    String? browserVersion;

    try {
      if (kIsWeb) {
        platform = 'WEB';
        final info = await plugin.webBrowserInfo;
        browserName = info.browserName.name;
        browserVersion = info.appVersion;
        osName = info.platform;
      } else if (Platform.isAndroid) {
        platform = 'ANDROID';
        final info = await plugin.androidInfo;
        osName = 'Android';
        osVersion = info.version.release;
        deviceModel = '${info.manufacturer} ${info.model}';
      } else if (Platform.isIOS) {
        platform = 'IOS';
        final info = await plugin.iosInfo;
        osName = 'iOS';
        osVersion = info.systemVersion;
        deviceModel = info.utsname.machine;
      }
    } catch (_) {
      // Best-effort metadata — a plugin failure must never block login/register.
    }

    String? appVersion;
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      appVersion = packageInfo.version;
    } catch (_) {
      // Same — best-effort only.
    }

    return {
      'deviceId': deviceId,
      if (platform != null) 'platform': platform,
      if (osName != null) 'osName': osName,
      if (osVersion != null) 'osVersion': osVersion,
      if (appVersion != null) 'appVersion': appVersion,
      if (browserName != null) 'browserName': browserName,
      if (browserVersion != null) 'browserVersion': browserVersion,
      if (deviceModel != null) 'deviceModel': deviceModel,
    };
  }
}
