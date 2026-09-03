import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/call_history.dart';
import '../../models/user_profile.dart';
import '../../services/call_api.dart';
import '../../services/api_service.dart';
import '../../screens/call_screen.dart';
import '../../services/call_signaling_service.dart';
import '../../state/call_state_manager.dart';
import '../../utils/timestamp_parser.dart';
import '../../components/squircle_avatar.dart';
import '../../responsive/desktop_content_wrapper.dart';
import 'package:social_chat_app/src/theme/colors.dart';

class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> with AutomaticKeepAliveClientMixin {
  late Future<List<CallHistory>> _futureCalls;
  final Map<int, UserProfile> _profileCache = {};
  int? _myUserId;
  bool _loading = false;
  Timer? _autoRefreshTimer;
  StreamSubscription? _historySub;
  StreamSubscription? _callEndedSub;

  @override
  void initState() {
    super.initState();
    // 1. Initial load from Local DB (Fast)
    _futureCalls = CallApi.getLocalCallHistory();
    _refresh(); // 2. Background sync from Network

    ApiService.getUserId().then((id) {
      setState(() {
        _myUserId = id;
      });
    });
    // Listen for incoming call updates via WebSocket
    _listenForCallUpdates();
    
    // Listen for call ended event (Reliable)
    _callEndedSub = CallStateManager().onCallEnded.listen((_) {
      print('[CallsScreen] 🔄 Call ended signal received - triggering refresh sequence');
      // Refresh immediately
      _refresh();
      // And again after delay (for server propagation)
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) _refresh();
      });
    });
  }

  /// Listen for call updates via WebSocket/notifications
  void _listenForCallUpdates() {
    try {
      // Subscribe to call history updates (sent by other user or server)
      _historySub = CallSignalingService().onCallHistoryUpdated.listen((_) {
        print('[CallsScreen] 🔄 Received CALL_HISTORY_UPDATED signal - refreshing...');
        if (mounted) _refresh();
      });
    } catch (e) {
      print('[CallsScreen] Warning: Could not set up call update listener: $e');
    }
  }

  @override
  void dispose() {
    _callEndedSub?.cancel();
    _historySub?.cancel();
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: DesktopContentWrapper(
        maxWidth: 640,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'RECENT ACTIVITY',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      color: primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('Calls', style: theme.textTheme.displaySmall),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: FutureBuilder<List<CallHistory>>(
                  future: _futureCalls,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                       // Only show loader if we have NO data (first load empty DB)
                       return const Center(child: CircularProgressIndicator());
                    } else if (snapshot.hasError) {
                      return _buildErrorState();
                    }

                    final rawCalls = snapshot.data ?? [];
                    if (rawCalls.isEmpty && snapshot.connectionState == ConnectionState.done) {
                       return _buildEmptyState();
                    }

                    // --- FILTERING & DEDUPLICATION LOGIC ---

                    if (_myUserId == null) {
                       // Show cached data while loading user id if possible, else loader
                       if (rawCalls.isEmpty) return const Center(child: CircularProgressIndicator());
                    }

                    // Filter: Remove self-calls if myUserId is known
                    final filtered = _myUserId == null
                        ? rawCalls
                        : rawCalls.where((c) => !(c.initiatorId == _myUserId && c.receiverId == _myUserId)).toList();

                    // Deduplicate by call id (keep only the latest per id)
                    final Map<int, CallHistory> uniqueCalls = {};
                    for (final call in filtered) {
                      uniqueCalls[call.id] = call;
                    }
                    final calls = uniqueCalls.values.toList()
                      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
                    // --- END FILTERING & DEDUPLICATION ---

                    if (calls.isEmpty && snapshot.connectionState == ConnectionState.done) {
                        return _buildEmptyState();
                    }

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(0, 4, 0, 110),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
                          child: Text('RECENT',
                              style: TextStyle(
                                  color: AppColors.mutedSolid,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2)),
                        ),
                        ...calls.map((callHistory) => _buildCallRow(context, callHistory)),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildCallRow(BuildContext context, CallHistory callHistory) {
    // Determine the other user ID based on initiator/receiver
    final isOutgoing = _myUserId == callHistory.initiatorId;
    final otherUserId = isOutgoing ? callHistory.receiverId : callHistory.initiatorId;

    // Determine if call was missed
    final isMissed = _myUserId != null && callHistory.isMissedBy(_myUserId!);

    return FutureBuilder<UserProfile?>(
      future: _getUserProfile(otherUserId),
      builder: (context, profileSnap) {
        final profile = profileSnap.data;

        // Get actual username and fallback safely
        final displayName = (profile != null && profile.fullName.isNotEmpty)
            ? profile.fullName
            : 'Unknown User';

        final initials = profile?.fullName.isNotEmpty == true
            ? _initials(profile!.fullName)
            : 'U';
        final avatar = profile?.profilePictureUrl;

        // WhatsApp-style color coding:
        // 🔴 RED: Missed incoming calls (receiver + declined/initiated)
        // 🔵 BLUE: Received calls (receiver + accepted)
        // 🟢 GREEN: All outgoing calls
        Color directionColor;
        IconData directionIcon;

        if (isOutgoing) {
          // Outgoing call: always green
          directionColor = AppColors.primary;
          directionIcon = Icons.call_made; // ↗ arrow
        } else {
          // Incoming call
          if (isMissed) {
            directionColor = AppColors.danger;
            directionIcon = Icons.call_received; // ↙ arrow
          } else {
            directionColor = AppColors.primary;
            directionIcon = Icons.call_received; // ↙ arrow
          }
        }

        // Call type icon
        final callTypeIcon = callHistory.type == CallType.video
            ? Icons.videocam
            : Icons.phone;

        // WhatsApp-style timestamp
        final timestamp = TimestampParser.formatWhatsAppStyle(callHistory.createdAt);

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: isMissed ? AppColors.accentSubtle100 : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              SquircleAvatar(
                size: 54,
                imageUrl: avatar,
                initials: initials,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: isMissed ? AppColors.danger : null,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          timestamp,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: isMissed ? AppColors.danger : AppColors.mutedSolid,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(directionIcon, size: 15, color: directionColor),
                        const SizedBox(width: 6),
                        Icon(
                          callTypeIcon,
                          size: 15,
                          color: isMissed ? AppColors.danger : AppColors.mutedSolid,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isMissed
                              ? 'Missed call'
                              : (isOutgoing ? 'Outgoing call' : 'Incoming call'),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: isMissed ? AppColors.danger : AppColors.mutedSolid,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              _CallActionButton(
                icon: Icons.call,
                onPressed: () => _startCall(context, otherUserId, false),
              ),
              const SizedBox(width: 8),
              _CallActionButton(
                icon: Icons.videocam,
                onPressed: () => _startCall(context, otherUserId, true),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.call_outlined, size: 64, color: AppColors.mutedSolid),
          const SizedBox(height: 16),
          Text('No calls yet', style: TextStyle(color: AppColors.mutedSolid, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off, size: 64, color: AppColors.mutedSolid),
          const SizedBox(height: 16),
          Text(
            'Failed to load call history',
            style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Check your network connection and try again.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.mutedSolid, fontSize: 14),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }


  String _initials(String name) {
    final parts = name.split(' ');
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  Future<UserProfile?> _getUserProfile(int userId) async {
    if (userId <= 0) return null;
    if (_profileCache.containsKey(userId)) return _profileCache[userId]!;
    try {
      final data = await ApiService.getUserProfile(userId);
      final profile = UserProfile.fromJson(data);
      _profileCache[userId] = profile;
      return profile;
    } catch (e) {
      return null;
    }
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final data = CallApi.fetchCallHistory();
    setState(() {
      _futureCalls = data;
      _loading = false;
    });
    await data;
  }

  void _startCall(BuildContext context, int userId, bool video) {
    print('[CallsScreen] 📞 _startCall CLICKED video=$video toUserId=$userId myUserId=$_myUserId');
    if (userId <= 0 || _myUserId == null) {
      print('[CallsScreen] ❌ userId or myUserId is invalid');
      return;
    }
    final callerId = _myUserId!;
    final channel = 'chat_${callerId}_$userId';
    print('[CallsScreen] 📞 channel=$channel callerId=$callerId');

    final cm = CallStateManager();
    print('[CallsScreen] 📞 current state=${cm.currentState}');
    // Only initiate an outgoing call if manager is currently idle.
    if (cm.currentState != CallState.idle) {
      print('[CallsScreen] ❌ NOT IN IDLE STATE, cannot start call');
      return;
    }

    final payload = {
      'fromUserId': callerId,
      'toUserId': userId,
      'channelName': channel,
      'isVideo': video,
    };
    print('[CallsScreen] 📞 payload=$payload');

    // Update state first, then send invite. Per rules: do NOT navigate or start Agora here.
    print('[CallsScreen] 📞 calling cm.setOutgoingCall()');
    cm.setOutgoingCall(payload);
    print('[CallsScreen] 📞 calling CallSignalingService().sendCallInvite()');
    CallSignalingService().sendCallInvite(fromUserId: callerId, toUserId: userId, channelName: channel, isVideo: video);
    print('[CallsScreen] ✅ sendCallInvite sent successfully');
  }
}

/// Rounded tonal icon button used for the audio/video call actions on each
/// call row — matches the accent-subtle circular icon treatment used
/// elsewhere in the app (e.g. group avatars in the chats list).
class _CallActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _CallActionButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accentSubtle100,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(icon, size: 19, color: AppColors.primary),
        ),
      ),
    );
  }
}
