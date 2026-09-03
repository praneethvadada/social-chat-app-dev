import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:uuid/uuid.dart';

import '../../database/local_chat_repository.dart';
import '../../models/group.dart';
import '../../models/message.dart';
import '../../services/api_service.dart';
import '../../services/chat_websocket_service.dart';
import '../../models/selected_media.dart';
import '../../services/group_api.dart';
import '../../services/media_service.dart';
import '../../services/group_call_signaling_service.dart';
import '../../services/call_api.dart';
import '../../components/squircle_avatar.dart';
import 'group_info_screen.dart';
import 'package:social_chat_app/src/theme/colors.dart';

/// G1: group conversation screen.
/// Sends over REST (response is the delivery ack); receives live messages via
/// the STOMP topic /topic/conversation.{id}.
class GroupChatScreen extends StatefulWidget {
  final GroupSummary group;

  /// True when rendered as the right-hand pane of the desktop Connect
  /// split view rather than pushed as its own route — see the matching
  /// doc comment on `ChatDetailScreen.embedded`. [onEmbeddedClose] is
  /// called instead of `Navigator.pop()` for the one place this screen
  /// closes itself (leaving the group), so the parent can clear the
  /// selection instead of popping a route that was never pushed.
  final bool embedded;
  final VoidCallback? onEmbeddedClose;

  const GroupChatScreen({super.key, required this.group, this.embedded = false, this.onEmbeddedClose});

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  /// Newest first (rendered in a reversed ListView).
  final List<Message> _messages = [];
  bool _loading = true;
  int _myId = 0;
  void Function()? _unsubscribe;

  /// Members, used to turn system-event ids into readable names.
  List<GroupMember> _members = [];

  /// G4 state
  Message? _replyingTo;              // composer quote target
  List<Message> _pinned = [];
  String _myRole = 'MEMBER';
  bool _searching = false;
  final _searchController = TextEditingController();
  List<Message>? _searchResults;
  bool _isStartingCall = false;

  /// Set from _init()'s active-call lookup and refreshed on return from a
  /// call — drives the "N on a call · Join" banner ("join later").
  Map<String, dynamic>? _activeGroupCall;

  // Spec §6: unsent drafts stored locally — mirrors the DIRECT chat screen's
  // wiring (see ChatDetailScreen for the full reasoning).
  Timer? _draftSaveTimer;

  Future<void> _startGroupCall({required bool isVideo}) async {
    setState(() => _isStartingCall = true);
    try {
      final failure = await GroupCallSignalingService().startGroupCall(
        groupId: widget.group.id,
        groupName: widget.group.name,
        isVideo: isVideo,
      );
      if (failure != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(failure == 'call_full'
              ? 'This call is full.'
              : 'Could not start the call. You may already be on one.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isStartingCall = false);
      _refreshActiveGroupCall();
    }
  }

  Future<void> _joinActiveGroupCall() async {
    setState(() => _isStartingCall = true);
    try {
      final failure = await GroupCallSignalingService().joinActiveCall(widget.group.id, widget.group.name);
      if (failure != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(failure == 'call_full' ? 'This call is full.' : 'Could not join the call.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isStartingCall = false);
      _refreshActiveGroupCall();
    }
  }

  Future<void> _refreshActiveGroupCall() async {
    try {
      final active = await CallApi.fetchActiveGroupCall(widget.group.id);
      if (mounted) {
        setState(() => _activeGroupCall = (active?['active'] == true) ? active : null);
      }
    } catch (_) {}
  }

  bool get _iAmAdmin => _myRole == 'OWNER' || _myRole == 'ADMIN';

  /// Spec §I reaction palette. Keys are stored; emoji are display only.
  static const Map<String, String> _reactions = {
    'heart': '❤️', 'laugh': '😂', 'like': '👍',
    'sad': '😢', 'wow': '😮', 'fire': '🔥',
  };

  @override
  void initState() {
    super.initState();
    _init();
    _controller.addListener(_onMessageTextChanged);
    _loadDraft();
  }

  Future<void> _init() async {
    _myId = await ApiService.getUserId() ?? 0;
    await _loadMembers();
    await _loadMessages();
    _subscribe();
    // Clears the unread badge on the Connect list; failures are non-fatal.
    GroupApi.markRead(widget.group.id).catchError((_) {});
    _refreshActiveGroupCall();
  }

  /// Local SQLite is mobile-only by design (Phase 2) — deliberately skipped
  /// on web. widget.group.id is the group's real conversationId (same
  /// shared-PK space as DIRECT conversations' conversationId, per G0/G1),
  /// so it's always a valid, non-nullable drafts key here — unlike the
  /// DIRECT screen, no legacy/brand-new-conversation null case to handle.
  Future<void> _loadDraft() async {
    if (kIsWeb) return;
    try {
      final draft = await LocalChatRepository().loadDraft(widget.group.id);
      if (draft != null && draft.isNotEmpty && mounted && _controller.text.isEmpty) {
        _controller.text = draft;
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length),
        );
      }
    } catch (e) {
      print('[GroupChat] Error loading draft: $e');
    }
  }

  void _onMessageTextChanged() {
    if (kIsWeb) return;
    _draftSaveTimer?.cancel();
    final text = _controller.text;
    _draftSaveTimer = Timer(const Duration(milliseconds: 500), () {
      LocalChatRepository().saveDraft(widget.group.id, text).catchError((e) {
        print('[GroupChat] Error saving draft: $e');
      });
    });
  }

  Future<void> _loadMembers() async {
    try {
      final members = await GroupApi.fetchMembers(widget.group.id);
      if (!mounted) return;
      setState(() {
        _members = members;
        _myRole = members
            .firstWhere((m) => m.userId == _myId,
                orElse: () => GroupMember(userId: _myId, username: '', role: 'MEMBER'))
            .role;
      });
      _loadPinned();
    } catch (_) {
      // Names fall back to "someone" in system messages; not fatal.
    }
  }

  Future<void> _loadMessages() async {
    try {
      final msgs = await GroupApi.fetchMessages(widget.group.id);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(msgs); // backend returns newest-first
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      Fluttertoast.showToast(msg: 'Failed to load messages');
    }
  }

  void _subscribe() {
    _unsubscribe = ChatWebSocketService().subscribeToConversationTopic(
      widget.group.id,
      (frame) {
        // G4: reaction/pin/delete changes arrive as a lightweight signal.
        if (frame['type'] == 'MESSAGE_UPDATED') {
          _loadMessages();
          _loadPinned();
          return;
        }
        final incoming = Message.fromJson(frame);
        if (!mounted) return;
        setState(() {
          // Dedupe: replace optimistic copy (same clientMessageId) or skip
          // if the server row is already present.
          final byClientId = incoming.clientMessageId != null
              ? _messages.indexWhere(
                  (m) => m.clientMessageId == incoming.clientMessageId)
              : -1;
          if (byClientId >= 0) {
            _messages[byClientId] = incoming;
          } else if (incoming.id == 0 ||
              !_messages.any((m) => m.id == incoming.id)) {
            _messages.insert(0, incoming);
          }
        });
      },
    );
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    _draftSaveTimer?.cancel();
    if (!kIsWeb) {
      LocalChatRepository().clearDraft(widget.group.id).catchError((e) {
        print('[GroupChat] Error clearing draft: $e');
      });
    }

    final clientId = const Uuid().v4();
    final replyTarget = _replyingTo;
    setState(() => _replyingTo = null);
    final optimistic = Message(
      id: 0,
      clientMessageId: clientId,
      senderId: _myId,
      senderName: 'You',
      recipientId: 0,
      content: text,
      createdAt: DateTime.now().toUtc(),
      isRead: false,
      status: MessageStatus.sending,
    );
    setState(() => _messages.insert(0, optimistic));

    try {
      final sent = await GroupApi.sendMessage(widget.group.id,
          content: text,
          clientMessageId: clientId,
          replyToMessageId: replyTarget?.id);
      if (!mounted) return;
      setState(() {
        final i = _messages.indexWhere((m) => m.clientMessageId == clientId);
        if (i >= 0) _messages[i] = sent;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final i = _messages.indexWhere((m) => m.clientMessageId == clientId);
        if (i >= 0) {
          _messages[i] = _messages[i].copyWith(status: MessageStatus.failed);
        }
      });
      Fluttertoast.showToast(msg: 'Message not sent');
    }
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    // Flush any pending debounced draft save immediately instead of losing
    // it — must read .text and cancel the timer BEFORE disposing the
    // controller. Fire-and-forget (dispose is sync); errors are logged, not
    // thrown, matching this method's other cleanup calls.
    _draftSaveTimer?.cancel();
    if (!kIsWeb) {
      final pendingText = _controller.text;
      LocalChatRepository().saveDraft(widget.group.id, pendingText).catchError((e) {
        print('[GroupChat] Error saving draft on dispose: $e');
      });
    }
    _controller.removeListener(_onMessageTextChanged);
    _controller.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        actions: [
          IconButton(
            tooltip: 'Voice call',
            icon: const Icon(Icons.call_outlined),
            onPressed: _isStartingCall ? null : () => _startGroupCall(isVideo: false),
          ),
          IconButton(
            tooltip: 'Video call',
            icon: const Icon(Icons.videocam_outlined),
            onPressed: _isStartingCall ? null : () => _startGroupCall(isVideo: true),
          ),
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search in group',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                _searchController.clear();
                _searchResults = null;
              }
            }),
          ),
        ],
        // Tapping the header opens Group Info (G2).
        title: InkWell(
          onTap: () async {
            final left = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                  builder: (_) => GroupInfoScreen(group: widget.group)),
            );
            if (left == true && mounted) {
              if (widget.embedded) {
                widget.onEmbeddedClose?.call();
              } else {
                Navigator.of(context).pop(); // we left the group; close the chat
              }
            }
          },
          child: Row(
            children: [
              SquircleAvatar(size: 36, icon: Icons.groups_rounded),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.group.name,
                        style: const TextStyle(fontSize: 16),
                        overflow: TextOverflow.ellipsis),
                    Text('${widget.group.memberCount} members',
                        style: TextStyle(
                            fontSize: 12,
                            color: theme.textTheme.bodySmall?.color)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          if (_searching)
            Padding(
              padding: const EdgeInsets.all(8),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search in this group...',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: _runSearch,
              ),
            ),
          if (_activeGroupCall != null && !_searching) _activeCallBanner(),
          if (_pinned.isNotEmpty && !_searching) _pinnedBanner(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _searchResults != null
                    ? (_searchResults!.isEmpty
                        ? const Center(child: Text('No matches'))
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _searchResults!.length,
                            itemBuilder: (context, i) =>
                                _bubble(_searchResults![i], primary),
                          ))
                    : ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        padding: const EdgeInsets.all(12),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) => _bubble(_messages[i], primary),
                      ),
          ),
          if (_replyingTo != null) _replyPreviewBar(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Attach',
                    icon: const Icon(Icons.attach_file),
                    onPressed: () => showModalBottomSheet(
                      context: context,
                      builder: (sheet) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.image),
                              title: const Text('Photo'),
                              onTap: () {
                                Navigator.pop(sheet);
                                _attachMedia(false);
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.videocam),
                              title: const Text('Video'),
                              onTap: () {
                                Navigator.pop(sheet);
                                _attachMedia(true);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Message...',
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24)),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.send, color: primary),
                    onPressed: _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }



  /// GAP-2: attach an image or video and send it as a group message.
  /// Reuses the same S3 upload pipeline as posts and 1:1 chat media.
  Future<void> _attachMedia(bool video) async {
    try {
      final picker = ImagePicker();
      final XFile? picked = video
          ? await picker.pickVideo(source: ImageSource.gallery)
          : await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      final clientId = const Uuid().v4();
      final optimistic = Message(
        id: 0,
        clientMessageId: clientId,
        senderId: _myId,
        senderName: 'You',
        recipientId: 0,
        content: '',
        createdAt: DateTime.now().toUtc(),
        isRead: false,
        status: MessageStatus.uploading,
      );
      setState(() => _messages.insert(0, optimistic));

      final url = await MediaService.uploadMedia(
        SelectedMedia(
          id: clientId,
          file: File(picked.path),
          type: video ? MediaType.video : MediaType.image,
        ),
        (_) {},
      );

      final sent = await GroupApi.sendMessage(
        widget.group.id,
        content: '',
        clientMessageId: clientId,
        mediaUrl: url,
        mediaType: video ? 'VIDEO' : 'IMAGE',
      );
      if (!mounted) return;
      setState(() {
        final i = _messages.indexWhere((m) => m.clientMessageId == clientId);
        if (i >= 0) _messages[i] = sent;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _messages.removeWhere(
            (m) => m.status == MessageStatus.uploading));
      }
      Fluttertoast.showToast(msg: 'Could not send media');
    }
  }

  /// GAP-3: pick a destination group and copy the message there.
  Future<void> _forward(Message msg) async {
    List<GroupSummary> groups;
    try {
      groups = (await GroupApi.fetchMyGroups())
          .where((g) => g.id != widget.group.id)
          .toList();
    } catch (e) {
      Fluttertoast.showToast(msg: 'Could not load groups');
      return;
    }
    if (!mounted) return;
    if (groups.isEmpty) {
      Fluttertoast.showToast(msg: 'No other groups to forward to');
      return;
    }

    await showModalBottomSheet(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Forward to',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const Divider(height: 1),
            ...groups.map((g) => ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: const Icon(Icons.groups,
                        color: Colors.white, size: 18),
                  ),
                  title: Text(g.name),
                  subtitle: Text('${g.memberCount} members'),
                  onTap: () async {
                    Navigator.pop(sheet);
                    try {
                      await GroupApi.forwardMessage(msg.id, g.id);
                      Fluttertoast.showToast(msg: 'Forwarded to ${g.name}');
                    } catch (e) {
                      // Surfaces the backend's own reason (e.g. "Admins only").
                      Fluttertoast.showToast(
                          msg: e.toString().replaceFirst('Exception: ', ''));
                    }
                  },
                )),
          ],
        ),
      ),
    );
  }

  Future<void> _loadPinned() async {
    try {
      final pinned = await GroupApi.fetchPinned(widget.group.id);
      if (mounted) setState(() => _pinned = pinned);
    } catch (_) {}
  }

  Future<void> _runAction(Future<void> Function() action, String ok) async {
    try {
      await action();
      Fluttertoast.showToast(msg: ok);
      await _loadMessages();
      await _loadPinned();
    } catch (e) {
      Fluttertoast.showToast(msg: e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// Spec §G: the action menu adapts to sender, role, and message state.
  void _messageActions(Message msg) {
    if (msg.isSystem || msg.isDeleted) return;
    final mine = msg.senderId == _myId;

    showModalBottomSheet(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Quick reactions row
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: _reactions.entries.map((e) {
                  final selected = msg.myReaction == e.key;
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(sheet);
                      _runAction(
                          () => GroupApi.reactToMessage(msg.id, e.key), '');
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected
                            ? Theme.of(context).dividerColor
                            : Colors.transparent,
                      ),
                      child: Text(e.value, style: const TextStyle(fontSize: 26)),
                    ),
                  );
                }).toList(),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(sheet);
                setState(() => _replyingTo = msg);
              },
            ),
            ListTile(
              leading: const Icon(Icons.forward),
              title: const Text('Forward'),
              onTap: () {
                Navigator.pop(sheet);
                _forward(msg);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy'),
              onTap: () {
                Navigator.pop(sheet);
                Clipboard.setData(ClipboardData(text: msg.content));
                Fluttertoast.showToast(msg: 'Copied');
              },
            ),
            if (msg.reactionCounts.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.emoji_emotions_outlined),
                title: const Text('View reactions'),
                onTap: () {
                  Navigator.pop(sheet);
                  _showReactions(msg);
                },
              ),
            // Pin is a moderation action (admins only in G4).
            if (_iAmAdmin)
              ListTile(
                leading: Icon(msg.isPinned
                    ? Icons.push_pin
                    : Icons.push_pin_outlined),
                title: Text(msg.isPinned ? 'Unpin' : 'Pin'),
                onTap: () {
                  Navigator.pop(sheet);
                  _runAction(() => GroupApi.setPinned(msg.id, !msg.isPinned),
                      msg.isPinned ? 'Unpinned' : 'Pinned');
                },
              ),
            // Own message, or any message if you moderate.
            if (mine || _iAmAdmin)
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: AppColors.danger),
                title: Text(mine ? 'Delete' : 'Delete for everyone',
                    style: const TextStyle(color: AppColors.danger)),
                onTap: () {
                  Navigator.pop(sheet);
                  _runAction(
                      () => GroupApi.deleteMessage(msg.id), 'Message deleted');
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showReactions(Message msg) async {
    try {
      final rows = await GroupApi.fetchMessageReactions(msg.id);
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        builder: (_) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Reactions',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const Divider(height: 1),
              ...rows.map((r) => ListTile(
                    leading: Text(
                        _reactions[r['reaction']] ?? r['reaction'].toString(),
                        style: const TextStyle(fontSize: 22)),
                    title: Text(r['fullName']?.toString() ??
                        r['username']?.toString() ??
                        'User'),
                  )),
            ],
          ),
        ),
      );
    } catch (e) {
      Fluttertoast.showToast(msg: 'Could not load reactions');
    }
  }

  Future<void> _runSearch(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _searchResults = null);
      return;
    }
    try {
      final results = await GroupApi.searchMessages(widget.group.id, q.trim());
      if (mounted) setState(() => _searchResults = results);
    } catch (_) {
      if (mounted) setState(() => _searchResults = []);
    }
  }

  /// Small banner showing the most recent pinned message (spec §S).
  /// "Join later" banner — shown when a group call is already in progress
  /// and this member hasn't joined it yet.
  Widget _activeCallBanner() {
    final count = _activeGroupCall?['participantCount'];
    final isVideo = _activeGroupCall?['isVideo'] == true;
    return Material(
      color: AppColors.danger.withOpacity(0.08),
      child: ListTile(
        dense: true,
        leading: Icon(isVideo ? Icons.videocam : Icons.call, color: AppColors.danger, size: 18),
        title: Text(
          count != null ? '$count on a call' : 'Call in progress',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        trailing: TextButton(
          onPressed: _isStartingCall ? null : _joinActiveGroupCall,
          child: const Text('Join'),
        ),
      ),
    );
  }

  Widget _pinnedBanner() {
    final pin = _pinned.first;
    return Material(
      color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.push_pin, size: 18),
        title: Text(pin.content,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13)),
        subtitle: _pinned.length > 1
            ? Text('${_pinned.length} pinned messages',
                style: const TextStyle(fontSize: 11))
            : null,
        trailing: _iAmAdmin
            ? IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => _runAction(
                    () => GroupApi.setPinned(pin.id, false), 'Unpinned'),
              )
            : null,
      ),
    );
  }

  /// Quote card shown above the composer while replying.
  Widget _replyPreviewBar() {
    final target = _replyingTo!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Theme.of(context).dividerColor.withOpacity(0.2),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 34,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    'Replying to ${target.senderId == _myId ? 'yourself' : target.senderName}',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary)),
                Text(target.content,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _replyingTo = null),
          ),
        ],
      ),
    );
  }

  /// System events render as a centered chip, not a chat bubble (spec §Q).
  Widget _systemChip(Message msg) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: Theme.of(context).dividerColor.withOpacity(0.25),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          _systemText(msg),
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 11.5, color: Theme.of(context).hintColor),
        ),
      ),
    );
  }

  String _systemText(Message msg) {
    final actor = msg.systemActorId == _myId
        ? 'You'
        : _memberName(msg.systemActorId);
    final target = msg.systemTargetId == _myId
        ? 'you'
        : _memberName(msg.systemTargetId);

    switch (msg.systemEvent) {
      case 'MEMBER_ADDED':
        return '$actor added $target';
      case 'MEMBER_REMOVED':
        return '$actor removed $target';
      case 'MEMBER_LEFT':
        return '$actor left the group';
      case 'MEMBER_BANNED':
        return '$actor banned $target';
      case 'MEMBER_UNBANNED':
        return '$actor lifted the ban on $target';
      case 'ADMIN_PROMOTED':
        return '$actor made $target an admin';
      case 'ADMIN_DEMOTED':
        return '$actor dismissed $target as admin';
      case 'OWNER_TRANSFERRED':
        return '$actor made $target the owner';
      case 'NAME_CHANGED':
        return '$actor changed the group name';
      case 'PHOTO_CHANGED':
        return '$actor changed the group photo';
      default:
        return 'Group updated';
    }
  }

  String _memberName(int? userId) {
    if (userId == null) return 'someone';
    final match = _members.where((m) => m.userId == userId);
    return match.isNotEmpty ? match.first.displayName : 'someone';
  }

  /// Renders group media: image thumbnail, video placeholder, or a document row.
  Widget _groupMedia(Message msg, bool mine) {
    final onBubble = mine ? Colors.white : null;
    if (msg.isDocument) {
      return Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (mine ? Colors.white : AppColors.mutedSolid).withOpacity(0.18),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file, size: 20, color: onBubble),
            const SizedBox(width: 8),
            Flexible(
              child: Text(msg.mediaName ?? 'Document',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: onBubble)),
            ),
          ],
        ),
      );
    }
    if (msg.isVideoMedia) {
      return Container(
        margin: const EdgeInsets.only(bottom: 4),
        height: 120,
        width: 180,
        color: Colors.black26,
        child: const Center(
          child: Icon(Icons.play_circle_outline,
              color: Colors.white70, size: 40),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          msg.mediaUrl!,
          width: 180,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.broken_image, color: onBubble),
        ),
      ),
    );
  }

  Widget _bubble(Message msg, Color primary) {
    if (msg.isSystem) return _systemChip(msg);
    final mine = msg.senderId == _myId;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _messageActions(msg),
        child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: mine ? primary : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: mine
              ? null
              : Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Group rule: incoming messages always identify the sender.
            if (!mine)
              Text(
                msg.senderName,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: primary),
              ),
            // G4: quoted message this one replies to.
            if (msg.isReply)
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: (mine ? Colors.white : Theme.of(context).dividerColor)
                      .withOpacity(0.18),
                  borderRadius: BorderRadius.circular(6),
                  border: Border(
                      left: BorderSide(
                          color: mine ? Colors.white70 : primary, width: 2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(msg.replyToSenderName ?? 'Someone',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: mine ? Colors.white70 : primary)),
                    Text(msg.replyToPreview ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            color: mine ? Colors.white70 : null)),
                  ],
                ),
              ),
            // GAP-3: forwarded marker
            if (msg.isForwarded && !msg.isDeleted)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.forward,
                      size: 11, color: mine ? Colors.white70 : AppColors.mutedSolid),
                  const SizedBox(width: 3),
                  Text('Forwarded',
                      style: TextStyle(
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                          color: mine ? Colors.white70 : AppColors.mutedSolid)),
                ],
              ),
            // GAP-2: media renders above any caption.
            if (msg.hasMedia && !msg.isDeleted) _groupMedia(msg, mine),
            // Deleted messages become a tombstone so history stays coherent.
            if (msg.isDeleted)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.block,
                      size: 13,
                      color: mine ? Colors.white70 : AppColors.mutedSolid),
                  const SizedBox(width: 4),
                  Text('This message was deleted',
                      style: TextStyle(
                          fontStyle: FontStyle.italic,
                          fontSize: 13,
                          color: mine ? Colors.white70 : AppColors.mutedSolid)),
                ],
              )
            else if (msg.content.isNotEmpty)
              Text(
                msg.content,
                style:
                    TextStyle(color: mine ? Colors.white : null, fontSize: 15),
              ),
            // Reaction chips under the bubble.
            if (msg.reactionCounts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 4,
                  children: msg.reactionCounts.entries.map((e) {
                    return GestureDetector(
                      onTap: () => _showReactions(msg),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (mine ? Colors.white : AppColors.mutedSolid)
                              .withOpacity(0.22),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                            '${_reactions[e.key] ?? e.key} ${e.value}',
                            style: TextStyle(
                                fontSize: 11,
                                color: mine ? Colors.white : null)),
                      ),
                    );
                  }).toList(),
                ),
              ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  msg.timeAgo,
                  style: TextStyle(
                      fontSize: 10,
                      color: mine ? Colors.white70 : AppColors.mutedSolid),
                ),
                if (mine) ...[
                  const SizedBox(width: 4),
                  Icon(
                    msg.status == MessageStatus.sending
                        ? Icons.access_time
                        : msg.status == MessageStatus.failed
                            ? Icons.error_outline
                            : Icons.done,
                    size: 12,
                    color: msg.status == MessageStatus.failed
                        ? const Color(0xFFFFCDD2)
                        : Colors.white70,
                  ),
                ],
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }
}
