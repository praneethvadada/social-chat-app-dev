import '../utils/timestamp_parser.dart';

class Comment {
  final int id;
  final int postId;
  final int userId;
  final String authorName;
  final String? authorProfilePictureUrl;
  final String content;
  final DateTime createdAt;
  final int likes;
  final bool isLikedByCurrentUser;
  final List<Comment> replies;

  const Comment({
    required this.id,
    required this.postId,
    required this.userId,
    required this.authorName,
    this.authorProfilePictureUrl,
    required this.content,
    required this.createdAt,
    this.likes = 0,
    this.isLikedByCurrentUser = false,
    this.replies = const [],
  });

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    // Guard against timestamps that are (or cached as) slightly in the future -
    // clock skew or old bad data must never render as negative seconds.
    if (diff.isNegative) return 'just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${(diff.inDays / 7).floor()}w';
  }

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: json['id'] is int ? json['id'] as int : int.tryParse(json['id']?.toString() ?? '') ?? 0,
      postId: json['postId'] is int ? json['postId'] as int : int.tryParse(json['postId']?.toString() ?? '') ?? 0,
      userId: json['userId'] is int ? json['userId'] as int : int.tryParse(json['userId']?.toString() ?? '') ?? 0,
      authorName: json['authorName']?.toString() ?? 'User',
      authorProfilePictureUrl: json['authorProfilePictureUrl']?.toString(),
      content: json['content']?.toString() ?? '',
      createdAt: TimestampParser.parseDynamic(json['createdAt']),
      likes: json['likes'] is int ? json['likes'] as int : int.tryParse(json['likes']?.toString() ?? '') ?? 0,
      isLikedByCurrentUser: json['likedByCurrentUser'] == true || json['isLikedByCurrentUser'] == true,
      replies: (json['replies'] as List?)?.map((r) => Comment.fromJson(r as Map<String, dynamic>)).toList() ?? [],
    );
  }
}
