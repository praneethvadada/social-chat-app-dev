class UserProfile {
  final int userId;
  final String fullName;
  final String? profilePictureUrl;
  final bool isPrivate;
  final bool isVerified;
  final bool showReadReceipts;
  final bool showActivityStatus;

  UserProfile({
    required this.userId,
    required this.fullName,
    this.profilePictureUrl,
    this.isPrivate = false,
    this.isVerified = false,
    this.showReadReceipts = true,
    this.showActivityStatus = true,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      userId: json['userId'] as int? ?? 0,
      fullName: json['fullName'] as String? ?? 'Unknown',
      profilePictureUrl: json['profilePictureUrl'] as String?,
      isPrivate: json['isPrivate'] as bool? ?? false,
      isVerified: json['isVerified'] as bool? ?? false,
      showReadReceipts: json['showReadReceipts'] as bool? ?? true,
      showActivityStatus: json['showActivityStatus'] as bool? ?? true,
    );
  }
}
