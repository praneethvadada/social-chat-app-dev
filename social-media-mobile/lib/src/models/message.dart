import '../utils/time_utils.dart';

/// Verbose per-message parse logging. Off by default: fromJson runs for every
/// message in every conversation load, and printing several lines per message
/// noticeably stalls the UI. Flip to true only when debugging parsing.
const bool _kVerboseMessageLog = false;

void _mlog(String message) {
  if (_kVerboseMessageLog) print(message);
}

enum MessageStatus {
  sending,    // ⏱ Pending (not yet acknowledged by server)
  sent,       // ✓ Single tick - Server acknowledged receipt
  read,       // ✓✓ Double ticks - Read by recipient (when chat window is open)
  uploading,  // 🔼 Uploading media
  failed      // ❌ Send failed / timed out - needs retry
}

class Message {
  final int id; // server message id (0 when not yet assigned)
  final String? clientMessageId; // client-generated id used to reconcile optimistic messages
  final int senderId;
  final String senderName;
  final String? senderProfilePic;
  final int recipientId;
  final String content;
  final String? mediaUrl;
  final MessageStatus status;
  final DateTime createdAt;
  final bool isRead;
  final DateTime? readAt;

  /// G2: group system events ("X was added"). USER for normal messages.
  final String messageType;
  final String? systemEvent;
  final int? systemActorId;
  final int? systemTargetId;

  /// S3: set when this DM replies to a 24h status (snapshot reference).
  final int? replyToStatusId;
  final String? replyToStatusType;
  final String? replyToStatusPreview;
  /// Non-null when this message is a reaction to the status, not a reply.
  final String? statusReaction;

  /// G4: in-conversation reply snapshot, pin/delete state, reaction summary.
  final int? replyToMessageId;
  final int? replyToSenderId;
  final String? replyToSenderName;
  final String? replyToPreview;
  final bool isPinned;
  final bool isDeleted;
  final Map<String, int> reactionCounts;
  final String? myReaction;

  /// GAP-2/3: media descriptor + forwarded marker.
  final String? mediaType;   // IMAGE | VIDEO | DOCUMENT
  final String? mediaName;   // original filename (documents)
  final bool isForwarded;

  Message({
    required this.id,
    this.clientMessageId,
    required this.senderId,
    required this.senderName,
    this.senderProfilePic,
    required this.recipientId,
    required this.content,
    this.mediaUrl,
    this.status = MessageStatus.sent,
    required this.createdAt,
    required this.isRead,
    this.readAt,
    this.messageType = 'USER',
    this.systemEvent,
    this.systemActorId,
    this.systemTargetId,
    this.replyToStatusId,
    this.replyToStatusType,
    this.replyToStatusPreview,
    this.statusReaction,
    this.replyToMessageId,
    this.replyToSenderId,
    this.replyToSenderName,
    this.replyToPreview,
    this.isPinned = false,
    this.isDeleted = false,
    this.reactionCounts = const {},
    this.myReaction,
    this.mediaType,
    this.mediaName,
    this.isForwarded = false,
  });

  bool get isSystem => messageType == 'SYSTEM';

  /// True when this DM was sent as a reply to someone's status.
  bool get isStatusReply => replyToStatusId != null;

  /// A status reaction is still a status reply, just rendered differently.
  bool get isStatusReaction => statusReaction != null;

  /// True when this message quotes another message in the same conversation.
  bool get isReply => replyToMessageId != null;

  bool get hasMedia => mediaUrl != null && mediaUrl!.isNotEmpty;
  bool get isDocument => mediaType == 'DOCUMENT';
  bool get isVideoMedia => mediaType == 'VIDEO';

  Message copyWith({
    int? id,
    String? clientMessageId,
    int? senderId,
    String? senderName,
    String? senderProfilePic,
    int? recipientId,
    String? content,
    String? mediaUrl,
    MessageStatus? status,
    DateTime? createdAt,
    bool? isRead,
    DateTime? readAt,
  }) {
    return Message(
      id: id ?? this.id,
      clientMessageId: clientMessageId ?? this.clientMessageId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      senderProfilePic: senderProfilePic ?? this.senderProfilePic,
      recipientId: recipientId ?? this.recipientId,
      content: content ?? this.content,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
      readAt: readAt ?? this.readAt,
      messageType: messageType,
      systemEvent: systemEvent,
      systemActorId: systemActorId,
      systemTargetId: systemTargetId,
      replyToStatusId: replyToStatusId,
      replyToStatusType: replyToStatusType,
      replyToStatusPreview: replyToStatusPreview,
      statusReaction: statusReaction,
      replyToMessageId: replyToMessageId,
      replyToSenderId: replyToSenderId,
      replyToSenderName: replyToSenderName,
      replyToPreview: replyToPreview,
      isPinned: isPinned,
      isDeleted: isDeleted,
      reactionCounts: reactionCounts,
      myReaction: myReaction,
      mediaType: mediaType,
      mediaName: mediaName,
      isForwarded: isForwarded,
    );
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    // Debug logging
    _mlog('[MESSAGE] 📨 Parsing message JSON: id=${json['id']}, clientMessageId=${json['clientMessageId']}, senderId=${json['senderId']}');

    // Extract id and clientMessageId early (needed for Message constructor)
    final serverId = json['id'] as int? ?? 0;
    final clientId = (json['messageId'] ?? json['clientMessageId'])?.toString();

    // Determine message status
    MessageStatus status = MessageStatus.sent;
    
    // First, check if backend sends explicit status field (NEW)
    final statusField = json['status'] as String?;
    _mlog('[MESSAGE] 🔍 statusField from JSON: "$statusField" (raw: ${json['status']})');
    if (statusField != null && statusField.isNotEmpty) {
      if (statusField == 'sending') {
        status = MessageStatus.sending;
        _mlog('[MESSAGE] 📤 Status: SENDING (from backend)');
      } else if (statusField == 'failed') {
        status = MessageStatus.failed;
        _mlog('[MESSAGE] ❌ Status: FAILED (from backend)');
      } else if (statusField == 'read') {
        status = MessageStatus.read;
        _mlog('[MESSAGE] 📖 Status: READ (from backend)');
      } else if (statusField == 'uploading') {
        status = MessageStatus.uploading;
        _mlog('[MESSAGE] 🔼 Status: UPLOADING (local)');
      } else {
        status = MessageStatus.sent;
        _mlog('[MESSAGE] ✅ Status: SENT (from backend status=$statusField)');
      }
    } else {
      // Fallback to inference if status field missing
      _mlog('[MESSAGE] ⚠️ No status field in JSON, using inference. serverId=$serverId, clientId=$clientId');
      if (serverId == 0 && clientId != null) {
        status = MessageStatus.sending;
        _mlog('[MESSAGE] 📤 Status: SENDING (optimistic - no server ID)');
      } else if (json['isRead'] == true) {
        status = MessageStatus.read;
        _mlog('[MESSAGE] 📖 Status: READ (inferred from isRead)');
      } else {
        status = MessageStatus.sent;
        _mlog('[MESSAGE] ✅ Status: SENT (inferred - has server ID=$serverId)');
      }
    }

    // ✅ FIX TIMESTAMP PARSING
    DateTime? parseTimestamp(dynamic ts) {
      if (ts == null) {
        // Return null if timestamp is null - don't use current time as fallback
        // This allows proper status inference based on readAt being null
        _mlog('[MESSAGE] ⚠️ Timestamp is null, returning null');
        return null;
      }
      
      try {
        if (ts is String) {
          // Handle ISO 8601 format (with or without Z)
          final parsed = DateTime.parse(ts);
          // Convert to local time for proper display
          final result = parsed.toLocal();
          _mlog('[MESSAGE] ✅ Parsed timestamp: $ts → $result (local)');
          return result;
        }
      } catch (e) {
        _mlog('[MESSAGE] ❌ Failed to parse timestamp "$ts": $e');
      }
      // Return null if parsing fails - don't fallback to current time
      _mlog('[MESSAGE] ⚠️ Timestamp parsing failed, returning null');
      return null;
    }

    final createdAtParsed = parseTimestamp(json['createdAt']) ?? DateTime.now();
    final readAtParsed = parseTimestamp(json['readAt'] ?? json['read_at']);

    return Message(
      id: serverId,
      clientMessageId: clientId,
      senderId: json['senderId'] as int? ?? 0,
      senderName: json['senderName'] as String? ?? 'Unknown',
      senderProfilePic: json['senderProfilePictureUrl'] as String?,
      recipientId: (json['receiverId'] as int?) ?? (json['recipientId'] as int?) ?? 0,
      content: json['content'] as String? ?? '',
      mediaUrl: json['mediaUrl'] as String?,
      status: status,
      createdAt: createdAtParsed,
      isRead: json['isRead'] as bool? ?? false,
      readAt: readAtParsed,  // Now properly null if not in JSON
      messageType: json['messageType']?.toString() ?? 'USER',
      systemEvent: json['systemEvent']?.toString(),
      systemActorId: json['systemActorId'] as int?,
      systemTargetId: json['systemTargetId'] as int?,
      replyToStatusId: json['replyToStatusId'] as int?,
      replyToStatusType: json['replyToStatusType']?.toString(),
      replyToStatusPreview: json['replyToStatusPreview']?.toString(),
      statusReaction: json['statusReaction']?.toString(),
      replyToMessageId: json['replyToMessageId'] as int?,
      replyToSenderId: json['replyToSenderId'] as int?,
      replyToSenderName: json['replyToSenderName']?.toString(),
      replyToPreview: json['replyToPreview']?.toString(),
      isPinned: json['isPinned'] as bool? ?? false,
      isDeleted: json['isDeleted'] as bool? ?? false,
      reactionCounts: ((json['reactionCounts'] as Map?) ?? {})
          .map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
      myReaction: json['myReaction']?.toString(),
      mediaType: json['mediaType']?.toString(),
      mediaName: json['mediaName']?.toString(),
      isForwarded: json['isForwarded'] as bool? ?? false,
    );
  }

  /// Convert message to JSON for sending to server
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'clientMessageId': clientMessageId,
      'senderId': senderId,
      'senderName': senderName,
      'senderProfilePictureUrl': senderProfilePic,
      'receiverId': recipientId,
      'content': content,
      'mediaUrl': mediaUrl,
      'status': status.toString().split('.').last,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'isRead': isRead,
      'readAt': readAt?.toUtc().toIso8601String(),
    };
  }

  String get timeAgo {
    final now = DateTime.now();
    final messageTime = createdAt.toLocal();
    final diff = now.difference(messageTime);
    
    // ✅ Use the utility function for consistent formatting
    return formatTimeAgo(diff);
  }
}

class Conversation {
  final int userId;
  final String username;
  final String fullName;
  final String? profilePictureUrl;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final bool isOnline;

  Conversation({
    required this.userId,
    required this.username,
    required this.fullName,
    this.profilePictureUrl,
    this.lastMessage,
    this.lastMessageTime,
    required this.unreadCount,
    required this.isOnline,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      userId: json['userId'] as int? ?? 0,
      username: json['username'] as String? ?? 'Unknown',
      fullName: json['fullName'] as String? ?? 'Unknown',
      profilePictureUrl: json['profilePictureUrl'] as String?,
      lastMessage: (json['lastMessageContent'] as String?) ?? json['lastMessage'] as String?,
      lastMessageTime: json['lastMessageTime'] != null
          ? DateTime.parse(json['lastMessageTime'] as String)
          : null,
      unreadCount: json['unreadCount'] as int? ?? 0,
      isOnline: json['isOnline'] as bool? ?? false,
    );
  }

  String get lastMessagePreview {
    if (lastMessage == null || lastMessage!.isEmpty) {
      return 'No messages yet';
    }
    return lastMessage!.length > 60
        ? '${lastMessage!.substring(0, 60)}...'
        : lastMessage!;
  }

  String get timeAgo {
    if (lastMessageTime == null) return '';

    final now = DateTime.now();
    final messageTime = lastMessageTime!.toLocal();
    final diff = now.difference(messageTime);

    // ✅ Use the utility function for consistent formatting
    return formatTimeAgo(diff);
  }
}

/// ReadReceipt model for tracking when messages are read
class ReadReceipt {
  final int fromUserId;
  final List<int> messageIds;

  ReadReceipt({
    required this.fromUserId,
    required this.messageIds,
  });
}
