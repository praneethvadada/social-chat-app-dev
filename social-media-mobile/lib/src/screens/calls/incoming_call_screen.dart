import 'package:flutter/material.dart';
import 'dart:async';
import '../../services/call_signaling_service.dart';
import '../../state/call_state_manager.dart';
import '../../screens/call_screen.dart';
import '../../services/api_service.dart';
import '../../services/user_profile_cache.dart';
import '../../services/call_notification_platform.dart';
import '../../models/user_profile.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:social_chat_app/src/theme/colors.dart';

class IncomingCallScreen extends StatefulWidget {
  final Map<String, dynamic> payload;

  const IncomingCallScreen({super.key, required this.payload});

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with SingleTickerProviderStateMixin {
  int _myUserId = 0;
  late AnimationController _rippleController;
  UserProfile? _callerProfile;
  bool _isAccepting = false; // Prevent multiple Accept clicks
  bool _isRejecting = false; // Prevent multiple Reject clicks

  Timer? _pickupTimeout;
  StreamSubscription? _cancelSub;

  @override
  void initState() {
    super.initState();
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    // play ringtone
    // FlutterRingtonePlayer().playRingtone(looping: true, volume: 1.0); // REMOVED: Native service handles ringtone
    ApiService.getUserId().then((id) {
      setState(() => _myUserId = id ?? 0);
    }).catchError((_) {});

    _loadCallerProfile();
    _listenForCancel();
    
    // ✅ Start 30s timeout for incoming call (auto-decline if missed)
    print('[IncomingCallScreen] ⏱️ Starting 30s pickup timeout');
    _pickupTimeout = Timer(const Duration(seconds: 30), _handlePickupTimeout);
  }

  void _listenForCancel() {
    // Listen for sender cancelling the call
    _cancelSub = CallSignalingService().onReject.listen((payload) {
       // 'Reject' from other side means Cancel if we are in Incoming state
       print('[IncomingCallScreen] 📵 Received REJECT/CANCEL signal from sender');
       _pickupTimeout?.cancel();
       if (mounted) {
         CallStateManager().reset();
       }
    });
  }

  void _handlePickupTimeout() async {
    if (!mounted || _isRejecting || _isAccepting) return;
    print('[IncomingCallScreen] ⏰ Incoming call TIMED OUT after 30s');
    
    _isRejecting = true; // Prevent user interaction
    FlutterRingtonePlayer().stop();
    await CallNotificationPlatform.stopCallNotification();

    final fromUserId = widget.payload['fromUserId'] as int? ?? 0;
    final channel = widget.payload['channelName'] as String? ?? '';
    final myId = _myUserId != 0 ? _myUserId : await ApiService.getUserId();

    // Send Reject signal — sendCallReject marks the call MISSED via the
    // real threaded callId (CallStateManager().activeCallId) internally.
    try {
        print('[IncomingCallScreen] ⏰ Sending TIMEOUT (Reject) signal...');
        CallSignalingService().sendCallReject(
            fromUserId: myId ?? 0,
            toUserId: fromUserId,
            channelName: channel,
            status: 'MISSED',
        );
    } catch (e) {
        print('[IncomingCallScreen] ⚠️ Failed to handle timeout: $e');
    }

    if (mounted) {
      CallStateManager().reset();
    }
  }

  Future<void> _loadCallerProfile() async {
    try {
      final fromUserId = widget.payload['fromUserId'] as int? ?? 0;

      // 🔥 FIRST: Try to get from cache (instant display)
      final cachedProfile = UserProfileCache().getCachedOnly(fromUserId);
      if (cachedProfile != null && mounted) {
        print(
            '[IncomingCallScreen] ✅ Using CACHED profile for caller userId=$fromUserId: ${cachedProfile.fullName}');
        setState(() {
          _callerProfile = cachedProfile;
        });
        // Don't return - also fetch fresh in background
      }

      // 🔄 THEN: Fetch from cache (which fetches from API if needed)
      print(
          '[IncomingCallScreen] 🔄 Fetching fresh profile for caller userId=$fromUserId');
      final profile = await UserProfileCache().getProfile(fromUserId);
      if (profile != null && mounted) {
        setState(() {
          _callerProfile = profile;
        });
      }
    } catch (e) {
      print('[IncomingCallScreen] ❌ Failed to load caller profile: $e');
    }
  }

  @override
  void dispose() {
    _rippleController.dispose();
    _pickupTimeout?.cancel(); // ✅ Cancel timeout
    _cancelSub?.cancel();
    // FlutterRingtonePlayer().stop();
    super.dispose();
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final payload = widget.payload;
    final fromUserId = payload['fromUserId'] as int? ?? 0;
    final channel = payload['channelName'] as String? ?? '';
    final isVideo = payload['isVideo'] as bool? ?? true;

    final callerName = _callerProfile?.fullName ?? 'User $fromUserId';
    final callerInitials = _getInitials(callerName);

    return Scaffold(
      body: Stack(
        children: [
          Container(
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
            child: SafeArea(
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
                                color: theme.colorScheme.primary.withOpacity(
                                    0.3 - (_rippleController.value * 0.3)),
                                width: 2,
                              ),
                            ),
                          );
                        },
                      ),

                      // Caller avatar
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
                        child: _callerProfile?.profilePictureUrl != null
                            ? CircleAvatar(
                                radius: 70,
                                backgroundImage: NetworkImage(
                                    _callerProfile!.profilePictureUrl!),
                              )
                            : CircleAvatar(
                                radius: 70,
                                backgroundColor: theme.colorScheme.primary,
                                child: Text(
                                  callerInitials,
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

                  // Caller name
                  Text(
                    callerName,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onBackground,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Incoming call badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Incoming ${isVideo ? 'video' : 'audio'} call...',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

                  const Spacer(flex: 3),

                  // Action buttons
                  Padding(
                    padding: const EdgeInsets.only(bottom: 60),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Decline button
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: () async {
                                // CRITICAL: Prevent multiple clicks
                                if (_isRejecting) {
                                  print(
                                      '[IncomingCallScreen] ⚠️ Reject already in progress, ignoring');
                                  return;
                                }
                                _isRejecting = true;

                                FlutterRingtonePlayer().stop();
                                
                                // 🔔 BUG FIX #2: Remove foreground notification when declining via UI
                                print('[IncomingCallScreen] 🔔 Removing foreground notification on decline');
                                await CallNotificationPlatform.stopCallNotification();
                                
                                final myId = _myUserId != 0
                                    ? _myUserId
                                    : await ApiService.getUserId();

                                print(
                                    '[IncomingCallScreen] ❌ Reject button pressed - rejecting call');

                                // Send CALL_REJECT signal — this marks the
                                // call DECLINED via the real threaded callId
                                // (CallStateManager().activeCallId) internally.
                                CallSignalingService().sendCallReject(
                                    fromUserId: myId ?? 0,
                                    toUserId: fromUserId,
                                    channelName: channel);

                                // Reset to idle state so user can make new calls immediately
                                print(
                                    '[IncomingCallScreen] 🔄 Resetting call state to IDLE');
                                try {
                                  CallStateManager().reset();
                                } catch (e) {
                                  print(
                                      '[IncomingCallScreen] ⚠️ Error resetting call state: $e');
                                }

                                // Pop the screen - REMOVED: Managed by CallOverlayManager
                                // if (context.mounted) {
                                //   Navigator.of(context).pop();
                                // }
                              },
                              child: Container(
                                width: 70,
                                height: 70,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.danger,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.red.withOpacity(0.4),
                                      blurRadius: 15,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.call_end,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Decline',
                              style: TextStyle(
                                fontSize: 14,
                                color: theme.colorScheme.onBackground
                                    .withOpacity(0.7),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),

                        // Accept button
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: () async {
                                // CRITICAL: Prevent multiple clicks
                                if (_isAccepting) {
                                  print(
                                      '[IncomingCallScreen] ⚠️ Accept already in progress, ignoring');
                                  return;
                                }
                                _isAccepting = true;

                                print(
                                    '\n\n===== [IncomingCallScreen] ACCEPT BUTTON PRESSED =====');
                                print(
                                    '[IncomingCallScreen] 🟢 Current state: ${CallStateManager().currentState}');

                                // Double-check we're still in incomingRinging state
                                if (CallStateManager().currentState !=
                                    CallState.incomingRinging) {
                                  print(
                                      '[IncomingCallScreen] ⚠️ State is not incomingRinging, aborting accept');
                                  _isAccepting = false;
                                  return;
                                }

                                FlutterRingtonePlayer().stop();
                                
                                // 🔔 BUG FIX #2: Remove foreground notification when accepting via UI
                                print('[IncomingCallScreen] 🔔 Removing foreground notification on accept');
                                await CallNotificationPlatform.stopCallNotification();
                                
                                // 📱 BUG FIX #3: Show background call notification immediately  
                                print('[IncomingCallScreen] 📱 Showing background call notification immediately');
                                final callerName = _callerProfile?.fullName ?? 'User $fromUserId';
                                await CallNotificationPlatform.showBackgroundCallNotification(
                                  callerName: callerName,
                                  channelName: channel,
                                );
                                
                                final myId = _myUserId != 0
                                    ? _myUserId
                                    : await ApiService.getUserId();
                                print(
                                    '[IncomingCallScreen] 🟢 myId=$myId fromUserId=$fromUserId channel=$channel');

                                // FIRST: Update state to inCall BEFORE sending signal
                                // This ensures we're in inCall state before any echoes come back
                                try {
                                  print(
                                      '[IncomingCallScreen] ✅ Setting state to inCall FIRST');
                                  // 🔴 BUG FIX: Mark that call was accepted from notification
                                  final payloadWithFlag = {...?widget.payload};
                                  payloadWithFlag['fromNotification'] = true;
                                  CallStateManager().setInCall(payloadWithFlag);
                                  print(
                                      '[IncomingCallScreen] ✅ State is now: ${CallStateManager().currentState}');
                                } catch (e) {
                                  print(
                                      '[IncomingCallScreen] ❌ setInCall error: $e');
                                  _isAccepting = false;
                                  return;
                                }

                                // THEN: Send accept signal to backend —
                                // sendCallAccept marks the call ACCEPTED via
                                // the real threaded callId internally.
                                print(
                                    '[IncomingCallScreen] ✅ Sending sendCallAccept');
                                CallSignalingService().sendCallAccept(
                                    fromUserId: myId ?? 0,
                                    toUserId: fromUserId,
                                    channelName: channel,
                                    isVideo: isVideo);
                                print('[IncomingCallScreen] ✅ Accept complete');
                              },
                              child: Container(
                                width: 70,
                                height: 70,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.primary,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.green.withOpacity(0.4),
                                      blurRadius: 15,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.call,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Accept',
                              style: TextStyle(
                                fontSize: 14,
                                color: theme.colorScheme.onBackground
                                    .withOpacity(0.7),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Minimize button at top left
          Positioned(
            top: 16,
            left: 16,
            child: SafeArea(
              child: GestureDetector(
                onTap: () {
                  print('[IncomingCallScreen] 📱 Minimize button pressed');
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
      ),
    );
  }
}
