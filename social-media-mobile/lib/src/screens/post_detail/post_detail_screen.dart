import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'dart:typed_data';
import '../../config/api_config.dart';
import '../../models/post.dart';
import '../../components/post_actions_widget.dart';
import '../fullscreen_media/fullscreen_image_viewer.dart';
import '../fullscreen_media/fullscreen_video_player.dart';
import '../user_profile_screen.dart';
import '../../services/api_service.dart';
import '../../services/post_service.dart';
import 'package:share_plus/share_plus.dart';
import '../create_post/create_post_screen.dart';
import '../../utils/time_utils.dart';
import '../../state/saved_posts_notifier.dart';
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
      body: SingleChildScrollView(
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

            // Post Media
            if (hasMedia)
              GestureDetector(
                onTap: () {
                  if (isVideo) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => FullscreenVideoPlayer(
                          videoUrl: mediaUrl!,
                        ),
                      ),
                    );
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => FullscreenImageViewer(
                          imageUrl: mediaUrl!,
                        ),
                      ),
                    );
                  }
                },
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 400),
                  child: _MediaDisplay(url: mediaUrl!),
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
      return FutureBuilder<Uint8List?>(
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
      );
    }

    String imageUrl = url;

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
        return Container(
          color: AppColors.border,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image, size: 48, color: AppColors.mutedSolid),
                const SizedBox(height: 8),
                Text(
                  'Image not available',
                  style: TextStyle(color: AppColors.mutedSolid),
                ),
              ],
            ),
          ),
        );
      },
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
