import 'dart:async';

import 'chat_websocket_service.dart';
import 'api_service.dart';
import 'call_api.dart';
import '../state/group_call_state_manager.dart';

/// Group-call WebSocket signaling — a parallel counterpart to
/// CallSignalingService that only handles GROUP_CALL_* event types. Both
/// register independent listeners on the same ChatWebSocketService
/// notification stream, so neither interferes with the other.
class GroupCallSignalingService {
  static final GroupCallSignalingService _instance = GroupCallSignalingService._internal();
  factory GroupCallSignalingService() => _instance;

  int? _cachedUserId;

  final StreamController<Map<String, dynamic>> _declineController =
      StreamController.broadcast();
  Stream<Map<String, dynamic>> get onDecline => _declineController.stream;

  /// Surfaces "X declined" as plain text the UI can toast — wires up the
  /// previously-orphaned onDecline stream (nothing subscribed to it before).
  final StreamController<String> _declineToastController = StreamController.broadcast();
  Stream<String> get onDeclineToast => _declineToastController.stream;

  GroupCallSignalingService._internal() {
    _initUserId();
    onDecline.listen((payload) {
      final name = payload['actorUsername'] as String? ?? payload['callerName'] as String?;
      _declineToastController.add('${name ?? 'Someone'} declined the call');
    });

    void handler(Map<String, dynamic> notif) {
      final type = notif['type'] as String? ?? '';
      if (!type.startsWith('GROUP_CALL_')) return; // not ours — 1:1 CallSignalingService owns the rest

      Future.microtask(() async {
        try {
          _cachedUserId ??= await ApiService.getUserId();
          final payload = (notif['payload'] is Map<String, dynamic>)
              ? notif['payload'] as Map<String, dynamic>
              : <String, dynamic>{};
          final fromUserId = payload['fromUserId'] as int?;

          // Ignore our own signal echoed back.
          if (fromUserId != null && fromUserId == _cachedUserId) return;

          final gm = GroupCallStateManager();
          final rawCallId = payload['callId'];
          final callId = rawCallId is int
              ? rawCallId
              : (rawCallId != null ? int.tryParse(rawCallId.toString()) : null);

          if (type == 'GROUP_CALL_INVITE') {
            final groupId = payload['groupId'] as int?;
            final channelName = payload['channelName'] as String?;
            if (groupId == null || channelName == null || fromUserId == null) return;

            if (gm.currentState != GroupCallState.idle) {
              // Busy — decline automatically so the caller isn't left hanging.
              sendDecline(groupId: groupId, channelName: channelName, fromUserId: _cachedUserId ?? 0, callId: callId);
              return;
            }

            gm.setIncoming(
              groupId: groupId,
              groupName: payload['groupName'] as String? ?? 'Group',
              channelName: channelName,
              isVideo: payload['isVideo'] as bool? ?? false,
              callerId: fromUserId,
              callerName: payload['callerName'] as String?,
              callId: callId,
            );
          } else if (type == 'GROUP_CALL_DECLINE') {
            _declineController.add(payload);
          } else if (type == 'GROUP_CALL_CANCEL') {
            final groupId = payload['groupId'] as int?;
            if (groupId != null) gm.handleRemoteCancel(groupId);
          } else if (type == 'GROUP_CALL_LEAVE' || type == 'GROUP_CALL_END') {
            // GROUP_CALL_END accepted as a legacy synonym — route it based
            // on our own local state (still ringing -> cancel, already
            // in-call -> just a roster update).
            final groupId = payload['groupId'] as int?;
            if (groupId != null) {
              if (gm.currentState == GroupCallState.incomingRinging) {
                gm.handleRemoteCancel(groupId);
              } else {
                gm.handleRemoteLeave(groupId);
              }
            }
          }
        } catch (e) {
          print('[GroupCallSignalingService] ❌ handler error: $e');
        }
      });
    }

    ChatWebSocketService().subscribeToNotifications(handler);
  }

  Future<void> _initUserId() async {
    _cachedUserId = await ApiService.getUserId();
  }

  Future<void> refreshUserSession() async {
    _cachedUserId = null;
    await _initUserId();
  }

  /// Starts a group call, or transparently joins one already in progress
  /// for this group ("join later" — see CallApi.fetchActiveGroupCall).
  /// Returns null on success, or a failure reason ('call_full'/'error').
  Future<String?> startGroupCall({
    required int groupId,
    required String groupName,
    required bool isVideo,
  }) async {
    final gm = GroupCallStateManager();
    if (gm.currentState != GroupCallState.idle) return 'error';

    final active = await CallApi.fetchActiveGroupCall(groupId);
    final isJoiningExisting = active?['active'] == true;

    String channel;
    int? callId;
    bool effectiveIsVideo = isVideo;

    if (isJoiningExisting) {
      channel = active!['channelName'] as String;
      effectiveIsVideo = active['isVideo'] as bool? ?? isVideo;
      final rawId = active['callId'];
      callId = rawId is int ? rawId : int.tryParse(rawId.toString());

      if (callId != null) {
        final myUserId = _cachedUserId ?? await ApiService.getUserId() ?? 0;
        final agoraUid = myUserId & 0x7FFFFFFF;
        final joinFailure = await CallApi.joinCallParticipant(callId, agoraUid);
        // Server-authoritative capacity check — fail before spending an
        // Agora join if the call is already at MAX_GROUP_PARTICIPANTS.
        if (joinFailure != null) return joinFailure;
      }
    } else {
      channel = 'group-$groupId-${DateTime.now().millisecondsSinceEpoch}';
      callId = await CallApi.logCall({
        'groupId': groupId,
        'isVideo': isVideo,
        'channelName': channel,
      });
    }

    final joined = await gm.joinAsCaller(
      groupId: groupId,
      groupName: groupName,
      channelName: channel,
      isVideo: effectiveIsVideo,
      callId: callId,
    );
    if (!joined) return 'error';

    if (!isJoiningExisting) {
      // Only fan an invite out when we actually created the call — silently
      // joining an already-active one doesn't need to re-notify anyone.
      final myUserId = _cachedUserId ?? await ApiService.getUserId() ?? 0;
      ChatWebSocketService().sendCallSignal('GROUP_CALL_INVITE', {
        'groupId': groupId,
        'groupName': groupName,
        'channelName': channel,
        'isVideo': isVideo,
        'fromUserId': myUserId,
        if (callId != null) 'callId': callId,
      });
    }
    return null;
  }

  /// "Join later" entry point for the group chat's "N on a call · Join"
  /// banner — isVideo is ignored when joining an already-active call (the
  /// call's own isVideo, from fetchActiveGroupCall, governs instead).
  Future<String?> joinActiveCall(int groupId, String groupName) {
    return startGroupCall(groupId: groupId, groupName: groupName, isVideo: false);
  }

  Future<bool> acceptIncoming() async {
    final gm = GroupCallStateManager();
    final callId = gm.activeCallId;
    if (callId != null) {
      final myUserId = _cachedUserId ?? await ApiService.getUserId() ?? 0;
      final agoraUid = myUserId & 0x7FFFFFFF;
      final joinFailure = await CallApi.joinCallParticipant(callId, agoraUid);
      if (joinFailure != null) {
        gm.reset();
        return false;
      }
    }
    return gm.acceptIncoming();
  }

  Future<void> declineIncoming() async {
    final gm = GroupCallStateManager();
    if (gm.groupId != null && gm.channelName != null) {
      final myUserId = _cachedUserId ?? await ApiService.getUserId() ?? 0;
      sendDecline(groupId: gm.groupId!, channelName: gm.channelName!, fromUserId: myUserId, callId: gm.activeCallId);
    }
    gm.reset();
  }

  /// A joined participant leaves — the call continues for everyone else.
  Future<void> leaveCall() async {
    final gm = GroupCallStateManager();
    if (gm.groupId != null && gm.channelName != null) {
      final myUserId = _cachedUserId ?? await ApiService.getUserId() ?? 0;
      sendLeave(groupId: gm.groupId!, channelName: gm.channelName!, fromUserId: myUserId, callId: gm.activeCallId);
    }
    if (gm.activeCallId != null) {
      unawaited(CallApi.leaveCallParticipant(gm.activeCallId!));
    }
    await gm.leaveAgora();
    gm.reset();
  }

  /// The caller backs out of their own unanswered invite — cancels for
  /// everyone still ringing. Distinct from leaveCall (a joined participant
  /// leaving an already-connected call).
  Future<void> cancelCall() async {
    final gm = GroupCallStateManager();
    if (gm.groupId != null && gm.channelName != null) {
      final myUserId = _cachedUserId ?? await ApiService.getUserId() ?? 0;
      sendCancel(groupId: gm.groupId!, channelName: gm.channelName!, fromUserId: myUserId, callId: gm.activeCallId);
    }
    await gm.leaveAgora();
    gm.reset();
  }

  void sendDecline({required int groupId, required String channelName, required int fromUserId, int? callId}) {
    ChatWebSocketService().sendCallSignal('GROUP_CALL_DECLINE', {
      'groupId': groupId,
      'channelName': channelName,
      'fromUserId': fromUserId,
      if (callId != null) 'callId': callId,
    });
  }

  void sendLeave({required int groupId, required String channelName, required int fromUserId, int? callId}) {
    ChatWebSocketService().sendCallSignal('GROUP_CALL_LEAVE', {
      'groupId': groupId,
      'channelName': channelName,
      'fromUserId': fromUserId,
      if (callId != null) 'callId': callId,
    });
  }

  void sendCancel({required int groupId, required String channelName, required int fromUserId, int? callId}) {
    ChatWebSocketService().sendCallSignal('GROUP_CALL_CANCEL', {
      'groupId': groupId,
      'channelName': channelName,
      'fromUserId': fromUserId,
      if (callId != null) 'callId': callId,
    });
  }
}
