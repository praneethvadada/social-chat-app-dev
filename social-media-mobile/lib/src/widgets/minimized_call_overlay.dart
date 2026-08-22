
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import '../models/user_profile.dart';
import '../services/user_profile_cache.dart';
import '../services/call_signaling_service.dart';
import '../state/call_state_manager.dart';
import '../navigation/root_navigator_key.dart';
import '../screens/call_screen.dart';
import 'package:social_chat_app/src/theme/colors.dart';

/// Timer widget for minimized audio call overlay
class _MinimizedCallTimer extends StatefulWidget {
  @override
  State<_MinimizedCallTimer> createState() => _MinimizedCallTimerState();
}

class _MinimizedCallTimerState extends State<_MinimizedCallTimer> {
  late Duration _duration;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _updateDuration();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateDuration());
  }

  void _updateDuration() {
    final start = CallStateManager().callStartTime;
    setState(() {
      _duration = start != null ? DateTime.now().difference(start) : Duration.zero;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final min = _duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = _duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return Text(
      '$min:$sec',
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 13,
      ),
    );
  }
}

/// Builds the minimized call overlay widgets to be added to a Stack
List<Widget> buildMinimizedCallOverlay({
  required BuildContext context,
  required Map<String, dynamic> callPayload,
  required bool isVideo,
}) {
  final callState = CallStateManager().currentState;
  
  // Get user profile synchronously from cache
  final toUserId = callPayload['toUserId'] as int? ?? 
                   callPayload['fromUserId'] as int? ?? 
                   0;
  final cachedProfile = UserProfileCache().getCachedOnly(toUserId);
  final userName = cachedProfile?.fullName ?? 'User';
  
  String stateLabel = '';
  switch (callState) {
    case CallState.outgoingCalling:
      stateLabel = 'Calling...';
      break;
    case CallState.incomingRinging:
      stateLabel = 'Ringing...';
      break;
    case CallState.inCall:
      stateLabel = 'In call';
      break;
    default:
      stateLabel = 'Call';
  }
  
  void maximizeCall() {
    print('[MinimizedCallOverlay] 📱 Maximizing call - CallOverlayManager will handle screen');
    // Just un-minimize - CallOverlayManager will automatically show the correct screen
    // based on current call state (CallingLoaderScreen, IncomingCallScreen, or CallScreen)
    CallStateManager().setMinimized(false);
  }
  
  Future<void> endCall() async {
    print('[MinimizedCallOverlay] 🔴 Ending call from minimized overlay');
    
    try {
      final fromUserId = callPayload['fromUserId'] as int? ?? 0;
      final toUserId = callPayload['toUserId'] as int? ?? 0;
      final channelName = callPayload['channelName'] as String? ?? '';

      CallSignalingService().sendCallEnd(
        fromUserId: fromUserId,
        toUserId: toUserId,
        channelName: channelName,
      );
    } catch (e) {
      print('[MinimizedCallOverlay] ⚠️ Failed to send end signal: $e');
    }

    CallStateManager().reset();
  }
  
  final List<Widget> widgets = [];
  
  // For audio calls: Show green bar at top with timer
  if (!isVideo) {
    widgets.add(
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Material(
          color: Colors.green[700],
          child: SafeArea(
            bottom: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  // Tap to expand
                  Expanded(
                    child: GestureDetector(
                      onTap: maximizeCall,
                      child: Row(
                        children: [
                          const Icon(
                            Icons.phone,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  userName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                // Timer
                                _MinimizedCallTimer(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Maximize button
                  GestureDetector(
                    onTap: maximizeCall,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white24,
                      ),
                      child: const Icon(
                        Icons.call,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // End Call Button
                  GestureDetector(
                    onTap: endCall,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.danger,
                      ),
                      child: const Icon(
                        Icons.call_end,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ...existing code...
  
  // For video calls: Show floating DRAGGABLE video preview (ALL states)
  if (isVideo) {
    widgets.add(
      DraggableVideoPreview(
        callPayload: callPayload,
        onMaximize: maximizeCall,
        onEndCall: endCall,
      ),
    );
  }
  
  return widgets;
}

/// Draggable floating video preview widget
class DraggableVideoPreview extends StatefulWidget {
  final Map<String, dynamic> callPayload;
  final VoidCallback onMaximize;
  final VoidCallback onEndCall;

  const DraggableVideoPreview({
    super.key,
    required this.callPayload,
    required this.onMaximize,
    required this.onEndCall,
  });

  @override
  State<DraggableVideoPreview> createState() => _DraggableVideoPreviewState();
}

class _DraggableVideoPreviewState extends State<DraggableVideoPreview> {
  // Position state for dragging
  Offset _position = const Offset(20, 100);
  
  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final callState = CallStateManager().currentState;
    final agoraService = CallStateManager().agoraService;
    final agoraEngine = agoraService?.engine;
    final isConnected = callState == CallState.inCall;
    
    // Use Agora's lastRemoteUid
    final remoteAgoraUid = agoraService?.lastRemoteUid ?? 0;
    
    // Get user info
    final toUserId = widget.callPayload['toUserId'] as int? ?? 
                     widget.callPayload['fromUserId'] as int? ?? 0;
    final cachedProfile = UserProfileCache().getCachedOnly(toUserId);
    final userName = cachedProfile?.fullName ?? 'User';
    
    // Constrain position to screen bounds
    final maxX = screenSize.width - 130; // 120 width + 10 padding
    final maxY = screenSize.height - 200; // 160 height + 40 padding for bottom nav
    
    return Positioned(
      left: _position.dx.clamp(10.0, maxX),
      top: _position.dy.clamp(50.0, maxY), // 50 for status bar
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _position = Offset(
              (_position.dx + details.delta.dx).clamp(10.0, maxX),
              (_position.dy + details.delta.dy).clamp(50.0, maxY),
            );
          });
        },
        onTap: widget.onMaximize,
        child: Container(
          width: 120,
          height: 160,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary, width: 3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Stack(
            children: [
              // Background - gradient (when not connected)
              if (!isConnected || remoteAgoraUid == 0)
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFFB8E6D5),
                        const Color(0xFFA8D8C8),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              
              // Video feed (only when connected and remote UID exists)
              if (isConnected && agoraEngine != null && remoteAgoraUid != 0)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: AgoraVideoView(
                    controller: VideoViewController.remote(
                      rtcEngine: agoraEngine,
                      canvas: VideoCanvas(uid: remoteAgoraUid),
                      connection: RtcConnection(
                        channelId: widget.callPayload['channelName'] as String? ?? '',
                      ),
                    ),
                  ),
                ),
              
              // Profile picture (when not connected)
              if (!isConnected || remoteAgoraUid == 0)
                Center(
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: ClipOval(
                      child: cachedProfile?.profilePictureUrl != null
                          ? Image.network(
                              cachedProfile!.profilePictureUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _buildInitialAvatar(userName),
                            )
                          : _buildInitialAvatar(userName),
                    ),
                  ),
                ),
              
              // User name at bottom
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.7),
                        Colors.transparent,
                      ],
                    ),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(10),
                      bottomRight: Radius.circular(10),
                    ),
                  ),
                  child: Text(
                    userName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              
              // End call button
              Positioned(
                top: 6,
                right: 6,
                child: GestureDetector(
                  onTap: widget.onEndCall,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.danger,
                    ),
                    child: const Icon(
                      Icons.call_end,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
              ),
              
              // Drag indicator
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(
                    Icons.open_with,
                    color: Colors.white70,
                    size: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildInitialAvatar(String name) {
    return Container(
      color: AppColors.border,
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
