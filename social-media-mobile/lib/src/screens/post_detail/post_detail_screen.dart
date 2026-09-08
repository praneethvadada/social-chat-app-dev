import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'dart:typed_data';
import '../../config/api_config.dart';
import '../../models/post.dart';
import '../../components/post_actions_widget.dart';
import '../../components/post_card.dart' show PollBlock, EventBlock;
import '../fullscreen_media/fullscreen_image_viewer.dart';
import '../fullscreen_media/fullscreen_video_player.dart';
import '../user_profile_screen.dart';
import '../../services/api_service.dart';
import '../../services/post_service.dart';
import 'package:share_plus/share_plus.dart';
import '../create_post/create_post_screen.dart';
import '../../utils/time_utils.dart';
import '../../state/saved_posts_notifier.dart';
import '../../responsive/desktop_content_wrapper.dart';
import '../../components/natural_image.dart';
import '../../components/post_media_carousel.dart';
import 'package:social_chat_app/src/theme/colors.dart';

class PostDetailScreen extends ConsumerStatefulWidget {
  final Post post;

  const PostDetailScreen({super.key, required this.post});

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  late int _currentLikeCount;

  @override
  void initState() {
    super.initState();
    _currentLikeCount = widget.post.likes;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasMedia = widget.post.imageUrls.isNotEmpty;
    final mediaUrl = hasMedia ? widget.post.imageUrls.first : null;
    final isVideo = mediaUrl != null &&
        (mediaUrl.toLowerCase().endsWith('.mp4') ||
            mediaUrl.toLowerCase().endsWith('.webm') ||
            mediaUrl.toLowerCase().endsWith('.mov'));

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.iconTheme.color),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Post',
          style: TextStyle(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: DesktopContentWrapper(
        maxWidth: 640,
        child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Post Header
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => UserProfileScreen(userId: widget.post.userId),
                        ),
                      );
                    },
                    child: widget.post.profilePicUrl != null && widget.post.profilePicUrl!.isNotEmpty
                        ? CircleAvatar(
                            radius: 24,
                            backgroundImage: NetworkImage(
                              widget.post.profilePicUrl!.startsWith('http')
                                  ? widget.post.profilePicUrl!
                                  : '${ApiConfig.serverUrl}/api/social${widget.post.profilePicUrl}',
                            ),
                          )
                        : CircleAvatar(
                            backgroundColor: theme.colorScheme.primary,
                            radius: 24,
                            child: Text(
                              widget.post.initials,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.post.authorName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        TimeAgoWidget(
                          timestamp: widget.post.timestamp,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.mutedSolid,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _PostDetailMenu(post: widget.post),
                ],
              ),
            ),

            // Post Content
            if (widget.post.content.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Text(
                  widget.post.content,
                  style: theme.textTheme.bodyLarge,
                ),
              ),

            // Poll / Event block — found missing entirely while wiring up
            // the poll/RSVP voters feature: this screen rendered plain
            // content text for a POLL or EVENT post with no options, vote
            // bars, or RSVP buttons at all. Reuses the exact same widgets
            // the feed's PostCard uses, not a second implementation.
            if (widget.post.postType == PostType.POLL)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: PollBlock(post: widget.post),
              ),
            if (widget.post.postType == PostType.EVENT)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: EventBlock(post: widget.post),
              ),

            // Post Media — PostMediaCarousel handles 1 image (natural
            // aspect ratio, no cap issue) same as before, or 2+ (swipeable,
            // "1/N" counter) — was hardcoded to imageUrls.first only,
            // silently dropping every image after the first on a
            // multi-image post.
            if (hasMedia)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: PostMediaCarousel(
                  urls: widget.post.imageUrls,
                  maxHeight: 500,
                  videoThumbnailBuilder: (url) => _MediaDisplay(url: url),
                  onTapImage: (url) => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => FullscreenImageViewer(imageUrl: url)),
                  ),
                  onTapVideo: (url) => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => FullscreenVideoPlayer(videoUrl: url)),
                  ),
                ),
              ),

            // Like Count
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Text(
                _currentLikeCount > 0
                    ? 'Liked by ${widget.post.authorName.toLowerCase().replaceAll(' ', '_')} and ${_currentLikeCount > 1 ? _currentLikeCount - 1 : 0} others'
                    : 'No likes yet',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            const Divider(height: 1),

            // Post Actions
            PostActionsWidget(
              post: widget.post,
              onLikeChanged: (newLikeCount) {
                setState(() {
                  _currentLikeCount = newLikeCount;
                });
              },
              onLikersUpdated: (newLikers) {
                // Update likers in post detail (if needed)
              },
              onSaveChanged: (isSaved) {
                // Notify that saved posts have changed
                ref.read(savedPostsNotifierProvider.notifier).notifySaveChanged();
              },
            ),

            const SizedBox(height: 16),
          ],
        ),
        ),
      ),
    );
  }
}

class _MediaDisplay extends StatelessWidget {
  final String url;

  const _MediaDisplay({required this.url});

  bool get _isVideo {
    final lowerUrl = url.toLowerCase();
    return lowerUrl.endsWith('.mp4') ||
        lowerUrl.endsWith('.webm') ||
        lowerUrl.endsWith('.mov');
  }

  @override
  Widget build(BuildContext context) {
    if (_isVideo) {
      // Unchanged (moved in from the old call-site wrapper, same 400px
      // cap) — this feature request is about image display only.
      return SizedBox(
        width: double.infinity,
        height: 400,
        child: FutureBuilder<Uint8List?>(
        future: VideoThumbnail.thumbnailData(
          video: url,
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
                  color: AppColors.text,
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                    ),
                  ),
                )
              else
                Container(
                  color: AppColors.text,
                ),
              // Play icon overlay
              Center(
                child: Icon(
                  Icons.play_circle_filled,
                  color: Colors.white.withValues(alpha: 0.9),
                  size: 64,
                ),
              ),
            ],
          );
        },
        ),
      );
    }

    // Image: natural aspect ratio, never force-cropped/stretched — was a
    // fixed-400px BoxFit.cover box before. maxHeight is a generous safety
    // cap, not a crop (see NaturalImage's own doc comment).
    return NaturalImage(
      provider: NetworkImage(url),
      maxHeight: 500,
    );
  }

}

// PopupMenuButton for post detail screen (must be outside of any class)
class _PostDetailMenu extends ConsumerStatefulWidget {
  final Post post;
  const _PostDetailMenu({required this.post});

  @override
  ConsumerState<_PostDetailMenu> createState() => _PostDetailMenuState();
}

class _PostDetailMenuState extends ConsumerState<_PostDetailMenu> {
  int? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadUserId();
  }

  Future<void> _loadUserId() async {
    final id = await ApiService.getUserId();
    if (mounted) setState(() => _currentUserId = id);
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    return PopupMenuButton<String>(
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
              Navigator.of(context).pop();
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
    );
  }
}
