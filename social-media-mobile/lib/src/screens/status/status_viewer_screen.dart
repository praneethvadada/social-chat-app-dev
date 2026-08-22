import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:video_player/video_player.dart';

import '../../models/status.dart';
import '../../services/api_service.dart';
import '../../services/status_api.dart';
import 'package:social_chat_app/src/theme/colors.dart';

/// Full-screen status viewer (S1 + S2).
///
/// Timing rule: the progress bar never runs while media is still loading, and
/// for video it follows the clip's real duration rather than a fixed interval -
/// otherwise a slow network silently burns a status's display time.
class StatusViewerScreen extends StatefulWidget {
  final List<UserStatusGroup> groups;
  final int initialGroupIndex;

  const StatusViewerScreen({
    super.key,
    required this.groups,
    this.initialGroupIndex = 0,
  });

  @override
  State<StatusViewerScreen> createState() => _StatusViewerScreenState();
}

class _StatusViewerScreenState extends State<StatusViewerScreen>
    with SingleTickerProviderStateMixin {
  static const _imageDuration = Duration(seconds: 5);

  /// Spec §M quick reactions. Keys are stored server-side; values are display.
  static const Map<String, String> _reactions = {
    'heart': '❤️',
    'laugh': '😂',
    'wow': '😮',
    'sad': '😢',
    'clap': '👏',
    'fire': '🔥',
    'like': '👍',
  };

  final TextEditingController _replyController = TextEditingController();

  late List<UserStatusGroup> _groups;
  late int _groupIndex;
  int _statusIndex = 0;

  late AnimationController _progress;
  VideoPlayerController? _video;

  bool _mediaReady = false;
  bool _mediaFailed = false;
  int _myId = 0;

  UserStatusGroup get _group => _groups[_groupIndex];
  StatusItem get _status => _group.statuses[_statusIndex];
  bool get _isMine => _group.userId == _myId;

  @override
  void initState() {
    super.initState();
    _groups = List.of(widget.groups);
    _groupIndex = widget.initialGroupIndex;
    _progress = AnimationController(vsync: this, duration: _imageDuration)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _next();
      });
    ApiService.getUserId().then((id) {
      if (mounted) setState(() => _myId = id ?? 0);
    });
    _prepare();
  }

  /// Load the current status's media, then start the timer.
  Future<void> _prepare() async {
    _progress.stop();
    _progress.reset();
    setState(() {
      _mediaReady = false;
      _mediaFailed = false;
    });

    await _disposeVideo();
    StatusApi.markViewed(_status.id); // best-effort

    if (_status.isText) {
      _beginTimer(_imageDuration);
      return;
    }

    if (_status.mediaUrl == null || _status.mediaUrl!.isEmpty) {
      setState(() => _mediaFailed = true);
      _beginTimer(_imageDuration);
      return;
    }

    if (_status.isVideo) {
      try {
        final controller =
            VideoPlayerController.networkUrl(Uri.parse(_status.mediaUrl!));
        _video = controller;
        await controller.initialize();
        if (!mounted || _video != controller) return;
        await controller.setLooping(false);
        await controller.play();
        // Progress follows the real clip length (capped so a long video
        // doesn't hold the viewer hostage).
        final duration = controller.value.duration;
        final effective = duration.inMilliseconds <= 0
            ? _imageDuration
            : (duration > const Duration(seconds: 30)
                ? const Duration(seconds: 30)
                : duration);
        setState(() => _mediaReady = true);
        _beginTimer(effective);
      } catch (e) {
        if (!mounted) return;
        setState(() => _mediaFailed = true);
        _beginTimer(_imageDuration);
      }
      return;
    }

    // Image: wait for the bytes before the clock starts.
    try {
      await precacheImage(NetworkImage(_status.mediaUrl!), context);
      if (!mounted) return;
      setState(() => _mediaReady = true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _mediaFailed = true);
    }
    _beginTimer(_imageDuration);
  }

  void _beginTimer(Duration duration) {
    if (!mounted) return;
    _progress.duration = duration;
    _progress
      ..reset()
      ..forward();
  }

  Future<void> _disposeVideo() async {
    final controller = _video;
    _video = null;
    if (controller != null) {
      await controller.pause();
      await controller.dispose();
    }
  }

  void _pause() {
    _progress.stop();
    _video?.pause();
  }

  void _resume() {
    if (_mediaReady || _status.isText || _mediaFailed) {
      _progress.forward();
      _video?.play();
    }
  }

  void _next() {
    if (_statusIndex < _group.statuses.length - 1) {
      setState(() => _statusIndex++);
      _prepare();
    } else {
      _nextUser();
    }
  }

  void _previous() {
    if (_statusIndex > 0) {
      setState(() => _statusIndex--);
      _prepare();
    } else {
      _previousUser();
    }
  }

  /// Spec §J: horizontal swipe jumps between people, not between statuses.
  void _nextUser() {
    if (_groupIndex < _groups.length - 1) {
      setState(() {
        _groupIndex++;
        _statusIndex = 0;
      });
      _prepare();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _previousUser() {
    if (_groupIndex > 0) {
      setState(() {
        _groupIndex--;
        _statusIndex = 0;
      });
      _prepare();
    } else {
      _prepare(); // replay from the start
    }
  }

  Future<void> _showViewers() async {
    if (!_isMine) return;
    _pause();
    try {
      final viewers = await StatusApi.fetchViewers(_status.id);
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        builder: (_) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.visibility, size: 18),
                    const SizedBox(width: 8),
                    Text('Viewed by ${viewers.length}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (viewers.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No views yet'),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: viewers.length,
                    itemBuilder: (_, i) {
                      final v = viewers[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: v.profilePictureUrl != null
                              ? NetworkImage(v.profilePictureUrl!)
                              : null,
                          child: v.profilePictureUrl == null
                              ? Text(v.displayName
                                  .substring(0, 1)
                                  .toUpperCase())
                              : null,
                        ),
                        title: Text(v.displayName),
                        subtitle: Text('@${v.username}'),
                        // S3: show what they reacted with, if anything.
                        trailing: v.reaction != null
                            ? Text(_reactions[v.reaction!] ?? v.reaction!,
                                style: const TextStyle(fontSize: 20))
                            : null,
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      );
    } catch (e) {
      Fluttertoast.showToast(msg: 'Could not load viewers');
    }
    if (mounted) _resume();
  }

  Future<void> _deleteStatus() async {
    _pause();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete status?'),
        content: const Text('This status will be removed for everyone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete',
                  style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );

    if (confirmed != true) {
      if (mounted) _resume();
      return;
    }

    try {
      await StatusApi.delete(_status.id);
      if (!mounted) return;
      // Drop it locally and move on; close if nothing is left.
      final remaining = List<StatusItem>.from(_group.statuses)
        ..removeAt(_statusIndex);
      if (remaining.isEmpty) {
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _groups[_groupIndex] = UserStatusGroup(
          userId: _group.userId,
          username: _group.username,
          fullName: _group.fullName,
          profilePictureUrl: _group.profilePictureUrl,
          allSeen: _group.allSeen,
          latestAt: _group.latestAt,
          statuses: remaining,
        );
        if (_statusIndex >= remaining.length) _statusIndex = remaining.length - 1;
      });
      _prepare();
    } catch (e) {
      Fluttertoast.showToast(msg: 'Could not delete status');
      if (mounted) _resume();
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    _video?.dispose();
    _replyController.dispose();
    super.dispose();
  }

  Color get _background {
    final hex = _status.backgroundColor;
    if (hex != null && hex.startsWith('#') && hex.length == 7) {
      return Color(int.parse('FF${hex.substring(1)}', radix: 16));
    }
    return Colors.black;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: _status.isText ? _background : Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          if (details.globalPosition.dx < width / 3) {
            _previous();
          } else {
            _next();
          }
        },
        onLongPressStart: (_) => _pause(),
        onLongPressEnd: (_) => _resume(),
        onVerticalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v > 200) {
            Navigator.of(context).pop(); // swipe down: close
          } else if (v < -200 && _isMine) {
            _showViewers(); // swipe up on own status: viewers (§J)
          }
        },
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -200) {
            _nextUser();
          } else if (v > 200) {
            _previousUser();
          }
        },
        child: Stack(
          children: [
            Positioned.fill(child: Center(child: _content())),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Row(
                      children: List.generate(_group.statuses.length, (i) {
                        return Expanded(
                          child: Container(
                            height: 2.5,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: AnimatedBuilder(
                              animation: _progress,
                              builder: (context, _) {
                                final value = i < _statusIndex
                                    ? 1.0
                                    : i == _statusIndex
                                        ? _progress.value
                                        : 0.0;
                                return FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: value,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.white24,
                          backgroundImage: _group.profilePictureUrl != null
                              ? NetworkImage(_group.profilePictureUrl!)
                              : null,
                          child: _group.profilePictureUrl == null
                              ? Text(
                                  _group.displayName
                                      .substring(0, 1)
                                      .toUpperCase(),
                                  style: const TextStyle(color: Colors.white),
                                )
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_isMine ? 'My Status' : _group.displayName,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600)),
                              Text(_timeAgo(_status.createdAt),
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 11)),
                            ],
                          ),
                        ),
                        if (_isMine)
                          IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.white),
                            onPressed: _deleteStatus,
                          ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // S3: viewers get a reaction row + reply box; owners get view count.
            if (!_isMine)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(child: _engagementBar()),
              ),
            // Owner-only: tappable view count (also reachable by swiping up).
            if (_isMine)
              Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: Center(
                  child: TextButton.icon(
                    onPressed: _showViewers,
                    icon: const Icon(Icons.visibility,
                        color: Colors.white70, size: 18),
                    label: Text('${_status.viewCount} views',
                        style: const TextStyle(color: Colors.white70)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// S3: quick reactions + reply box, shown to viewers (not the owner).
  Widget _engagementBar() {
    final status = _status;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (status.allowReactions)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _reactions.entries.map((entry) {
                final selected = status.myReaction == entry.key;
                return GestureDetector(
                  onTap: () => _react(entry.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: EdgeInsets.all(selected ? 8 : 6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? Colors.white24 : Colors.transparent,
                    ),
                    child: Text(entry.value,
                        style: TextStyle(fontSize: selected ? 28 : 24)),
                  ),
                );
              }).toList(),
            ),
          ),
        if (status.allowReplies)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _replyController,
                    style: const TextStyle(color: Colors.white),
                    onTap: _pause,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Reply to ${_group.displayName}...',
                      hintStyle: const TextStyle(color: Colors.white54),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: Colors.white38),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: Colors.white),
                      ),
                    ),
                    onSubmitted: (_) => _sendReply(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  onPressed: _sendReply,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _react(String key) async {
    // Pin down WHICH status and WHOSE it is before any await. _status and
    // _group are getters over _statusIndex/_groupIndex, and the auto-advance
    // timer can move both while the network call is in flight - that raced,
    // tagging the DM with whatever status happened to be on screen when the
    // request came back (or DMing the next author entirely).
    final target = _status;
    final ownerId = _group.userId;
    final current = target.myReaction;
    final clearing = current == key; // tapping the same one removes it

    // Hold the story still while we talk to the server, same as every other
    // async action in this screen.
    _pause();

    // Optimistic: the bar should respond instantly.
    setState(() => _replaceStatus(
        target.copyWith(myReaction: clearing ? null : key, clearReaction: clearing)));
    try {
      await StatusApi.react(target.id, clearing ? null : key);

      // A reaction should be *visible* to the owner, not just recorded.
      // Send it as a status-tagged DM (same reference the reply uses), so it
      // lands in chat attributed to this status rather than as a bare emoji.
      if (!clearing) {
        await _sendStatusTagged(_reactions[key] ?? key,
            status: target, recipientId: ownerId, reactionKey: key);
        Fluttertoast.showToast(msg: 'Reaction sent');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _replaceStatus(
          target.copyWith(myReaction: current, clearReaction: current == null)));
      Fluttertoast.showToast(msg: 'Could not react');
    }
    if (mounted) _resume();
  }

  /// Swap the current status in the in-memory group list.
  void _replaceStatus(StatusItem updated) {
    final list = List<StatusItem>.from(_group.statuses);
    // Match by id rather than trusting _statusIndex - an async caller may
    // have moved on by the time its result lands.
    final at = list.indexWhere((s) => s.id == updated.id);
    if (at == -1) return;
    list[at] = updated;
    _groups[_groupIndex] = UserStatusGroup(
      userId: _group.userId,
      username: _group.username,
      fullName: _group.fullName,
      profilePictureUrl: _group.profilePictureUrl,
      allSeen: _group.allSeen,
      latestAt: _group.latestAt,
      statuses: list,
    );
  }

  /// Send a DM that is tagged with the status currently being viewed.
  ///
  /// Both replies and reactions go through here, so a reaction shows up in
  /// chat attributed to the status instead of looking like a stray emoji.
  Future<void> _sendStatusTagged(String text,
      {StatusItem? status, int? recipientId, String? reactionKey}) async {
    // Callers that already awaited something MUST pass the status/recipient
    // they captured up front; the getters may point elsewhere by now.
    final s = status ?? _status;
    await ApiService.sendMessage(
      recipientId ?? _group.userId,
      text,
      replyToStatusId: s.id,
      replyToStatusType: s.type,
      replyToStatusPreview: s.isText ? s.content : s.mediaUrl,
      statusReaction: reactionKey,
    );
  }

  /// Spec §L: a status reply is a normal private DM that references the status.
  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;
    _replyController.clear();
    FocusScope.of(context).unfocus();

    try {
      await _sendStatusTagged(text);
      Fluttertoast.showToast(msg: 'Reply sent');
    } catch (e) {
      Fluttertoast.showToast(msg: 'Could not send reply');
    }
    if (mounted) _resume();
  }

  Widget _content() {
    if (_status.isText) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          _status.content ?? '',
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.white, fontSize: 26, fontWeight: FontWeight.w600),
        ),
      );
    }

    if (_mediaFailed) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image, color: Colors.white54, size: 56),
          SizedBox(height: 8),
          Text('Status unavailable', style: TextStyle(color: Colors.white70)),
        ],
      );
    }

    if (!_mediaReady) {
      return const CircularProgressIndicator(color: Colors.white70);
    }

    if (_status.isVideo && _video != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: AspectRatio(
              aspectRatio: _video!.value.aspectRatio == 0
                  ? 9 / 16
                  : _video!.value.aspectRatio,
              child: VideoPlayer(_video!),
            ),
          ),
          if (_status.content != null && _status.content!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_status.content!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16)),
            ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Image.network(_status.mediaUrl!, fit: BoxFit.contain)),
        if (_status.content != null && _status.content!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_status.content!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16)),
          ),
      ],
    );
  }

  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t.toLocal());
    if (diff.isNegative || diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
