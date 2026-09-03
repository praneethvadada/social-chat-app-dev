import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'dart:math';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../database/local_chat_repository.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../../config/api_config.dart';
import '../../models/message.dart';
import '../../models/chat.dart';
import '../../services/api_service.dart';
import '../../services/chat_websocket_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/message_queue_service.dart';
import '../../state/chat_store.dart';
import '../fullscreen_media/fullscreen_image_viewer.dart';
import '../fullscreen_media/fullscreen_video_player.dart';
import '../user_profile_screen.dart';  // ✅ Import profile screen
import 'chat_image_editor.dart';
import '../post_detail/post_detail_screen.dart';
// Removed trimmer flow for now; send picked video directly.
import '../../state/call_state_manager.dart';
import '../../services/call_signaling_service.dart';
import '../../services/api_service.dart';
import '../../services/firebase_messaging_service.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../services/status_api.dart';
import '../status/status_viewer_screen.dart';
import '../../components/squircle_avatar.dart';
import 'package:social_chat_app/src/theme/colors.dart';

class ChatDetailScreen extends StatefulWidget {
  final Conversation conversation;
  final bool isNewChat;

  /// True when this is rendered as the right-hand pane of the desktop
  /// Connect split view (`ChatsScreen` at 768px+) rather than pushed as its
  /// own full-screen route. The conversation list stays visible alongside
  /// it in that mode, so there's nothing to "go back" to — the back arrow
  /// is hidden instead of wired to `Navigator.pop()`, which would have
  /// nothing to pop (no route was pushed) and could pop the wrong thing.
  /// Every other line of this screen (WebSocket, drafts, typing, presence)
  /// is completely unchanged between the two modes.
  final bool embedded;

  const ChatDetailScreen(
      {super.key, required this.conversation, this.isNewChat = false, this.embedded = false});

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> with WidgetsBindingObserver {
  late Future<List<Message>> _messagesFuture;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final bool _isLoading = false;
  late ChatWebSocketService _webSocketService;
  late ConnectivityService _connectivityService;
  ChatStore? _chatStoreRef; // ✅ Store reference to clear active chat in dispose
  int _currentUserId = 0;
  String _currentUserName = '';  // ✅ NEW: Store current user's name
  String? _currentUserProfilePic;  // ✅ NEW: Store current user's profile pic
  String? _lastMessageKey;
  bool _canSendMessages = true;
  bool _isTargetPrivate = false;
  bool _isTargetFollowing = false;
  bool _isNetworkOnline = true; // ✅ NEW: Track network status
  bool _targetShowActivityStatus =
      true; // Whether target user shows their online status
  bool _targetShowReadReceipts =
      true; // Whether target user shows read receipts
    Timer? _typingTimer;
    bool _isTypingSent = false;
    Timer? _participantTypingTimer;
    // Spec §6: unsent drafts stored locally. Storage layer already existed
    // (LocalChatRepository.saveDraft/loadDraft/clearDraft) but nothing in
    // the UI ever called it — wiring it in here.
    Timer? _draftSaveTimer;
  StreamSubscription<String>? _errorSub;
  // Presence is read from ChatStore via Consumer.

  @override
  void initState() {
    super.initState();
    _webSocketService = ChatWebSocketService();
    _connectivityService = ConnectivityService();

    // ✅ Register for app lifecycle events (pause/resume)
    WidgetsBinding.instance.addObserver(this);

    // ✅ NEW: Listen to network connectivity changes
    _isNetworkOnline = _connectivityService.isOnline;
    _connectivityService.addListener(_onConnectivityChanged);

    // Surface send failures to the user. Without this, a message that never
    // reached the server would fail silently.
    _errorSub = _webSocketService.errorStream.listen((error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: AppColors.danger,
          duration: const Duration(seconds: 3),
        ),
      );
    });

    // Ensure WebSocket is connected. Do NOT fetch messages or send read receipts here.
    _initializeWebSocket();

    // ✅ NEW: Load currentUserId from storage immediately for offline mode
    _loadCurrentUserId();

    // Presence and messages are provided by ChatStore; do not subscribe UI to WebSocket directly.

    // Initialize active chat and load messages
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final chatStore = Provider.of<ChatStore>(context, listen: false);
        _chatStoreRef = chatStore; // ✅ Store reference for dispose
        
        // 🔴 REMOVED: Don't set initial online status from stale widget.conversation.isOnline
        // ChatStore's presence subscription from WebSocket provides real-time status
        // chatStore.setUserOnline(widget.conversation.userId, widget.conversation.isOnline);
        
        // Mark this conversation as active so incoming messages are auto-read
          try {
          chatStore.setActiveChat(widget.conversation.userId);
          FirebaseMessagingService.setContextActiveChatId(widget.conversation.userId); // ✅ NEW
          print('[ChatDetailScreen] setActiveChat=${chatStore.activeChatUserId} currentUser=$_currentUserId other=${widget.conversation.userId} activeSince=${chatStore.activeSinceFor(widget.conversation.userId)}');
          
          // ✅ EXPLICIT: Send read receipts for all unread messages NOW that chat is active
          print('[ChatDetailScreen] 📖 Sending read receipts for unread messages in conversation with user=${widget.conversation.userId}');
          final messages = chatStore.messagesForUser(widget.conversation.userId);
          final unreadMessageIds = messages
              .where((msg) => msg.senderId == widget.conversation.userId && !msg.isRead)
              .map((msg) => msg.id)
              .where((id) => id != 0) // Only messages with server IDs
              .toList();
          
          if (unreadMessageIds.isNotEmpty) {
            print('[ChatDetailScreen] 📖 Found ${unreadMessageIds.length} unread messages, marking as read');
            // ✅ Call async markMessagesRead and handle via .then()
            chatStore.markMessagesRead(widget.conversation.userId, messageIds: unreadMessageIds, currentUserId: _currentUserId).then((_) {
              _webSocketService.sendReadReceipt(widget.conversation.userId, unreadMessageIds);
              print('[ChatDetailScreen] ✅ Read receipts sent for messages: $unreadMessageIds');
            }).catchError((e) {
              print('[ChatDetailScreen] ❌ Error marking messages as read: $e');
            });
          } else {
            print('[ChatDetailScreen] ℹ️ No unread messages to send read receipts for');
          }
            
            // If ChatStore has no messages for this conversation, load initial
            // history once so past messages appear in the UI.
            try {
              final existing = chatStore.messagesForUser(widget.conversation.userId);
              if (existing.isEmpty && !widget.isNewChat) {
                ApiService.getConversation(widget.conversation.userId).then((raw) {
                  final initial = raw.map((j) => Message.fromJson(j)).toList();
                  // Feed into the canonical store via WebSocketService so
                  // downstream logic (reconciliation) is applied consistently.
                  try {
                    _webSocketService.addInitialMessages(widget.conversation.userId, initial);
                  } catch (e) {
                    // If service cannot accept, fallback to direct store insert
                    try {
                      chatStore.addInitialMessages(widget.conversation.userId, initial);
                    } catch (_) {}
                  }
                }).catchError((e) {
                  print('[ChatDetailScreen] load initial messages failed: $e');
                });
              }
            } catch (_) {}
        } catch (_) {}
      } catch (e) {
        print('[ChatDetailScreen] seed presence failed: $e');
      }
    });

    // Evaluate chat permissions based on target's privacy and follow status
    _evaluateChatPermission();

    // ✅ NEW: Listen for WebSocket connection changes to update UI
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _webSocketService.addConnectionListener(_onWebSocketConnectionChanged);
    });

    // Drafts: restore any unsent text, then save (debounced) as the user types.
    _messageController.addListener(_onMessageTextChanged);
    _loadDraft();
  }

  /// Local SQLite is mobile-only by design (Phase 2) — deliberately skipped
  /// on web rather than letting LocalChatRepository's own try/catch log a
  /// confusing "DB open failed"-looking error for what's actually expected.
  /// Null conversationId means a legacy row that predates conversationId
  /// stamping, or a brand-new conversation before its first message — drafts
  /// are skipped rather than keyed by something that could collide with a
  /// real conversationId later.
  Future<void> _loadDraft() async {
    if (kIsWeb) return;
    final conversationId = widget.conversation.conversationId;
    if (conversationId == null) return;
    try {
      final draft = await LocalChatRepository().loadDraft(conversationId);
      if (draft != null && draft.isNotEmpty && mounted && _messageController.text.isEmpty) {
        _messageController.text = draft;
        _messageController.selection = TextSelection.fromPosition(
          TextPosition(offset: _messageController.text.length),
        );
      }
    } catch (e) {
      print('[Chat] Error loading draft: $e');
    }
  }

  void _onMessageTextChanged() {
    if (kIsWeb) return;
    final conversationId = widget.conversation.conversationId;
    if (conversationId == null) return;
    _draftSaveTimer?.cancel();
    final text = _messageController.text;
    // Debounced so typing doesn't turn into a SQLite write per keystroke —
    // same reasoning as DeviceSessionService's last-active-at throttle.
    _draftSaveTimer = Timer(const Duration(milliseconds: 500), () {
      LocalChatRepository().saveDraft(conversationId, text).catchError((e) {
        print('[Chat] Error saving draft: $e');
      });
    });
  }

  /// ✅ Handle app lifecycle changes - clear active chat when app goes to background
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final chatStore = _chatStoreRef;
    if (chatStore == null) return;
    
    try {
      if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
        // App is going to background - clear active chat so no auto read receipts
        print('[ChatDetailScreen] 📱 App going to background - clearing active chat');
        chatStore.clearActiveChat();
        FirebaseMessagingService.setContextActiveChatId(null); // ✅ NEW
      } else if (state == AppLifecycleState.resumed) {
        // App is coming back to foreground - restore active chat
        print('[ChatDetailScreen] 📱 App resumed - restoring active chat=${widget.conversation.userId}');
        chatStore.setActiveChat(widget.conversation.userId);
        FirebaseMessagingService.setContextActiveChatId(widget.conversation.userId); // ✅ NEW
        
        // Send read receipts for any messages that came in while backgrounded
        final messages = chatStore.messagesForUser(widget.conversation.userId);
        final unreadMessageIds = messages
            .where((msg) => msg.senderId == widget.conversation.userId && !msg.isRead && msg.id != 0)
            .map((msg) => msg.id)
            .toList();
        
        if (unreadMessageIds.isNotEmpty) {
          print('[ChatDetailScreen] 📖 Sending read receipts for ${unreadMessageIds.length} messages received while backgrounded');
          // ✅ Call async markMessagesRead and handle via .then()
          chatStore.markMessagesRead(widget.conversation.userId, messageIds: unreadMessageIds, currentUserId: _currentUserId).then((_) {
            _webSocketService.sendReadReceipt(widget.conversation.userId, unreadMessageIds);
            print('[ChatDetailScreen] ✅ Read receipts sent after resuming');
          }).catchError((e) {
            print('[ChatDetailScreen] ❌ Error marking messages as read on resume: $e');
          });
        }
      }
    } catch (e) {
      print('[ChatDetailScreen] Lifecycle state change error: $e');
    }
  }

  /// ✅ NEW: Called when WebSocket connection status changes
  void _onWebSocketConnectionChanged(bool isConnected) {
    if (mounted) {
      setState(() {
        // Trigger rebuild to update offline indicator and send button
      });
      if (isConnected) {
        print('[ChatDetailScreen] ✅ Back online - UI updated');
      } else {
        print('[ChatDetailScreen] ❌ Went offline - UI updated');
      }
    }
  }

  Future<void> _evaluateChatPermission() async {
    try {
      final profile =
          await ApiService.getUserProfile(widget.conversation.userId);
      final isPrivate = profile['isPrivate'] as bool? ?? false;
      final isFollowing = profile['isFollowing'] as bool? ?? false;
      final showActivityStatus = profile['showActivityStatus'] as bool? ?? true;
      final showReadReceipts = profile['showReadReceipts'] as bool? ?? true;
      if (mounted) {
        setState(() {
          _isTargetPrivate = isPrivate;
          _isTargetFollowing = isFollowing;
          _targetShowActivityStatus = showActivityStatus;
          _targetShowReadReceipts = showReadReceipts;
          _canSendMessages = !isPrivate || isFollowing; // public OR following
        });
      }
    } catch (e) {
      // On failure, default to conservative: block sending
      if (mounted) {
        setState(() {
          _canSendMessages = false;
        });
      }
    }
  }

  Future<void> _initializeWebSocket() async {
    try {
      final token = await ApiService.getToken();
      final profile = await ApiService.getMyProfile();
      _currentUserId = profile['userId'] as int? ?? 0;
      _currentUserName = profile['fullName'] as String? ?? profile['name'] as String? ?? 'Unknown';
      _currentUserProfilePic = profile['profilePic'] as String?;
      if (mounted) setState(() {}); // ensure UI alignment updates with current user id

      if (token != null && _currentUserId > 0) {
        print('[ChatDetailScreen] WebSocket: connecting with userId=$_currentUserId');
        // CRITICAL: Explicitly connect WebSocket for this user
        // This ensures proper connection/reconnection on app restart or user change
        try {
          await _webSocketService.connect(token, _currentUserId);
          print('[ChatDetailScreen] ✅ WebSocket connected for userId=$_currentUserId');
        } catch (e) {
          print('[ChatDetailScreen] ❌ WebSocket connection failed: $e');
        }
      }
      // Inform ChatStore of current user id so markMessagesRead can run safely.
      try {
        final chatStore = Provider.of<ChatStore>(context, listen: false);
        chatStore.setCurrentUserId(_currentUserId);
        print('[ChatDetailScreen] initialized currentUserId=$_currentUserId; chatStore set');
        // If this conversation was already marked active, now perform explicit
        // mark of unread messages as the current user id is known.
        if (chatStore.activeChatUserId == widget.conversation.userId) {
          try {
            print('[ChatDetailScreen] post-init markMessagesRead for other=${widget.conversation.userId} currentUser=$_currentUserId');
            // ✅ AWAIT the async markMessagesRead
            await chatStore.markMessagesRead(widget.conversation.userId, currentUserId: _currentUserId);
          } catch (e) {
            print('[ChatDetailScreen] post-init markMessagesRead error: $e');
          }
        }
      } catch (e) {
        print('[ChatDetailScreen] setCurrentUserId failed: $e');
      }
    } catch (e) {
      print('[Chat] Error initializing WebSocket: $e');
    }
  }

  // Message handling is now performed inside `ChatWebSocketService` and
  // the UI consumes the conversation list via `messagesForUser(otherUserId)`.

  /// ✅ NEW: Load current user ID from storage for offline mode
  Future<void> _loadCurrentUserId() async {
    try {
      final userId = await ApiService.getUserId();
      if (userId != null && userId > 0) {
        setState(() {
          _currentUserId = userId;
        });
        print('[ChatDetailScreen] ✅ Loaded currentUserId=$_currentUserId from storage');
      }
    } catch (e) {
      print('[ChatDetailScreen] Failed to load currentUserId from storage: $e');
    }
  }

  /// ✅ NEW: Handle connectivity changes
  void _onConnectivityChanged(bool isOnline) {
    print('[ChatDetailScreen] Connectivity changed: ${isOnline ? "🟢 ONLINE" : "🔴 OFFLINE"}');
    
    if (!mounted) return;
    
    setState(() {
      _isNetworkOnline = isOnline;
    });
    
    // Show toast notification
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isOnline ? '🟢 Back Online' : '🔴 You\'re Offline',
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: isOnline ? AppColors.primary : AppColors.danger,
      ),
    );
  }

  void _onUserTyping(String text) {
    try {
      final chatId = widget.conversation.userId;
      // If not yet indicated typing, send TYPING_START
      if (!_isTypingSent) {
        _webSocketService.sendTypingStart(chatId);
        _isTypingSent = true;
      }

      // Reset debounce timer to send TYPING_STOP after 1.5s of inactivity
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(milliseconds: 1500), () async {
        try {
          await _webSocketService.sendTypingStop(chatId);
        } catch (e) {
          print('[Chat] Error sending TYPING_STOP: $e');
        }
        _isTypingSent = false;
      });
    } catch (e) {
      print('[Chat] Error in typing handler: $e');
    }
  }

  void _onMessageReceived(Message message) {
    // legacy handler - not used when ChatStore is active
    print('[ChatDetailScreen] _onMessageReceived (legacy)');
  }

  Future<List<Message>> _loadMessages() async {
    // Removed: ChatScreen must not fetch conversation history on open.
    // ChatStore is the single source of truth and should be populated elsewhere.
    throw UnsupportedError('_loadMessages is disabled; ChatStore provides messages');
  }

  void _markVisibleMessagesAsRead() {
    // Removed: marking visible messages from UI is now handled by ChatStore/WebSocketService.
    throw UnsupportedError('_markVisibleMessagesAsRead is disabled; ChatStore handles reads');
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _markMessageAsRead(Message msg) {
    // Removed: UI must not mark messages as read directly; ChatStore and WebSocketService manage read receipts.
    throw UnsupportedError('_markMessageAsRead is disabled; ChatStore handles reads');
  }

  Future<void> _sendMessage() async {
    // ✅ NEW: Allow sending messages in offline mode (even if account is private)
    if (!_canSendMessages && _webSocketService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('This account is private. Follow to send messages.')),
      );
      return;
    }
    if (_messageController.text.isEmpty) return;

    final messageText = _messageController.text.trim();
    _messageController.clear();
    _draftSaveTimer?.cancel();
    if (!kIsWeb) {
      final conversationId = widget.conversation.conversationId;
      if (conversationId != null) {
        LocalChatRepository().clearDraft(conversationId).catchError((e) {
          print('[Chat] Error clearing draft: $e');
        });
      }
    }

    try {
      final recipientId = widget.conversation.userId;
      final chatStore = Provider.of<ChatStore>(context, listen: false);
      final clientMessageId = '${_currentUserId}_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}';
      
      // If offline or connection unstable, queue the message for retry
      if (!_isNetworkOnline) {
        print('[Chat] Network offline - queueing message with clock icon');
        
        // 1. Create optimistic message with PENDING status (⏱)
        final optimisticMessage = Message(
          id: 0,
          clientMessageId: clientMessageId,
          senderId: _currentUserId,
          senderName: _currentUserName,
          senderProfilePic: _currentUserProfilePic,
          recipientId: recipientId,
          content: messageText,
          status: MessageStatus.sending,  // ⏱ Clock icon
          createdAt: DateTime.now(),
          isRead: false,
        );
        
        // 2. Add to chat immediately so user sees ⏱
        chatStore.addIncomingMessage(optimisticMessage, _currentUserId);
        print('[Chat] Added optimistic message with ⏱ icon: $clientMessageId');
        
        // 3. Queue message to SQLite for retry when online
        final messageQueueService = MessageQueueService();
        await messageQueueService.queueMessage(
          clientMessageId: clientMessageId,
          chatId: recipientId,
          senderId: _currentUserId,
          receiverId: recipientId,
          content: messageText,
          createdAt: DateTime.now(),
        );
        
        print('[Chat] Message queued to SQLite: $clientMessageId');
      } else {
        // Online - send immediately via WebSocket
        print('[Chat] Network online - sending message immediately');
        
        // DON'T add optimistic message here - let ChatWebSocketService handle it
        // to avoid duplicate message in chat
        // Just send via WebSocket (it will create optimistic message internally)
        _webSocketService.sendChatMessage(recipientId, messageText);
      }
      
      print('[Chat] MESSAGE_SEND sent/queued to userId=$recipientId');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send message: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  bool _isImageUrl(String url) {
    final u = url.toLowerCase();
    return u.endsWith('.png') ||
        u.endsWith('.jpg') ||
        u.endsWith('.jpeg') ||
        u.endsWith('.gif') ||
        u.contains('/images/');
  }

  bool _isVideoUrl(String url) {
    final u = url.toLowerCase();
    return u.endsWith('.mp4') ||
        u.endsWith('.mov') ||
        u.endsWith('.m4v') ||
        u.endsWith('.webm') ||
        u.contains('/videos/');
  }

  String _messageKey(Message m) {
    if (m.id != 0) return 'id:${m.id}';
    return 'cid:${m.clientMessageId ?? ''}:${m.createdAt.toUtc().millisecondsSinceEpoch}';
  }

  Future<void> _pickAttachment() async {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo, color: AppColors.primary),
                title: const Text('Image'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final picker = ImagePicker();
                  final xfile = await picker.pickImage(
                      source: ImageSource.gallery, imageQuality: 95);
                  if (xfile == null) return;
                  
                  // Go to editor
                  final bytes = await xfile.readAsBytes();
                  final edited = await Navigator.push<Uint8List>(
                      context,
                      MaterialPageRoute(
                          builder: (_) => ChatImageEditor(imageBytes: bytes)));
                  
                  final Uint8List toUpload = edited ?? bytes;
                  final tempDir = await getTemporaryDirectory();
                  final f = File(
                      '${tempDir.path}/chat_img_${DateTime.now().millisecondsSinceEpoch}.jpg');
                  await f.writeAsBytes(toUpload);

                  // Perform optimistic send + upload
                  await _sendMediaMessage(f.path, label: 'photo', isLocalFile: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam, color: AppColors.primary),
                title: const Text('Video'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final picker = ImagePicker();
                  final xfile =
                      await picker.pickVideo(source: ImageSource.gallery);
                  if (xfile == null) return;
                  
                  // Perform optimistic send + upload
                  await _sendMediaMessage(xfile.path, label: 'video', isLocalFile: true);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _sendMediaMessage(String mediaPath,
      {required String label, bool isLocalFile = false}) async {
    if (!_canSendMessages) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('This account is private. Follow to send messages.')),
      );
      return;
    }

    try {
      String? finalUrl = mediaPath;
      String clientMessageId = '${_currentUserId}_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}';

      if (isLocalFile) {
        // 1. Create optimistic uploading message
        final optimisticMsg = Message(
          id: 0,
          clientMessageId: clientMessageId,
          senderId: _currentUserId,
          senderName: _currentUserName,
          senderProfilePic: _currentUserProfilePic,
          recipientId: widget.conversation.userId,
          content: label, // 'photo' or 'video'
          mediaUrl: mediaPath, // Local path
          status: MessageStatus.uploading,
          createdAt: DateTime.now(),
          isRead: false,
        );

        // 2. Add to store immediately for UI update
        final chatStore = Provider.of<ChatStore>(context, listen: false);
        chatStore.addIncomingMessage(optimisticMsg, _currentUserId);
        _scrollToBottom();

        try {
          // 3. Upload the file
          finalUrl = await ApiService.uploadMedia(mediaPath);
          
          // 4. Send real message (this updates optimistic message to 'sending' and sets remote URL)
          // We must use the SAME clientMessageId so reconciliation works
          _webSocketService.sendChatMessage(
            widget.conversation.userId,
            label,
            mediaUrl: finalUrl,
            clientMessageId: clientMessageId,
          );
        } catch (e) {
            // Upload failure
            print('[ChatDetailScreen] Upload failed: $e');
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Upload failed: $e'))
            );
            // Remove optimistic message on failure
            chatStore.removeMessage(widget.conversation.userId, clientMessageId);
            return;
        }
      } else {
        // Fallback for non-local files (shouldn't happen with this flow)
        await _webSocketService.sendMessage(
          widget.conversation.userId,
          label,
          mediaUrl: mediaPath,
        );
      }
      _scrollToBottom();
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to send media: $e')));
    }
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    // Flush any pending debounced draft save immediately instead of losing
    // it — must read .text and cancel the timer BEFORE disposing the
    // controller. Fire-and-forget (dispose is sync); errors are logged, not
    // thrown, matching every other cleanup call in this method.
    _draftSaveTimer?.cancel();
    if (!kIsWeb) {
      final conversationId = widget.conversation.conversationId;
      final pendingText = _messageController.text;
      if (conversationId != null) {
        LocalChatRepository().saveDraft(conversationId, pendingText).catchError((e) {
          print('[Chat] Error saving draft on dispose: $e');
        });
      }
    }
    _messageController.removeListener(_onMessageTextChanged);
    _messageController.dispose();
    _scrollController.dispose();
    // Cancel typing timer and send typing=false if needed
    _typingTimer?.cancel();
    if (_isTypingSent) {
      try {
        // use explicit stop endpoint
        _webSocketService.sendTypingStop(widget.conversation.userId);
      } catch (e) {
        print('[Chat] Error sending typing=false on dispose: $e');
      }
    }

    // Cancel any timers/listeners owned by the screen
    _participantTypingTimer?.cancel();
    
    // ✅ NEW: Remove connectivity listener
    _connectivityService.removeListener(_onConnectivityChanged);
    
    // ✅ Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);
    
    // ✅ Clear active chat marker using stored reference (context may be invalid in dispose)
    if (_chatStoreRef != null) {
      _chatStoreRef!.clearActiveChat();
      FirebaseMessagingService.setContextActiveChatId(null); // ✅ NEW
      print('[ChatDetailScreen] ✅ clearActiveChat (dispose) - using stored reference');
    } else {
      // Fallback to Provider (may fail)
      try {
        final chatStore = Provider.of<ChatStore>(context, listen: false);
        chatStore.clearActiveChat();
        FirebaseMessagingService.setContextActiveChatId(null); // ✅ NEW
        print('[ChatDetailScreen] clearActiveChat (dispose) - using Provider');
      } catch (e) {
        print('[ChatDetailScreen] ❌ clearActiveChat failed in dispose: $e');
      }
    }
    // NOTE: do NOT unsubscribe from the chat topic on dispose. ChatStore is
    // the single source of truth and UI reads state from it.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conv = widget.conversation;
    final chatIdForUi = conv.userId;
    final theme = Theme.of(context);

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          // ✅ Clear active chat when system back button/gesture is used
          _chatStoreRef?.clearActiveChat();
          FirebaseMessagingService.setContextActiveChatId(null); // ✅ NEW
          print('[ChatDetailScreen] ✅ clearActiveChat (system back/pop)');
        }
      },
      child: Scaffold(
      appBar: AppBar(
        backgroundColor: theme.cardColor,
        elevation: 0.5,
        leading: widget.embedded
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back, color: AppColors.primary),
                onPressed: () {
                  // ✅ Clear active chat BEFORE navigating back
                  _chatStoreRef?.clearActiveChat();
                  FirebaseMessagingService.setContextActiveChatId(null); // ✅ NEW
                  print('[ChatDetailScreen] ✅ clearActiveChat (back button pressed)');
                  Navigator.of(context).pop();
                },
              ),
        automaticallyImplyLeading: !widget.embedded,
        title: GestureDetector(
          onTap: () {
            // ✅ Navigate to user profile when tapping avatar/name
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => UserProfileScreen(userId: conv.userId),
              ),
            );
          },
          child: Row(
            children: [
              SquircleAvatar(
                size: 40,
                imageUrl: conv.profilePictureUrl != null && conv.profilePictureUrl!.isNotEmpty
                    ? (conv.profilePictureUrl!.startsWith('http')
                        ? conv.profilePictureUrl!
                        : '${ApiConfig.serverUrl}/api/social${conv.profilePictureUrl}')
                    : null,
                initials: conv.fullName.isNotEmpty ? conv.fullName[0].toUpperCase() : 'U',
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conv.fullName,
                    style: TextStyle(
                      color: theme.textTheme.bodyMedium?.color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Consumer<ChatStore>(
                    builder: (context, chatStore, child) {
                      final isOnline = chatStore.isUserOnline(conv.userId);
                      final isTyping = chatStore.isUserTyping(conv.userId);
                      
                      print('[ChatScreen] 📊 ConvItem REBUILD: user=${conv.userId} isTyping=$isTyping isOnline=$isOnline');
                      
                      // Show typing status first, then online/offline
                      String statusText;
                      Color statusColor;
                      
                      if (isTyping) {
                        statusText = 'typing...';
                        statusColor = AppColors.primary;
                        print('[ChatScreen]    ✅ TYPING DETECTED - displaying "typing..."');
                      } else if (_targetShowActivityStatus) {
                        statusText = isOnline ? 'Online' : 'Offline';
                        statusColor = isOnline ? AppColors.primary : AppColors.mutedSolid;
                      } else {
                        statusText = 'Active now';
                        statusColor = AppColors.primary;
                      }
                      
                      return Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 12,
                          fontStyle: isTyping ? FontStyle.italic : FontStyle.normal,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call, color: AppColors.primary),
            onPressed: () => _startCall(conv.userId, false),
          ),
          IconButton(
            icon: const Icon(Icons.videocam, color: AppColors.primary),
            onPressed: () => _startCall(conv.userId, true),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ✅ NEW: Show offline indicator when not connected
            if (!_isNetworkOnline)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                color: AppColors.danger.withValues(alpha: 0.15),
                child: Row(
                  children: [
                    Icon(Icons.wifi_off, color: AppColors.danger, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'You\'re offline',
                      style: TextStyle(
                        color: AppColors.danger,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            // ✅ NEW: Hide private account warning in offline mode (allow messaging locally)
            if (!_canSendMessages && _isNetworkOnline)
              Container(
                width: double.infinity,
                color: AppColors.goldSubtle100,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: const [
                    Icon(Icons.lock, color: AppColors.gold),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This account is private. Follow to send messages.',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Consumer<ChatStore>(
                builder: (context, chatStore, child) {
                  final chatIdForUi = widget.conversation.userId;
                  final msgs = chatStore.messagesForUser(chatIdForUi);
                  // Auto-scroll when a new message arrives (compare a lightweight key)
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    if (msgs.isEmpty) return;
                    final last = msgs.last;
                    final newKey = _messageKey(last);
                    if (newKey != _lastMessageKey) {
                      _lastMessageKey = newKey;
                      _scrollToBottom();
                    }
                  });
                  if (msgs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.message, size: 64, color: AppColors.mutedSolid),
                          const SizedBox(height: 16),
                          Text(
                            'No messages yet. Start a conversation!',
                            style: TextStyle(color: AppColors.mutedSolid),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                    itemCount: msgs.length,
                    itemBuilder: (context, index) {
                      final msg = msgs[index];
                      final isMine = msg.senderId == _currentUserId;
                      return Align(
                        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75,
                          ),
                          decoration: BoxDecoration(
                            color: isMine ? theme.colorScheme.primary : theme.cardColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Column(
                            crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              // S3: a DM sent as a status reply shows what it answers.
                              if (msg.isStatusReply)
                                _buildStatusReplyRef(msg, isMine, theme),
                              if (msg.mediaUrl != null && msg.mediaUrl!.isNotEmpty)
                                _buildMediaBubble(msg, isMine, theme)
                              else
                                Text(
                                  msg.content,
                                  style: TextStyle(
                                    color: isMine ? Colors.white : theme.textTheme.bodyMedium?.color,
                                  ),
                                ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    msg.timeAgo,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isMine ? Colors.white70 : AppColors.mutedSolid,
                                    ),
                                  ),
                                  if (isMine) ...[
                                    const SizedBox(width: 4),
                                    _buildReadReceipt(msg),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            // Typing indicator (driven by ChatStore)
            Consumer<ChatStore>(
              builder: (context, chatStore, child) {
                final chatIdForUi = widget.conversation.userId;
                final isTyping = chatStore.isUserTyping(chatIdForUi);
                print('[ChatScreen-DETAIL] 🔤 Typing indicator REBUILD: chatId=$chatIdForUi isTyping=$isTyping');
                if (!isTyping) {
                  print('[ChatScreen-DETAIL]    └─ Not typing, returning SizedBox.shrink()');
                  return const SizedBox.shrink();
                }
                print('[ChatScreen-DETAIL]    ✅ DISPLAYING typing indicator: "${widget.conversation.fullName} is typing…"');
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  color: Colors.transparent,
                  child: Text(
                    '${widget.conversation.fullName} is typing…',
                    style: TextStyle(color: AppColors.mutedSolid, fontStyle: FontStyle.italic),
                  ),
                );
              },
            ),
            // Message input
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.cardColor,
                border: Border(top: BorderSide(color: theme.dividerColor)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: AppColors.primary),
                    onPressed: _canSendMessages && _isNetworkOnline ? _pickAttachment : null,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      onChanged: _onUserTyping,
                      decoration: InputDecoration(
                        hintText: 'Message...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: theme.scaffoldBackgroundColor,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                      ),
                      // ✅ NEW: Allow input in offline mode even if account is private
                      enabled: !_isLoading && (_canSendMessages || !_webSocketService.isConnected),
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.send,
                      color: AppColors.primary,
                    ),
                    onPressed: (!_isLoading && _canSendMessages && _isNetworkOnline) 
                      ? _sendMessage 
                      : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ), // Scaffold
    ); // PopScope
  }
}

extension _MediaWidgets on _ChatDetailScreenState {
  Widget _buildMediaBubble(Message msg, bool isMine, ThemeData theme) {
    final url = msg.mediaUrl!;
    final isUploading = msg.status == MessageStatus.uploading;
    final isLocal = !url.startsWith('http');

    Widget childWidget;

    if (_isImageUrl(url)) {
      // Check for forwarded post token
      final content = msg.content;
      final forwardedPrefix = 'FORWARDED_POST:';
      if (content.startsWith(forwardedPrefix)) {
        try {
          final parts = content.split('|');
          final token = parts.first; 
          final idStr = token.substring(forwardedPrefix.length);
          final postId = int.tryParse(idStr);
          if (postId != null) {
            // Forwarded post logic - fetch post (network only mostly)
            childWidget = GestureDetector(
              onTap: () async {
                try {
                  final post = await ApiService.getPost(postId);
                  if (!mounted) return;
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => PostDetailScreen(post: post)));
                } catch (e) {
                  // Fallback
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => FullscreenImageViewer(imageUrl: url)));
                }
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  url,
                  width: 200,
                  height: 200,
                  fit: BoxFit.cover,
                ),
              ),
            );
          } else {
             // Fallback
             childWidget = const SizedBox(); 
          }
        } catch (_) {
          childWidget = const SizedBox();
        }
      } else {
        // Standard Image
        Widget imageDisplay;
        if (isLocal) {
          imageDisplay = Image.file(
            File(url),
            width: 200,
            height: 200,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
               return Container(
                 width: 200, height: 200,
                 color: AppColors.border,
                 child: const Icon(Icons.broken_image, color: AppColors.mutedSolid),
               );
            },
          );
        } else {
          imageDisplay = Image.network(
            url,
            width: 200,
            height: 200,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
                 width: 200, height: 200,
                 color: AppColors.border,
                 child: const Icon(Icons.broken_image, color: AppColors.mutedSolid),
            ),
          );
        }

        childWidget = GestureDetector(
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => FullscreenImageViewer(imageUrl: url))),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: imageDisplay,
          ),
        );
      }
    } else if (_isVideoUrl(url)) {
      childWidget = FutureBuilder<Uint8List?>(
        future: VideoThumbnail.thumbnailData(
          video: url,
          imageFormat: ImageFormat.PNG,
          maxWidth: 220,
          quality: 25,
        ),
        builder: (context, snapshot) {
          Widget thumb;
          if (snapshot.connectionState == ConnectionState.done &&
              snapshot.hasData) {
            thumb = ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                snapshot.data!,
                width: 220,
                height: 140,
                fit: BoxFit.cover,
              ),
            );
          } else {
            thumb = Container(
              width: 220,
              height: 140,
              decoration: BoxDecoration(
                color: isMine ? Colors.white12 : AppColors.surface2,
                borderRadius: BorderRadius.circular(8),
              ),
            );
          }
          return GestureDetector(
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => FullscreenVideoPlayer(videoUrl: url))),
            child: Stack(
              alignment: Alignment.center,
              children: [
                thumb,
                Container(
                  width: 220,
                  height: 140,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.play_circle_fill, color: AppColors.primary, size: 48),
                    SizedBox(height: 8),
                    Text('Tap to play video',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          );
        },
      );
    } else {
      childWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.audiotrack, color: AppColors.primary),
          SizedBox(width: 6),
          Text('Audio attachment'),
        ],
      );
    }

    if (isUploading) {
      return Stack(
        alignment: Alignment.center,
        children: [
          Opacity(opacity: 0.6, child: childWidget),
          Container(
            width: 200,
            height: _isVideoUrl(url) ? 140 : 200, 
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          ),
        ],
      );
    }

    return childWidget;
  }

  void _startCall(int toUserId, bool isVideo) {
    print('[ChatScreen] 📞 _startCall CLICKED video=$isVideo toUserId=$toUserId myUserId=$_currentUserId');
    if (toUserId <= 0 || _currentUserId <= 0) {
      print('[ChatScreen] ❌ userId or myUserId is invalid');
      return;
    }
    
    final callerId = _currentUserId;
    final channel = 'chat_${callerId}_$toUserId';
    print('[ChatScreen] 📞 channel=$channel callerId=$callerId');

    final cm = CallStateManager();
    print('[ChatScreen] 📞 current state=${cm.currentState}');
    // Only initiate an outgoing call if manager is currently idle.
    if (cm.currentState != CallState.idle) {
      print('[ChatScreen] ❌ NOT IN IDLE STATE, cannot start call');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A call is already in progress')),
      );
      return;
    }

    final payload = {
      'fromUserId': callerId,
      'toUserId': toUserId,
      'channelName': channel,
      'isVideo': isVideo,
    };
    print('[ChatScreen] 📞 payload=$payload');

    // Update state first, then send invite. Per rules: do NOT navigate or start Agora here.
    // CallingLoaderScreen will be shown automatically by CallOverlayManager
    print('[ChatScreen] 📞 calling cm.setOutgoingCall()');
    cm.setOutgoingCall(payload);
    print('[ChatScreen] 📞 calling CallSignalingService().sendCallInvite()');
    CallSignalingService().sendCallInvite(
      fromUserId: callerId,
      toUserId: toUserId,
      channelName: channel,
      isVideo: isVideo,
    );
    print('[ChatScreen] ✅ sendCallInvite sent successfully');
  }

  /// S3: small card above a reply showing the status it answers.
  /// Uses the snapshot stored on the message, so it still renders after the
  /// status has expired or been deleted.
  /// Open the status a bubble refers to. The status may well be gone - it
  /// only lives 24h and the chat message outlives it - so say so plainly
  /// rather than surfacing an error.
  Future<void> _openTaggedStatus(Message msg) async {
    final statusId = msg.replyToStatusId;
    if (statusId == null) return;
    try {
      final group = await StatusApi.fetchOne(statusId);
      if (!mounted) return;
      if (group == null || group.statuses.isEmpty) {
        Fluttertoast.showToast(msg: 'This status is no longer available');
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StatusViewerScreen(groups: [group], initialGroupIndex: 0),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Fluttertoast.showToast(msg: 'Could not open status');
    }
  }

  Widget _buildStatusReplyRef(Message msg, bool isMine, ThemeData theme) {
    final onBubble = isMine ? Colors.white : theme.textTheme.bodyMedium?.color;
    final isMedia = msg.replyToStatusType != null &&
        msg.replyToStatusType != 'TEXT' &&
        (msg.replyToStatusPreview?.startsWith('http') ?? false);

    return GestureDetector(
      onTap: () => _openTaggedStatus(msg),
      child: Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: (isMine ? Colors.white : theme.dividerColor).withOpacity(0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
              color: (onBubble ?? AppColors.mutedSolid).withOpacity(0.7), width: 3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isMedia)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                msg.replyToStatusPreview!,
                width: 32,
                height: 32,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Icon(Icons.image, size: 20, color: onBubble),
              ),
            )
          else
            Icon(Icons.auto_awesome, size: 14, color: onBubble),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(msg.isStatusReaction ? 'Reacted to status' : 'Replied to status',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: onBubble?.withOpacity(0.9))),
                if (!isMedia &&
                    msg.replyToStatusPreview != null &&
                    msg.replyToStatusPreview!.isNotEmpty)
                  Text(
                    msg.replyToStatusPreview!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11, color: onBubble?.withOpacity(0.75)),
                  ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildReadReceipt(Message msg) {
    // If target user has disabled read receipts, always show single tick
    // When the recipient has read receipts disabled we must still show the real
    // delivery state (pending / failed) - only the read (✓✓) distinction is
    // suppressed. Previously this returned a single tick for every state, which
    // made unsent messages look delivered.
    if (!_targetShowReadReceipts &&
        msg.status != MessageStatus.sending &&
        msg.status != MessageStatus.failed &&
        msg.status != MessageStatus.uploading) {
      return Icon(
        Icons.done,
        size: 14,
        color: Colors.white70,
      );
    }
    // Determine delivery/read state using MessageStatus. Be defensive: during
    // hot-reload some existing Message instances may lack the new `status`
    // field; fall back to inferred status based on server id/readAt.
    final MessageStatus status = (msg.status != null)
        ? msg.status
        : (msg.id != 0
            ? (msg.readAt != null ? MessageStatus.read : MessageStatus.sent)
            : MessageStatus.sending);

    Widget child;
    switch (status) {
      case MessageStatus.sending:
        child = const Icon(
          Icons.access_time,
          key: ValueKey('sending'),
          size: 14,
          color: Colors.white70,
        );
        break;
      case MessageStatus.uploading:
        child = SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
          ),
        );
        break;
      case MessageStatus.failed:
        child = const Icon(
          Icons.error_outline,
          key: ValueKey('failed'),
          size: 14,
          color: Color(0xFFFFCDD2), // light red - visible on the green bubble
        );
        break;
      case MessageStatus.read:
        child = Icon(
          Icons.done_all,
          key: const ValueKey('read'),
          size: 14,
          color: Colors.white70,  // 📖 White double ticks for read messages
        );
        break;
      case MessageStatus.sent:
      case MessageStatus.delivered:
        child = Icon(
          Icons.done,
          key: const ValueKey('delivered'),
          size: 14,
          color: Colors.white70,
        );
        break;
    }

    final indicator = AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
      child: child,
    );

    // A failed message is actionable: tapping it re-sends using the original
    // clientMessageId so the existing bubble is reused rather than duplicated.
    if (status == MessageStatus.failed && msg.clientMessageId != null) {
      return GestureDetector(
        onTap: () {
          _webSocketService.retryFailedMessage(
            recipientId: widget.conversation.userId,
            clientMessageId: msg.clientMessageId!,
            content: msg.content,
            mediaUrl: msg.mediaUrl,
          );
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Retrying...'), duration: Duration(seconds: 1)),
          );
        },
        child: Tooltip(
          message: 'Not sent - tap to retry',
          child: indicator,
        ),
      );
    }

    return indicator;
  }

}
/// Compatibility wrapper for old ChatScreen API (used by router)
/// Converts ChatModel to Conversation and delegates to ChatDetailScreen
class ChatScreen extends StatelessWidget {
  final ChatModel chat;

  const ChatScreen({super.key, required this.chat});

  @override
  Widget build(BuildContext context) {
    // Convert ChatModel to Conversation for compatibility
    final conversation = Conversation(
      userId: int.tryParse(chat.id) ?? 0,
      username: chat.name.replaceAll(' ', '').toLowerCase(),
      fullName: chat.name,
      profilePictureUrl: null, // ChatModel doesn't have picture URL
      lastMessage: null,
      lastMessageTime: null,
      unreadCount: 0,
      isOnline: chat.online,
    );

    return ChatDetailScreen(conversation: conversation);
  }
}
