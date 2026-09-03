/// Mirrors the backend's MobileStorageStatusResponse DTO.
class MobileStorageStatus {
  final bool isOwner;
  final MobileStorageOwnerDevice? ownerDevice; // null if nobody has ever claimed it yet

  const MobileStorageStatus({required this.isOwner, this.ownerDevice});

  factory MobileStorageStatus.fromJson(Map<String, dynamic> json) {
    return MobileStorageStatus(
      isOwner: json['owner'] as bool? ?? false,
      ownerDevice: json['ownerDevice'] != null
          ? MobileStorageOwnerDevice.fromJson(json['ownerDevice'] as Map<String, dynamic>)
          : null,
    );
  }
}

class MobileStorageOwnerDevice {
  final int deviceId;
  final String? platform;
  final String? osName;
  final String? deviceModel;

  const MobileStorageOwnerDevice({
    required this.deviceId,
    this.platform,
    this.osName,
    this.deviceModel,
  });

  factory MobileStorageOwnerDevice.fromJson(Map<String, dynamic> json) {
    return MobileStorageOwnerDevice(
      deviceId: json['deviceId'] as int,
      platform: json['platform'] as String?,
      osName: json['osName'] as String?,
      deviceModel: json['deviceModel'] as String?,
    );
  }

  String get displayName {
    if (deviceModel != null && deviceModel!.trim().isNotEmpty) return deviceModel!;
    if (osName != null && osName!.trim().isNotEmpty) return osName!;
    return platform ?? 'another device';
  }
}
