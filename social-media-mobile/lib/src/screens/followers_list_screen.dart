import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../state/app_state_manager.dart';
import 'profile/user_profile_screen.dart';
import 'package:social_chat_app/src/theme/colors.dart';

class FollowersListScreen extends ConsumerStatefulWidget {
  final int userId;
  final String title;
  final bool isFollowing; // true for following list, false for followers list

  const FollowersListScreen({
    super.key,
    required this.userId,
    required this.title,
    required this.isFollowing,
  });

  @override
  ConsumerState<FollowersListScreen> createState() =>
      _FollowersListScreenState();
}

class _FollowersListScreenState extends ConsumerState<FollowersListScreen> {
  late Future<List<Map<String, dynamic>>> _listFuture;
  late Future<int> _currentUserIdFuture;
  late Future<List<Map<String, dynamic>>> _followRequestsFuture;
  int? currentUserId;
  List<Map<String, dynamic>> _followRequests = [];
  final Set<int> _requestedIds = {}; // locally track outgoing requests

  @override
  void initState() {
    super.initState();
    _currentUserIdFuture = _loadCurrentUserId();
    _listFuture = widget.isFollowing
        ? ApiService.getFollowers(widget.userId)
        : ApiService.getFollowing(widget.userId);
    
    // 🔴 FIX: Load follow requests to show in this screen
    _followRequestsFuture = _loadFollowRequests();
  }
  
  /// 🔴 FIX: Load incoming follow requests for current user
  Future<List<Map<String, dynamic>>> _loadFollowRequests() async {
    try {
      final requests = await ApiService.getFollowRequests();
      if (mounted) {
        setState(() {
          _followRequests = requests;
        });
      }
      return requests;
    } catch (e) {
      print('Error loading follow requests: $e');
      return [];
    }
  }

  Future<int> _loadCurrentUserId() async {
    try {
      final profile = await ApiService.getMyProfile();
      final id = profile['userId'] as int? ?? profile['id'] as int?;
      if (id != null) {
        setState(() {
          currentUserId = id;
        });
        return id;
      }
      throw Exception('Failed to get current user ID');
    } catch (e) {
      print('Error loading current user ID: $e');
      rethrow;
    }
  }

  Future<void> _toggleFollow(int targetUserId, bool isCurrentlyFollowing,
      {bool? isPrivate}) async {
    try {
      if (isCurrentlyFollowing) {
        await ApiService.unfollowUser(targetUserId);
        setState(() {
          _requestedIds.remove(targetUserId);
        });
      } else {
        bool private = isPrivate ?? false;
        if (isPrivate == null) {
          final profile = await ApiService.getUserProfile(targetUserId);
          private = profile['isPrivate'] as bool? ?? false;
        }
        if (private) {
          // Check if already requested
          final hasRequest = await ApiService.hasFollowRequest(targetUserId);
          if (!hasRequest) {
            await ApiService.sendFollowRequest(targetUserId);
            setState(() {
              _requestedIds.add(targetUserId);
            });
          }
        } else {
          await ApiService.followUser(targetUserId);
          setState(() {
            _requestedIds.remove(targetUserId);
          });
        }
      }
      setState(() {
        _listFuture = widget.isFollowing
            ? ApiService.getFollowers(widget.userId)
            : ApiService.getFollowing(widget.userId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isCurrentlyFollowing
                ? 'Unfollowed'
                : ((_requestedIds.contains(targetUserId) &&
                        (isPrivate ?? false))
                    ? 'Request sent'
                    : 'Now following'),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: AppColors.danger,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _handleBack() {
    // Check if this screen was opened via Navigator.push (regular navigation)
    // If not, assume it's a modal and close it via app state
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      ref.read(appStateProvider.notifier).closeModal();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleBack();
        }
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: theme.scaffoldBackgroundColor,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: theme.iconTheme.color),
            onPressed: _handleBack,
          ),
          title: Text(
            widget.title,
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _listFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Error loading list: ${snapshot.error}'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _listFuture = widget.isFollowing
                              ? ApiService.getFollowers(widget.userId)
                              : ApiService.getFollowing(widget.userId);
                        });
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }

            final list = snapshot.data ?? [];
            
            // 🔴 FIX: Calculate total item count = follow requests + followers
            final totalItems = _followRequests.length + list.length;
            
            return ListView.builder(
              itemCount: totalItems,
              itemBuilder: (context, index) {
                // 🔴 FIX: Show follow requests first with accept/decline buttons
                if (index < _followRequests.length) {
                  final request = _followRequests[index];
                  final requester = request['requester'] as Map<String, dynamic>? ?? {};
                  final requesterId = requester['userId'] as int? ?? 0;
                  final displayName = requester['fullName'] ?? requester['username'] ?? 'Unknown';
                  final profilePic = requester['profilePictureUrl'] as String?;
                  final requestId = request['id'] as int? ?? 0;
                  
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primary, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        // Avatar
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: AppColors.border,
                          backgroundImage: profilePic != null && profilePic.isNotEmpty
                              ? NetworkImage(profilePic)
                              : null,
                          child: profilePic == null || profilePic.isEmpty
                              ? Text(displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                              : null,
                        ),
                        const SizedBox(width: 12),
                        // Name & request message
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Wants to follow you',
                                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedSolid),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Accept button
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            minimumSize: const Size(60, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          onPressed: () async {
                            try {
                              await ApiService.respondFollowRequest(requestId, true);
                              if (mounted) {
                                setState(() {
                                  _followRequests.removeAt(index);
                                  _followRequestsFuture = _loadFollowRequests();
                                });
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Request accepted')),
                              );
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e')),
                              );
                            }
                          },
                          child: const Text('Accept', style: TextStyle(fontSize: 12, color: Colors.white)),
                        ),
                        const SizedBox(width: 6),
                        // Decline button
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.mutedSolid),
                            minimumSize: const Size(60, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          onPressed: () async {
                            try {
                              await ApiService.respondFollowRequest(requestId, false);
                              if (mounted) {
                                setState(() {
                                  _followRequests.removeAt(index);
                                  _followRequestsFuture = _loadFollowRequests();
                                });
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Request declined')),
                              );
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e')),
                              );
                            }
                          },
                          child: const Text('Decline', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  );
                }
                
                // Show followers list after follow requests
                final followerIndex = index - _followRequests.length;
                final user = list[followerIndex];
                final userId =
                    user['userId'] as int? ?? user['id'] as int? ?? 0;
                
                // Skip invalid user IDs
                if (userId <= 0) {
                  return const SizedBox.shrink();
                }
                
                return FutureBuilder<Map<String, dynamic>>(
                  future: ApiService.getUserProfile(userId),
                  builder: (context, profileSnapshot) {
                    if (profileSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: theme.dividerColor),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child:
                              const CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }
                    if (profileSnapshot.hasError) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: theme.dividerColor),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('Error loading user'),
                        ),
                      );
                    }
                    final userProfile = profileSnapshot.data ?? {};
                    final username =
                        userProfile['username'] as String? ?? 'Unknown';
                    final fullName =
                        userProfile['fullName'] as String? ?? username;
                    final profilePicUrl =
                        userProfile['profilePictureUrl'] as String?;
                    final isFollowing =
                        userProfile['isFollowing'] as bool? ?? false;
                    final isPrivate =
                        userProfile['isPrivate'] as bool? ?? false;
                    final loadedCurrentUserId = currentUserId;
                    final isOwnProfile = loadedCurrentUserId == userId;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: GestureDetector(
                        onTap: () {
                          final initialRequested =
                              isPrivate && _requestedIds.contains(userId);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => UserProfileScreen(
                                userId: userId,
                                initialFollowRequested: initialRequested,
                              ),
                            ),
                          );
                        },
                        child: Row(
                          children: [
                            if (profilePicUrl != null &&
                                profilePicUrl.isNotEmpty)
                              CircleAvatar(
                                radius: 24,
                                backgroundImage: NetworkImage(profilePicUrl),
                              )
                            else
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: theme.colorScheme.primary,
                                child: Text(
                                  fullName.isNotEmpty
                                      ? fullName[0].toUpperCase()
                                      : 'U',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    fullName,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '@$username',
                                    style: theme.textTheme.bodySmall,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (!isOwnProfile)
                              SizedBox(
                                width: 100,
                                child: Builder(
                                  builder: (context) {
                                    final shouldCheckBackend = isPrivate &&
                                        !isFollowing &&
                                        !_requestedIds.contains(userId);
                                    return FutureBuilder<bool>(
                                      future: shouldCheckBackend
                                          ? ApiService.hasFollowRequest(userId)
                                          : Future.value(
                                              _requestedIds.contains(userId)),
                                      builder: (context, pendingSnap) {
                                        final isRequested =
                                            pendingSnap.data == true ||
                                                _requestedIds.contains(userId);
                                        final disabled =
                                            isPrivate && isRequested;
                                        return ElevatedButton(
                                          onPressed: disabled
                                              ? null
                                              : () => _toggleFollow(
                                                  userId, isFollowing,
                                                  isPrivate: isPrivate),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: isFollowing
                                                ? theme.scaffoldBackgroundColor
                                                : theme.colorScheme.primary,
                                            foregroundColor: isFollowing
                                                ? theme.colorScheme.primary
                                                : Colors.white,
                                            side: isFollowing
                                                ? BorderSide(
                                                    color: theme
                                                        .colorScheme.primary)
                                                : BorderSide.none,
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 8),
                                          ),
                                          child: Text(
                                            isFollowing
                                                ? 'Unfollow'
                                                : (isPrivate
                                                    ? (isRequested
                                                        ? 'Requested'
                                                        : 'Request')
                                                    : 'Follow'),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12,
                                            ),
                                          ),
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
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}
