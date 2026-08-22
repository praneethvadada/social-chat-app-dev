import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';

import '../services/agora_service.dart';
import '../services/call_api.dart';
import '../services/api_service.dart';
import '../services/firebase_messaging_service.dart';

/// Global call state enum. `connecting` is reserved for future use by
/// CallOverlayManager's routing (falls into the same screen as `inCall`);
/// this manager doesn't transition through it yet to avoid touching the
/// heavily-guarded outgoing/incoming -> inCall transitions.
enum CallState {
  idle,
  outgoingCalling,
  incomingRinging,
  connecting,
  inCall,
  reconnecting,
  failed,
  ended,
}

/// Why a call ended/failed — carried alongside CallState.ended/failed so the
/// UI (and eventually call history) can distinguish "hung up normally" from
/// "they were busy" from "permission denied" etc. without multiplying
/// CallState itself.
enum CallEndReason { normal, declined, busy, missed, canceled, failed }

/// How long we wait for the Agora connection to recover before giving up
/// and ending a reconnecting call.
const _reconnectGiveUpDuration = Duration(seconds: 15);

/// A ChangeNotifier that holds call state and optional payload.
///
/// Responsibilities:
/// - Store `currentState` and `activeCallPayload`.
/// - Manage Agora lifecycle: when transitioning to `inCall` initialize and join;
///   when transitioning to `ended` leave and dispose.
/// - Expose the active `AgoraService` instance for UI to use.
///
/// IMPORTANT: Agora callbacks MUST NOT update CallState. CallState controls Agora.
class CallStateManager extends ChangeNotifier {
  static final CallStateManager _instance = CallStateManager._internal();
  factory CallStateManager() => _instance;
  CallStateManager._internal();

  CallState currentState = CallState.idle;
  Map<String, dynamic>? activeCallPayload;
  bool isMinimized = false; // Track if call is minimized

  /// The backend CallLog id for the active call, threaded through from
  /// POST /calls so signal/REST calls don't need to re-scan history to find
  /// which row to update.
  int? activeCallId;

  /// Why the call most recently ended/failed — set right before the state
  /// transitions to `ended`/`failed`.
  CallEndReason? lastEndReason;

  /// The time when the call started (for stable timer)
  DateTime? callStartTime;

  AgoraService? _agoraService;
  bool _agoraJoined = false;
  int? _agoraUid;

  StreamSubscription? _tokenExpirySub;
  StreamSubscription? _connectionStateSub;
  Timer? _reconnectWatchdog;

  /// Expose AgoraService (may be null if not initialized yet)
  AgoraService? get agoraService => _agoraService;

  /// Whether Agora has joined the channel for the active call
  bool get isAgoraJoined => _agoraJoined;

  void setMinimized(bool minimized) {
    print('[CallStateManager] 📱 setMinimized: $minimized');
    isMinimized = minimized;
    notifyListeners();
  }

  void _update(CallState newState, [Map<String, dynamic>? payload]) {
    final prev = currentState;
    print('[CallStateManager] 🔄 _update CALLED: prev=$prev -> newState=$newState');
    print('[CallStateManager] 🔄 payload=$payload');
    currentState = newState;
    activeCallPayload = payload;
    print('[CallStateManager] 🔄 state change $prev -> $newState');
    print('[CallStateManager] 🔄 notifyListeners() called');
    notifyListeners();
  }

  void setOutgoingCall(Map<String, dynamic>? payload) {
    print('[CallStateManager] 📞 setOutgoingCall CALLED payload=$payload');
    print('[CallStateManager] 📞 Current state: $currentState');
    
    // CRITICAL: Only allow outgoing call if we're idle
    if (currentState != CallState.idle) {
      print('[CallStateManager] ❌ BLOCKING setOutgoingCall - not in idle state (current=$currentState)');
      return;
    }

    lastEndReason = null;
    activeCallId = payload?['callId'] as int?;
    _update(CallState.outgoingCalling, payload);
  }

  void setIncomingCall(Map<String, dynamic>? payload) {
    print('[CallStateManager] 📳 setIncomingCall CALLED payload=$payload');
    print('[CallStateManager] 📳 Current state: $currentState');
    
    // CRITICAL: Only allow incoming call if we're idle
    // This prevents the sender from accidentally showing IncomingCallScreen
    if (currentState != CallState.idle) {
      print('[CallStateManager] ❌ BLOCKING setIncomingCall - not in idle state (current=$currentState)');
      return;
    }

    lastEndReason = null;
    activeCallId = payload?['callId'] as int?;
    _update(CallState.incomingRinging, payload);
  }

  void setInCall(Map<String, dynamic>? payload) {
    print('[CallStateManager] 🟢 setInCall CALLED - ACCEPTING THE CALL');
    print('[CallStateManager] 🟢 Current state BEFORE: $currentState');
    print('[CallStateManager] 🟢 Payload: $payload');
    
    // CRITICAL: Only allow inCall transition from valid states
    // Valid: outgoingCalling (caller received CALL_ACCEPT)
    // Valid: incomingRinging (callee clicked Accept)
    // Invalid: idle (no call in progress), inCall (already in call)
    if (currentState != CallState.outgoingCalling && currentState != CallState.incomingRinging) {
      print('[CallStateManager] ❌ BLOCKING setInCall - invalid state transition from $currentState');
      return;
    }
    // Only set callStartTime if not already set (prevents reset on screen rebuild)
    if (callStartTime == null) {
      callStartTime = DateTime.now();
      print('[CallStateManager] ⏱️ callStartTime set to: '
          '${callStartTime?.toIso8601String()}');
    }
    _update(CallState.inCall, payload);
    print('[CallStateManager] 🟢 State updated to: $currentState');
    print('[CallStateManager] 🟢 Calling _initAgoraForPayload...');
    _initAgoraForPayload(payload); // async fire-and-forget
  }

  Future<void> endCall({CallEndReason reason = CallEndReason.normal}) async {
    // Transition state first so UI can react immediately.
    print('[CallStateManager] 📵 endCall() - transitioning to ended state');
    lastEndReason = reason;

    // Cancel all call notifications when ending call
    print('[CallStateManager] 🔔 Dismissing all call notifications on endCall');
    await FirebaseMessagingService.cancelAllCallNotifications();
    print('[CallStateManager] 🔔 All notifications dismissed');

    _update(CallState.ended, activeCallPayload);
    print('[CallStateManager] 📵 State updated to ended');
    // Perform Agora cleanup asynchronously.
    _cleanupAgora();
  }

  /// Handle call rejection - show "Missed Call" notification
  Future<void> handleCallRejected(int callerId, String? callerName) async {
    print('[CallStateManager] 📵 handleCallRejected CALLED for caller: $callerId');
    
    // Show missed call notification instead of regular notification
    await FirebaseMessagingService.showMissedCallNotification(
      callerId: callerId,
      callerName: callerName ?? 'Missed Call',
    );
    
    // Then reset state
    await reset();
  }

  final StreamController<void> _callEndedController = StreamController.broadcast();
  Stream<void> get onCallEnded => _callEndedController.stream;

  Future<void> reset() async {
    print('[CallStateManager] 🔄 ============ RESET() CALLED ============');
    print('[CallStateManager] 🔄 Previous state: $currentState');
    print('[CallStateManager] 🔄 Setting state to IDLE and cleaning up...');
    
    // Check if we are transitioning FROM a non-idle state (actually ending a call)
    final bool wasActive = currentState != CallState.idle;
    
    currentState = CallState.idle;
    activeCallPayload = null;
    activeCallId = null;
    lastEndReason = null;
    isMinimized = false; // Reset minimization
    callStartTime = null; // Reset call start time

    // Cancel all call notifications when resetting to idle
    print('[CallStateManager] 🔔 Dismissing all call notifications');
    await FirebaseMessagingService.cancelAllCallNotifications();
    print('[CallStateManager] 🔔 All notifications dismissed in reset()');
    
    // Ensure Agora is cleaned up when resetting.
    _cleanupAgora();
    print('[CallStateManager] 🔄 Calling notifyListeners() after reset');
    notifyListeners();
    
    if (wasActive) {
      print('[CallStateManager] 🔄 Triggering onCallEnded stream');
      _callEndedController.add(null);
    }
    
    print('[CallStateManager] 🔄 ============ RESET COMPLETE ============');
  }

  Future<void> _initAgoraForPayload(Map<String, dynamic>? payload) async {
    try {
      final initStartTime = DateTime.now();
      print('[CallStateManager] 🎥 _initAgoraForPayload CALLED at ${initStartTime.toIso8601String()} payload=$payload');
      if (payload == null) {
        print('[CallStateManager] ❌ payload is null, cannot init Agora');
        return;
      }

      final channel = payload['channelName'] as String? ?? payload['channel'] as String?;
      final isVideo = payload['isVideo'] as bool? ?? false; // default to audio calls
      print('[CallStateManager] 🎥 channel=$channel isVideo=$isVideo');

      if (channel == null || channel.isEmpty) {
        print('[CallStateManager] ❌ missing channel in payload, cannot init Agora');
        return;
      }

      // Request permissions (mic only for audio by default)
      print('[CallStateManager] 🎥 Requesting permissions: isVideo=$isVideo');
      final permissions = isVideo ? [Permission.camera, Permission.microphone] : [Permission.microphone];
      for (final p in permissions) {
        print('[CallStateManager] 🎥 Checking permission: $p');
        if (!await p.request().isGranted) {
          print('[CallStateManager] ❌ permission denied: $p');
          lastEndReason = CallEndReason.failed;
          currentState = CallState.failed;
          notifyListeners();
          return;
        }
        print('[CallStateManager] ✅ permission granted: $p');
      }

      final myUserId = await ApiService.getUserId() ?? 0;
      final callerId = (payload['fromUserId'] as int?) ?? myUserId;
      final calleeId = (payload['toUserId'] as int?) ?? (payload['otherUserId'] as int?) ?? 0;

      // Deterministic uid derived from userId (not a timestamp) — stays
      // stable across reconnects/token refresh, and a remote uid *is* the
      // remote userId, so tiles/labels never need a separate identity
      // handshake.
      final uid = myUserId & 0x7FFFFFFF;
      _agoraUid = uid;
      print('[CallStateManager] 🎥 Agora UID (from userId $myUserId): $uid');

      print('[CallStateManager] 🎥 Fetching Agora token for channel=$channel uid=$uid');
      final tokenResp = await CallApi.fetchAgoraToken(channel, uid);
      if (tokenResp == null) {
        print('[CallStateManager] ❌ failed to fetch Agora token');
        lastEndReason = CallEndReason.failed;
        currentState = CallState.failed;
        notifyListeners();
        return;
      }

      final appId = tokenResp['appId'] as String? ?? '';
      final token = tokenResp['token'] as String? ?? '';
      print('[CallStateManager] 🎥 Got token: appId=$appId token length=${token.length}');

      print('[CallStateManager] 🎥 Creating AgoraService instance');
      _agoraService = AgoraService(appId);
      print('[CallStateManager] 🎥 Initializing AgoraService');
      await _agoraService!.initialize();
      print('[CallStateManager] ✅ AgoraService initialized successfully');

      _agoraService!.onRemoteUid.listen((remoteUid) {
        print('[CallStateManager] 👤 Remote user joined: $remoteUid');
        // Do not change CallState here. UI may listen to this stream from the AgoraService.
      });

      // CRITICAL: Listen for remote user leaving - this is a BACKUP mechanism
      // In case CALL_END WebSocket signal doesn't arrive, end the call when Agora detects user left
      _agoraService!.onRemoteUserLeft.listen((remoteUid) {
        print('[CallStateManager] 🔴 ============ REMOTE USER LEFT (Agora backup) ============');
        print('[CallStateManager] 🔴 Remote user $remoteUid left the Agora channel');
        print('[CallStateManager] 🔴 Current state: $currentState');
        
        // Only reset if we're still in a call
        if (currentState == CallState.inCall) {
          print('[CallStateManager] 🔴 Ending call because remote user left');
          reset();
          print('[CallStateManager] 🔴 Call ended via Agora backup mechanism');
        } else {
          print('[CallStateManager] 🔴 Ignoring - not in inCall state');
        }
        print('[CallStateManager] 🔴 ============================================');
      });

      // Refresh the Agora token before it expires and hand it back to the
      // live connection — without this a call silently loses media after
      // the token's 1-hour TTL.
      _tokenExpirySub?.cancel();
      _tokenExpirySub = _agoraService!.onTokenWillExpire.listen((_) async {
        print('[CallStateManager] ⏰ Token expiring — fetching a fresh one');
        try {
          final refreshed = await CallApi.fetchAgoraToken(channel, uid);
          final newToken = refreshed?['token'] as String?;
          if (newToken != null && _agoraService != null) {
            await _agoraService!.renewToken(newToken);
            print('[CallStateManager] ✅ Token renewed');
          }
        } catch (e) {
          print('[CallStateManager] ⚠️ Token renewal failed: $e');
        }
      });

      // Surface network drops as a `reconnecting` state instead of letting
      // the call silently hang; give up and end it after 15s.
      _connectionStateSub?.cancel();
      _connectionStateSub = _agoraService!.onConnectionStateChanged.listen((state) {
        if (state == ConnectionStateType.connectionStateReconnecting ||
            state == ConnectionStateType.connectionStateFailed) {
          if (currentState == CallState.inCall) {
            print('[CallStateManager] 🔌 Connection lost — entering reconnecting state');
            currentState = CallState.reconnecting;
            notifyListeners();
            _reconnectWatchdog?.cancel();
            _reconnectWatchdog = Timer(_reconnectGiveUpDuration, () {
              if (currentState == CallState.reconnecting) {
                print('[CallStateManager] ⏰ Reconnect watchdog expired — ending call');
                endCall(reason: CallEndReason.failed);
              }
            });
          }
        } else if (state == ConnectionStateType.connectionStateConnected) {
          if (currentState == CallState.reconnecting) {
            print('[CallStateManager] ✅ Reconnected');
            _reconnectWatchdog?.cancel();
            currentState = CallState.inCall;
            notifyListeners();
          }
        }
      });

      print('[CallStateManager] 🎥 Joining Agora channel: $channel with token');
      final joinStartTime = DateTime.now();
      await _agoraService!.joinChannel(token: token, channelName: channel, uid: uid, isVideo: isVideo);
      final joinEndTime = DateTime.now();
      final joinDuration = joinEndTime.difference(joinStartTime);
      _agoraJoined = true;
      print('[CallStateManager] ✅ Joined Agora channel successfully in ${joinDuration.inMilliseconds}ms');
      notifyListeners();

      final initEndTime = DateTime.now();
      final totalDuration = initEndTime.difference(initStartTime);
      print('[CallStateManager] ✅ Total Agora init time: ${totalDuration.inMilliseconds}ms');
    } catch (e) {
      print('[CallStateManager] _initAgoraForPayload failed: $e');
      lastEndReason = CallEndReason.failed;
      currentState = CallState.failed;
      notifyListeners();
    }
  }

  Future<void> _cleanupAgora() async {
    _tokenExpirySub?.cancel();
    _tokenExpirySub = null;
    _connectionStateSub?.cancel();
    _connectionStateSub = null;
    _reconnectWatchdog?.cancel();
    _reconnectWatchdog = null;
    try {
      if (_agoraService != null) {
        try {
          await _agoraService!.leaveChannel();
        } catch (_) {}
        try {
          await _agoraService!.dispose();
        } catch (_) {}
      }
    } catch (e) {
      print('[CallStateManager] _cleanupAgora error: $e');
    } finally {
      _agoraService = null;
      _agoraJoined = false;
      _agoraUid = null;
      notifyListeners();
    }
  }
}
