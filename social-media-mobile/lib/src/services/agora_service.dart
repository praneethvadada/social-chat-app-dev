import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';

/// Minimal Agora wrapper aligned with the official Flutter audio quickstart.
class AgoraService {
  AgoraService(this.appId);

  final String appId;
  RtcEngine? _engine;
  RtcEngine? get engine => _engine;

  /// Set by [joinChannel] — used by the token-refresh flow to know which
  /// channel/uid to fetch a fresh token for.
  String? channelName;
  int? uid;

  /// Store the last known remote user ID so new screens can retrieve it
  int _lastRemoteUid = 0;
  int get lastRemoteUid => _lastRemoteUid;

  final StreamController<int> _remoteUidController =
      StreamController.broadcast();
  Stream<int> get onRemoteUid => _remoteUidController.stream;

  /// Full set of currently-joined remote uids — group calls can have more
  /// than one, unlike the single-uid API above which 1:1 screens use.
  final Set<int> _remoteUids = {};
  Set<int> get remoteUids => Set.unmodifiable(_remoteUids);

  final StreamController<Set<int>> _remoteUidsController =
      StreamController.broadcast();
  Stream<Set<int>> get onRemoteUidsChanged => _remoteUidsController.stream;

  final StreamController<bool> _remoteVideoMutedController =
      StreamController.broadcast();
  Stream<bool> get onRemoteVideoMuted => _remoteVideoMutedController.stream;

  // NEW: Stream to notify when remote user leaves the call
  final StreamController<int> _remoteUserLeftController =
      StreamController.broadcast();
  Stream<int> get onRemoteUserLeft => _remoteUserLeftController.stream;

  /// Uid of the loudest currently-speaking participant (local or remote),
  /// or null when nobody's speaking above the volume threshold.
  final StreamController<int?> _activeSpeakerController =
      StreamController.broadcast();
  Stream<int?> get onActiveSpeaker => _activeSpeakerController.stream;

  /// Fires when the Agora token is about to expire (or already has) — the
  /// listener should fetch a fresh token and call [renewToken].
  final StreamController<void> _tokenWillExpireController =
      StreamController.broadcast();
  Stream<void> get onTokenWillExpire => _tokenWillExpireController.stream;

  final StreamController<ConnectionStateType> _connectionStateController =
      StreamController.broadcast();
  Stream<ConnectionStateType> get onConnectionStateChanged =>
      _connectionStateController.stream;

  Future<void> initialize() async {
    if (_engine != null) return;

    _engine = createAgoraRtcEngine();
    await _engine!.initialize(RtcEngineContext(appId: appId));

    await _engine!.setChannelProfile(
      ChannelProfileType.channelProfileCommunication,
    );
    await _engine!.setAudioProfile(
      profile: AudioProfileType.audioProfileSpeechStandard,
      scenario: AudioScenarioType.audioScenarioDefault,
    );
    // Reports per-speaker volume every 300ms — drives active-speaker
    // highlighting in group calls (and is harmless/unused for 1:1).
    await _engine!.enableAudioVolumeIndication(
      interval: 300,
      smooth: 3,
      reportVad: false,
    );

    _engine!.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (connection, elapsed) {
          print('[AgoraService] onJoinChannelSuccess channel=${connection.channelId} uid=${connection.localUid}');
        },
        onUserJoined: (connection, remoteUid, elapsed) {
          print('[AgoraService] onUserJoined uid=$remoteUid');
          _lastRemoteUid = remoteUid;  // Store for later retrieval
          _remoteUidController.add(remoteUid);
          _remoteUids.add(remoteUid);
          _remoteUidsController.add(Set.unmodifiable(_remoteUids));
        },
        onUserOffline: (connection, remoteUid, reason) {
          print('[AgoraService] onUserOffline uid=$remoteUid reason=$reason');
          _lastRemoteUid = 0;  // Clear stored UID
          _remoteUidController.add(0);
          _remoteUids.remove(remoteUid);
          _remoteUidsController.add(Set.unmodifiable(_remoteUids));

          // CRITICAL: Notify that remote user has left - this is a backup for CALL_END
          // If the WebSocket signal doesn't arrive, this will still end the call
          if (reason == UserOfflineReasonType.userOfflineQuit ||
              reason == UserOfflineReasonType.userOfflineDropped) {
            print('[AgoraService] 🔴 Remote user LEFT the call - emitting onRemoteUserLeft');
            _remoteUserLeftController.add(remoteUid);
          }
        },
        onRemoteVideoStateChanged: (
          connection,
          remoteUid,
          RemoteVideoState state,
          RemoteVideoStateReason reason,
          int elapsed,
        ) {
          final muted = state == RemoteVideoState.remoteVideoStateStopped ||
              reason == RemoteVideoStateReason.remoteVideoStateReasonLocalMuted ||
              reason == RemoteVideoStateReason.remoteVideoStateReasonRemoteMuted;
          print('[AgoraService] onRemoteVideoStateChanged uid=$remoteUid state=$state reason=$reason muted=$muted');
          _remoteVideoMutedController.add(muted);
        },
        onAudioVolumeIndication: (connection, speakers, speakerNumber, totalVolume) {
          if (speakers.isEmpty) return;
          // speakers[].uid == 0 means the local user in Agora's callback.
          AudioVolumeInfo? loudest;
          for (final s in speakers) {
            if (loudest == null || (s.volume ?? 0) > (loudest.volume ?? 0)) {
              loudest = s;
            }
          }
          final loudestVolume = loudest?.volume ?? 0;
          if (loudestVolume < 5) {
            _activeSpeakerController.add(null);
          } else {
            final speakerUid = (loudest!.uid == 0) ? uid : loudest.uid;
            _activeSpeakerController.add(speakerUid);
          }
        },
        onTokenPrivilegeWillExpire: (connection, token) {
          print('[AgoraService] ⏰ onTokenPrivilegeWillExpire');
          _tokenWillExpireController.add(null);
        },
        onRequestToken: (connection) {
          print('[AgoraService] ⏰ onRequestToken (token already expired)');
          _tokenWillExpireController.add(null);
        },
        onConnectionStateChanged: (connection, state, reason) {
          print('[AgoraService] 🔌 onConnectionStateChanged state=$state reason=$reason');
          _connectionStateController.add(state);
        },
        onError: (err, msg) {
          print('[AgoraService] onError code=$err msg=$msg');
        },
      ),
    );
  }

  Future<void> joinChannel({
    required String token,
    required String channelName,
    required int uid,
    bool isVideo = false,
  }) async {
    if (_engine == null) await initialize();

    print('[AgoraService] joinChannel channel=$channelName uid=$uid isVideo=$isVideo');
    this.channelName = channelName;
    this.uid = uid;

    await _engine!.enableAudio();
    if (isVideo) {
      await _engine!.enableVideo();
      await _engine!.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
      await _engine!.setVideoEncoderConfiguration(
        const VideoEncoderConfiguration(
          dimensions: VideoDimensions(width: 640, height: 360),
          frameRate: 15,
          bitrate: 0,
        ),
      );
      await _engine!.startPreview();
    } else {
      await _engine!.disableVideo();
    }

    await _engine!.joinChannel(
      token: token,
      channelId: channelName,
      uid: uid,
      options: ChannelMediaOptions(
        autoSubscribeAudio: true,
        autoSubscribeVideo: isVideo,
        publishCameraTrack: isVideo,
        publishMicrophoneTrack: true,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
      ),
    );
  }

  Future<void> leaveChannel() async {
    if (_engine == null) return;
    await _engine!.leaveChannel();
    _remoteUids.clear();
  }

  Future<void> dispose() async {
    await leaveChannel();
    await _remoteUidController.close();
    await _remoteUidsController.close();
    await _remoteVideoMutedController.close();
    await _remoteUserLeftController.close();
    await _activeSpeakerController.close();
    await _tokenWillExpireController.close();
    await _connectionStateController.close();
    if (_engine != null) {
      await _engine!.release();
      _engine = null;
    }
  }

  // Convenience helpers
  Future<void> muteLocalAudio(bool mute) async {
    if (_engine != null) {
      await _engine!.muteLocalAudioStream(mute);
    }
  }

  Future<void> switchCamera() async {
    if (_engine != null) {
      await _engine!.switchCamera();
    }
  }

  /// Enables/disables the local camera track — stops publishing (not just
  /// muting) so the remote side sees video as fully off, matching the
  /// behavior both call screens' "video off" toggle relies on.
  Future<void> setLocalVideoEnabled(bool enabled) async {
    if (_engine == null) return;
    await _engine!.muteLocalVideoStream(!enabled);
    await _engine!.enableLocalVideo(enabled);
  }

  /// Applies a freshly-fetched token to the already-joined channel, in
  /// response to [onTokenWillExpire]. Does not rejoin — Agora swaps the
  /// token on the live connection.
  Future<void> renewToken(String token) async {
    if (_engine == null) return;
    await _engine!.renewToken(token);
  }
}
