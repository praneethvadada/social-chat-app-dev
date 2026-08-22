import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import '../../services/group_call_signaling_service.dart';
import '../../state/group_call_state_manager.dart';
import 'package:social_chat_app/src/theme/colors.dart';

/// Incoming group call — same visual language as the 1:1 IncomingCallScreen,
/// but shows the group's name instead of a single caller.
class IncomingGroupCallScreen extends StatefulWidget {
  const IncomingGroupCallScreen({super.key});

  @override
  State<IncomingGroupCallScreen> createState() => _IncomingGroupCallScreenState();
}

class _IncomingGroupCallScreenState extends State<IncomingGroupCallScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _rippleController;
  bool _isAccepting = false;
  bool _isDeclining = false;
  Timer? _pickupTimeout;

  @override
  void initState() {
    super.initState();
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _pickupTimeout = Timer(const Duration(seconds: 30), _handleTimeout);
  }

  void _handleTimeout() {
    if (!mounted || _isAccepting || _isDeclining) return;
    _isDeclining = true;
    FlutterRingtonePlayer().stop();
    GroupCallSignalingService().declineIncoming();
  }

  @override
  void dispose() {
    _rippleController.dispose();
    _pickupTimeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gm = GroupCallStateManager();
    final groupName = gm.groupName ?? 'Group';
    final isVideo = gm.isVideo;

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  theme.colorScheme.primary.withValues(alpha: 0.1),
                  theme.scaffoldBackgroundColor,
                  theme.scaffoldBackgroundColor,
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  Stack(
                    alignment: Alignment.center,
                    children: [
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
                                    .withValues(alpha: 0.3 - (_rippleController.value * 0.3)),
                                width: 2,
                              ),
                            ),
                          );
                        },
                      ),
                      Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(46),
                          color: AppColors.accentSubtle100,
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20, spreadRadius: 5),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Icon(Icons.groups_rounded, size: 64, color: theme.colorScheme.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  Text(groupName,
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: theme.textTheme.bodyMedium?.color)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Incoming group ${isVideo ? 'video' : 'audio'} call...',
                      style: TextStyle(fontSize: 14, color: theme.colorScheme.primary, fontWeight: FontWeight.w500),
                    ),
                  ),
                  const Spacer(flex: 3),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 60),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: () async {
                                if (_isDeclining || _isAccepting) return;
                                _isDeclining = true;
                                FlutterRingtonePlayer().stop();
                                await GroupCallSignalingService().declineIncoming();
                              },
                              child: Container(
                                width: 70,
                                height: 70,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.danger,
                                  boxShadow: [
                                    BoxShadow(color: AppColors.danger.withValues(alpha: 0.4), blurRadius: 15, spreadRadius: 2),
                                  ],
                                ),
                                child: const Icon(Icons.call_end, color: Colors.white, size: 32),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text('Decline',
                                style: TextStyle(fontSize: 14, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7))),
                          ],
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: () async {
                                if (_isAccepting || _isDeclining) return;
                                _isAccepting = true;
                                FlutterRingtonePlayer().stop();
                                // GroupCallOverlayManager reacts to the resulting
                                // state change and swaps in GroupCallScreen —
                                // this screen doesn't navigate itself.
                                final ok = await GroupCallSignalingService().acceptIncoming();
                                if (!ok) _isAccepting = false;
                              },
                              child: Container(
                                width: 70,
                                height: 70,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.primary,
                                  boxShadow: [
                                    BoxShadow(color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 15, spreadRadius: 2),
                                  ],
                                ),
                                child: const Icon(Icons.call, color: Colors.white, size: 32),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text('Accept',
                                style: TextStyle(fontSize: 14, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7))),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
