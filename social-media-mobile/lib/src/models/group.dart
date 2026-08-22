import '../utils/timestamp_parser.dart';

/// A GROUP conversation summary (G1), as returned by
/// GET /api/social/conversations/groups.
class GroupSummary {
  final int id;
  final String name;
  final String? description;
  final String? photoUrl;
  final int memberCount;
  final String myRole; // OWNER / ADMIN / MEMBER
  final String? lastMessageContent;
  final String? lastMessageSenderName;
  final DateTime? lastMessageTime;
  final List<int> skippedMemberIds;
  /// G5 per-group settings (spec §R/§U)
  final String whoCanSend;
  final String whoCanEditInfo;
  final String whoCanAddMembers;
  final String whoCanPin;
  final bool approveNewMembers;
  final String myNotificationLevel;
  final int unreadCount;

  GroupSummary({
    required this.id,
    required this.name,
    this.description,
    this.photoUrl,
    required this.memberCount,
    required this.myRole,
    this.lastMessageContent,
    this.lastMessageSenderName,
    this.lastMessageTime,
    this.skippedMemberIds = const [],
    this.whoCanSend = 'EVERYONE',
    this.whoCanEditInfo = 'ADMINS',
    this.whoCanAddMembers = 'ADMINS',
    this.whoCanPin = 'ADMINS',
    this.approveNewMembers = false,
    this.myNotificationLevel = 'ALL',
    this.unreadCount = 0,
  });

  factory GroupSummary.fromJson(Map<String, dynamic> json) {
    return GroupSummary(
      id: json['id'] as int? ?? 0,
      name: json['name']?.toString() ?? 'Group',
      description: json['description']?.toString(),
      photoUrl: json['photoUrl']?.toString(),
      memberCount: json['memberCount'] as int? ?? 0,
      myRole: json['myRole']?.toString() ?? 'MEMBER',
      lastMessageContent: json['lastMessageContent']?.toString(),
      lastMessageSenderName: json['lastMessageSenderName']?.toString(),
      lastMessageTime: json['lastMessageTime'] != null
          ? TimestampParser.parseDynamic(json['lastMessageTime'])
          : null,
      skippedMemberIds: (json['skippedMemberIds'] as List?)
              ?.map((e) => e is int ? e : int.tryParse(e.toString()) ?? 0)
              .toList() ??
          const [],
      whoCanSend: json['whoCanSend']?.toString() ?? 'EVERYONE',
      whoCanEditInfo: json['whoCanEditInfo']?.toString() ?? 'ADMINS',
      whoCanAddMembers: json['whoCanAddMembers']?.toString() ?? 'ADMINS',
      whoCanPin: json['whoCanPin']?.toString() ?? 'ADMINS',
      approveNewMembers: json['approveNewMembers'] as bool? ?? false,
      myNotificationLevel: json['myNotificationLevel']?.toString() ?? 'ALL',
      unreadCount: json['unreadCount'] as int? ?? 0,
    );
  }

  bool get iAmOwner => myRole == 'OWNER';
  bool get iAmAdmin => myRole == 'OWNER' || myRole == 'ADMIN';

  String get lastMessagePreview {
    if (lastMessageContent == null || lastMessageContent!.isEmpty) {
      return 'No messages yet';
    }
    final prefix =
        lastMessageSenderName != null ? '$lastMessageSenderName: ' : '';
    final full = '$prefix$lastMessageContent';
    return full.length > 60 ? '${full.substring(0, 60)}...' : full;
  }
}

/// A group member with profile data and role (G2).
class GroupMember {
  final int userId;
  final String username;
  final String? fullName;
  final String? profilePictureUrl;
  final String role; // OWNER / ADMIN / MEMBER

  GroupMember({
    required this.userId,
    required this.username,
    this.fullName,
    this.profilePictureUrl,
    required this.role,
  });

  bool get isOwner => role == 'OWNER';
  bool get isAdmin => role == 'ADMIN';

  String get displayName =>
      (fullName != null && fullName!.isNotEmpty) ? fullName! : username;

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      userId: json['userId'] as int? ?? 0,
      username: json['username']?.toString() ?? 'user',
      fullName: json['fullName']?.toString(),
      profilePictureUrl: json['profilePictureUrl']?.toString(),
      role: json['role']?.toString() ?? 'MEMBER',
    );
  }
}
