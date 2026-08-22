import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/post.dart';
import '../models/user_profile.dart';
import '../services/post_interaction_service.dart';
import '../services/api_service.dart';
import '../services/post_service.dart';
import '../screens/comments/comments_screen.dart';
import '../state/saved_posts_notifier.dart';
import '../theme/colors.dart';

class PostActionsWidget extends ConsumerStatefulWidget {
  final Post post;
  final Function(int)? onLikeChanged;  // Passes like count
  final Function(List<UserProfile>)? onLikersUpdated;  // Passes updated sampleLikers
  final Function(bool)? onSaveChanged;
  final Function(int)? onCommentAdded;

  const PostActionsWidget({
    super.key,
    required this.post,
    this.onLikeChanged,
    this.onLikersUpdated,
    this.onSaveChanged,
    this.onCommentAdded,
  });

  @override
  ConsumerState<PostActionsWidget> createState() => _PostActionsWidgetState();
}

class _PostActionsWidgetState extends ConsumerState<PostActionsWidget> {
  late bool _isLiked;
  late bool _isSaved;
  late int _likesCount;
  late int _savesCount;
  late int _commentsCount;
  late List<UserProfile> _sampleLikers;  // ✅ Cache sample likers
  int? _currentUserId;  // ✅ Current user ID for filtering
  bool _liking = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.post.isLiked;
    _isSaved = widget.post.isSaved;
    _likesCount = widget.post.likes;
    _savesCount = widget.post.saves;
    _commentsCount = widget.post.comments;
    _sampleLikers = List.from(widget.post.sampleLikers ?? []);  // ✅ Initialize likers
    _loadCurrentUserId();  // ✅ Load current user ID
  }

  Future<void> _loadCurrentUserId() async {
    final id = await ApiService.getUserId();
    if (mounted) {
      setState(() => _currentUserId = id);
    }
  }

  @override
  void didUpdateWidget(PostActionsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // ✅ FIX: Sync state when post object changes from parent (e.g., after global state update)
    // Always sync to ensure consistency with the updated Post object
    if (widget.post.id == oldWidget.post.id) {
      // Same post, sync updated values from the Post object only if they differ
      bool needsUpdate = false;
      
      if (widget.post.isLiked != _isLiked || 
          widget.post.likes != _likesCount || 
          widget.post.sampleLikers.length != _sampleLikers.length) {
        needsUpdate = true;
      }
      
      if (widget.post.isSaved != _isSaved || widget.post.saves != _savesCount) {
        needsUpdate = true;
      }
      
      if (widget.post.comments != _commentsCount) {
        needsUpdate = true;
      }
      
      if (needsUpdate) {
        setState(() {
          _isLiked = widget.post.isLiked;
          _isSaved = widget.post.isSaved;
          _likesCount = widget.post.likes;
          _savesCount = widget.post.saves;
          _commentsCount = widget.post.comments;
          _sampleLikers = List.from(widget.post.sampleLikers ?? []);
        });
      }
    } else {
      // Different post, reset all state
      setState(() {
        _isLiked = widget.post.isLiked;
        _isSaved = widget.post.isSaved;
        _likesCount = widget.post.likes;
        _savesCount = widget.post.saves;
        _commentsCount = widget.post.comments;
        _sampleLikers = List.from(widget.post.sampleLikers ?? []);
      });
    }
  }

  Future<void> _openForwardSheet() async {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _loadFollowings(),
          builder: (c, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
            }

            if (snap.hasError) {
              return SizedBox(
                height: 200,
                child: Center(child: Text('Failed to load followings')),
              );
            }

            final list = snap.data ?? [];
            final selected = <int>{};

            return StatefulBuilder(
              builder: (BuildContext stCtx, StateSetter setStateModal) {
                return SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, left: 12, right: 12, bottom: 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text('Forward to', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: theme.colorScheme.primary)),
                            const Spacer(),
                            IconButton(icon: Icon(Icons.close), onPressed: () => Navigator.of(ctx).pop()),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: list.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, idx) {
                              final u = list[idx];
                              final uid = (u['userId'] ?? u['id'] ?? u['userID']) is int
                                  ? (u['userId'] ?? u['id'] ?? u['userID']) as int
                                  : int.tryParse((u['userId'] ?? u['id'] ?? '').toString()) ?? 0;
                              final usernameRaw = u['username'] ?? u['actorUsername'] ?? u['userName'];
                              final username = (usernameRaw is String && usernameRaw.trim().isNotEmpty) ? usernameRaw as String : null;
                              final fullNameRaw = u['fullName'] ?? u['actorFullName'] ?? u['name'];
                              final fullName = (fullNameRaw is String && fullNameRaw.trim().isNotEmpty) ? fullNameRaw as String : null;
                              final picRaw = u['profilePictureUrl'] ?? u['actorProfilePictureUrl'] ?? u['avatar'];
                              final pic = (picRaw is String && picRaw.trim().isNotEmpty) ? picRaw as String : null;

                              final checked = selected.contains(uid);

                              final displayName = fullName ?? username ?? 'User';
                              final initials = (fullName ?? username ?? 'U')
                                  .toString()
                                  .split(' ')
                                  .where((s) => s.isNotEmpty)
                                  .map((s) => s[0])
                                  .take(2)
                                  .join()
                                  .toUpperCase();

                              return ListTile(
                                leading: pic != null
                                    ? CircleAvatar(backgroundImage: NetworkImage(pic))
                                    : CircleAvatar(child: Text(initials)),
                                title: Text(displayName),
                                subtitle: username != null ? Text('@$username') : null,
                                trailing: Checkbox(
                                  value: checked,
                                  onChanged: (_) {
                                    setStateModal(() {
                                      if (checked) selected.remove(uid); else selected.add(uid);
                                    });
                                  },
                                ),
                                onTap: () => setStateModal(() {
                                  if (checked) selected.remove(uid); else selected.add(uid);
                                }),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: selected.isEmpty
                                    ? null
                                    : () async {
                                        Navigator.of(ctx).pop();
                                        final snackKey = GlobalKey<ScaffoldMessengerState>();
                                        int success = 0;
                                        for (final rid in selected) {
                                          try {
                                            final media = widget.post.imageUrls.isNotEmpty ? widget.post.imageUrls.first : null;
                                            // Include a machine-readable token so recipients can open the original post
                                            // Also include a short preview of the post content so recipients without media see useful text
                                            final preview = (widget.post.content != null && widget.post.content.isNotEmpty)
                                              ? widget.post.content.trim()
                                              : (widget.post.authorName != null ? 'Post by ${widget.post.authorName}' : 'Forwarded post');
                                            final trimmed = preview.length > 240 ? '${preview.substring(0, 237)}...' : preview;
                                            final text = 'FORWARDED_POST:${widget.post.id}|$trimmed';
                                            await ApiService.sendMessage(rid, text, mediaUrl: media);
                                            success++;
                                          } catch (e) {
                                            // ignore per-recipient failures
                                          }
                                        }
                                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Forwarded to $success user(s)')));
                                      },
                                child: const Text('Forward'),
                              ),
                            ),
                          ],
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
    );
  }

  Future<List<Map<String, dynamic>>> _loadFollowings() async {
    final myId = await ApiService.getUserId();
    if (myId == null) throw Exception('Not authenticated');
    final list = await ApiService.getFollowing(myId);

    // Enrich entries that lack display names by fetching their profile
    final futures = <Future<void>>[];
    for (var i = 0; i < list.length; i++) {
      final u = list[i];
      final usernameRaw = u['username'] ?? u['actorUsername'] ?? u['userName'];
      final fullNameRaw = u['fullName'] ?? u['actorFullName'] ?? u['name'];
      final hasName = (usernameRaw is String && usernameRaw.trim().isNotEmpty) || (fullNameRaw is String && fullNameRaw.trim().isNotEmpty);
      if (!hasName) {
        final uidVal = u['userId'] ?? u['id'] ?? u['userID'];
        final uid = uidVal is int ? uidVal : int.tryParse(uidVal?.toString() ?? '');
        if (uid != null && uid > 0) {
          futures.add(Future<void>(() async {
            try {
              final profile = await ApiService.getUserProfile(uid);
              if (profile != null) {
                // merge known fields
                u['username'] = profile['username'] ?? u['username'];
                u['fullName'] = profile['fullName'] ?? u['fullName'];
                u['profilePictureUrl'] = profile['profilePictureUrl'] ?? u['profilePictureUrl'];
              }
            } catch (_) {
              // ignore profile fetch errors
            }
          }));
        }
      }
    }

    if (futures.isNotEmpty) await Future.wait(futures);

    return list;
  }

  Future<void> _toggleLike() async {
    if (_liking) return;
    
    setState(() => _liking = true);
    
    final previousLikeState = _isLiked;
    final previousLikesCount = _likesCount;
    final previousLikers = List<UserProfile>.from(_sampleLikers);
    
    // ✅ OPTIMISTIC UPDATE: Update count, likers, and heart immediately
    final newLikesCount = _isLiked ? previousLikesCount - 1 : previousLikesCount + 1;
    final newLikersList = _isLiked 
        ? previousLikers.where((u) => u.userId != _currentUserId).toList()
        : previousLikers;
    
    setState(() {
      _isLiked = !_isLiked;
      _likesCount = newLikesCount;
      _sampleLikers = newLikersList;
    });
    
    // ✅ OPTIMISTIC UPDATE: Notify parent immediately
    widget.onLikeChanged?.call(newLikesCount);
    widget.onLikersUpdated?.call(newLikersList);
    
    try {
      print('[POST ACTIONS] 🔄 Toggling like for postId=${widget.post.id}');
      Map<String, dynamic> result;
      if (previousLikeState) {
        print('[POST ACTIONS] 🔄 Calling unlikePost...');
        result = await PostInteractionService.unlikePost(widget.post.id);
      } else {
        print('[POST ACTIONS] 🔄 Calling likePost...');
        result = await PostInteractionService.likePost(widget.post.id);
      }
      
      // ✅ CONFIRM: Update with exact data from backend
      print('[POST ACTIONS] 📝 Result from API: isLiked=${result['isLiked']}, count=${result['likesCount']}');
      final confirmedIsLiked = result['isLiked'] as bool? ?? !previousLikeState;
      final confirmedLikesCount = result['likesCount'] as int? ?? newLikesCount;
      
      setState(() {
        _isLiked = confirmedIsLiked;
        _likesCount = confirmedLikesCount;
      });
      
      // ✅ CONFIRM: Pass confirmed count and likers to parent
      widget.onLikeChanged?.call(_likesCount);

      
      // Also pass updated likers list (already UserProfile objects, not JSON)
      final sampleLikers = result['sampleLikers'] as List? ?? [];
      List<UserProfile> confirmedLikers = [];
      if (sampleLikers.isNotEmpty) {
        // sampleLikers are already UserProfile objects from the Post model
        confirmedLikers = sampleLikers.cast<UserProfile>();
        widget.onLikersUpdated?.call(confirmedLikers);
      } else {
        widget.onLikersUpdated?.call([]);
      }
      
      // ✅ UPDATE GLOBAL STATE: Update the post in the provider so it persists across scrolling
      ref.read(postProvider.notifier).updatePostLikeState(
        postId: widget.post.id,
        isLiked: confirmedIsLiked,
        likesCount: confirmedLikesCount,
        sampleLikers: confirmedLikers,
      );
      
      print('[POST ACTIONS] ✅ Like updated - isLiked: $_isLiked, count: $_likesCount');
    } catch (e) {
      // Revert on error
      print('[POST ACTIONS] ❌ Error during like: $e');
      print('[POST ACTIONS] ↩️ Reverting to previous state - isLiked: $previousLikeState, count: $previousLikesCount');
      setState(() {
        _isLiked = previousLikeState;
        _likesCount = previousLikesCount;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.danger,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _liking = false);
      }
    }
  }

  Future<void> _toggleSave() async {
    if (_saving) return;
    
    setState(() => _saving = true);
    try {
      if (_isSaved) {
        await PostInteractionService.unsavePost(widget.post.id);
      } else {
        await PostInteractionService.savePost(widget.post.id);
      }
      
      setState(() => _isSaved = !_isSaved);
      widget.onSaveChanged?.call(_isSaved);
      
      // Notify saved posts to refresh in profile screen
      ref.read(savedPostsNotifierProvider.notifier).notifySaveChanged();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => _saving = false);
    }
  }

  Widget _pillAction({
    required IconData icon,
    required IconData activeIcon,
    required bool active,
    required String count,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final activeColor = theme.colorScheme.primary;
    final inactiveColor = theme.textTheme.bodySmall?.color;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: active ? theme.colorScheme.primary.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(active ? activeIcon : icon, size: 18, color: active ? activeColor : inactiveColor),
            const SizedBox(width: 7),
            Text(
              count,
              style: TextStyle(
                fontSize: 13.5,
                color: active ? activeColor : inactiveColor,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Row(
        children: [
          // Grouped like/comment/share pill — mirrors the reference's
          // rounded action cluster.
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _pillAction(
                  icon: Icons.favorite_border,
                  activeIcon: Icons.favorite,
                  active: _isLiked,
                  count: _likesCount.toString(),
                  onTap: _toggleLike,
                ),
                _pillAction(
                  icon: Icons.chat_bubble_outline,
                  activeIcon: Icons.chat_bubble_outline,
                  active: false,
                  count: _commentsCount.toString(),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CommentsScreen(
                          post: widget.post,
                          onCommentAdded: (count) {
                            if (mounted) {
                              setState(() => _commentsCount = count);
                              widget.onCommentAdded?.call(count);
                            }
                          },
                        ),
                      ),
                    );
                  },
                ),
                _pillAction(
                  icon: Icons.send_outlined,
                  activeIcon: Icons.send_outlined,
                  active: false,
                  count: widget.post.shares.toString(),
                  onTap: _openForwardSheet,
                ),
              ],
            ),
          ),
          const Spacer(),
          // Save — a standalone squared button, separate from the pill.
          GestureDetector(
            onTap: _toggleSave,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.dividerColor),
              ),
              child: Icon(
                _isSaved ? Icons.bookmark : Icons.bookmark_border,
                size: 18,
                color: _isSaved ? theme.colorScheme.primary : theme.textTheme.bodySmall?.color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
