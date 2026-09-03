import '../utils/time_utils.dart';

/// Mirrors the backend's SecurityEventResponse (GET /security/events).
/// Carries the same raw device fields as DeviceSession, not a pre-formatted
/// label, so [deviceDisplayName] below mirrors DeviceSession.displayName
/// rather than trusting a server-formatted string.
class SecurityEvent {
  final int id;
  final String eventType;
  final DateTime? createdAt;
  final String? ipAddress;
  final Map<String, dynamic>? metadata;
  final String? platform;
  final String? osName;
  final String? browserName;
  final String? deviceModel;

  const SecurityEvent({
    required this.id,
    required this.eventType,
    this.createdAt,
    this.ipAddress,
    this.metadata,
    this.platform,
    this.osName,
    this.browserName,
    this.deviceModel,
  });

  factory SecurityEvent.fromJson(Map<String, dynamic> json) {
    return SecurityEvent(
      id: json['id'] as int,
      eventType: json['eventType'] as String? ?? 'UNKNOWN',
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
      ipAddress: json['ipAddress'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
      platform: json['platform'] as String?,
      osName: json['osName'] as String?,
      browserName: json['browserName'] as String?,
      deviceModel: json['deviceModel'] as String?,
    );
  }

  String? get deviceDisplayName {
    if (deviceModel != null && deviceModel!.trim().isNotEmpty) return deviceModel;
    if (platform == 'WEB' && browserName != null) return browserName;
    if (osName != null) return osName;
    return platform;
  }

  String get timeAgo {
    if (createdAt == null) return '';
    return formatTimeAgo(DateTime.now().difference(createdAt!.toLocal()));
  }

  /// Human-readable label for [eventType] — e.g. "TWO_FA_ENABLED" -> "Two-factor authentication enabled".
  String get label {
    switch (eventType) {
      case 'LOGIN':
        return 'Signed in';
      case 'LOGOUT':
        return 'Signed out';
      case 'NEW_DEVICE':
        return 'New device registered';
      case 'PASSWORD_CHANGED':
        return 'Password changed';
      case 'EMAIL_CHANGED':
        return 'Email added or changed';
      case 'PHONE_CHANGED':
        return 'Phone number added or changed';
      case 'TWO_FA_ENABLED':
        return 'Two-factor authentication turned on';
      case 'TWO_FA_DISABLED':
        return 'Two-factor authentication turned off';
      case 'TWO_FA_METHOD_CHANGED':
        return 'Two-factor authentication method changed';
      case 'SESSION_REVOKED':
        return 'A device was logged out remotely';
      case 'WEB_SESSION_REPLACED':
        return 'Signed in on another browser';
      case 'LOCAL_STORAGE_DEVICE_CHANGED':
        return 'Chat storage device changed';
      case 'ACCOUNT_DELETED':
        return 'Account deleted';
      default:
        return eventType;
    }
  }
}
