import 'package:flutter/material.dart';
import 'dart:async'; // Add async for delayed future
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import '../../state/call_state_manager.dart';
import '../../services/call_signaling_service.dart';
import '../../services/api_service.dart';
import '../../services/user_profile_cache.dart';
import '../../models/user_profile.dart';
import 'package:social_chat_app/src/theme/colors.dart';

class CallingLoaderScreen extends StatefulWidget {
  final Map<String, dynamic> payload;
  const CallingLoaderScreen({super.key, required this.payload});

  @override
  State<CallingLoaderScreen> createState() => _CallingLoaderScreenState();
}

class _CallingLoaderScreenState extends State<CallingLoaderScreen> {
  UserProfile? _otherUserProfile;
  bool _isEndingCall = false; // Prevent multiple clicks
  String _statusText = ''; // Dynamic status text
  StreamSubscription? _rejectSub;
  StreamSubscription? _acceptSub;
  Timer? _callTimeout;

  @override
  void initState() {
    super.initState();
    _statusText = widget.payload['isVideo'] == true ? 'Calling (video)...' : 'Calling (audio)...';
    _loadUserProfile();
    _startRinging();
    _listenForCallEvents();
    
    // ✅ Start 30s timeout
    print('[CallingLoaderScreen] ⏱️ Starting 30s call timeout');
    _callTimeout = Timer(const Duration(seconds: 30), _handleCallTimeout);
  }

  void _handleCallTimeout() async {
    if (!mounted || _isEndingCall) return;
    print('[CallingLoaderScreen] ⏰ Call TIMED OUT after 30s');
    
    setState(() {
      _statusText = 'No Answer';
    });
    
    FlutterRingtonePlayer().stop();
    _isEndingCall = true; // Prevent double-handling
    
    // Send Cancel/End signal
    final channel = widget.payload['channelName'] as String? ?? '';
    final fromUserId = widget.payload['fromUserId'] as int? ?? 0;
    final toUserId = widget.payload['toUserId'] as int? ?? 0;

    try {
        // No answer within 30s — the receiver missed the call. sendCallReject
        // marks the call MISSED via the real threaded callId internally.
        print('[CallingLoaderScreen] ⏰ Sending TIMEOUT signal...');
        CallSignalingService().sendCallReject(
            fromUserId: fromUserId,
            toUserId: toUserId,
            channelName: channel,
            status: 'MISSED',
        );
    } catch (e) {
        print('[CallingLoaderScreen] ⚠️ Failed to send timeout signal: $e');
    }
    
    // Show 'No Answer' for a moment then close
    await Future.delayed(const Duration(seconds: 2));
    
    if (mounted) {
      CallStateManager().reset();
    }
  }

  void _startRinging() {
    print('[CallingLoaderScreen] 🎵 Starting ringback tone (ASSET)...');
    try {
      FlutterRingtonePlayer().play(
        fromAsset: 'assets/sounds/ringing.mp3',
        ios: IosSounds.glass, // Fallback for iOS if asset fails
        looping: true, 
        volume: 0.5,
      );
    } catch (e) {
      print('[CallingLoaderScreen] ⚠️ Failed to play asset ringtone: $e');
      // Fallback
      FlutterRingtonePlayer().play(
        android: AndroidSounds.ringtone,
        ios: IosSounds.glass,
        looping: true,
      );
    }
  }

  void _listenForCallEvents() {
    // Listen for reject to handle "busy" reason
    _rejectSub = CallSignalingService().onReject.listen((payload) async {
       print('[CallingLoaderScreen] 📵 Received REJECT signal: $payload');
       _callTimeout?.cancel(); // ✅ Cancel timeout on response
       final reason = payload['reason'];
       
       if (reason == 'busy') {
         print('[CallingLoaderScreen] ⚠️ User is BUSY');
         // Stop Ringing
         FlutterRingtonePlayer().stop();
         
         if (mounted) {
           setState(() {
             _statusText = 'User is busy';
           });
         }
         
         // Play Busy Tone
         print('[CallingLoaderScreen] 🎵 Playing BUSY tone');
         // We'll mimic a busy tone by playing a short notification sound repeatedly or just once distinct sound
         // Unfortunately system "busy" tone isn't standard in flutter_ringtone_player
         // We'll use a short beep
         // Play Busy Tone (ASSET)
         print('[CallingLoaderScreen] 🎵 Playing BUSY tone (ASSET)...');
         try {
             FlutterRingtonePlayer().play(
                fromAsset: 'assets/sounds/busy.mp3',
                ios: IosSounds.glass, // Fallback
                looping: false,
                volume: 0.8,
             );
         } catch (e) {
             print('[CallingLoaderScreen] ⚠️ Failed to play busy asset: $e');
         }
         
         // Wait for 3 seconds to let tone play
         await Future.delayed(const Duration(seconds: 3));
         
         // Close screen after showing busy state
         if (mounted) {
           CallStateManager().reset();
         }
       } else {
         // Normal rejection, stop sounds immediately
         FlutterRingtonePlayer().stop();
         if (mounted) CallStateManager().reset(); // Ensure closure on reject
       }
    });
    
    // Listen for accept to stop ringing
    _acceptSub = CallSignalingService().onAccept.listen((_) {
       print('[CallingLoaderScreen] ✅ Call ACCEPTED - stopping ringback');
       _callTimeout?.cancel(); // ✅ Cancel timeout on accept
       FlutterRingtonePlayer().stop();
    });
  }

  Future<void> _loadUserProfile() async {
    try {
      final toUserId = widget.payload['toUserId'] as int? ?? 0;
      
      // 🔥 FIRST: Try to get from cache (instant display)
      final cachedProfile = UserProfileCache().getCachedOnly(toUserId);
      if (cachedProfile != null && mounted) {
        print('[CallingLoaderScreen] ✅ Using CACHED profile for userId=$toUserId: ${cachedProfile.fullName}');
        setState(() {
          _otherUserProfile = cachedProfile;
        });
        // Don't return - also fetch fresh in background
      }
      
      // 🔄 THEN: Fetch from cache (which fetches from API if needed)
      print('[CallingLoaderScreen] 🔄 Fetching fresh profile for userId=$toUserId');
      final profile = await UserProfileCache().getProfile(toUserId);
      if (profile != null && mounted) {
        setState(() {
          _otherUserProfile = profile;
        });
      }
    } catch (e) {
      print('[CallingLoaderScreen] ❌ Failed to load user profile: $e');
    }
  }

  @override
  void dispose() {
    print('[CallingLoaderScreen] 🧹 Dispose - stopping sounds');
    _callTimeout?.cancel(); // ✅ Safety cancel
    FlutterRingtonePlayer().stop();
    _rejectSub?.cancel();
    _acceptSub?.cancel();
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
    final channel = widget.payload['channelName'] as String? ?? '';
    final isVideo = widget.payload['isVideo'] as bool? ?? true;
    final fromUserId = widget.payload['fromUserId'] as int? ?? 0;
    final toUserId = widget.payload['toUserId'] as int? ?? 0;
    
    final userName = _otherUserProfile?.fullName ?? 'User $toUserId';
    final userInitials = _getInitials(userName);

    return WillPopScope(
      onWillPop: () async {
        // Handle back button - minimize call instead of ending
        print('[CallingLoaderScreen] 📱 Back pressed - minimizing call');
        CallStateManager().setMinimized(true);
        Navigator.of(context).pop();
        return false;
      },
      child: Scaffold(
        body: Stack(
          children: [
            Container(
              width: double.infinity,
              height: double.infinity,
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              
              // User avatar (static, no animation)
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
                        backgroundImage: NetworkImage(_otherUserProfile!.profilePictureUrl!),
                      )
                    : CircleAvatar(
                        radius: 70,
                        backgroundColor: theme.colorScheme.primary,
                        child: Text(
                          userInitials,
                          style: const TextStyle(fontSize: 48, color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
              ),
              
              const SizedBox(height: 40),
              
              // User name
              Text(
                userName,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onBackground,
                ),
              ),
              
              const SizedBox(height: 12),
              
              // Calling status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_statusText.contains('Calling')) // Only show spinner if calling
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                        ),
                      ),
                    if (_statusText.contains('Calling')) const SizedBox(width: 8),
                    Text(
                      _statusText,
                      style: TextStyle(
                        fontSize: 14,
                        color: _statusText.contains('busy') ? AppColors.danger : theme.colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              
              const Spacer(flex: 3),
              
              // End call button
              Padding(
                padding: const EdgeInsets.only(bottom: 60),
                child: GestureDetector(
                  onTap: () async {
                    // CRITICAL: Prevent multiple clicks
                    if (_isEndingCall) {
                      print('[CallingLoaderScreen] ⚠️ End call already in progress, ignoring');
                      return;
                    }
                    _isEndingCall = true;
                    
                    // Stop sounds immediately on manual end
                    FlutterRingtonePlayer().stop();

                    final channel = widget.payload['channelName'] as String? ?? '';
                    final fromUserId = widget.payload['fromUserId'] as int? ?? 0;
                    final toUserId = widget.payload['toUserId'] as int? ?? 0;
                    
                    print('[CallingLoaderScreen] 🔴 ============ END BUTTON PRESSED ============');
                    
                    // Send CALL_REJECT immediately (don't await) — the
                    // caller backing out before anyone answered is a
                    // cancellation, not a decline. sendCallReject marks the
                    // call CANCELED via the real threaded callId internally.
                    try {
                      print('[CallingLoaderScreen] 🔴 Sending CALL_REJECT signal...');
                      CallSignalingService().sendCallReject(
                        fromUserId: fromUserId,
                        toUserId: toUserId,
                        channelName: channel,
                        status: 'CANCELED',
                      );
                    } catch (e) {
                      print('[CallingLoaderScreen] ⚠️ Failed to send reject signal: $e');
                    }

                    // Reset state IMMEDIATELY to close the screen
                    try {
                      print('[CallingLoaderScreen] 🔴 Calling reset() IMMEDIATELY...');
                      CallStateManager().reset();
                    } catch (e) {
                      print('[CallingLoaderScreen] ⚠️ Failed to reset: $e');
                    }
                    print('[CallingLoaderScreen] 🔴 ============ END BUTTON COMPLETE ============');
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
                    print('[CallingLoaderScreen] 📱 Minimize button pressed');
                    CallStateManager().setMinimized(true);
                    Navigator.of(context).pop();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                      // shape: BoxShape.circle, // Duplicate line removed (commented out) 
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
      ),
    );
  }
}
