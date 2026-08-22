import 'package:flutter/foundation.dart';
import '../utils/timestamp_parser.dart';

enum CallType { audio, video }
enum CallStatus { initiated, accepted, declined, ended, missed, canceled, busy }

class CallHistory {
  final int id;
  final int initiatorId;  // Person who started the call
  final int receiverId;   // Person receiving the call
  final CallType type;    // AUDIO or VIDEO
  final CallStatus status; // INITIATED, ACCEPTED, DECLINED, ENDED
  final int duration;     // seconds
  final DateTime createdAt;

  CallHistory({
    required this.id,
    required this.initiatorId,
    required this.receiverId,
    required this.type,
    required this.status,
    required this.duration,
    required this.createdAt,
  });

  factory CallHistory.fromJson(Map<String, dynamic> json) {
    // Parse call type (backend returns "AUDIO" or "VIDEO" as strings)
    String? callTypeStr = json['callType'] as String? ?? json['type'] as String?;
    CallType callTypeEnum = CallType.audio;
    if (callTypeStr != null && callTypeStr.toUpperCase() == 'VIDEO') {
      callTypeEnum = CallType.video;
    }

    // Parse call status - accept either String or CallStatus enum
    dynamic statusValue = json['status'];
    print('[CallHistory.fromJson] 🔍 Raw status value: "$statusValue" (type: ${statusValue.runtimeType})');
    CallStatus statusEnum = _parseCallStatus(statusValue ?? 'INITIATED');

    // Parse ID
    final idValue = json['id'];
    final id = idValue is int ? idValue : (idValue == null ? -1 : int.tryParse(idValue.toString()) ?? -1);
    
    if (id <= 0) {
      print('[CallHistory] ⚠️ WARNING: Invalid ID found in response: $json');
    }

    // Parse initiator and receiver - backend returns as fromUserId/toUserId
    final initiatorId = json['initiatorId'] as int? ?? json['fromUserId'] as int? ?? 0;
    final receiverId = json['receiverId'] as int? ?? json['toUserId'] as int? ?? 0;

    return CallHistory(
      id: id,
      initiatorId: initiatorId,
      receiverId: receiverId,
      type: callTypeEnum,
      status: statusEnum,
      duration: json['duration'] is int ? json['duration'] as int : (json['duration'] == null ? 0 : int.tryParse(json['duration'].toString()) ?? 0),
      createdAt: TimestampParser.parseDynamic(json['createdAt']),
    );
  }

  static CallStatus _parseCallStatus(dynamic statusInput) {
    // Handle null case
    if (statusInput == null) {
      print('[CallHistory] ⚠️ statusInput is null, defaulting to INITIATED');
      return CallStatus.initiated;
    }
    
    // Handle if already a CallStatus enum
    if (statusInput is CallStatus) {
      print('[CallHistory] ✅ statusInput is already CallStatus: $statusInput');
      return statusInput;
    }
    
    // Convert to string and uppercase, handle backend's enum format
    String statusStr = statusInput.toString().toUpperCase().trim();
    
    // Handle enum-like strings from backend (e.g., "CallStatus.rejected")
    if (statusStr.contains('.')) {
      statusStr = statusStr.split('.').last;
    }
    
    print('[CallHistory] 🔍 Parsing status from: "$statusInput" → "$statusStr"');
    
    switch (statusStr) {
      case 'ACCEPTED':
        print('[CallHistory] ✅ Parsed as ACCEPTED');
        return CallStatus.accepted;
      case 'REJECTED':
      case 'DECLINED':
        print('[CallHistory] ✅ Parsed as DECLINED (from $statusStr)');
        return CallStatus.declined;
      case 'ENDED':
        print('[CallHistory] ✅ Parsed as ENDED');
        return CallStatus.ended;
      case 'MISSED':
        print('[CallHistory] ✅ Parsed as MISSED');
        return CallStatus.missed;
      case 'CANCELED':
      case 'CANCELLED':
        print('[CallHistory] ✅ Parsed as CANCELED');
        return CallStatus.canceled;
      case 'BUSY':
        print('[CallHistory] ✅ Parsed as BUSY');
        return CallStatus.busy;
      case 'INITIATED':
      case 'RINGING':
      case 'ACTIVE':
        print('[CallHistory] ✅ Parsed as INITIATED');
        return CallStatus.initiated;
      default:
        print('[CallHistory] ⚠️ Unknown status "$statusStr", defaulting to INITIATED');
        return CallStatus.initiated;
    }
  }

  /// Check if this call was missed by the given user — true only for a
  /// receiver whose call is canonically MISSED (see CallStatus.missed).
  /// Declined/busy/canceled calls are shown distinctly, not lumped in here.
  bool isMissedBy(int userId) {
    if (userId != receiverId) return false;
    return status == CallStatus.missed;
  }
}