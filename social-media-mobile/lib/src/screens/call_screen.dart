import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'dart:io';

import '../services/agora_service.dart';
import '../services/call_api.dart';
import '../services/call_signaling_service.dart';
import '../services/api_service.dart';
import '../services/user_profile_cache.dart';
import '../services/call_notification_platform.dart';
import '../state/call_state_manager.dart';
import '../models/user_profile.dart';
import 'dart:async';
import 'package:social_chat_app/src/theme/colors.dart';

class CallScreen extends StatefulWidget {
  final String channelName;
  final int otherUserId;
  final bool isVideo;
  final bool fromNotification; // Track if opened from notification

  const CallScreen(
      {super.key,
      required this.channelName,
      required this.otherUserId,
      this.isVideo = true,
      this.fromNotification = false}); // Default to false for normal navigation

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with SingleTickerProviderStateMixin {

  Future<void> _toggleSpeaker() async {
    if (_agoraService?.engine != null) {
      setState(() => _speakerOn = !_speakerOn);
      await _agoraService!.engine!.setEnableSpeakerphone(_speakerOn);
    }
  }
  AgoraService? _agoraService;
  int _remoteUid = 0;
  late AnimationController _rippleController;
  bool _isIncomingCall = true; // Track if showing incoming call screen
  bool _joined = false;
  bool _muted = false;
  bool _videoOff = false;
  bool _remoteVideoMuted = false;
  bool _speakerOn = true;
  bool _switchingCamera = false;
  bool _showLocalPrimary = false;
  bool _isEndingCall = false; // Prevent multiple end call clicks
  String? _errorMsg;
  Stopwatch? _callTimer;
  late final ValueNotifier<Duration> _callDuration;
  DateTime? _callStartTime;
  StreamSubscription<Map<String, dynamic>>? _endSub;
  StreamSubscription<Map<String, dynamic>>? _acceptSub;
  StreamSubscription<Map<String, dynamic>>? _rejectSub;
  int _myUserId = 0;
  int _callerId = 0;
  int _calleeId = 0;
  VoidCallback? _cmListener;
  UserProfile? _otherUserProfile;

  @override
  void initState() {
    super.initState();
    print('\n\n===== [CallScreen] CONSTRUCTOR/INIT CALLED =====');
    print('[CallScreen] 📱 channelName: ${widget.channelName}');
    print('[CallScreen] 📱 otherUserId: ${widget.otherUserId}');
    print('[CallScreen] 📱 isVideo: ${widget.isVideo}');
    print(
        '[CallScreen] 📱 Current CallState: ${CallStateManager().currentState}');
    print('=============================================\n');

    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    // Get the call start time from CallStateManager (for stable timer)
    _callStartTime = CallStateManager().callStartTime;
    // Initialize _callDuration to correct elapsed time if available
    if (_callStartTime != null) {
      final elapsed = DateTime.now().difference(_callStartTime!);
      _callDuration = ValueNotifier(elapsed);
    } else {
      _callDuration = ValueNotifier(Duration.zero);
    }
    _loadOtherUserProfile();
    
    // Show background call notification on BOTH sender and receiver sides when call is active
    // NOTE: For receiver, this was already called from IncomingCallScreen's Accept button
    // For sender, we call it here to ensure it appears on their side too
    print('[CallScreen] 📱 Ensuring background call notification is visible (active on both sides)');
    CallNotificationPlatform.showBackgroundCallNotification(
      callerName: 'Call in Progress',
      channelName: widget.channelName,
    ).ignore();
    
    _endSub = CallSignalingService().onEnd.listen((payload) {
      final ch = payload['channelName'] as String?;
      if (ch == widget.channelName) {
        print('[CallScreen] 📵 Received CALL_END signal from remote');
        // remote ended: cleanup UI and reset state to idle
        _cleanupAfterRemoteEnd();
        // Ensure state is reset to idle
        try {
          CallStateManager().reset();
        } catch (e) {
          print('[CallScreen] ⚠️ Error resetting state: $e');
        }
      }
    });
    // Determine role (caller vs callee) from channel name: chat_{caller}_{callee}
    ApiService.getUserId().then((id) {
      print('[CallScreen] 🔍 getUserId completed: id=$id');
      _myUserId = id ?? 0;
      try {
        final parts = widget.channelName.split('_');
        if (parts.length >= 3) {
          _callerId = int.tryParse(parts[1]) ?? 0;
          _calleeId = int.tryParse(parts[2]) ?? 0;
        }
      } catch (_) {}

      print(
          '[CallScreen] 🔍 Parsed channel: callerId=$_callerId, calleeId=$_calleeId, myUserId=$_myUserId');

      // Check current call state - if already inCall, don't send CALL_INVITE
      final currentState = CallStateManager().currentState;
      print(
          '[CallScreen] 🎬 Current state when determining role: $currentState');

      if (currentState == CallState.inCall) {
        // Already in a call (e.g., accepted incoming call) - don't send CALL_INVITE
        print(
            '[CallScreen] ✅ Already in call (RECEIVER ACCEPTED) - skipping CALL_INVITE');
        print('[CallScreen] ✅ This is NOT a new outgoing call!');
        return;
      }

      if (_myUserId != 0 && _myUserId == _callerId) {
        // I'm the caller: send CALL_INVITE and wait for accept/reject
        print(
            '[CallScreen] 📞 I am the CALLER (initiating new call) - starting caller flow');
        print('[CallScreen] 📞 Sending CALL_INVITE to user $_calleeId');
        _startCallerFlow();
      } else {
        // I'm the callee or unknown: do not start Agora here. Wait for CallState to become `inCall`.
        print(
            '[CallScreen] 📞 I am the CALLEE (received call) - waiting for state to become inCall');
      }
    }).catchError((e) {
      print('[CallScreen] ❌ Error getting userId: $e');
      // Fallback: do nothing; CallStateManager will control Agora lifecycle.
    });

    // Register a listener to CallStateManager so UI can attach to the AgoraService
    try {
      final cm = CallStateManager();
      _cmListener = () {
        if (!mounted) return; // Guard against setState after dispose

        // Monitor state changes specifically for local UI updates (like connection status)
        // Navigation is mainly handled by CallOverlayManager now.
        
        // However, if opened from notification (not via OverlayManager), we might need to handle exit?
        // CallOverlayManager manages the route if it pushed it.
        // If widget.fromNotification is true, CallScreen might be the root or pushed differently.
        
        if (cm.currentState == CallState.idle || cm.currentState == CallState.ended) {
          if (widget.fromNotification) {
             print('[CallScreen] 🛑 Opened from notification & Call Ended - exiting app');
             if (mounted) exit(0);
          }
          return;
        }

        // connecting/reconnecting/failed (and returning from reconnecting to
        // inCall) don't attach a new AgoraService (it's already attached),
        // so they wouldn't otherwise trigger a rebuild — force one so the
        // banner/error UI in build() reflects the change either way.
        if (cm.currentState == CallState.connecting ||
            cm.currentState == CallState.reconnecting ||
            cm.currentState == CallState.failed ||
            cm.currentState == CallState.inCall) {
          setState(() {});
        }

        final nowCmService = cm.agoraService;
        if (_agoraService == null && nowCmService != null) {
          _agoraService = nowCmService;

          // CRITICAL: Initialize _remoteUid from stored value (for screen recreation)
          if (_agoraService!.lastRemoteUid != 0) {
            print(
                '[CallScreen] 🔄 Restoring remote UID from AgoraService: ${_agoraService!.lastRemoteUid}');
            _remoteUid = _agoraService!.lastRemoteUid;
          }

          _agoraService!.onRemoteUid.listen((remoteUid) {
            if (mounted) {
              setState(() => _remoteUid = remoteUid);
            }
          });
          _agoraService!.onRemoteVideoMuted.listen((muted) {
            if (mounted) {
              setState(() => _remoteVideoMuted = muted);
            }
          });
          if (mounted) {
            setState(() {
              _joined = cm.isAgoraJoined;
              _errorMsg = null;
              _isIncomingCall = false; // Switch to in-call screen
            });
          }
          _rippleController.stop(); // Stop animation when call starts
          // Use global callStartTime for stable timer
          _callStartTime = CallStateManager().callStartTime;
          _callTimer = Stopwatch()..start();
          _startTimerTicker();
        }
      };
      cm.addListener(_cmListener!);
      // If already available, attach immediately
      if (cm.agoraService != null) {
        _agoraService = cm.agoraService;

        // CRITICAL: Initialize _remoteUid from stored value (for screen recreation)
        if (_agoraService!.lastRemoteUid != 0) {
          print(
              '[CallScreen] 🔄 Immediately restoring remote UID: ${_agoraService!.lastRemoteUid}');
          _remoteUid = _agoraService!.lastRemoteUid;
        }

        _agoraService!.onRemoteUid.listen((remoteUid) {
          setState(() => _remoteUid = remoteUid);
        });
        _agoraService!.onRemoteVideoMuted.listen((muted) {
          setState(() => _remoteVideoMuted = muted);
        });
        _joined = cm.isAgoraJoined;
        _isIncomingCall = false; // Already in call
        _rippleController.stop(); // Stop animation
        _callStartTime = CallStateManager().callStartTime;
        _callTimer = Stopwatch()..start();
        _startTimerTicker();
      }
    } catch (_) {}
  }

  void _startCallerFlow() {
    print('[CallScreen] 🔔 _startCallerFlow CALLED');
    print(
        '[CallScreen] 🔔 Sending CALL_INVITE: from=$_myUserId to=$_calleeId channel=${widget.channelName}');
    // Send CALL_INVITE
    try {
      CallSignalingService().sendCallInvite(
          fromUserId: _myUserId,
          toUserId: _calleeId,
          channelName: widget.channelName,
          isVideo: widget.isVideo);
      print('[CallScreen] 🔔 CALL_INVITE sent successfully');
    } catch (e) {
      print('[CallScreen] ❌ Failed to send invite: $e');
    }

    // Listen for accept/reject
    _acceptSub = CallSignalingService().onAccept.listen((payload) async {
      print(
          '[CallScreen] onAccept received payload=$payload channel=${widget.channelName}');
      try {
        final ch = payload['channelName'] as String? ?? '';
        if (ch == widget.channelName) {
          // Signaling will update CallStateManager to inCall. Just cancel listeners here.
          _acceptSub?.cancel();
          _rejectSub?.cancel();
        }
      } catch (e) {}
    });

    _rejectSub = CallSignalingService().onReject.listen((payload) {
      print(
          '[CallScreen] onReject received payload=$payload channel=${widget.channelName}');
      try {
        final ch = payload['channelName'] as String? ?? '';
        if (ch == widget.channelName) {
          _acceptSub?.cancel();
          _rejectSub?.cancel();
          // CallStateManager will transition to ended; UI will react via global listener.
        }
      } catch (e) {}
    });
  }

  void _startTimerTicker() {
    Future.doWhile(() async {
      if (_callTimer == null || !_callTimer!.isRunning) return false;
      await Future.delayed(const Duration(seconds: 1));

      // Only update if widget is still mounted and ValueNotifier not disposed
      if (mounted && !_callDuration.hasListeners) {
        // Widget is disposed, stop the timer
        _callTimer?.stop();
        return false;
      }

      if (mounted) {
        try {
          // Always base duration on callStartTime for stability
          final now = DateTime.now();
          if (_callStartTime != null) {
            _callDuration.value = now.difference(_callStartTime!);
          } else {
            _callDuration.value = Duration.zero;
          }
        } catch (e) {
          // ValueNotifier was disposed
          return false;
        }
      }
      return true;
    });
  }

  Future<void> _loadOtherUserProfile() async {
    try {
      // 🔥 FIRST: Try to get from cache (instant display)
      final cachedProfile =
          UserProfileCache().getCachedOnly(widget.otherUserId);
      if (cachedProfile != null && mounted) {
        print(
            '[CallScreen] ✅ Using CACHED profile for userId=${widget.otherUserId}: ${cachedProfile.fullName}');
        setState(() {
          _otherUserProfile = cachedProfile;
        });
        // Don't return - also fetch fresh in background
      } else {
        print(
            '[CallScreen] ❌ No cached profile for userId=${widget.otherUserId}');
      }

      // 🔄 THEN: Fetch from API and update cache (background refresh)
      print(
          '[CallScreen] 🔄 Fetching fresh profile for userId=${widget.otherUserId}');
      final profile = await UserProfileCache().getProfile(widget.otherUserId);
      if (profile != null && mounted) {
        setState(() {
          _otherUserProfile = profile;
        });
      }
    } catch (e) {
      print('[CallScreen] ❌ Failed to load user profile: $e');
    }
  }

  Future<void> _endCall() async {
    // CRITICAL: Prevent multiple clicks
    if (_isEndingCall) {
      print(
          '[CallScreen] ⚠️ End call already in progress, ignoring duplicate click');
      return;
    }
    _isEndingCall = true;

    print('[CallScreen] 🔴 ============ END CALL BUTTON PRESSED ============');
    print('[CallScreen] 🔴 Stopping call timer...');
    _callTimer?.stop();

    // Calculate call duration in seconds
    final durationSeconds = (_callTimer?.elapsedMilliseconds ?? 0) ~/ 1000;
    print('[CallScreen] 🔴 Call duration: $durationSeconds seconds');

    // Send end signal IMMEDIATELY (don't await)
    print(
        '[CallScreen] 🔴 Sending CALL_END signal to user ${widget.otherUserId}');
    try {
      CallSignalingService().sendCallEnd(
          fromUserId: _myUserId,
          toUserId: widget.otherUserId,
          channelName: widget.channelName);
    } catch (e) {
      print('[CallScreen] ❌ Error sending CALL_END: $e');
    }

    // Reset state IMMEDIATELY to close the screen
    print('[CallScreen] 🔴 Calling CallStateManager().reset() IMMEDIATELY...');
    try {
      await CallStateManager().reset();
    } catch (_) {}

    print('[CallScreen] 🔴 Canceling subscriptions...');
    _acceptSub?.cancel();
    _rejectSub?.cancel();
    print('[CallScreen] 🔴 ============ END CALL COMPLETE ============');

    // Update call log in BACKGROUND (don't block UI)
    Future.microtask(() async {
      try {
        print(
            '[CallScreen] 🔴 Updating call log with duration (background)...');
        await CallSignalingService().updateCallEnded(
          fromUserId: _myUserId,
          toUserId: widget.otherUserId,
          channelName: widget.channelName,
          isVideo: widget.isVideo,
          durationSeconds: durationSeconds,
        );
        print('[CallScreen] ✅ Call log updated successfully');
      } catch (e) {
        print('[CallScreen] ⚠️ Failed to update call log: $e');
      }
    });

    // 🔴 BUG FIX: Close app if call was opened from notification
    if (widget.fromNotification) {
      print('[CallScreen] 🔴 Call was from notification - closing app instead of navigating back');
      await Future.delayed(const Duration(milliseconds: 300));
      // Close the entire app
      exit(0);
    }
  }

  // Cleanup when remote signals CALL_END. Do not send signaling back.
  void _cleanupAfterRemoteEnd() {
    print('[CallScreen] 🧹 Cleaning up after remote ended call');
    try {
      _callTimer?.stop();
    } catch (_) {}
    // Agora cleanup will be handled by CallStateManager when state is reset.
    try {
      _acceptSub?.cancel();
      _rejectSub?.cancel();
    } catch (_) {}
  }

  Future<void> _toggleMute() async {
    if (_agoraService?.engine != null) {
      setState(() => _muted = !_muted);
      await _agoraService!.engine!.muteLocalAudioStream(_muted);
    }
  }

  Future<void> _toggleVideo() async {
    if (_agoraService != null) {
      setState(() => _videoOff = !_videoOff);
      await _agoraService!.setLocalVideoEnabled(!_videoOff);
    }
  }

  Future<void> _switchCamera() async {
    if (_agoraService?.engine != null && !_switchingCamera) {
      setState(() => _switchingCamera = true);
      await _agoraService!.engine!.switchCamera();
      setState(() => _switchingCamera = false);
    }
  }

  void _togglePrimary() {
    setState(() => _showLocalPrimary = !_showLocalPrimary);
  }

  Widget _buildPrimaryVideo() {
    final isPrimaryLocal = _showLocalPrimary || _remoteUid == 0;
    if (_agoraService?.engine == null) {
      return const Center(child: Text('Initializing...'));
    }

    if (isPrimaryLocal) {
      return AgoraVideoView(
        controller: VideoViewController(
          rtcEngine: _agoraService!.engine!,
          canvas: const VideoCanvas(uid: 0),
        ),
      );
    }

    if (_remoteUid != 0) {
      return AgoraVideoView(
        controller: VideoViewController.remote(
          rtcEngine: _agoraService!.engine!,
          canvas: VideoCanvas(uid: _remoteUid),
          connection: RtcConnection(channelId: widget.channelName),
        ),
      );
    }

    if (_remoteVideoMuted) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Text(
            'Remote video off',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return const Center(child: Text('Waiting for remote...'));
  }

  Widget _buildSecondaryVideo() {
    final isPrimaryLocal = _showLocalPrimary || _remoteUid == 0;
    if (_agoraService?.engine == null) {
      return Container(color: Colors.black12);
    }

    // Secondary shows the opposite of primary when possible
    if (isPrimaryLocal) {
      // Secondary should be remote view if available, otherwise placeholder
      if (_remoteUid != 0) {
        return AgoraVideoView(
          controller: VideoViewController.remote(
            rtcEngine: _agoraService!.engine!,
            canvas: VideoCanvas(uid: _remoteUid),
            connection: RtcConnection(channelId: widget.channelName),
          ),
        );
      }
      if (_remoteVideoMuted) {
        return Container(
          color: Colors.black,
          child: const Center(
            child: Text(
              'Remote video off',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        );
      }
      return Container(
        color: Colors.black,
        child: const Center(
          child: Text(
            'Waiting...',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      );
    } else {
      // Primary is remote; secondary shows local preview
      return AgoraVideoView(
        controller: VideoViewController(
          rtcEngine: _agoraService!.engine!,
          canvas: const VideoCanvas(uid: 0),
        ),
      );
    }
  }

  @override
  void dispose() {
    _rippleController.dispose();
    _callTimer?.stop();
    _callDuration.dispose();
    
    // Hide background call notification when either side leaves (removes on both sides)
    print('[CallScreen] 📵 Hiding background call notification (removed on both sides)');
    CallNotificationPlatform.hideBackgroundCallNotification().ignore();
    
    // Agora is managed by CallStateManager; only cancel local refs/subscriptions here.
    _endSub?.cancel();
    try {
      final cm = CallStateManager();
      if (_cmListener != null) cm.removeListener(_cmListener!);
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userName =
        _otherUserProfile?.fullName ?? 'User ${widget.otherUserId}';
    final userInitials = _getInitials(userName);
    final cmState = CallStateManager().currentState;
    final isFailed = cmState == CallState.failed;
    final isReconnecting = cmState == CallState.reconnecting;

    return WillPopScope(
      onWillPop: () async {
        // Handle back button - minimize call instead of ending
        final currentState = CallStateManager().currentState;
        if (currentState == CallState.outgoingCalling ||
            currentState == CallState.inCall ||
            currentState == CallState.connecting ||
            currentState == CallState.reconnecting ||
            currentState == CallState.incomingRinging) {
          print('[CallScreen] 📱 Back pressed - minimizing call');
          CallStateManager().setMinimized(true);
          Navigator.of(context).pop(); // Close fullscreen
          return false; // Prevent default back action
        }
        return true; // Allow default back action if not in call
      },
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                theme.colorScheme.primary.withOpacity(0.1),
                theme.scaffoldBackgroundColor,
                theme.scaffoldBackgroundColor,
              ],
            ),
          ),
          child: Stack(
            children: [
              isFailed
                  ? _buildFailedState(theme)
                  : (_errorMsg != null
                      ? Center(
                          child: Text(_errorMsg!,
                              style: const TextStyle(color: AppColors.danger)))
                      : _joined
                          ? _buildInCallScreen(
                              context, userName, userInitials, theme)
                          : Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(
                                      color: theme.colorScheme.primary),
                                  const SizedBox(height: 20),
                                  Text(
                                    'Connecting...',
                                    style: TextStyle(
                                      color: theme.colorScheme.onBackground,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            )),
              if (isReconnecting) _buildReconnectingBanner(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFailedState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: AppColors.danger, size: 48),
            const SizedBox(height: 16),
            Text(
              'Camera and microphone access is needed for calls.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: theme.colorScheme.onBackground, fontSize: 16),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => openAppSettings(),
              icon: const Icon(Icons.settings),
              label: const Text('Open Settings'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => CallStateManager().reset(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReconnectingBanner(ThemeData theme) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Center(
          child: Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                ),
                SizedBox(width: 8),
                Text('Reconnecting…',
                    style: TextStyle(color: Colors.white, fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInCallScreen(BuildContext context, String userName,
      String userInitials, ThemeData theme) {
    return Stack(
      children: [
        Column(
          children: [
            // Timer display
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: ValueListenableBuilder<Duration>(
                  valueListenable: _callDuration,
                  builder: (context, duration, _) {
                    final min = duration.inMinutes
                        .remainder(60)
                        .toString()
                        .padLeft(2, '0');
                    final sec = duration.inSeconds
                        .remainder(60)
                        .toString()
                        .padLeft(2, '0');
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.phone_in_talk,
                              color: AppColors.primary, size: 16),
                          const SizedBox(width: 8),
                          Text('$min:$sec',
                              style: TextStyle(
                                  color: theme.colorScheme.onBackground,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16)),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            Expanded(
              child: widget.isVideo
                  ? Stack(
                      children: [
                        Positioned.fill(child: _buildPrimaryVideo()),
                        Positioned(
                          top: 12,
                          right: 12,
                          child: GestureDetector(
                            onTap: _togglePrimary,
                            child: AbsorbPointer(
                              absorbing: _switchingCamera,
                              child: Container(
                                width: 120,
                                height: 160,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border:
                                      Border.all(color: Colors.white, width: 2),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: _buildSecondaryVideo(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // User avatar
                          _otherUserProfile?.profilePictureUrl != null
                              ? CircleAvatar(
                                  radius: 60,
                                  backgroundImage: NetworkImage(
                                      _otherUserProfile!.profilePictureUrl!),
                                )
                              : CircleAvatar(
                                  radius: 60,
                                  backgroundColor: theme.colorScheme.primary,
                                  child: Text(
                                    userInitials,
                                    style: const TextStyle(
                                        fontSize: 36,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                          const SizedBox(height: 20),
                          Text(
                            userName,
                            style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onBackground),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Audio call',
                            style: TextStyle(
                                fontSize: 16,
                                color: theme.colorScheme.onBackground
                                    .withOpacity(0.6)),
                          ),
                        ],
                      ),
                    ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildControlButton(
                      icon: _muted ? Icons.mic_off : Icons.mic,
                      color: _muted ? AppColors.danger : Colors.white,
                      backgroundColor: _muted
                          ? Colors.red.withOpacity(0.2)
                          : AppColors.border,
                      onPressed: _toggleMute,
                      tooltip: _muted ? 'Unmute' : 'Mute',
                    ),
                    if (!widget.isVideo)
                      _buildControlButton(
                        icon: _speakerOn ? Icons.volume_up : Icons.hearing,
                        color: _speakerOn ? AppColors.primary : AppColors.primary,
                        backgroundColor: _speakerOn
                            ? Colors.green.withOpacity(0.15)
                            : AppColors.primary.withOpacity(0.15),
                        onPressed: _toggleSpeaker,
                        tooltip: _speakerOn ? 'Speaker' : 'Earpiece',
                      ),
                    if (widget.isVideo)
                      _buildControlButton(
                        icon: _videoOff ? Icons.videocam_off : Icons.videocam,
                        color: _videoOff ? AppColors.danger : Colors.white,
                        backgroundColor: _videoOff
                            ? Colors.red.withOpacity(0.2)
                            : AppColors.border,
                        onPressed: _toggleVideo,
                        tooltip: _videoOff ? 'Turn Video On' : 'Turn Video Off',
                      ),
                    if (widget.isVideo)
                      _buildControlButton(
                        icon: Icons.cameraswitch,
                        color: Colors.white,
                        backgroundColor: AppColors.border,
                        onPressed: _switchCamera,
                        tooltip: 'Switch Camera',
                      ),
                    _buildControlButton(
                      icon: Icons.call_end,
                      color: Colors.white,
                      backgroundColor: AppColors.danger,
                      onPressed: _endCall,
                      tooltip: 'End Call',
                      size: 70,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        // Minimize button at top left
        Positioned(
          top: 16,
          left: 16,
          child: SafeArea(
            child: GestureDetector(
              onTap: () {
                print('[CallScreen] 📱 Minimize button pressed');
                CallStateManager().setMinimized(true);
                Navigator.of(context).pop();
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.keyboard_arrow_down,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIncomingCallScreen(BuildContext context, String userName,
      String userInitials, ThemeData theme) {
    return SafeArea(
      child: Column(
        children: [
          const Spacer(flex: 2),
          // Ripple animation around avatar
          Stack(
            alignment: Alignment.center,
            children: [
              // Animated ripples
              AnimatedBuilder(
                animation: _rippleController,
                builder: (context, child) {
                  return Container(
                    width: 200 + (_rippleController.value * 50),
                    height: 200 + (_rippleController.value * 50),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.colorScheme.primary
                            .withOpacity(0.3 - (_rippleController.value * 0.3)),
                        width: 2,
                      ),
                    ),
                  );
                },
              ),
              // User avatar
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: _otherUserProfile?.profilePictureUrl != null
                    ? CircleAvatar(
                        radius: 70,
                        backgroundImage:
                            NetworkImage(_otherUserProfile!.profilePictureUrl!),
                      )
                    : CircleAvatar(
                        radius: 70,
                        backgroundColor: theme.colorScheme.primary,
                        child: Text(
                          userInitials,
                          style: const TextStyle(
                              fontSize: 48,
                              color: Colors.white,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 40),
          // User name
          Text(
            userName,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onBackground,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          // Call type
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              widget.isVideo
                  ? 'Incoming video call...'
                  : 'Incoming audio call...',
              style: TextStyle(
                fontSize: 16,
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Spacer(flex: 3),
          // Accept and Reject buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 40),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Reject button
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.4),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.call_end,
                            color: Colors.white, size: 32),
                        onPressed: _endCall,
                        tooltip: 'Reject',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Decline',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.onBackground.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
                // Accept button
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.green.withOpacity(0.4),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.call,
                            color: Colors.white, size: 32),
                        onPressed: () {
                          // Accept call - this will trigger Agora to start
                          setState(() {});
                        },
                        tooltip: 'Accept',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Accept',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.onBackground.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required Color color,
    required Color backgroundColor,
    required VoidCallback onPressed,
    required String tooltip,
    double size = 60,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: color, size: size * 0.45),
        onPressed: onPressed,
        tooltip: tooltip,
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[parts.length - 1].substring(0, 1))
        .toUpperCase();
  }
}
