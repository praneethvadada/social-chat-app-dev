import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/post.dart';
import '../../services/api_service.dart';
import '../../services/post_service.dart';
import '../followers_list_screen.dart';
import '../post_detail/post_detail_screen.dart';
import '../../utils/friendly_error.dart';
import 'package:social_chat_app/src/theme/colors.dart';

class UserProfileScreen extends ConsumerStatefulWidget {
  final int userId;
  final String? userName;
  final bool initialFollowRequested;

  const UserProfileScreen({
    super.key,
    required this.userId,
    this.userName,
    this.initialFollowRequested = false,
  });

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen> with WidgetsBindingObserver {
  bool _isLoading = true;
  String? _errorMessage;

  String _fullName = '';
  String _username = '';
  String _bio = '';
  String? _profilePicUrl;
  int _postsCount = 0;
  int _followersCount = 0;
  int _followingCount = 0;
  List<Post> _userPosts = [];

  bool _isFollowing = false;
  bool _isFollowLoading = false;
  bool _followRequested = false;
  int? _currentUserId;
  bool _isPrivate = false;
  
  // 🔴 FIX: Track if returning from requests screen
  bool _justReturned = false;

  @override
  void initState() {
    super.initState();
    // Seed local state so the button is disabled immediately if we came
    // from a screen that already knows a request was sent.
    _followRequested = widget.initialFollowRequested;
    _loadUserProfile();
    
    // 🔴 FIX: Listen for app lifecycle changes to refresh follow status
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _loadUserProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      print('\n========== LOAD USER PROFILE ==========');
      print('userId: ${widget.userId}');

      // Get current user ID
      _currentUserId = await ApiService.getUserId();

      // Fetch user profile
      final profile = await ApiService.getUserProfile(widget.userId);
      print('Profile received: ${profile['fullName']}');

      if (mounted) {
        setState(() {
          _fullName = profile['fullName'] ?? '';
          _username = profile['username'] ?? '';
          _bio = profile['bio'] ?? '';
          _profilePicUrl = profile['profilePictureUrl'];
          _postsCount = profile['postsCount'] ?? 0;
          _followersCount = profile['followersCount'] ?? 0;
          _followingCount = profile['followingCount'] ?? 0;
          _isPrivate = profile['isPrivate'] ?? false;
          _isLoading = false;
        });

        // Check follow status FIRST if not current user (before loading posts)
        if (_currentUserId != widget.userId) {
          await _checkFollowStatus();
        }

        // Load user posts AFTER checking follow status
        // This ensures _isFollowing and _followRequested are set correctly
        await _loadUserPosts();
      }
    } catch (e) {
      print('Error loading user profile: $e');
      if (mounted) {
        setState(() {
          _errorMessage = FriendlyError.messageOf(e);
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadUserPosts() async {
    try {
      // For private accounts: only show posts if user is actually following
      // NOT if they just sent a request (waiting for approval)
      final isOwnProfile = _currentUserId == widget.userId;

      print('[POST LOAD] Starting post load for userId: ${widget.userId}');
      print(
          '  _isPrivate=$_isPrivate, _isFollowing=$_isFollowing, _followRequested=$_followRequested, isOwnProfile=$isOwnProfile');

      if (_isPrivate && !isOwnProfile && !_isFollowing) {
        // Private account, not own profile, and not following
        // Even if follow request was sent, don't show posts until actually following
        print(
            '[POST VISIBILITY] ❌ HIDING posts - Private account, user NOT following');
        print(
            '  Reason: _isPrivate=$_isPrivate && !isOwnProfile=true && !_isFollowing=true');
        print(
            '  Even though _followRequested=$_followRequested, wait until _isFollowing=true');
        if (mounted) {
          setState(() {
            _userPosts = [];
          });
        }
        return;
      }

      final posts = await ApiService.getUserPosts(widget.userId);
      if (mounted) {
        setState(() {
          _userPosts = posts;
        });
      }
      print('[POST VISIBILITY] ✅ Showing ${posts.length} posts');
      print(
          '  Conditions: _isPrivate=$_isPrivate || isOwnProfile=$isOwnProfile || _isFollowing=$_isFollowing');
    } catch (e) {
      print('Error loading user posts: $e');
    }
  }
  
  // 🔴 FIX: Add lifecycle management to refresh follow status
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Refresh follow status when returning from requests screen (declined/accepted)
    if (state == AppLifecycleState.resumed && mounted && _justReturned) {
      print('[LIFECYCLE] App resumed - refreshing follow status for userId=${widget.userId}');
      _checkFollowStatus();
      _justReturned = false;
    }
  }
  
  @override
  void deactivate() {
    // 🔴 FIX: Mark that we're leaving screen (might be visiting requests screen next)
    _justReturned = true;
    super.deactivate();
  }

  Future<void> _checkFollowStatus() async {
    try {
      final isFollowing = await ApiService.checkFollowStatus(widget.userId);
      bool hasRequest = false;

      // Only check for follow request if not currently following
      if (!isFollowing && _isPrivate) {
        hasRequest = await ApiService.hasFollowRequest(widget.userId);
      }

      if (mounted) {
        setState(() {
          _isFollowing = isFollowing;
          _followRequested = hasRequest;
        });
      }

      print(
          '[FOLLOW STATUS CHECK] userId: ${widget.userId}, isFollowing: $isFollowing, hasRequest: $hasRequest, isPrivate: $_isPrivate');
    } catch (e) {
      print('Error checking follow status: $e');
    }
  }

  Future<void> _toggleFollow() async {
    // Extra safety check: prevent any action if already requested or loading
    print('\n[TOGGLE FOLLOW] Button pressed - checking state...');
    print('  _followRequested: $_followRequested');
    print('  _isFollowLoading: $_isFollowLoading');
    print('  _isFollowing: $_isFollowing');
    print('  _isPrivate: $_isPrivate');

    if (_followRequested) {
      print('[FOLLOW] ❌ BLOCKED - request already sent!');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Follow request already sent - waiting for approval'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (_isFollowLoading) {
      print('[FOLLOW] ❌ Already loading - please wait');
      return;
    }

    setState(() => _isFollowLoading = true);
    try {
      print('\n========== TOGGLE FOLLOW ==========');
      print(
          'userId: ${widget.userId}, isFollowing: $_isFollowing, isPrivate: $_isPrivate, followRequested: $_followRequested');

      if (_isFollowing) {
        // User is already following, so unfollow
        await ApiService.unfollowUser(widget.userId);
        print('[UNFOLLOW] Success');
        if (mounted) {
          setState(() {
            _isFollowing = false;
            _followersCount = (_followersCount - 1).clamp(0, 999999);
            _isFollowLoading = false;
          });
          // Reload posts - they should be hidden now
          await _loadUserPosts();
        }
      } else if (_isPrivate) {
        // Send follow request for private account
        print('[FOLLOW REQUEST] Sending request to private account...');
        await ApiService.sendFollowRequest(widget.userId);
        print('[FOLLOW REQUEST] ✅ Sent successfully');
        if (mounted) {
          setState(() {
            _followRequested = true;
            _isFollowLoading = false;
            print('[STATE UPDATE] _followRequested set to TRUE');
            print('[STATE UPDATE] Button should now be DISABLED');
          });
          // DON'T load posts after follow request!
          // Posts should only show after request is approved
          print(
              '[POST VISIBILITY] Request sent - NOT loading posts until approval');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Follow request sent - waiting for approval'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        // Instant follow for public account
        await ApiService.followUser(widget.userId);
        print('[FOLLOW] Success');
        if (mounted) {
          setState(() {
            _isFollowing = true;
            _followersCount = (_followersCount + 1).clamp(0, 999999);
            _isFollowLoading = false;
          });
          // Reload posts - they should now be visible
          await _loadUserPosts();
        }
      }
    } catch (e) {
      print('[FOLLOW ERROR] $e');
      if (mounted) {
        setState(() => _isFollowLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: ${e.toString()}')),
        );
      }
    }
  }

  String _getInitials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  Future<void> _showBlockConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Block User'),
        content: Text('Are you sure you want to block @$_username? They will no longer be able to see your posts or interact with you.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Block'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _blockUser();
    }
  }

  Future<void> _blockUser() async {
    try {
      await ApiService.blockUser(widget.userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('@$_username has been blocked')),
        );
        // Go back to previous screen
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to block user: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final isOwnProfile = _currentUserId == widget.userId;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadUserProfile,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back,
                            color: theme.iconTheme.color),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            isOwnProfile ? 'Profile' : _username,
                            style: TextStyle(
                              color: primary,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      if (!isOwnProfile)
                        PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert, color: theme.iconTheme.color),
                          onSelected: (value) async {
                            if (value == 'block') {
                              await _showBlockConfirmation();
                            } else if (value == 'report') {
                              // TODO: Implement report functionality
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Report feature coming soon')),
                              );
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'block',
                              child: Row(
                                children: [
                                  Icon(Icons.block, color: AppColors.danger),
                                  SizedBox(width: 12),
                                  Text('Block User', style: TextStyle(color: AppColors.danger)),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'report',
                              child: Row(
                                children: [
                                  Icon(Icons.report, color: AppColors.gold),
                                  SizedBox(width: 12),
                                  Text('Report'),
                                ],
                              ),
                            ),
                          ],
                        )
                      else
                        SizedBox(width: 48),
                    ],
                  ),
                ),
                const Divider(height: 1),
                const SizedBox(height: 18),

                // Loading or Error State
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 60),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 60),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline,
                              size: 48, color: AppColors.mutedSolid),
                          const SizedBox(height: 16),
                          Text(_errorMessage!,
                              style: TextStyle(color: AppColors.mutedSolid)),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _loadUserProfile,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Column(
                    children: [
                      // Avatar, name and bio
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18.0),
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 54,
                              backgroundImage: _profilePicUrl != null &&
                                      _profilePicUrl!.isNotEmpty
                                  ? NetworkImage(_profilePicUrl!)
                                  : null,
                              backgroundColor: _profilePicUrl == null ||
                                      _profilePicUrl!.isEmpty
                                  ? primary
                                  : Colors.transparent,
                              child: _profilePicUrl == null ||
                                      _profilePicUrl!.isEmpty
                                  ? Text(
                                      _getInitials(_fullName),
                                      style: theme.textTheme.headlineSmall
                                          ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            Text(_fullName,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text('@$_username',
                                style: TextStyle(color: AppColors.mutedSolid)),
                            const SizedBox(height: 6),
                            Text(_bio.isEmpty ? 'No bio yet' : _bio,
                                style: TextStyle(color: AppColors.mutedSolid)),
                            const SizedBox(height: 18),

                            // Stats row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildStat(_postsCount.toString(), 'Posts', null),
                                _buildStat(_followersCount.toString(), 'Followers', () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => FollowersListScreen(
                                        userId: widget.userId,
                                        title: 'Followers',
                                        isFollowing: true,
                                      ),
                                    ),
                                  );
                                  // Refresh profile after returning
                                  await _loadUserProfile();
                                }),
                                _buildStat(_followingCount.toString(), 'Following', () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => FollowersListScreen(
                                        userId: widget.userId,
                                        title: 'Following',
                                        isFollowing: false,
                                      ),
                                    ),
                                  );
                                  // Refresh profile after returning
                                  await _loadUserProfile();
                                }),
                              ],
                            ),
                            const SizedBox(height: 18),

                            // Follow button (if not own profile)
                            if (!isOwnProfile)
                              Tooltip(
                                message: _followRequested
                                    ? 'Request pending - waiting for approval'
                                    : 'Click to follow',
                                child: SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed:
                                        (_followRequested || _isFollowLoading)
                                            ? null
                                            : _toggleFollow,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _followRequested
                                          ? Colors.grey[
                                              400] // Darker grey when requested
                                          : (_isFollowing
                                              ? AppColors.border
                                              : primary),
                                      foregroundColor: _followRequested
                                          ? AppColors.text
                                          : null,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      disabledBackgroundColor: AppColors.mutedSolid,
                                    ),
                                    child: _isFollowLoading
                                        ? const SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : Text(
                                            _isFollowing
                                                ? 'Following'
                                                : (_followRequested
                                                    ? 'Requested'
                                                    : 'Follow'),
                                            style: TextStyle(
                                              color: _followRequested
                                                  ? AppColors.text
                                                  : ((_isFollowing)
                                                      ? Colors.black
                                                      : Colors.white),
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 18),
                          ],
                        ),
                      ),

                      // Posts area with privacy enforcement
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18.0),
                        child: Builder(
                          builder: (context) {
                            final isOwnProfile =
                                _currentUserId == widget.userId;
                            final isLocked =
                                _isPrivate && !isOwnProfile && !_isFollowing;

                            if (isLocked) {
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 36.0),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.lock,
                                        size: 56, color: AppColors.mutedSolid),
                                    const SizedBox(height: 12),
                                    Text(
                                      'This account is private',
                                      style: TextStyle(
                                        color: AppColors.text,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Follow to see their photos and videos.',
                                      style: TextStyle(color: AppColors.mutedSolid),
                                    ),
                                  ],
                                ),
                              );
                            }

                            if (_userPosts.isEmpty) {
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 32.0),
                                child: Center(
                                  child: Text(
                                    'No posts yet',
                                    style: TextStyle(
                                      color: AppColors.mutedSolid,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              );
                            }

                            return GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              padding:
                                  const EdgeInsets.only(top: 8, bottom: 24),
                              itemCount: _userPosts.length,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 14,
                                childAspectRatio: 1,
                              ),
                              itemBuilder: (context, index) {
                                return _buildPostTile(_userPosts[index]);
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStat(String value, String label, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value,
                style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(label, 
                style: TextStyle(
                  color: onTap != null ? AppColors.primary : AppColors.mutedSolid, 
                  fontSize: 12
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildPostTile(Post post) {
    final hasMedia = post.imageUrls.isNotEmpty;
    final mediaUrl = hasMedia ? post.imageUrls.first : null;
    final isVideo = mediaUrl != null &&
        (mediaUrl.toLowerCase().endsWith('.mp4') ||
            mediaUrl.toLowerCase().endsWith('.webm') ||
            mediaUrl.toLowerCase().endsWith('.mov'));

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PostDetailScreen(post: post),
            ),
          );
        },
        child: hasMedia
            ? Stack(
                fit: StackFit.expand,
                children: [
                  if (isVideo)
                    Container(
                      color: Colors.black,
                      child: const Center(
                        child: Icon(
                          Icons.play_circle_filled,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    )
                  else
                    Image.network(
                      mediaUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: AppColors.border,
                          child: const Center(
                            child: Icon(Icons.broken_image, color: AppColors.mutedSolid),
                          ),
                        );
                      },
                    ),
                ],
              )
            : Container(
                color: AppColors.border,
                child: Center(
                  child: Text(
                    post.content.length > 50
                        ? '${post.content.substring(0, 50)}...'
                        : post.content,
                    style: TextStyle(color: AppColors.mutedSolid, fontSize: 10),
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
      ),
    );
  }
}
