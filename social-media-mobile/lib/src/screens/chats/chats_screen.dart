import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/message.dart';
import '../../services/api_service.dart';
import '../../services/chat_websocket_service.dart';
import 'package:provider/provider.dart';
import '../../state/chat_store.dart';
import 'chat_screen.dart';
import 'new_chat_screen.dart';
import '../../models/group.dart';
import '../../services/group_api.dart';
import '../groups/create_group_screen.dart';
import '../groups/group_chat_screen.dart';
import '../../database/local_chat_repository.dart';
import '../calls/calls_screen.dart';
import '../../components/squircle_avatar.dart';
import 'package:social_chat_app/src/theme/colors.dart';
// Call invite handling moved to global CallOverlayManager; imports removed

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  @override
  bool get wantKeepAlive => true;

  /// Re-sync conversations (and therefore unread counts) when the app returns
  /// to the foreground. Messages that arrived via push while backgrounded are
  /// not in the store, so without this the badges stay stale until some other
  /// action happens to trigger a reload.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && mounted) {
      print('[ChatsScreen] ▶️ App resumed - refreshing conversations/unread counts');
      unawaited(_refreshOnResume());
      unawaited(_loadGroups());
    }
  }

  Future<void> _refreshOnResume() async {
    try {
      final refreshed = await _loadConversations();
      if (!mounted) return;
      setState(() {
        _conversations = refreshed;
        _filterConversations();
      });
    } catch (e) {
      print('[ChatsScreen] ⚠️ Resume refresh failed: $e');
    }
  }

  late Future<List<Conversation>> _conversationsFuture;
  List<Conversation> _conversations = [];
  List<Conversation> _filteredConversations = [];
  int _currentUserId = 0;
  // Invite subscription removed — handled globally by CallOverlayManager
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = false;
  bool _selectionMode = false;
  final Set<int> _selectedUserIds = {};
  late ChatWebSocketService _webSocketService;
  Timer? _timestampRefreshTimer;
  
  // 🔴 PERFORMANCE FIX: Track last known conversation user IDs to avoid reloading on just typing
  Set<int> _lastKnownConversationUserIds = {};
  Map<int, String?> _lastMessageContentByUser = {};

  // G1: my group conversations (shown in a section above 1:1 chats)
  List<GroupSummary> _groups = [];

  Future<void> _loadGroups() async {
    try {
      final groups = await GroupApi.fetchMyGroups();
      if (mounted) setState(() => _groups = groups);
    } catch (e) {
      print('[ChatsScreen] ⚠️ Failed to load groups: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _webSocketService = ChatWebSocketService();
    WidgetsBinding.instance.addObserver(this); // for resume-time refresh
    _conversationsFuture = _loadConversations();
    _loadGroups();
    _initProfile();
    _searchController.addListener(_filterConversations);
    
    // Listen for ChatStore changes (new messages arriving)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final chatStore = Provider.of<ChatStore>(context, listen: false);
        chatStore.addListener(_onChatStoreChanged);
      } catch (_) {}
    });
    
    // ✅ NEW: Listen for WebSocket reconnection and auto-load conversations
    // When user was offline and reconnects, they should see new messages immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _webSocketService.addConnectionListener(_onWebSocketConnectionChanged);
    });
    
    // Listen for new conversation notifications
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _webSocketService.subscribeToNotifications(_handleNotification);
    });

    // ✅ NEW: Refresh timestamps every minute so they stay accurate (just now → 1m → 2m, etc)
    _timestampRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {
          // Trigger rebuild to recalculate timeAgo for all conversations
        });
      }
    });
  }

  void _onChatStoreChanged() {
    // When ChatStore changes (new message OR typing indicator), check if we need to reload
    if (!mounted) return;
    
    try {
      final chatStore = Provider.of<ChatStore>(context, listen: false);
      bool needsUpdate = false;
      
      // Get all users that have messages in ChatStore
      final allMessagesMap = chatStore.allConversations;
      final currentUserIds = allMessagesMap.keys.toSet();
      
      // 🔴 OPTIMIZATION: Only reload if conversation list structure changed
      // Don't reload on every typing indicator change - only on NEW conversations or ACTUAL messages
      
      // Check if there are NEW users (new conversations)
      final newUserIds = currentUserIds.difference(_lastKnownConversationUserIds);
      if (newUserIds.isNotEmpty) {
        print('[ChatsScreen] 🔴 NEW CONVERSATION DETECTED from userIds: $newUserIds');
        print('[ChatsScreen] 🔴 Reloading conversations to add new chats...');
        needsUpdate = true;
      }
      
      // Check if any ACTUAL MESSAGE content changed (not just typing)
      if (!needsUpdate) {
        for (final userId in currentUserIds) {
          final messages = allMessagesMap[userId];
          if (messages != null && messages.isNotEmpty) {
            final lastMsg = messages.last;
            final lastKnownContent = _lastMessageContentByUser[userId];
            
            // Only update if message content actually changed (not just typing status)
            if (lastKnownContent != lastMsg.content) {
              print('[ChatsScreen] ✅ NEW MESSAGE from userId=$userId');
              needsUpdate = true;
              break;
            }
          }
        }
      }
      
      // Only reload if there's actual structural change, not just typing
      if (needsUpdate && mounted) {
        print('[ChatsScreen] ⏰ Reloading conversations due to new message/conversation...');
        
        // Update tracking before reloading
        _lastKnownConversationUserIds = currentUserIds;
        for (final userId in currentUserIds) {
          final messages = allMessagesMap[userId];
          if (messages != null && messages.isNotEmpty) {
            _lastMessageContentByUser[userId] = messages.last.content;
          }
        }
        
        // 🔴 FIX: Load new conversations WITHOUT reassigning _conversationsFuture
        // This prevents re-showing loader when new messages arrive
        // The FutureBuilder stays in "done" state; only the list data updates
        _loadConversations().then((newConversations) {
          if (mounted) {
            setState(() {
              _conversations = newConversations;
              _filteredConversations = newConversations;
              
              // Update tracking after reloading
              _lastKnownConversationUserIds = newConversations.map((c) => c.userId).toSet();
              for (final conv in newConversations) {
                _lastMessageContentByUser[conv.userId] = conv.lastMessage;
              }
            });
          }
        });
      } else {
        // Even if we don't reload, update the tracking for next comparison
        _lastKnownConversationUserIds = currentUserIds;
        for (final userId in currentUserIds) {
          final messages = allMessagesMap[userId];
          if (messages != null && messages.isNotEmpty) {
            _lastMessageContentByUser[userId] = messages.last.content;
          }
        }
      }
    } catch (e) {
      if (mounted) {
        print('[ChatsScreen] Error in _onChatStoreChanged: $e');
      }
    }
  }

  /// ✅ NEW: Called when WebSocket connection status changes
  /// When user reconnects after being offline, auto-load conversations
  /// This ensures they see any new messages that arrived while offline
  void _onWebSocketConnectionChanged(bool isConnected) {
    if (!mounted) return;
    
    if (isConnected) {
      print('[ChatsScreen] 🟢 WebSocket CONNECTED - auto-loading conversations');
      // Reload conversations from server to get any new messages while offline
      if (mounted) {
        setState(() {
          _conversationsFuture = _loadConversations();
        });
      }
    } else {
      print('[ChatsScreen] 🔴 WebSocket DISCONNECTED');
    }
  }

  void _handleNotification(Map<String, dynamic> notification) {
    final type = notification['type'] as String? ?? '';
    
    if (type == 'new_conversation' || type == 'new_message') {
      final senderId = notification['senderId'] as int? ?? notification['userId'] as int? ?? 0;
      if (senderId > 0) {
        print('[ChatsScreen] ✅ New conversation detected from user $senderId - refreshing...');
        // Instantly reload conversations to add the new chat
        // This triggers without user needing to restart app
        if (mounted) {
          setState(() {
            _conversationsFuture = _loadConversations();
          });
        }
      }
    } else if (type == 'new_group_message') {
      // Refresh group unread badges live, same as 1:1 conversations above.
      if (mounted) _loadGroups();
    }
  }

  Future<void> _initProfile() async {
    try {
      final chatStore = Provider.of<ChatStore>(context, listen: false);
      final profile = await ApiService.getMyProfile();
      _currentUserId = profile['userId'] as int? ?? 0;
      // inform ChatStore of current user if provider exists
      try {
        if (_currentUserId != 0) chatStore.setCurrentUserId(_currentUserId);
      } catch (_) {}
    } catch (e) {
      print('[ChatsScreen] failed to load profile: $e');
    }
  }

  Future<List<Conversation>> _loadConversations() async {
    try {
      // ✅ NEW: Try to load from API, fall back to SQLite if offline
      try {
        final conversations = await ApiService.getConversations();

        // Seed unread cache from backend so badges survive app restarts.
        // Batched: one notify for the whole set instead of one per conversation.
        try {
          final chatStore = Provider.of<ChatStore>(context, listen: false);
          chatStore.seedUnreadCounts({
            for (final conv in conversations) conv.userId: conv.unreadCount,
          });
        } catch (e) {
          print('[ChatsScreen] ⚠️ Failed seeding unread cache from API: $e');
        }

        // ✅ NEW: Save conversations to SQLite for offline access
        try {
          for (final conv in conversations) {
            final repo = LocalChatRepository();
            await repo.upsertConversation(
              SQLiteConversation(
                chatId: conv.userId,
                otherUserId: conv.userId,
                otherUserName: conv.fullName,
                otherUserProfilePic: conv.profilePictureUrl,
                lastMessage: conv.lastMessage,
                lastMessageTime: conv.lastMessageTime?.millisecondsSinceEpoch,
                unreadCount: conv.unreadCount,
              ),
            );
          }
          print('[ChatsScreen] 💾 Saved ${conversations.length} conversations to SQLite');
        } catch (e) {
          print('[ChatsScreen] ⚠️ Failed to save conversations to SQLite: $e (non-blocking)');
        }
        
        // 🔴 FIX: Only call setState if widget is still mounted
        if (mounted) {
          setState(() {
            _conversations = conversations;
            _filteredConversations = conversations;
            
            // 🔴 OPTIMIZATION: Update tracking after loading conversations
            // This prevents unnecessary reloads on typing indicators
            _lastKnownConversationUserIds = conversations.map((c) => c.userId).toSet();
            for (final conv in conversations) {
              _lastMessageContentByUser[conv.userId] = conv.lastMessage;
            }
          });
        }
        
        return conversations;
      } catch (apiError) {
        print('[ChatsScreen] 🔄 API load failed: $apiError, trying SQLite...');
        
        // Fall back to loading from SQLite when offline
        final repo = LocalChatRepository();
        final sqliteConversations = await repo.loadAllConversations();
        
        if (sqliteConversations.isEmpty) {
          print('[ChatsScreen] ❌ SQLite also empty - no cached data available');
          throw Exception('No offline data available. Network error: $apiError');
        }
        
        print('[ChatsScreen] ✅ Loaded ${sqliteConversations.length} conversations from SQLite');
        
        // Convert SQLite conversations to Conversation objects
        List<Conversation> offlineConversations = [];
        for (final conv in sqliteConversations) {
          offlineConversations.add(
            Conversation(
              userId: conv.otherUserId,
              username: conv.otherUserId.toString(),
              fullName: conv.otherUserName ?? 'Unknown',
              profilePictureUrl: conv.otherUserProfilePic,
              lastMessage: conv.lastMessage ?? '[Offline - No recent message]',
              lastMessageTime: conv.lastMessageTime != null 
                ? DateTime.fromMillisecondsSinceEpoch(conv.lastMessageTime!)
                : null,
              unreadCount: conv.unreadCount,
              isOnline: false, // Can't determine online status offline
            ),
          );
        }
        
        if (mounted) {
          setState(() {
            _conversations = offlineConversations;
            _filteredConversations = offlineConversations;
            _lastKnownConversationUserIds = offlineConversations.map((c) => c.userId).toSet();
            for (final conv in offlineConversations) {
              _lastMessageContentByUser[conv.userId] = conv.lastMessage;
            }
          });

          // Seed unread cache from SQLite-backed conversations as well (batched).
          try {
            final chatStore = Provider.of<ChatStore>(context, listen: false);
            chatStore.seedUnreadCounts({
              for (final conv in offlineConversations) conv.userId: conv.unreadCount,
            });
          } catch (e) {
            print('[ChatsScreen] ⚠️ Failed seeding unread cache from SQLite: $e');
          }
          
          // Show offline indicator
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('📵 Offline Mode'),
              duration: const Duration(seconds: 3),
              backgroundColor: AppColors.goldLight700,
            ),
          );
        }
        
        return offlineConversations;
      }
    } catch (e) {
      print('[ChatsScreen] ❌ Error loading conversations: $e');
      rethrow;
    }
  }

  void _filterConversations() {
    setState(() {
      if (_searchController.text.isEmpty) {
        _filteredConversations = _conversations;
      } else {
        _filteredConversations = _conversations
            .where((c) => c.fullName
                .toLowerCase()
                .contains(_searchController.text.toLowerCase()))
            .toList();
      }
    });
  }

  void _toggleSelection(Conversation c) {
    setState(() {
      _selectionMode = true;
      if (_selectedUserIds.contains(c.userId)) {
        _selectedUserIds.remove(c.userId);
      } else {
        _selectedUserIds.add(c.userId);
      }
      if (_selectedUserIds.isEmpty) {
        _selectionMode = false;
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectionMode = false;
      _selectedUserIds.clear();
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedUserIds.isEmpty) return;
    // 🔴 FIX: Only call setState if widget is still mounted
    if (mounted) {
      setState(() => _isLoading = true);
    }
    try {
      for (final uid in _selectedUserIds.toList()) {
        await ApiService.deleteConversation(uid);
        _conversations.removeWhere((c) => c.userId == uid);
      }
      _filteredConversations = _conversations;
      _clearSelection();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    } finally {
      // 🔴 FIX: Only call setState if widget is still mounted
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _timestampRefreshTimer?.cancel();  // ✅ Cancel timestamp refresh timer
    try {
      final chatStore = Provider.of<ChatStore>(context, listen: false);
      chatStore.removeListener(_onChatStoreChanged);
    } catch (_) {}
    _webSocketService.unsubscribeFromNotifications(_handleNotification);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final primary = AppColors.primary;
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (!_selectionMode)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'YOUR CIRCLES',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                            color: primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('Connect', style: theme.textTheme.displaySmall),
                      ],
                    )
                  else
                    Text('Connect', style: theme.textTheme.displaySmall),
                  if (!_selectionMode)
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Calls',
                          icon: Icon(Icons.call_outlined, color: primary),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => CallsScreen()),
                          ),
                        ),
                        IconButton(
                          tooltip: 'New group',
                          icon: Icon(Icons.group_add, color: primary),
                          onPressed: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
                            );
                            _loadGroups(); // refresh after returning from create/chat
                          },
                        ),
                        Container(
                          margin: const EdgeInsets.only(left: 4),
                          decoration: BoxDecoration(
                            color: primary,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: IconButton(
                            tooltip: 'New message',
                            icon: const Icon(Icons.edit_outlined, color: Colors.white, size: 20),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const NewChatScreen()),
                              ).then((_) {
                                if (mounted) {
                                  setState(() {
                                    _conversationsFuture = _loadConversations();
                                  });
                                }
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  if (_selectionMode)
                    Row(children: [
                      Text('${_selectedUserIds.length}', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 12),
                      IconButton(
                        tooltip: 'Delete selected',
                        icon: const Icon(Icons.delete, color: AppColors.danger),
                        onPressed: _isLoading ? null : _deleteSelected,
                      ),
                      IconButton(
                        tooltip: 'Cancel',
                        icon: const Icon(Icons.close, color: AppColors.mutedSolid),
                        onPressed: _clearSelection,
                      ),
                    ]),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: theme.dividerColor),
                ),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search conversations',
                    prefixIcon: Icon(Icons.search, color: theme.iconTheme.color?.withValues(alpha: 0.8)),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Consumer<ChatStore>(
                builder: (context, chatStore, _) {
                  return FutureBuilder<List<Conversation>>(
                    future: _conversationsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.wifi_off, size: 64, color: AppColors.mutedSolid),
                              const SizedBox(height: 16),
                              Text(
                                '📵 Offline Mode',
                                style: TextStyle(
                                  color: AppColors.text,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Unable to load conversations.\nCheck your network connection.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppColors.mutedSolid, fontSize: 14),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _conversationsFuture = _loadConversations();
                                  });
                                },
                                icon: const Icon(Icons.refresh),
                                label: const Text('Retry'),
                              ),
                            ],
                          ),
                        );
                      }
                      // Only show the empty state when there's truly nothing —
                      // no 1:1 conversations AND no groups. A groups-only
                      // account should still see its Group spaces grid.
                      if (_filteredConversations.isEmpty && _groups.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.message, size: 64, color: AppColors.mutedSolid),
                              const SizedBox(height: 16),
                              Text(
                                _searchController.text.isEmpty
                                  ? 'No conversations yet'
                                  : 'No conversations found',
                                style: TextStyle(color: AppColors.mutedSolid, fontSize: 16),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView(
                        padding: const EdgeInsets.only(bottom: 110),
                        children: [
                          // "Active now" — squircle avatars for conversations
                          // ChatStore currently reports online, matching the
                          // reference's Active Now row exactly.
                          Builder(builder: (context) {
                            final activeNow = _filteredConversations
                                .where((c) => chatStore.isUserOnline(c.userId))
                                .take(8)
                                .toList();
                            if (activeNow.isEmpty) return const SizedBox.shrink();
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
                                  child: Text('ACTIVE NOW',
                                      style: TextStyle(
                                          color: AppColors.mutedSolid,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.2)),
                                ),
                                SizedBox(
                                  height: 88,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    padding: const EdgeInsets.symmetric(horizontal: 18),
                                    itemCount: activeNow.length,
                                    separatorBuilder: (_, __) => const SizedBox(width: 14),
                                    itemBuilder: (context, i) {
                                      final c = activeNow[i];
                                      final firstName = c.fullName.split(' ').first;
                                      return GestureDetector(
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => ChatDetailScreen(conversation: c),
                                          ),
                                        ),
                                        child: SizedBox(
                                          width: 62,
                                          child: Column(
                                            children: [
                                              SquircleAvatar(
                                                size: 58,
                                                imageUrl: c.profilePictureUrl,
                                                initials: c.fullName.isNotEmpty ? c.fullName[0].toUpperCase() : 'U',
                                                online: true,
                                              ),
                                              const SizedBox(height: 6),
                                              Text(firstName,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(fontSize: 11.5)),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                            );
                          }),

                          if (_filteredConversations.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
                              child: Text('RECENT',
                                  style: TextStyle(
                                      color: AppColors.mutedSolid,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.2)),
                            ),
                          ..._filteredConversations.map((conv) {
                            // Use ChatStore for live values (unread, online, last message)
                            return Consumer<ChatStore>(builder: (context, chatStore, child) {
                              final otherId = conv.userId;
                              final unread = chatStore.unreadCountForConversation(otherId);
                              final online = chatStore.isUserOnline(otherId);
                              // NOTE: no logging here - this runs for every row on
                              // every store notification, and printing in a hot
                              // itemBuilder measurably stalls list rendering.
                              final msgs = chatStore.messagesForUser(otherId);
                              final lastMsg = msgs.isNotEmpty ? msgs.last : null;
                              final lastPreview = lastMsg?.content ?? conv.lastMessagePreview;
                              final timeAgo = lastMsg != null ? lastMsg.timeAgo : conv.timeAgo;

                              return ConversationListItem(
                                conversation: conv,
                                selectionMode: _selectionMode,
                                selected: _selectedUserIds.contains(conv.userId),
                                unreadCount: unread,
                                isOnline: online,
                                lastMessagePreview: lastPreview,
                                timeAgo: timeAgo,
                                onTap: () {
                                  if (_selectionMode) {
                                    _toggleSelection(conv);
                                  } else {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => ChatDetailScreen(
                                          conversation: conv,
                                        ),
                                      ),
                                    ).then((_) {
                                      // Refresh conversations after returning from chat
                                      // Add mounted check to prevent setState after dispose
                                      if (mounted) {
                                        setState(() {
                                          _conversationsFuture = _loadConversations();
                                        });
                                      }
                                    });
                                  }
                                },
                                onLongPress: () => _toggleSelection(conv),
                              );
                            });
                          }),

                          // "Group spaces" — grid, matching the reference exactly.
                          if (_groups.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
                              child: Text('GROUP SPACES',
                                  style: TextStyle(
                                      color: AppColors.mutedSolid,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.2)),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 18),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  // Stack single-column on phone-width screens; allow
                                  // side-by-side only once there's room (tablet/desktop).
                                  final crossAxisCount = constraints.maxWidth < 600 ? 1 : 2;
                                  return GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: crossAxisCount == 1 ? 5.4 : 2.6,
                                ),
                                itemCount: _groups.length,
                                itemBuilder: (context, i) {
                                  final g = _groups[i];
                                  return GestureDetector(
                                    onTap: () async {
                                      await Navigator.of(context).push(
                                        MaterialPageRoute(builder: (_) => GroupChatScreen(group: g)),
                                      );
                                      _loadGroups(); // refresh last-message preview on return
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(13),
                                      decoration: BoxDecoration(
                                        color: g.unreadCount > 0 ? AppColors.accentSubtle100 : theme.cardColor,
                                        border: Border.all(color: theme.dividerColor),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 44,
                                            height: 44,
                                            decoration: BoxDecoration(
                                              color: AppColors.accentSubtle100,
                                              borderRadius: const BorderRadius.only(
                                                topLeft: Radius.circular(15),
                                                topRight: Radius.circular(15),
                                                bottomRight: Radius.circular(15),
                                                bottomLeft: Radius.circular(6),
                                              ),
                                            ),
                                            alignment: Alignment.center,
                                            child: Icon(Icons.groups_rounded, color: primary, size: 22),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(g.name,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                                                const SizedBox(height: 2),
                                                Text('${g.memberCount} members',
                                                    style: TextStyle(fontSize: 11, color: AppColors.mutedSolid)),
                                              ],
                                            ),
                                          ),
                                          if (g.unreadCount > 0)
                                            Container(
                                              margin: const EdgeInsets.only(left: 6),
                                              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                                              padding: const EdgeInsets.symmetric(horizontal: 6),
                                              decoration: BoxDecoration(
                                                color: primary,
                                                borderRadius: BorderRadius.circular(999),
                                              ),
                                              alignment: Alignment.center,
                                              child: Text(
                                                g.unreadCount > 99 ? '99+' : '${g.unreadCount}',
                                                style: const TextStyle(
                                                    color: AppColors.onAccent, fontSize: 11.5, fontWeight: FontWeight.w700),
                                              ),
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
                          ],
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ConversationListItem extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selectionMode;
  final bool selected;
  final int unreadCount;
  final bool isOnline;
  final String lastMessagePreview;
  final String timeAgo;

  const ConversationListItem({
    super.key,
    required this.conversation,
    required this.onTap,
    this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
    this.unreadCount = 0,
    this.isOnline = false,
    this.lastMessagePreview = '',
    this.timeAgo = '',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: unreadCount > 0 ? AppColors.accentSubtle100 : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            // Avatar with online indicator
            if (selectionMode)
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: selected ? AppColors.accentSubtle200 : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(color: selected ? AppColors.primary : AppColors.border),
                ),
                child: Icon(
                  selected ? Icons.check : Icons.radio_button_unchecked,
                  color: selected ? AppColors.primary : AppColors.mutedSolid,
                ),
              )
            else
              SquircleAvatar(
                size: 54,
                imageUrl: conversation.profilePictureUrl,
                initials: conversation.fullName.isNotEmpty ? conversation.fullName[0].toUpperCase() : 'U',
                online: isOnline,
              ),
            const SizedBox(width: 12),
            // Message content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        conversation.fullName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        timeAgo.isNotEmpty ? timeAgo : conversation.timeAgo,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.mutedSolid,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          lastMessagePreview.isNotEmpty ? lastMessagePreview : conversation.lastMessagePreview,
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (unreadCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            unreadCount.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
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
      );
    }

    }

