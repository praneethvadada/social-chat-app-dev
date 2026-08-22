import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/message.dart';
import '../../services/api_service.dart';
import 'chat_screen.dart';
import 'package:social_chat_app/src/theme/colors.dart';

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  bool _isSearching = false;
  Timer? _debounce;
  int _currentUserId = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    try {
      // Fast path: get stored userId; fallback to network profile
      final storedId = await ApiService.getUserId();
      if (storedId != null && storedId > 0) {
        setState(() {
          _currentUserId = storedId;
        });
      } else {
        final profile = await ApiService.getMyProfile();
        setState(() {
          _currentUserId = profile['userId'] as int? ?? 0;
        });
      }
    } catch (e) {
      print('Error loading current user: $e');
    }
  }

  void _onSearchChanged() {
    _debounce?.cancel();

    if (_searchController.text.isEmpty) {
      setState(() {
        _filteredUsers = [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final results = await ApiService.searchUsers(_searchController.text);
        print('[NEW_CHAT] Search results: ${results.length} users');
        if (results.isNotEmpty) {
          print('[NEW_CHAT] First user data: ${results.first}');
        }
        // Determine my user id with a quick fallback to stored session
        final myId = _currentUserId > 0
            ? _currentUserId
            : (await ApiService.getUserId() ?? 0);
        setState(() {
          _users = results;
          // Filter out the current user
          _filteredUsers = results
              .where((user) => (user['userId'] as int? ?? 0) != myId)
              .toList();
          _isSearching = false;
        });
      } catch (e) {
        print('Error searching users: $e');
        setState(() {
          _isSearching = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    });
  }

  Future<void> _startChat(Map<String, dynamic> user) async {
    final userId = user['userId'] as int? ?? 0;
    final fullName = user['fullName'] as String? ?? 'User';

    // Prevent starting a chat with yourself
    if (userId == _currentUserId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You cannot start a chat with yourself')),
      );
      return;
    }

    // Check privacy/follow status before allowing chat
    try {
      final profile = await ApiService.getUserProfile(userId);
      final isPrivate = profile['isPrivate'] as bool? ?? false;
      final isFollowing = profile['isFollowing'] as bool? ?? false;
      if (isPrivate && !isFollowing) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This account is private. Follow to send messages.'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }
    } catch (e) {
      // If profile load fails, be safe and block starting the chat
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to start chat: $e')),
      );
      return;
    }

    // Create a conversation object (allowed)
    final conversation = Conversation(
      userId: userId,
      username: user['username'] as String? ?? '',
      fullName: fullName,
      profilePictureUrl: user['profilePictureUrl'] as String?,
      lastMessage: null,
      lastMessageTime: null,
      unreadCount: 0,
      isOnline: false,
    );

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatDetailScreen(
          conversation: conversation,
          isNewChat: true,
        ),
      ),
    ).then((_) {
      // Refresh and pop back to chats screen
      Navigator.pop(context);
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        title: Text(
          'New Chat',
          style: TextStyle(
              color: primary, fontSize: 20, fontWeight: FontWeight.w700),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: primary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search users...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _isSearching
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(strokeWidth: 2)))
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: theme.cardColor,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          Expanded(
            child: _buildUsersList(),
          ),
        ],
      ),
    );
  }

  Widget _buildUsersList() {
    final theme = Theme.of(context);

    if (_searchController.text.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: AppColors.mutedSolid),
            const SizedBox(height: 16),
            Text(
              'Search for users to start a chat',
              style: TextStyle(color: AppColors.mutedSolid, fontSize: 16),
            ),
          ],
        ),
      );
    }

    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_filteredUsers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_search, size: 64, color: AppColors.mutedSolid),
            const SizedBox(height: 16),
            Text(
              'No users found',
              style: TextStyle(color: AppColors.mutedSolid, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _filteredUsers.length,
      itemBuilder: (context, index) {
        final user = _filteredUsers[index];
        final fullName = user['fullName'] as String? ?? 'Unknown User';
        final username = user['username'] as String? ?? 'unknown';
        final profilePictureUrl = user['profilePictureUrl'] as String?;
        final isVerified = user['isVerified'] as bool? ?? false;
        
        print('[NEW_CHAT] User $username: profilePictureUrl = $profilePictureUrl');

        return GestureDetector(
          onTap: () => _startChat(user),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 28,
                  backgroundColor: theme.colorScheme.primary,
                  backgroundImage: (profilePictureUrl != null && profilePictureUrl.isNotEmpty)
                      ? NetworkImage(profilePictureUrl)
                      : null,
                  onBackgroundImageError: (profilePictureUrl != null && profilePictureUrl.isNotEmpty)
                      ? (exception, stackTrace) {
                          print('Error loading profile picture: $exception');
                        }
                      : null,
                  child: (profilePictureUrl == null || profilePictureUrl.isEmpty)
                      ? Text(
                          fullName.isNotEmpty ? fullName[0].toUpperCase() : 'U',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                // User info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              fullName,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isVerified)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Icon(
                                Icons.verified,
                                size: 16,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '@$username',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.mutedSolid,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Chevron
                Icon(Icons.chevron_right, color: AppColors.mutedSolid),
              ],
            ),
          ),
        );
      },
    );
  }
}
