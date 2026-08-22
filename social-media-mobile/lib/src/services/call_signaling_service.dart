import 'dart:async';

import '../services/chat_websocket_service.dart';
import '../services/api_service.dart';
import '../services/call_api.dart';
import '../services/user_profile_cache.dart';
import '../services/firebase_messaging_service.dart';
import '../services/call_notification_platform.dart';
import '../state/call_state_manager.dart';

class CallSignalingService {
  static final CallSignalingService _instance =
      CallSignalingService._internal();
  factory CallSignalingService() {
    print('[CallSignalingService] ✅ getInstance called');
    return _instance;
  }

  // Legacy streams for UI modules that still subscribe to signaling events.
  final StreamController<Map<String, dynamic>> _acceptController =
      StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _rejectController =
      StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _endController =
      StreamController.broadcast();

  // Cache userId to avoid async calls in the notification handler
  int? _cachedUserId;

  Stream<Map<String, dynamic>> get onAccept => _acceptController.stream;
  Stream<Map<String, dynamic>> get onReject => _rejectController.stream;
  Stream<Map<String, dynamic>> get onEnd => _endController.stream;
  
  final StreamController<void> _historyUpdatedController = StreamController.broadcast();
  Stream<void> get onCallHistoryUpdated => _historyUpdatedController.stream;

  CallSignalingService._internal() {
    print('\n\n===== [CallSignalingService] ===== CONSTRUCTOR CALLED =====');

    // Cache the current user ID for use in the notification handler
    _initializeUserId();

    // Subscribe to websocket notifications and update CallStateManager only.
    void notificationHandler(Map<String, dynamic> notif) {
      print('[CallSignalingService] 📥 notificationHandler CALLED');
      print('[CallSignalingService] 📥 notif=$notif');
      
      // Wrap async operations in fire-and-forget
      Future.microtask(() async {
        try {
          // 🛡️ CRITICAL FIX: Ensure we have userId checks to prevent echo processing
          if (_cachedUserId == null || _cachedUserId == 0) {
            print('[CallSignalingService] ⚠️ _cachedUserId is null/0, fetching from ApiService...');
            try {
              _cachedUserId = await ApiService.getUserId();
              print('[CallSignalingService] ✅ Fetched & cached userId=$_cachedUserId');
            } catch (e) {
               print('[CallSignalingService] ❌ Failed to fetch userId: $e');
            }
          }

          final type = notif['type'] as String? ?? '';
          final payload = (notif['payload'] is Map<String, dynamic>)
              ? notif['payload'] as Map<String, dynamic>
              : <String, dynamic>{};
          final cm = CallStateManager();
          print('[CallSignalingService] 📥 type=$type payload=$payload');
          print(
              '[CallSignalingService] 📨 NOTIFICATION RECEIVED type=$type currentState=${cm.currentState}');

          if (type == 'CALL_INVITE') {
          print('[CallSignalingService] 📨 ============ CALL_INVITE RECEIVED ============');
          
          final fromUserId = payload['fromUserId'] as int?;
          final toUserId = payload['toUserId'] as int?;
          
          // Use cached user ID to check if this is our own CALL_INVITE
          final myUserId = _cachedUserId;
          
          print('[CallSignalingService] 📨 from=$fromUserId to=$toUserId myId=$myUserId');
          print('[CallSignalingService] 📨 currentState=${cm.currentState}');
          
          // Ignore CALL_INVITE if we're NOT idle (any active call state)
          // 🛡️ AUTO-REJECT check: If busy, send rejection automatically
          if (cm.currentState != CallState.idle) {
            print('[CallSignalingService] ⚠️ User is BUSY (state=${cm.currentState}). Auto-rejecting incoming call from $fromUserId');
            
            // Send rejection signal with "busy" reason
            try {
              ChatWebSocketService().sendCallSignal('CALL_REJECT', {
                'fromUserId': myUserId ?? 0,
                'toUserId': fromUserId,
                'channelName': payload['channelName'],
                'reason': 'busy' // Custom payload for busy state
              });
            } catch (e) {
              print('[CallSignalingService] ❌ Failed to send auto-reject: $e');
            }
            
            print('[CallSignalingService] ============ CALL_INVITE AUTO-REJECTED (BUSY) ============');
            return;
          }
          
          // Ignore if this is our own CALL_INVITE echoed back
          if (myUserId != null && fromUserId == myUserId) {
            print('[CallSignalingService] ❌ Ignoring CALL_INVITE - echo of our own call');
            print('[CallSignalingService] ============ CALL_INVITE IGNORED ============');
            return;
          }
          
          // Ignore if we're not the intended recipient
          if (myUserId != null && toUserId != null && toUserId != myUserId) {
            print('[CallSignalingService] ❌ Ignoring CALL_INVITE - not for me (to=$toUserId, me=$myUserId)');
            print('[CallSignalingService] ============ CALL_INVITE IGNORED ============');
            return;
          }
          
          print('[CallSignalingService] ✅ ACCEPTING CALL_INVITE - setting incoming call');
          
          // 🔄 PRE-FETCH caller's profile for instant display
          if (fromUserId != null && fromUserId > 0) {
            print('[CallSignalingService] 🔄 Pre-fetching profile for caller userId=$fromUserId');
            UserProfileCache().prefetchProfile(fromUserId).ignore();
          }
          
          // 📞 START WHATSAPP-STYLE FOREGROUND NOTIFICATION with Answer/Decline buttons
          if (fromUserId != null) {
            final isVideo = payload['isVideo'] as bool? ?? false;
            final cachedProfile = UserProfileCache().getCachedOnly(fromUserId);
            final callerLabel = cachedProfile?.fullName
                ?? 'Incoming ${isVideo ? 'Video' : 'Audio'} Call';
            print('[CallSignalingService] 📞 Starting foreground call notification for caller: $fromUserId ($callerLabel)');
            await CallNotificationPlatform.startCallNotification(
              callerId: fromUserId,
              callerName: callerLabel,
              channelName: payload['channelName'] as String? ?? '',
              isVideo: isVideo,
            );
          }
          
          cm.setIncomingCall(payload);
          print('[CallSignalingService] ✅ setIncomingCall completed');
          print('[CallSignalingService] ============ CALL_INVITE PROCESSED ============');
        } else if (type == 'CALL_ACCEPT') {
          final fromUserId = payload['fromUserId'] as int?;
          final toUserId = payload['toUserId'] as int?;
          final myUserId = _cachedUserId;
          
          print('[CallSignalingService] 📞 ============ CALL_ACCEPT RECEIVED ============');
          print('[CallSignalingService] 📞 from=$fromUserId to=$toUserId myId=$myUserId');
          print('[CallSignalingService] 📞 currentState=${cm.currentState}');
          print('[CallSignalingService] 📞 existing payload=${cm.activeCallPayload}');
          
          // Ignore if this is our own CALL_ACCEPT echoed back
          if (myUserId != null && fromUserId == myUserId) {
            print('[CallSignalingService] ❌ Ignoring CALL_ACCEPT - echo of our own accept');
            print('[CallSignalingService] ============ CALL_ACCEPT IGNORED ============');
            return;
          }
          
          // Only transition to inCall if we initiated an outgoing call
          if (cm.currentState == CallState.outgoingCalling) {
            print('[CallSignalingService] ✅ state is outgoingCalling, transitioning to inCall');
            // CRITICAL: Use the EXISTING activeCallPayload, not the CALL_ACCEPT payload
            // The existing payload has correct fromUserId (us) and toUserId (them)
            // The CALL_ACCEPT payload has swapped IDs from receiver's perspective
            final existingPayload = cm.activeCallPayload;
            if (existingPayload != null) {
              print('[CallSignalingService] ✅ Using existing payload for setInCall');
              cm.setInCall(existingPayload);
            } else {
              print('[CallSignalingService] ⚠️ No existing payload, using CALL_ACCEPT payload');
              cm.setInCall(payload);
            }
            print('[CallSignalingService] ✅ setInCall completed');
          } else {
            print('[CallSignalingService] ❌ Ignoring CALL_ACCEPT, not in outgoingCalling state');
          }
          
          try {
            _acceptController.add(payload);
          } catch (_) {}
          print('[CallSignalingService] ============ CALL_ACCEPT PROCESSED ============');
        } else if (type == 'CALL_REJECT' || type == 'CALL_END') {
          final fromUserId = payload['fromUserId'] as int?;
          final toUserId = payload['toUserId'] as int?;
          final channelName = payload['channelName'] as String?;
          final callerName = payload['actorUsername'] as String? ?? 'Unknown Caller';
          final myUserId = _cachedUserId;
          
          print('[CallSignalingService] 📵 ============ CALL_REJECT/CALL_END RECEIVED ============');
          print('[CallSignalingService] 📵 type=$type');
          print('[CallSignalingService] 📵 fromUserId=$fromUserId toUserId=$toUserId');
          print('[CallSignalingService] 📵 channelName=$channelName');
          print('[CallSignalingService] 📵 callerName=$callerName');
          print('[CallSignalingService] 📵 myUserId=$myUserId');
          print('[CallSignalingService] 📵 currentState=${cm.currentState}');
          
          // Only process if we're in a call state (not idle)
          if (cm.currentState == CallState.idle) {
            print('[CallSignalingService] ⚠️ Ignoring $type - already in idle state');
          } else {
            // Stop the foreground call notification first
            print('[CallSignalingService] 📵 Stopping foreground call notification');
            await CallNotificationPlatform.stopCallNotification();
            
            // Then handle state changes

            if (type == 'CALL_REJECT' && fromUserId != null) {
              // Call was rejected - show missed call notification
              print('[CallSignalingService] 📵 Call rejected - showing MISSED CALL notification for: $callerName (ID: $fromUserId)');
              cm.lastEndReason = payload['reason'] == 'busy' ? CallEndReason.busy : CallEndReason.declined;
              // Use CallStateManager to properly handle the sequence
              await cm.handleCallRejected(fromUserId, callerName);
              // handleCallRejected already calls reset()
            } else {
              // Call ended - just cleanup
              print('[CallSignalingService] 📵 Call ended - cleaning up');
              await cm.reset();
            }
          }
          
          try {
            if (type == 'CALL_REJECT') _rejectController.add(payload);
            if (type == 'CALL_END') _endController.add(payload);
          } catch (_) {}
          print('[CallSignalingService] 📵 ============ END HANDLER COMPLETE ============');
          
          // Trigger history refresh for everyone involved in a call end
          if (type == 'CALL_END' || type == 'CALL_REJECT') {
             print('[CallSignalingService] 🔄 Triggering local history refresh signal');
             _historyUpdatedController.add(null);
          }
        } else if (type == 'CALL_HISTORY_UPDATED') {
          print('[CallSignalingService] 🔄 CALL_HISTORY_UPDATED RECEIVED - notifying listeners');
          _historyUpdatedController.add(null);
        } else {
          print(
              '[CallSignalingService] ⚠️ UNKNOWN type=$type (not CALL_INVITE/ACCEPT/REJECT/END)');
        }
        } catch (e) {
          print('[CallSignalingService] ❌ notificationHandler error: $e');
          print('[CallSignalingService] ❌ Stack: ${StackTrace.current}');
        }
      }); // End Future.microtask
    }

    // Register notification handler via ChatWebSocketService.
    // subscribeToNotifications adds the handler to a list. The actual STOMP subscription
    // happens in ChatWebSocketService._onConnect() which is triggered when the websocket connects.
    print('[CallSignalingService] 🔄 Creating notification handler function');
    try {
      final ws = ChatWebSocketService();
      print('[CallSignalingService] 🔄 Got ChatWebSocketService instance');
      ws.subscribeToNotifications(notificationHandler);
      print(
          '[CallSignalingService] ✅✅✅ SUCCESSFULLY registered notification handler ✅✅✅');
      print(
          '[CallSignalingService] ✅ This device will now receive ALL notifications');
    } catch (e, st) {
      print('[CallSignalingService] ❌❌❌ CRITICAL ERROR during init: $e');
      print('[CallSignalingService] ❌ Stack trace: $st');
    }
    print('[CallSignalingService] ===== CONSTRUCTOR COMPLETE =====\n');
  }

  // Initialize userId asynchronously
  Future<void> _initializeUserId() async {
    try {
      _cachedUserId = await ApiService.getUserId();
      print('[CallSignalingService] 📌 Cached userId=$_cachedUserId');
    } catch (e) {
      print('[CallSignalingService] ⚠️ Could not cache userId: $e');
    }
  }

  // ✅ NEW: Public method to force refresh the cached user ID (called on Login)
  Future<void> refreshUserSession() async {
    print('[CallSignalingService] 🔄 Refreshing user session...');
    _cachedUserId = null; // Clear first to ensure we don't stick with old ID if fetch fails
    await _initializeUserId();
    print('[CallSignalingService] ✅ Session refreshed. New userId: $_cachedUserId');
  }

  // ✅ NEW: Public method to clear session (called on Logout)
  void clearSession() {
    print('[CallSignalingService] 🧹 Clearing user session');
    _cachedUserId = null;
  }

  Future<void> sendCallInvite(
      {required int fromUserId,
      required int toUserId,
      required String channelName,
      required bool isVideo}) async {
    print('[CallSignalingService] 📤 sendCallInvite CALLED');

    final cm = CallStateManager();
    if (cm.currentState != CallState.idle &&
        cm.currentState != CallState.outgoingCalling) {
      print('[CallSignalingService] ❌ BLOCKED duplicate CALL_INVITE - state=${cm.currentState}');
      return;
    }

    print(
        '[CallSignalingService] 📤 fromUserId=$fromUserId toUserId=$toUserId channelName=$channelName isVideo=$isVideo');

    // 🔄 PRE-FETCH recipient's profile for instant display
    print('[CallSignalingService] 🔄 Pre-fetching profile for recipient userId=$toUserId');
    UserProfileCache().prefetchProfile(toUserId).ignore();

    // Log (and thus create) the call row BEFORE sending the invite, so the
    // real callId can ride in the signal itself instead of every later
    // accept/reject/status-update having to re-scan history to guess which
    // row it refers to.
    int? callId;
    try {
      callId = await CallApi.logCall({
        'toUserId': toUserId,
        'channelName': channelName,
        'isVideo': isVideo,
      });
    } catch (e) {
      print('[CallSignalingService] ⚠️ logCall failed before invite: $e');
    }
    cm.activeCallId = callId;

    final payload = {
      'fromUserId': fromUserId,
      'toUserId': toUserId,
      'channelName': channelName,
      'isVideo': isVideo,
      if (callId != null) 'callId': callId,
    };
    print('[CallSignalingService] 📤 payload=$payload');
    print(
        '[CallSignalingService] 📤 calling ChatWebSocketService().sendCallSignal()');
    ChatWebSocketService().sendCallSignal('CALL_INVITE', payload);

    print('[CallSignalingService] ✅ sendCallInvite COMPLETED');
  }

  Future<void> sendCallAccept(
      {required int fromUserId,
      required int toUserId,
      required String channelName,
      required bool isVideo}) async {
    print('[CallSignalingService] 📤 sendCallAccept CALLED');
    print(
        '[CallSignalingService] 📤 fromUserId=$fromUserId toUserId=$toUserId channelName=$channelName isVideo=$isVideo');
    final callId = CallStateManager().activeCallId;
    final payload = {
      'fromUserId': fromUserId,
      'toUserId': toUserId,
      'channelName': channelName,
      'isVideo': isVideo,
      if (callId != null) 'callId': callId,
    };
    print('[CallSignalingService] 📤 calling sendCallSignal CALL_ACCEPT (WS)');
    ChatWebSocketService().sendCallSignal('CALL_ACCEPT', payload);

    // 2. ALSO Try REST API (Fallback/Race)
    print('[CallSignalingService] 📤 calling CallApi.acceptCallSignal (HTTP)');
    try {
      await CallApi.acceptCallSignal(toUserId, channelName, isVideo);
    } catch (e) {
      print('[CallSignalingService] ⚠️ REST accept failed: $e');
    }

    if (callId != null) {
      try {
        await CallApi.updateCallStatus(callId, 'ACCEPTED', duration: 0);
      } catch (e) {
        print('[CallSignalingService] ⚠️ Failed to mark call ACCEPTED: $e');
      }
    }

    print('[CallSignalingService] ✅ sendCallAccept COMPLETED');
  }

  Future<void> sendCallReject(
      {required int fromUserId,
      required int toUserId,
      required String channelName,
      String status = 'DECLINED'}) async {
    print('[CallSignalingService] 📤 sendCallReject CALLED');
    final callId = CallStateManager().activeCallId;
    final payload = {
      'fromUserId': fromUserId,
      'toUserId': toUserId,
      'channelName': channelName,
      if (callId != null) 'callId': callId,
    };

    // 1. Try WebSocket (Fastest if connected)
    print('[CallSignalingService] 📤 calling sendCallSignal CALL_REJECT (WS)');
    ChatWebSocketService().sendCallSignal('CALL_REJECT', payload);

    // 2. ALSO Try REST API (Fallback for killed app/cold start)
    // This ensures the rejection reaches the server even if WS is connecting
    print('[CallSignalingService] 📤 calling CallApi.rejectCallSignal (HTTP)');
    try {
      await CallApi.rejectCallSignal(toUserId, channelName);
    } catch (e) {
      print('[CallSignalingService] ⚠️ REST reject failed: $e');
    }

    if (callId != null) {
      try {
        await CallApi.updateCallStatus(callId, status, duration: 0);
      } catch (e) {
        print('[CallSignalingService] ⚠️ Failed to mark call $status: $e');
      }
    }

    print('[CallSignalingService] ✅ sendCallReject COMPLETED');
  }

  void sendCallEnd(
      {required int fromUserId,
      required int toUserId,
      required String channelName}) {
    print('[CallSignalingService] 📤 ============ SENDING CALL_END ============');
    print('[CallSignalingService] 📤 fromUserId=$fromUserId');
    print('[CallSignalingService] 📤 toUserId=$toUserId');
    print('[CallSignalingService] 📤 channelName=$channelName');
    final callId = CallStateManager().activeCallId;
    final payload = {
      'fromUserId': fromUserId,
      'toUserId': toUserId,
      'channelName': channelName,
      if (callId != null) 'callId': callId,
    };
    print('[CallSignalingService] 📤 calling sendCallSignal CALL_END');
    ChatWebSocketService().sendCallSignal('CALL_END', payload);
    print('[CallSignalingService] ✅ CALL_END sent successfully');
    print('[CallSignalingService] 📤 ==========================================');
  }

  // Log call end with duration — uses the real callId threaded through
  // CallStateManager.activeCallId instead of re-scanning history and
  // pattern-matching "most recent call", which was racy under concurrent
  // calls.
  Future<void> updateCallEnded({
    required int fromUserId,
    required int toUserId,
    required String channelName,
    required bool isVideo,
    required int durationSeconds,
  }) async {
    final callId = CallStateManager().activeCallId;
    if (callId == null) {
      print('[CallSignalingService] ⚠️ No activeCallId — cannot log call end');
      return;
    }
    try {
      final success = await CallApi.updateCallStatus(callId, 'ENDED', duration: durationSeconds);
      if (success) {
        print('[CallSignalingService] ✅ Call ended logged: callId=$callId duration=${durationSeconds}s');
      } else {
        print('[CallSignalingService] ⚠️ Failed to update call end status');
      }
    } catch (e) {
      print('[CallSignalingService] ❌ Failed to log call end: $e');
    }
  }
}
