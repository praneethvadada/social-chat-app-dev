/// Mirrors the backend's DeviceResponse DTO (GET /devices). Note the JSON
/// key is "currentDevice", not "isCurrentDevice" — Jackson strips the "is"
/// prefix off boolean getters when serializing.
class DeviceSession {
  final int deviceId;
  final String? platform;
  final String? osName;
  final String? osVersion;
  final String? appVersion;
  final String? browserName;
  final String? browserVersion;
  final String? deviceModel;
  final String? sessionStatus;
  final DateTime? loginTime;
  final DateTime? lastActiveAt;
  final bool isCurrentDevice;

  const DeviceSession({
    required this.deviceId,
    this.platform,
    this.osName,
    this.osVersion,
    this.appVersion,
    this.browserName,
    this.browserVersion,
    this.deviceModel,
    this.sessionStatus,
    this.loginTime,
    this.lastActiveAt,
    this.isCurrentDevice = false,
  });

  factory DeviceSession.fromJson(Map<String, dynamic> json) {
    return DeviceSession(
      deviceId: json['deviceId'] as int,
      platform: json['platform'] as String?,
      osName: json['osName'] as String?,
      osVersion: json['osVersion'] as String?,
      appVersion: json['appVersion'] as String?,
      browserName: json['browserName'] as String?,
      browserVersion: json['browserVersion'] as String?,
      deviceModel: json['deviceModel'] as String?,
      sessionStatus: json['sessionStatus'] as String?,
      loginTime: json['loginTime'] != null ? DateTime.tryParse(json['loginTime'] as String) : null,
      lastActiveAt: json['lastActiveAt'] != null ? DateTime.tryParse(json['lastActiveAt'] as String) : null,
      isCurrentDevice: json['currentDevice'] as bool? ?? false,
    );
  }

  bool get isActive => sessionStatus == 'ACTIVE';

  String get displayName {
    if (deviceModel != null && deviceModel!.trim().isNotEmpty) return deviceModel!;
    if (platform == 'WEB' && browserName != null) return browserName!;
    if (osName != null) return osName!;
    return platform ?? 'Unknown device';
  }

  String get displaySubtitle {
    final parts = <String>[];
    if (platform == 'WEB') {
      if (browserName != null) parts.add(browserName!);
      if (osName != null) parts.add(osName!);
    } else {
      if (osName != null && osVersion != null) {
        parts.add('$osName $osVersion');
      } else if (osName != null) {
        parts.add(osName!);
      }
    }
    return parts.join(' · ');
  }
}
