import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';

import '../services/agora_service.dart';
import '../services/api_service.dart';
import '../services/call_api.dart';

/// Group call state — deliberately separate from [CallStateManager]. 1:1
/// calling has a lot of carefully-sequenced, battle-tested state machinery
/// (minimize/replace-screen edge cases, foreground notifications, etc.);
/// rather than risk destabilizing it, group calling gets its own small,
/// self-contained state machine that reuses the same WebSocket channel,
/// Agora token endpoint, and call-log endpoint. Outbound/inbound signaling
/// lives in [GroupCallSignalingService], which drives this class — mirrors
/// how CallSignalingService drives CallStateManager.
enum GroupCallState { idle, incomingRinging, inCall }

const _reconnectGiveUpDuration = Duration(seconds: 15);

class GroupCallStateManager extends ChangeNotifier {
  static final GroupCallStateManager _instance = GroupCallStateManager._internal();
  factory GroupCallStateManager() => _instance;
  GroupCallStateManager._internal();

  GroupCallState currentState = GroupCallState.idle;
  int? groupId;
  String? groupName;
  String? channelName;

  /// The backend CallLog id for this call — threaded through so join/leave
  /// REST calls and signaling don't need to guess which row they refer to.
  int? activeCallId;

  bool isVideo = false;
  int? callerId;
  String? callerName;
  bool isMinimized = false;

  /// True while Agora reports the connection as dropped/reconnecting — see
  /// [_reconnectGiveUpDuration] for the give-up watchdog.
  bool isReconnecting = false;

  AgoraService? _agoraService;
  AgoraService? get agoraService => _agoraService;
  int? _agoraUid;
  int? get agoraUid => _agoraUid;

  StreamSubscription? _connectionStateSub;
  Timer? _reconnectWatchdog;

  /// Fires when another participant leaves an active call (informational
  /// roster update — the call keeps running for everyone else).
  final StreamController<void> _rosterUpdateController = StreamController.broadcast();
  Stream<void> get onRosterUpdate => _rosterUpdateController.stream;

  void setMinimized(bool minimized) {
    isMinimized = minimized;
    notifyListeners();
  }

  /// Joins Agora for a call the local user is the "caller" side of — either
  /// a brand-new call, or an already-active one being joined silently
  /// ("join later" — see GroupCallSignalingService.startGroupCall, which
  /// decides which and passes the right channelName/callId either way).
  Future<bool> joinAsCaller({
    required int groupId,
    required String groupName,
    required String channelName,
    required bool isVideo,
    int? callId,
  }) async {
    if (currentState != GroupCallState.idle) return false;

    final joined = await _joinAgora(channelName, isVideo);
    if (!joined) return false;

    this.groupId = groupId;
    this.groupName = groupName;
    this.channelName = channelName;
    this.isVideo = isVideo;
    activeCallId = callId;
    currentState = GroupCallState.inCall;
    notifyListeners();
    return true;
  }

  /// Recipient flow: another member's invite arrived.
  void setIncoming({
    required int groupId,
    required String groupName,
    required String channelName,
    required bool isVideo,
    required int callerId,
    String? callerName,
    int? callId,
  }) {
    if (currentState != GroupCallState.idle) return;
    this.groupId = groupId;
    this.groupName = groupName;
    this.channelName = channelName;
    this.isVideo = isVideo;
    this.callerId = callerId;
    this.callerName = callerName;
    activeCallId = callId;
    currentState = GroupCallState.incomingRinging;
    notifyListeners();
  }

  Future<bool> acceptIncoming() async {
    if (currentState != GroupCallState.incomingRinging || channelName == null) return false;
    final joined = await _joinAgora(channelName!, isVideo);
    if (!joined) {
      reset();
      return false;
    }
    currentState = GroupCallState.inCall;
    notifyListeners();
    return true;
  }

  Future<void> leaveAgora() async {
    _connectionStateSub?.cancel();
    _connectionStateSub = null;
    _reconnectWatchdog?.cancel();
    _reconnectWatchdog = null;
    await _agoraService?.dispose();
    _agoraService = null;
  }

  /// Caller cancelled an unanswered invite (GROUP_CALL_CANCEL received while
  /// we're still ringing) — closes our incoming-call screen.
  void handleRemoteCancel(int forGroupId) {
    if (currentState == GroupCallState.incomingRinging && groupId == forGroupId) {
      reset();
    }
  }

  /// Another participant left an active call (GROUP_CALL_LEAVE) — purely a
  /// roster update; the call keeps running for us.
  void handleRemoteLeave(int forGroupId) {
    if (currentState == GroupCallState.inCall && groupId == forGroupId) {
      _rosterUpdateController.add(null);
    }
  }

  void reset() {
    _connectionStateSub?.cancel();
    _connectionStateSub = null;
    _reconnectWatchdog?.cancel();
    _reconnectWatchdog = null;
    currentState = GroupCallState.idle;
    groupId = null;
    groupName = null;
    channelName = null;
    activeCallId = null;
    callerId = null;
    callerName = null;
    isMinimized = false;
    isReconnecting = false;
    notifyListeners();
  }

  Future<bool> _joinAgora(String channel, bool isVideo) async {
    final perms = <Permission>[Permission.microphone, if (isVideo) Permission.camera];
    for (final p in perms) {
      final status = await p.request();
      if (!status.isGranted) {
        print('[GroupCallStateManager] ❌ permission denied: $p');
        return false;
      }
    }

    final myUserId = await ApiService.getUserId() ?? 0;
    // Deterministic uid derived from userId (not a timestamp) — a remote
    // uid *is* the remote userId, so tiles resolve real names/avatars via
    // UserProfileCache with no separate identity handshake, and the uid
    // stays stable across reconnects.
    final uid = myUserId & 0x7FFFFFFF;
    _agoraUid = uid;

    final tokenResp = await CallApi.fetchAgoraToken(channel, uid);
    if (tokenResp == null) {
      print('[GroupCallStateManager] ❌ failed to fetch Agora token');
      return false;
    }

    final appId = tokenResp['appId'] as String? ?? '';
    final token = tokenResp['token'] as String? ?? '';
    _agoraService = AgoraService(appId);
    await _agoraService!.initialize();
    await _agoraService!.joinChannel(
      token: token,
      channelName: channel,
      uid: uid,
      isVideo: isVideo,
    );

    _connectionStateSub?.cancel();
    _connectionStateSub = _agoraService!.onConnectionStateChanged.listen((state) {
      if (state == ConnectionStateType.connectionStateReconnecting ||
          state == ConnectionStateType.connectionStateFailed) {
        if (currentState == GroupCallState.inCall && !isReconnecting) {
          print('[GroupCallStateManager] 🔌 Connection lost — entering reconnecting state');
          isReconnecting = true;
          notifyListeners();
          _reconnectWatchdog?.cancel();
          _reconnectWatchdog = Timer(_reconnectGiveUpDuration, () {
            if (isReconnecting) {
              print('[GroupCallStateManager] ⏰ Reconnect watchdog expired — leaving call');
              leaveAgora();
              reset();
            }
          });
        }
      } else if (state == ConnectionStateType.connectionStateConnected) {
        if (isReconnecting) {
          print('[GroupCallStateManager] ✅ Reconnected');
          isReconnecting = false;
          _reconnectWatchdog?.cancel();
          notifyListeners();
        }
      }
    });

    return true;
  }
}
