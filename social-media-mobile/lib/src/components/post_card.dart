import 'package:flutter/material.dart';
// removed unused video_player import
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'dart:io';
import 'dart:typed_data';
import '../config/api_config.dart';
import '../models/post.dart';
import '../models/user_profile.dart';
import '../services/api_service.dart';
import '../services/post_service.dart';
import '../screens/create_post/create_post_screen.dart';
import 'package:go_router/go_router.dart';
import '../screens/fullscreen_media/fullscreen_image_viewer.dart';
import '../screens/fullscreen_media/fullscreen_video_player.dart';
 import 'post_actions_widget.dart';
import '../screens/user_profile_screen.dart';
import '../utils/post_timestamp_widget.dart';
import '../state/saved_posts_notifier.dart';
import '../theme/colors.dart';
import 'mentionable_text.dart';

/// Reference-style "kind" label — Poll/Event take priority (they're an
/// explicit backend type), otherwise Photo/Video/Note is derived from what
/// the post actually carries.
String _postKind(Post post) {
  if (post.postType == PostType.POLL) return 'Poll';
  if (post.postType == PostType.EVENT) return 'Event';
  if (post.imageUrls.isNotEmpty) {
    final url = post.imageUrls.first.toLowerCase();
    final isVideo = url.endsWith('.mp4') || url.endsWith('.webm') || url.endsWith('.mov');
    return isVideo ? 'Video' : 'Photo';
  }
  return 'Note';
}

IconData _kindIcon(String kind) {
  switch (kind) {
    case 'Video':
      return Icons.play_arrow_rounded;
    case 'Photo':
      return Icons.image_rounded;
    case 'Poll':
      return Icons.bar_chart_rounded;
    case 'Event':
      return Icons.event_rounded;
    default:
      return Icons.auto_awesome_rounded;
  }
}

/// Small pill badge showing the post's kind — overlaid on media, or shown
/// beside the header for text-only posts, mirroring the reference exactly.
class _KindBadge extends StatelessWidget {
  final String kind;
  final bool onMedia;
  const _KindBadge({required this.kind, this.onMedia = true});

  @override
  Widget build(BuildContext context) {
    // On media: white pill + dark emerald text (matches the reference's
    // Photo/Video badge). Off media (text-only "Note" posts): the
    // reference's --sage tokens, which for Emerald Luxe ARE the gold
    // accent, not a separate teal — so this uses gold, not green.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = onMedia
        ? Colors.white.withValues(alpha: 0.92)
        : (isDark ? AppColors.goldSubtle100 : AppColorsLight.goldSubtle100);
    final fg = onMedia
        ? const Color(0xFF074E36)
        : (isDark ? AppColors.goldLight700 : AppColorsLight.gold700);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_kindIcon(kind), size: 13, color: fg),
          const SizedBox(width: 5),
          Text(
            kind,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class PostCard extends ConsumerStatefulWidget {
  final Post post;
  final int index;

  const PostCard({super.key, required this.post, required this.index});

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;
  late final Animation<Offset> _offsetAnim;
  late final Animation<double> _opacityAnim;
  late int _currentLikeCount;
  late List<UserProfile> _currentSampleLikers;

  @override
  void initState() {
    super.initState();
    _currentLikeCount = widget.post.likes;
    _currentSampleLikers = List.from(widget.post.sampleLikers ?? []);
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );

    final curved = CurvedAnimation(parent: _ctl, curve: Curves.easeOut);
    _offsetAnim = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(curved);
    _opacityAnim = Tween<double>(begin: 0.0, end: 1.0).animate(curved);

    // staggered start
    Future.delayed(Duration(milliseconds: 80 * widget.index), () {
      if (mounted) _ctl.forward();
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // ✅ FIX: Sync local state when post data changes
    // This ensures the UI shows updated data after likes/saves/etc.
    if (oldWidget.post.id == widget.post.id) {
      // Same post, check if likes or likers changed
      if (oldWidget.post.likes != widget.post.likes || 
          oldWidget.post.sampleLikers != widget.post.sampleLikers) {
        print('[PostCard] 🔄 Post data updated: likes ${oldWidget.post.likes} -> ${widget.post.likes}');
        setState(() {
          _currentLikeCount = widget.post.likes;
          _currentSampleLikers = List.from(widget.post.sampleLikers ?? []);
        });
      }
    } else {
      // Different post (widget recycling), reset all state
      print('[PostCard] 🔄 Different post: old=${oldWidget.post.id}, new=${widget.post.id}');
      setState(() {
        _currentLikeCount = widget.post.likes;
        _currentSampleLikers = List.from(widget.post.sampleLikers ?? []);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RepaintBoundary(
      child: FadeTransition(
        opacity: _opacityAnim,
        child: SlideTransition(
          position: _offsetAnim,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: theme.dividerColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.post.imageUrls.isNotEmpty)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                        child: GestureDetector(
                          onTap: () {
                            final url = widget.post.imageUrls.first;
                            final isVideo = url.endsWith('.mp4') ||
                                url.endsWith('.webm') ||
                                url.endsWith('.mov');

                            if (isVideo) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => FullscreenVideoPlayer(
                                    videoUrl: url,
                                  ),
                                ),
                              );
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => FullscreenImageViewer(
                                    imageUrl: url,
                                  ),
                                ),
                              );
                            }
                          },
                          child: _MediaDisplay(url: widget.post.imageUrls.first),
                        ),
                      ),
                      Positioned(
                        top: 14,
                        left: 14,
                        child: _KindBadge(kind: _postKind(widget.post)),
                      ),
                    ],
                  ),
                _PostHeader(post: widget.post, showKindBadge: widget.post.imageUrls.isEmpty),
                if (widget.post.content.isNotEmpty)
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: MentionableText(widget.post.content,
                        style: theme.textTheme.bodyMedium?.copyWith(height: 1.4)),
                  ),
                if (widget.post.postType == PostType.POLL)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: _PollBlock(post: widget.post),
                  ),
                if (widget.post.postType == PostType.EVENT)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: _EventBlock(post: widget.post),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  child: FutureBuilder<int?>(
                    future: ApiService.getUserId(),
                    builder: (context, snapshot) {
                      final likers = _currentSampleLikers;  // Use local state instead of widget.post
                      final likeCount = _currentLikeCount;
                      final currentUserId = snapshot.data;
                      
                      // ✅ FIX Issue 1: Only show "Liked by" when both count > 0 AND sampleLikers has data
                      if (likeCount <= 0 || likers.isEmpty) {
                        return Text(
                          'No likes yet',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodySmall?.color),
                        );
                      }
                      
                      List<String> likerNames = likers.map((u) {
                        if (currentUserId != null && u.userId == currentUserId) {
                          return 'You';
                        }
                        return u.fullName;
                      }).toList();
                      String text = '';
                      if (likerNames.length == 1) {
                        text = 'Liked by ${likerNames[0]}';
                        if (likeCount > 1) {
                          text += ' and ${likeCount - 1} others';
                        }
                      } else if (likerNames.length == 2) {
                        text = 'Liked by ${likerNames[0]} and ${likerNames[1]}';
                        if (likeCount > 2) {
                          text += ' and ${likeCount - 2} others';
                        }
                      } else {
                        text = 'Liked by ${likerNames[0]}, ${likerNames[1]}';
                        if (likerNames.length > 2) {
                          text += ' and ${likerNames[2]}';
                        }
                        if (likeCount > likerNames.length) {
                          text += ' and ${likeCount - likerNames.length} others';
                        }
                      }
                      return Text(
                        text,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodySmall?.color),
                      );
                    },
                  ),
                ),
                PostActionsWidget(
                  post: widget.post,
                  onLikeChanged: (newLikeCount) {
                    setState(() {
                      _currentLikeCount = newLikeCount;
                    });
                  },
                  onLikersUpdated: (newLikers) {
                    setState(() {
                      _currentSampleLikers = newLikers;
                    });
                  },
                  onSaveChanged: (isSaved) {
                    // Notify that saved posts have changed
                    ref.read(savedPostsNotifierProvider.notifier).notifySaveChanged();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MediaDisplay extends StatefulWidget {
  final String url;

  const _MediaDisplay({required this.url});

  @override
  State<_MediaDisplay> createState() => _MediaDisplayState();
}

class _MediaDisplayState extends State<_MediaDisplay> {
  bool get _isVideo {
    final lowerUrl = widget.url.toLowerCase();
    return lowerUrl.endsWith('.mp4') ||
        lowerUrl.endsWith('.webm') ||
        lowerUrl.endsWith('.mov');
  }

  void _openVideoPlayer(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullscreenVideoPlayer(
          videoUrl: widget.url,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _isVideo ? () => _openVideoPlayer(context) : null,
      child: Container(
        height: 240,
        margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: AppColors.surface2,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: _isVideo ? _buildVideoThumbnail() : _buildImage(),
        ),
      ),
    );
  }

  Widget _buildVideoThumbnail() {
    // Generate and display video thumbnail
    return FutureBuilder<Uint8List?>(
      future: VideoThumbnail.thumbnailData(
        video: widget.url,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 800,
        quality: 75,
      ),
      builder: (context, snapshot) {
        return Stack(
          fit: StackFit.expand,
          children: [
            if (snapshot.hasData && snapshot.data != null)
              Image.memory(
                snapshot.data!,
                fit: BoxFit.cover,
              )
            else if (snapshot.connectionState == ConnectionState.waiting)
              Container(
                color: AppColors.art,
                child: const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                  ),
                ),
              )
            else
              Container(
                color: AppColors.art,
              ),
            // Play icon overlay
            Center(
              child: Icon(
                Icons.play_circle_filled,
                color: Colors.white.withValues(alpha: 0.92),
                size: 64,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildImage() {
    // S3 URLs are already complete, use them directly
    String imageUrl = widget.url;
    
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Center(
          child: CircularProgressIndicator(
            value: loadingProgress.expectedTotalBytes != null
                ? loadingProgress.cumulativeBytesLoaded /
                    loadingProgress.expectedTotalBytes!
                : null,
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
                debugPrint('Image load error: $error');
                return Container(
                  color: AppColors.surface2,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.broken_image, size: 48, color: AppColors.mutedSolid),
                        const SizedBox(height: 8),
                        Text(
                          'Image not available',
                          style: const TextStyle(color: AppColors.mutedSolid),
                        ),
                      ],
                    ),
                  ),
                );
      },
    );
  }
}

class _PostHeader extends ConsumerStatefulWidget {
  final Post post;
  final bool showKindBadge;
  const _PostHeader({required this.post, this.showKindBadge = false});

  @override
  ConsumerState<_PostHeader> createState() => _PostHeaderState();
}

class _PostHeaderState extends ConsumerState<_PostHeader> {
  int? _currentUserId;
  DateTime? _cachedTimestamp;  // ✅ Nullable to ensure safe initialization

  @override
  void initState() {
    super.initState();
    _cachedTimestamp = widget.post.timestamp;  // ✅ Cache timestamp on init
    _loadUserId();
  }

  Future<void> _loadUserId() async {
    final id = await ApiService.getUserId();
    if (mounted) setState(() => _currentUserId = id);
  }

  @override
  void didUpdateWidget(_PostHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // ✅ FIX: When post object changes (due to list reordering/deletion),
    // update cached timestamp to match the new post
    if (oldWidget.post.id != widget.post.id ||
        oldWidget.post.timestamp != widget.post.timestamp) {
      print('[PostHeader] 🔄 Post updated: old=${oldWidget.post.id}, new=${widget.post.id}, timestamp=${widget.post.timestamp}');
      _cachedTimestamp = widget.post.timestamp;  // ✅ Update cached timestamp
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final theme = Theme.of(context);
    final hasPic = post.profilePicUrl != null && post.profilePicUrl!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UserProfileScreen(userId: post.userId),
                ),
              );
            },
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.accentSubtle100,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(15),
                  topRight: Radius.circular(15),
                  bottomRight: Radius.circular(15),
                  bottomLeft: Radius.circular(6),
                ),
                image: hasPic
                    ? DecorationImage(
                        image: NetworkImage(
                          post.profilePicUrl!.startsWith('http')
                              ? post.profilePicUrl!
                              : '${ApiConfig.serverUrl}/api/social${post.profilePicUrl}',
                        ),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              alignment: Alignment.center,
              child: hasPic
                  ? null
                  : Text(
                      post.initials,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(post.authorName,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    PostTimestampWidget(timestamp: _cachedTimestamp ?? widget.post.timestamp, style: theme.textTheme.bodySmall),
                    // Close Friends badge
                    if (post.visibility == PostVisibility.CLOSE_FRIENDS) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.gold.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded, size: 11, color: AppColors.gold),
                            const SizedBox(width: 3),
                            Text(
                              'Close Friends',
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.gold,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (widget.showKindBadge) ...[
            _KindBadge(kind: _postKind(post), onMedia: false),
            const SizedBox(width: 4),
          ],
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              final isAuthor = _currentUserId != null && _currentUserId == post.userId;
              if (value == 'edit' && isAuthor) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CreatePostScreen(
                      editingPostId: post.id,
                      initialContent: post.content,
                      initialImageUrls: post.imageUrls,
                      initialVisibility: post.visibility,
                    ),
                  ),
                );
                return;
              }
              if (value == 'delete' && isAuthor) {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Delete post'),
                    content: const Text('Are you sure you want to delete this post?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Delete')),
                    ],
                  ),
                );
                if (confirmed == true) {
                  try {
                    await ref.read(postProvider.notifier).removePost(post.id);
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Post deleted')));
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
                  }
                }
                return;
              }
              if (value == 'share') {
                final text = post.content + (post.imageUrls.isNotEmpty ? '\n${post.imageUrls.first}' : '');
                await SharePlus.instance.share(ShareParams(text: text));
              }
            },
            itemBuilder: (context) {
              final isAuthor = _currentUserId != null && _currentUserId == post.userId;
              if (isAuthor) {
                return [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  const PopupMenuItem(value: 'share', child: Text('Share')),
                ];
              } else {
                return [
                  const PopupMenuItem(value: 'share', child: Text('Share')),
                ];
              }
            },
          ),
        ],
      ),
    );
  }
}


/// Poll content block — options with vote-share bars; tapping an option
/// casts (or changes) the current user's vote.
class _PollBlock extends ConsumerStatefulWidget {
  final Post post;
  const _PollBlock({required this.post});

  @override
  ConsumerState<_PollBlock> createState() => _PollBlockState();
}

class _PollBlockState extends ConsumerState<_PollBlock> {
  bool _voting = false;

  Future<void> _vote(int optionId) async {
    if (_voting) return;
    setState(() => _voting = true);
    try {
      await ref.read(postProvider.notifier).votePoll(widget.post.id, optionId);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to vote')));
      }
    } finally {
      if (mounted) setState(() => _voting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final post = widget.post;
    final totalVotes = post.pollOptions.fold<int>(0, (sum, o) => sum + o.voteCount);
    final hasVoted = post.myPollVoteOptionId != null;
    final maxVotes = post.pollOptions.isEmpty
        ? 0
        : post.pollOptions.map((o) => o.voteCount).reduce((a, b) => a > b ? a : b);
    // The server only ever sets isCorrect once this viewer has voted, so
    // finding one here means this poll IS a quiz and results are revealed.
    final correctOption =
        post.pollOptions.where((o) => o.isCorrect).cast<PollOptionData?>().firstWhere((_) => true, orElse: () => null);
    final answeredCorrectly = correctOption != null && post.myPollVoteOptionId == correctOption.id;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final option in post.pollOptions) ...[
            _PollOptionRow(
              option: option,
              totalVotes: totalVotes,
              selected: post.myPollVoteOptionId == option.id,
              revealResults: hasVoted,
              isLeading: hasVoted && maxVotes > 0 && option.voteCount == maxVotes,
              isCorrectAnswer: hasVoted && option.isCorrect,
              onTap: _voting ? null : () => _vote(option.id),
            ),
            if (option != post.pollOptions.last) const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                totalVotes == 0 ? 'No votes yet' : '$totalVotes ${totalVotes == 1 ? 'vote' : 'votes'}',
                style: TextStyle(color: AppColors.mutedSolid, fontSize: 12),
              ),
              if (correctOption != null) ...[
                const SizedBox(width: 8),
                Text('·', style: TextStyle(color: AppColors.mutedSolid, fontSize: 12)),
                const SizedBox(width: 8),
                Icon(answeredCorrectly ? Icons.check_circle : Icons.cancel,
                    size: 13, color: answeredCorrectly ? AppColors.primary : AppColors.danger),
                const SizedBox(width: 3),
                Text(answeredCorrectly ? 'You got it right!' : 'Not quite — see the correct answer above',
                    style: TextStyle(
                        color: answeredCorrectly ? AppColors.primary : AppColors.danger,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _PollOptionRow extends StatelessWidget {
  final PollOptionData option;
  final int totalVotes;
  final bool selected;
  final bool revealResults;
  final bool isLeading;
  final bool isCorrectAnswer;
  final VoidCallback? onTap;

  const _PollOptionRow({
    required this.option,
    required this.totalVotes,
    required this.selected,
    required this.revealResults,
    required this.isLeading,
    required this.isCorrectAnswer,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final share = totalVotes == 0 ? 0.0 : option.voteCount / totalVotes;
    // A fixed-hue, alpha-scaled fill (rather than a pre-baked light/dark
    // token) so the bar reads clearly as "filled" on both themes — the
    // leading option gets a visibly stronger fill than the rest. The
    // quiz's correct answer (if any) always wins the accent, in gold, so
    // it never gets confused with merely-popular.
    final accent = isCorrectAnswer ? AppColors.gold : primary;
    final fillAlpha = isCorrectAnswer ? 0.32 : (isLeading ? 0.30 : 0.16);

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: isCorrectAnswer ? AppColors.gold : (selected ? primary : theme.dividerColor),
                  width: (selected || isCorrectAnswer) ? 1.5 : 1),
            ),
          ),
          if (revealResults)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: share.clamp(0.0, 1.0) == 0 ? 0.02 : share.clamp(0.0, 1.0),
                  child: Container(height: 40, color: accent.withValues(alpha: fillAlpha)),
                ),
              ),
            ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  if (isCorrectAnswer)
                    const Icon(Icons.emoji_events_rounded, size: 16, color: AppColors.gold)
                  else if (selected)
                    Icon(Icons.check_circle, size: 16, color: primary),
                  if (selected || isCorrectAnswer) const SizedBox(width: 6),
                  Expanded(
                    child: Text(option.text,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (isCorrectAnswer) ...[
                    Text('Correct',
                        style: TextStyle(color: AppColors.gold, fontSize: 11, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 6),
                  ],
                  if (revealResults)
                    Text('${(share * 100).round()}%',
                        style: TextStyle(color: accent, fontSize: 12.5, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Event content block — date/time, location, and RSVP buttons.
class _EventBlock extends ConsumerStatefulWidget {
  final Post post;
  const _EventBlock({required this.post});

  @override
  ConsumerState<_EventBlock> createState() => _EventBlockState();
}

class _EventBlockState extends ConsumerState<_EventBlock> {
  bool _rsvping = false;

  Future<void> _rsvp(String status) async {
    if (_rsvping) return;
    setState(() => _rsvping = true);
    try {
      await ref.read(postProvider.notifier).rsvpEvent(widget.post.id, status);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to RSVP')));
      }
    } finally {
      if (mounted) setState(() => _rsvping = false);
    }
  }

  Widget _rsvpButton(String status, String label, IconData icon) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final active = widget.post.myRsvpStatus == status;
    final count = widget.post.eventRsvpCounts[status] ?? 0;
    return Expanded(
      child: GestureDetector(
        onTap: _rsvping ? null : () => _rsvp(status),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: active ? primary : theme.dividerColor),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: active ? Colors.white : AppColors.mutedSolid),
              const SizedBox(height: 2),
              Text(count > 0 ? '$label ($count)' : label,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: active ? Colors.white : AppColors.mutedSolid)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final post = widget.post;
    final start = post.eventStartTime;
    final dateLabel = start != null ? DateFormat('EEE, MMM d · h:mm a').format(start) : 'Date TBD';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_rounded, size: 18, color: AppColors.gold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(dateLabel, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ],
          ),
          if (post.eventLocation != null && post.eventLocation!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.place_outlined, size: 16, color: AppColors.mutedSolid),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(post.eventLocation!,
                      style: TextStyle(color: AppColors.mutedSolid, fontSize: 12.5)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              _rsvpButton('GOING', 'Going', Icons.check_rounded),
              _rsvpButton('INTERESTED', 'Interested', Icons.star_border_rounded),
              _rsvpButton('NOT_GOING', "Can't go", Icons.close_rounded),
            ],
          ),
        ],
      ),
    );
  }
}
