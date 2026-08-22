import '../utils/timestamp_parser.dart';

/// One 24-hour status item (S1).
class StatusItem {
  final int id;
  final String type; // TEXT | IMAGE | VIDEO
  final String? content;
  final String? mediaUrl;
  final String? backgroundColor;
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool seen;
  final int viewCount; // only meaningful on your own statuses
  final bool allowReplies;
  final bool allowReactions;
  /// My own reaction emoji key (null if I haven't reacted).
  final String? myReaction;
  /// emoji -> count. Populated for the owner only.
  final Map<String, int> reactionCounts;
  /// S4: CONTACTS / EXCEPT / ONLY (owner-facing).
  final String privacyType;

  StatusItem({
    required this.id,
    required this.type,
    this.content,
    this.mediaUrl,
    this.backgroundColor,
    required this.createdAt,
    required this.expiresAt,
    required this.seen,
    required this.viewCount,
    this.allowReplies = true,
    this.allowReactions = true,
    this.myReaction,
    this.reactionCounts = const {},
    this.privacyType = 'CONTACTS',
  });

  bool get isText => type == 'TEXT';
  bool get isVideo => type == 'VIDEO';

  factory StatusItem.fromJson(Map<String, dynamic> json) {
    return StatusItem(
      id: json['id'] as int? ?? 0,
      type: json['type']?.toString() ?? 'TEXT',
      content: json['content']?.toString(),
      mediaUrl: json['mediaUrl']?.toString(),
      backgroundColor: json['backgroundColor']?.toString(),
      createdAt: TimestampParser.parseDynamic(json['createdAt']),
      expiresAt: TimestampParser.parseDynamic(json['expiresAt']),
      seen: json['seen'] as bool? ?? false,
      viewCount: json['viewCount'] as int? ?? 0,
      allowReplies: json['allowReplies'] as bool? ?? true,
      allowReactions: json['allowReactions'] as bool? ?? true,
      myReaction: json['myReaction']?.toString(),
      reactionCounts: ((json['reactionCounts'] as Map?) ?? {})
          .map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
      privacyType: json['privacyType']?.toString() ?? 'CONTACTS',
    );
  }

  StatusItem copyWith({bool? seen, String? myReaction, bool clearReaction = false}) => StatusItem(
        id: id,
        type: type,
        content: content,
        mediaUrl: mediaUrl,
        backgroundColor: backgroundColor,
        createdAt: createdAt,
        expiresAt: expiresAt,
        seen: seen ?? this.seen,
        viewCount: viewCount,
        allowReplies: allowReplies,
        allowReactions: allowReactions,
        myReaction: clearReaction ? null : (myReaction ?? this.myReaction),
        reactionCounts: reactionCounts,
        privacyType: privacyType,
      );
}

/// All active statuses of one author, plus ring state for the viewer.
class UserStatusGroup {
  final int userId;
  final String username;
  final String? fullName;
  final String? profilePictureUrl;
  final bool allSeen;
  final DateTime? latestAt;
  final List<StatusItem> statuses;

  UserStatusGroup({
    required this.userId,
    required this.username,
    this.fullName,
    this.profilePictureUrl,
    required this.allSeen,
    this.latestAt,
    required this.statuses,
  });

  String get displayName =>
      (fullName != null && fullName!.isNotEmpty) ? fullName! : username;

  factory UserStatusGroup.fromJson(Map<String, dynamic> json) {
    return UserStatusGroup(
      userId: json['userId'] as int? ?? 0,
      username: json['username']?.toString() ?? 'user',
      fullName: json['fullName']?.toString(),
      profilePictureUrl: json['profilePictureUrl']?.toString(),
      allSeen: json['allSeen'] as bool? ?? false,
      latestAt: json['latestAt'] != null
          ? TimestampParser.parseDynamic(json['latestAt'])
          : null,
      statuses: (json['statuses'] as List? ?? [])
          .map((e) => StatusItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class StatusFeed {
  final UserStatusGroup? myStatus;
  final List<UserStatusGroup> recent;

  StatusFeed({this.myStatus, required this.recent});

  factory StatusFeed.fromJson(Map<String, dynamic> json) {
    return StatusFeed(
      myStatus: json['myStatus'] != null
          ? UserStatusGroup.fromJson(json['myStatus'] as Map<String, dynamic>)
          : null,
      recent: (json['recent'] as List? ?? [])
          .map((e) => UserStatusGroup.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Someone who viewed a status (S2 "Viewed by" sheet).
class StatusViewer {
  final int userId;
  final String username;
  final String? fullName;
  final String? profilePictureUrl;
  final DateTime? viewedAt;
  final String? reaction; // populated in S3

  StatusViewer({
    required this.userId,
    required this.username,
    this.fullName,
    this.profilePictureUrl,
    this.viewedAt,
    this.reaction,
  });

  String get displayName =>
      (fullName != null && fullName!.isNotEmpty) ? fullName! : username;

  factory StatusViewer.fromJson(Map<String, dynamic> json) {
    return StatusViewer(
      userId: json['userId'] as int? ?? 0,
      username: json['username']?.toString() ?? 'user',
      fullName: json['fullName']?.toString(),
      profilePictureUrl: json['profilePictureUrl']?.toString(),
      viewedAt: json['viewedAt'] != null
          ? TimestampParser.parseDynamic(json['viewedAt'])
          : null,
      reaction: json['reaction']?.toString(),
    );
  }
}
