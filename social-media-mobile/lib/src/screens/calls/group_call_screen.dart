import 'dart:async';
import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';

import '../../services/agora_service.dart';
import '../../services/group_call_signaling_service.dart';
import '../../services/user_profile_cache.dart';
import '../../state/group_call_state_manager.dart';
import 'package:social_chat_app/src/theme/colors.dart';

/// In-call screen for a group call — a grid of participant tiles instead of
/// the 1:1 screen's single local/remote pair. Each tile shows live Agora
/// video when available, otherwise a squircle initials placeholder (audio
/// call, or that participant's camera is off).
class GroupCallScreen extends StatefulWidget {
  const GroupCallScreen({super.key});

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen> {
  final GroupCallStateManager _gm = GroupCallStateManager();
  AgoraService? get _agora => _gm.agoraService;

  static const int _tilesPerPage = 9;

  Set<int> _remoteUids = {};
  int? _activeSpeakerUid;
  StreamSubscription<Set<int>>? _remoteUidsSub;
  StreamSubscription<int?>? _activeSpeakerSub;
  StreamSubscription<void>? _rosterSub;
  StreamSubscription<String>? _declineToastSub;
  VoidCallback? _gmListener;
  bool _muted = false;
  bool _videoOff = false;
  bool _speakerOn = true;
  bool _switchingCamera = false;
  Stopwatch? _timer;
  late final ValueNotifier<Duration> _duration;
  Timer? _tick;
  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    _remoteUids = _agora?.remoteUids ?? {};
    _remoteUidsSub = _agora?.onRemoteUidsChanged.listen((uids) {
      if (mounted) setState(() => _remoteUids = uids);
    });
    _activeSpeakerSub = _agora?.onActiveSpeaker.listen((uid) {
      if (mounted) setState(() => _activeSpeakerUid = uid);
    });
    _rosterSub = _gm.onRosterUpdate.listen((_) {
      // Remote uid set changes independently via onRemoteUidsChanged; this
      // just guarantees a rebuild if a leave arrives with no uid change yet.
      if (mounted) setState(() {});
    });
    _declineToastSub = GroupCallSignalingService().onDeclineToast.listen((message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    });
    _gmListener = () {
      if (mounted) setState(() {}); // reflects isReconnecting changes
    };
    _gm.addListener(_gmListener!);
    _videoOff = !_gm.isVideo;
    _duration = ValueNotifier(Duration.zero);
    _timer = Stopwatch()..start();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      _duration.value = _timer!.elapsed;
    });
  }

  @override
  void dispose() {
    _remoteUidsSub?.cancel();
    _activeSpeakerSub?.cancel();
    _rosterSub?.cancel();
    _declineToastSub?.cancel();
    if (_gmListener != null) _gm.removeListener(_gmListener!);
    _tick?.cancel();
    _duration.dispose();
    _pageController.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    await _agora?.muteLocalAudio(_muted);
  }

  Future<void> _toggleVideo() async {
    setState(() => _videoOff = !_videoOff);
    await _agora?.setLocalVideoEnabled(!_videoOff);
  }

  Future<void> _toggleSpeaker() async {
    setState(() => _speakerOn = !_speakerOn);
    await _agora?.engine?.setEnableSpeakerphone(_speakerOn);
  }

  Future<void> _switchCamera() async {
    if (_switchingCamera) return;
    setState(() => _switchingCamera = true);
    await _agora?.switchCamera();
    if (mounted) setState(() => _switchingCamera = false);
  }

  Future<void> _leaveCall() async {
    await GroupCallSignalingService().leaveCall();
    if (mounted) Navigator.of(context).maybePop();
  }

  Widget _tile({required int? uid, required String label, bool isActiveSpeaker = false}) {
    final engine = _agora?.engine;
    final showVideo = _gm.isVideo && !(uid == null && _videoOff) && engine != null;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.art,
        borderRadius: BorderRadius.circular(18),
        border: isActiveSpeaker ? Border.all(color: AppColors.primary, width: 3) : null,
        boxShadow: isActiveSpeaker
            ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.5), blurRadius: 12, spreadRadius: 1)]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showVideo)
            AgoraVideoView(
              controller: uid == null
                  ? VideoViewController(rtcEngine: engine, canvas: const VideoCanvas(uid: 0))
                  : VideoViewController.remote(
                      rtcEngine: engine,
                      canvas: VideoCanvas(uid: uid),
                      connection: RtcConnection(channelId: _gm.channelName ?? ''),
                    ),
            )
          else
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.accentSubtle100,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(22),
                    topRight: Radius.circular(22),
                    bottomRight: Radius.circular(22),
                    bottomLeft: Radius.circular(9),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  label.isNotEmpty ? label[0].toUpperCase() : '?',
                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 22),
                ),
              ),
            ),
          Positioned(
            left: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  /// Resolves a remote tile's display label from the cached profile — the
  /// Agora uid *is* the remote userId (deterministic uid, see
  /// GroupCallStateManager._joinAgora), so no separate identity handshake
  /// is needed.
  String _labelFor(int uid) {
    final profile = UserProfileCache().getCachedOnly(uid);
    if (profile != null && profile.fullName.isNotEmpty) return profile.fullName;
    // Kick off a background fetch so a later rebuild (roster/active-speaker
    // change) picks up the real name.
    UserProfileCache().getProfile(uid).then((_) {
      if (mounted) setState(() {});
    });
    return 'User $uid';
  }

  /// 1 -> full screen, 2 -> 1 column, 3-4 -> 2x2, 5-6 -> 2x3, 7-9 -> 3x3.
  /// Above 9, tiles paginate 9-per-page (max call size is 12, so at most 2
  /// pages).
  int _crossAxisCountFor(int tileCount) {
    if (tileCount <= 1) return 1;
    if (tileCount == 2) return 1;
    if (tileCount <= 4) return 2;
    return 3;
  }

  double _aspectRatioFor(int tileCount, int crossAxisCount) {
    if (tileCount == 1) return 1.1;
    if (crossAxisCount == 1) return 1.4;
    if (crossAxisCount == 2) return 0.85;
    return 0.72;
  }

  Widget _buildGrid(List<Widget> tiles) {
    if (tiles.length <= _tilesPerPage) {
      final crossAxisCount = _crossAxisCountFor(tiles.length);
      return GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: _aspectRatioFor(tiles.length, crossAxisCount),
        ),
        itemCount: tiles.length,
        itemBuilder: (context, i) => tiles[i],
      );
    }

    // Paginate beyond 9 tiles (only reachable up to 12 — the max group size).
    final pages = <List<Widget>>[];
    for (var i = 0; i < tiles.length; i += _tilesPerPage) {
      pages.add(tiles.sublist(i, i + _tilesPerPage > tiles.length ? tiles.length : i + _tilesPerPage));
    }

    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: pages.length,
            itemBuilder: (context, pageIndex) {
              final pageTiles = pages[pageIndex];
              final crossAxisCount = _crossAxisCountFor(pageTiles.length);
              return GridView.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: _aspectRatioFor(pageTiles.length, crossAxisCount),
                ),
                itemCount: pageTiles.length,
                itemBuilder: (context, i) => pageTiles[i],
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            pages.length,
            (i) => AnimatedBuilder(
              animation: _pageController,
              builder: (context, _) {
                final page = _pageController.hasClients && _pageController.page != null
                    ? _pageController.page!.round()
                    : 0;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: page == i ? AppColors.primary : Colors.white.withValues(alpha: 0.3),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final myUid = _agora?.uid;
    final tiles = <Widget>[
      _tile(uid: null, label: 'You', isActiveSpeaker: myUid != null && _activeSpeakerUid == myUid),
      for (final uid in _remoteUids)
        _tile(uid: uid, label: _labelFor(uid), isActiveSpeaker: _activeSpeakerUid == uid),
    ];
    final participantCount = tiles.length;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.art,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        _gm.setMinimized(true);
                        Navigator.of(context).maybePop();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), shape: BoxShape.circle),
                        child: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_gm.groupName ?? 'Group call',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                          ValueListenableBuilder<Duration>(
                            valueListenable: _duration,
                            builder: (context, d, _) => Text(
                              '$participantCount on the call · ${_fmt(d)}',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_gm.isReconnecting)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      ),
                      SizedBox(width: 8),
                      Text('Reconnecting…', style: TextStyle(color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: _buildGrid(tiles),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _control(
                      icon: _muted ? Icons.mic_off : Icons.mic,
                      active: _muted,
                      onTap: _toggleMute,
                    ),
                    if (_gm.isVideo)
                      _control(
                        icon: _videoOff ? Icons.videocam_off : Icons.videocam,
                        active: _videoOff,
                        onTap: _toggleVideo,
                      ),
                    if (_gm.isVideo)
                      _control(
                        icon: Icons.cameraswitch,
                        active: false,
                        onTap: _switchCamera,
                      ),
                    _control(
                      icon: _speakerOn ? Icons.volume_up : Icons.hearing,
                      active: !_speakerOn,
                      onTap: _toggleSpeaker,
                    ),
                    GestureDetector(
                      onTap: _leaveCall,
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
                        child: const Icon(Icons.call_end, color: Colors.white, size: 26),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _control({required IconData icon, required bool active, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.white.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: active ? AppColors.art : Colors.white, size: 24),
      ),
    );
  }
}
