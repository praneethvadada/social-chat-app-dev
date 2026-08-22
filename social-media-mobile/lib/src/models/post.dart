import 'selected_media.dart';
import '../utils/post_timestamp_utils.dart';

import 'user_profile.dart';

enum PostVisibility {
  PUBLIC,
  CLOSE_FRIENDS,
}

enum PostType { TEXT, POLL, EVENT }

class PollOptionData {
  final int id;
  final String text;
  final int voteCount;
  /// Only ever true once the viewer has voted — the server never leaks the
  /// correct answer to a poll the viewer hasn't answered yet.
  final bool isCorrect;

  const PollOptionData({
    required this.id,
    required this.text,
    required this.voteCount,
    this.isCorrect = false,
  });

  factory PollOptionData.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final votes = json['voteCount'];
    return PollOptionData(
      id: id is int ? id : int.tryParse(id?.toString() ?? '') ?? 0,
      text: json['text']?.toString() ?? '',
      voteCount: votes is int ? votes : int.tryParse(votes?.toString() ?? '') ?? 0,
      isCorrect: json['isCorrect'] == true,
    );
  }
}

class Post {
  final int id;
  final int userId;
  final String authorName;
  final String? profilePicUrl;
  final DateTime timestamp;
  final String content;
  final List<String> imageUrls;
  final List<SelectedMedia> media;
  final int likes;
  final int comments;
  final int shares;
  final int saves;
  final bool isLiked;
  final bool isSaved;
  final PostVisibility visibility;
  final List<UserProfile> sampleLikers;

  final PostType postType;
  // POLL only
  final List<PollOptionData> pollOptions;
  final int? myPollVoteOptionId;
  // EVENT only
  final DateTime? eventStartTime;
  final String? eventLocation;
  final Map<String, int> eventRsvpCounts;
  final String? myRsvpStatus;

  const Post({
    required this.id,
    required this.userId,
    required this.authorName,
    this.profilePicUrl,
    required this.timestamp,
    required this.content,
    this.imageUrls = const [],
    this.media = const [],
    this.likes = 0,
    this.comments = 0,
    this.shares = 0,
    this.saves = 0,
    this.isLiked = false,
    this.isSaved = false,
    this.visibility = PostVisibility.PUBLIC,
    this.sampleLikers = const [],
    this.postType = PostType.TEXT,
    this.pollOptions = const [],
    this.myPollVoteOptionId,
    this.eventStartTime,
    this.eventLocation,
    this.eventRsvpCounts = const {},
    this.myRsvpStatus,
  });

  String get initials {
    final parts = authorName.split(' ');
    if (parts.isEmpty || parts.first.isEmpty) return 'U';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  String get timeAgo {
    // Use the new post timestamp utility for consistent IST formatting
    return formatPostTimestamp(timestamp);
  }

  factory Post.fromJson(Map<String, dynamic> json) {
    // ✅ FIX: Use createdAt ONLY for post timestamp (when it was created)
    // Do NOT use updatedAt - that changes when people like/edit, not when post was created
    final createdAt = json['createdAt']?.toString();
    final timestampStr = createdAt;
    final imageUrls = (json['imageUrls'] as List?)
            ?.whereType<String>()
            .toList() ??
        const <String>[];
    final likes = json['likesCount'];
    final comments = json['commentsCount'];
    final shares = json['sharesCount'];
    final saves = json['savesCount'];
    final userIdRaw = json['userId'];
    // Use authorName from backend (which is fullName or username)
    final authorName = json['authorName']?.toString();
    final profilePic = json['authorProfilePictureUrl']?.toString();
    final sampleLikersJson = json['sampleLikers'] as List?;
    final sampleLikers = sampleLikersJson != null
        ? sampleLikersJson.map((e) => UserProfile.fromJson(e as Map<String, dynamic>)).toList()
        : <UserProfile>[];
    
    // Parse visibility (Close Friends feature)
    final visibilityStr = json['visibility']?.toString() ?? 'PUBLIC';
    final visibility = visibilityStr == 'CLOSE_FRIENDS'
        ? PostVisibility.CLOSE_FRIENDS
        : PostVisibility.PUBLIC;

    final postTypeStr = json['postType']?.toString() ?? 'TEXT';
    final postType = postTypeStr == 'POLL'
        ? PostType.POLL
        : postTypeStr == 'EVENT'
            ? PostType.EVENT
            : PostType.TEXT;
    final pollOptionsJson = json['pollOptions'] as List?;
    final pollOptions = pollOptionsJson != null
        ? pollOptionsJson.map((e) => PollOptionData.fromJson(e as Map<String, dynamic>)).toList()
        : <PollOptionData>[];
    final myVoteRaw = json['myPollVoteOptionId'];
    final myPollVoteOptionId = myVoteRaw is int ? myVoteRaw : int.tryParse(myVoteRaw?.toString() ?? '');
    final eventStartTimeStr = json['eventStartTime']?.toString();
    final eventRsvpCountsJson = json['eventRsvpCounts'] as Map?;
    final eventRsvpCounts = eventRsvpCountsJson != null
        ? eventRsvpCountsJson.map((k, v) => MapEntry(k.toString(), v is int ? v : int.tryParse(v.toString()) ?? 0))
        : <String, int>{};

    return Post(
      id: (json['id'] is int) ? json['id'] as int : int.tryParse(json['id']?.toString() ?? '') ?? 0,
      userId: userIdRaw is int ? userIdRaw : int.tryParse(userIdRaw?.toString() ?? '') ?? 0,
      authorName: authorName != null && authorName.isNotEmpty
          ? authorName
          : 'User${json['userId'] ?? ''}',
      profilePicUrl: profilePic,
      timestamp: timestampStr != null 
          ? _parseUtcTimestamp(timestampStr)
          : DateTime.now().toUtc(),
      content: (json['content'] ?? '').toString(),
      imageUrls: imageUrls,
      likes: likes is int ? likes : int.tryParse(likes?.toString() ?? '') ?? 0,
      comments: comments is int ? comments : int.tryParse(comments?.toString() ?? '') ?? 0,
      shares: shares is int ? shares : int.tryParse(shares?.toString() ?? '') ?? 0,
      saves: saves is int ? saves : int.tryParse(saves?.toString() ?? '') ?? 0,
      isLiked: json['isLikedByCurrentUser'] == true,
      isSaved: json['isSavedByCurrentUser'] == true,
      visibility: visibility,
      media: const [],
      sampleLikers: sampleLikers,
      postType: postType,
      pollOptions: pollOptions,
      myPollVoteOptionId: myPollVoteOptionId,
      eventStartTime: eventStartTimeStr != null ? _parseUtcTimestamp(eventStartTimeStr) : null,
      eventLocation: json['eventLocation']?.toString(),
      eventRsvpCounts: eventRsvpCounts,
      myRsvpStatus: json['myRsvpStatus']?.toString(),
    );
  }

  /// Parse timestamp from backend (UTC) and convert to local time
  /// Backend sends UTC timestamps without 'Z' suffix
  static DateTime _parseUtcTimestamp(String timestamp) {
    try {
      // If timestamp has timezone info (Z or +/-), parse and convert to local
      if (timestamp.endsWith('Z') || timestamp.contains('+') || 
          (timestamp.contains('T') && timestamp.split('T').last.contains('-') && timestamp.split('T').last.length > 8)) {
        return DateTime.parse(timestamp).toLocal();
      }
      // Backend sends UTC without 'Z', add it and convert to local
      return DateTime.parse('${timestamp}Z').toLocal();
    } catch (e) {
      print('Error parsing timestamp: $timestamp, error: $e');
      return DateTime.now();
    }
  }

  /// Create a copy of this post with updated fields
  Post copyWith({
    int? id,
    int? userId,
    String? authorName,
    String? profilePicUrl,
    DateTime? timestamp,
    String? content,
    List<String>? imageUrls,
    List<SelectedMedia>? media,
    int? likes,
    int? comments,
    int? shares,
    int? saves,
    bool? isLiked,
    bool? isSaved,
    PostVisibility? visibility,
    List<UserProfile>? sampleLikers,
    PostType? postType,
    List<PollOptionData>? pollOptions,
    int? myPollVoteOptionId,
    DateTime? eventStartTime,
    String? eventLocation,
    Map<String, int>? eventRsvpCounts,
    String? myRsvpStatus,
  }) {
    return Post(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      authorName: authorName ?? this.authorName,
      profilePicUrl: profilePicUrl ?? this.profilePicUrl,
      timestamp: timestamp ?? this.timestamp,
      content: content ?? this.content,
      imageUrls: imageUrls ?? this.imageUrls,
      media: media ?? this.media,
      likes: likes ?? this.likes,
      comments: comments ?? this.comments,
      shares: shares ?? this.shares,
      saves: saves ?? this.saves,
      isLiked: isLiked ?? this.isLiked,
      isSaved: isSaved ?? this.isSaved,
      visibility: visibility ?? this.visibility,
      sampleLikers: sampleLikers ?? this.sampleLikers,
      postType: postType ?? this.postType,
      pollOptions: pollOptions ?? this.pollOptions,
      myPollVoteOptionId: myPollVoteOptionId ?? this.myPollVoteOptionId,
      eventStartTime: eventStartTime ?? this.eventStartTime,
      eventLocation: eventLocation ?? this.eventLocation,
      eventRsvpCounts: eventRsvpCounts ?? this.eventRsvpCounts,
      myRsvpStatus: myRsvpStatus ?? this.myRsvpStatus,
    );
  }
}

final mockPosts = <Post>[
  Post(
    id: 1,
    userId: 1,
    authorName: 'John Doe',
    timestamp: DateTime.now().subtract(const Duration(hours: 2)),
    content: 'Just had an amazing day at the beach! The sunset was incredible 🌅',
    likes: 124,
    comments: 12,
  ),
  Post(
    id: 2,
    userId: 2,
    authorName: 'Sarah Wilson',
    timestamp: DateTime.now().subtract(const Duration(hours: 4)),
    content: 'Coffee and code - perfect combination for a productive morning! ☕️',
    likes: 98,
    comments: 8,
  ),
  Post(
    id: 3,
    userId: 3,
    authorName: 'Alex Green',
    timestamp: DateTime.now().subtract(const Duration(days: 1)),
    content: 'Hiked a new trail today — the views were worth every step.',
    likes: 76,
    comments: 5,
  ),
];