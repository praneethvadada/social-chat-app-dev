import 'package:flutter/material.dart';
import '../../models/post.dart';
import '../../models/comment.dart';
import '../../models/user_profile.dart';
import '../../services/post_interaction_service.dart';
import '../../services/api_service.dart';
import '../../services/user_profile_cache.dart';
import '../../components/mentionable_text.dart';
import 'package:social_chat_app/src/theme/colors.dart';

class CommentsScreen extends StatefulWidget {
  final Post post;
  final Function(int)? onCommentAdded;

  const CommentsScreen({
    super.key,
    required this.post,
    this.onCommentAdded,
  });

  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  final TextEditingController _commentController = TextEditingController();
  late List<Comment> _comments = [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  int? _replyingToCommentId;
  String? _replyingToUsername;
  UserProfile? _currentUserProfile;

  @override
  void initState() {
    super.initState();
    _fetchComments();
    _loadCurrentUserProfile();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUserProfile() async {
    try {
      final userId = await ApiService.getUserId();
      if (userId != null) {
        final profile = await UserProfileCache().getProfile(userId);
        if (mounted) {
          setState(() {
            _currentUserProfile = profile;
          });
        }
      }
    } catch (e) {
      print('Error loading current user profile: $e');
    }
  }

  Future<void> _fetchComments() async {
    try {
      final comments = await PostInteractionService.getComments(widget.post.id);
      setState(() {
        _comments = comments;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading comments: $e')),
        );
      }
    }
  }

  Future<void> _submitComment() async {
    final comment = _commentController.text.trim();
    if (comment.isEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      if (_replyingToCommentId != null) {
        await PostInteractionService.replyToComment(widget.post.id, _replyingToCommentId!, comment);
      } else {
        await PostInteractionService.addComment(widget.post.id, comment);
      }
      _commentController.clear();
      setState(() => _replyingToCommentId = null);

      // Refresh comments
      await _fetchComments();

      // Notify parent of new comment count
      widget.onCommentAdded?.call(_comments.length);

      // Best-effort @mentions: resolve usernames typed in the comment and
      // notify them, same as post tagging already does.
      _notifyMentioned(comment);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  /// Resolves @usernames in [text] to user IDs and fires a mention
  /// notification for each. Failures are swallowed — a missed mention
  /// notification shouldn't surface as a comment-posting error, since the
  /// comment itself already saved successfully.
  Future<void> _notifyMentioned(String text) async {
    final usernames = extractMentionedUsernames(text);
    if (usernames.isEmpty) return;
    try {
      final ids = <int>[];
      for (final username in usernames) {
        final results = await ApiService.searchUsers(username);
        final match = results.firstWhere(
          (u) => (u['username']?.toString().toLowerCase() ?? '') == username.toLowerCase(),
          orElse: () => const {},
        );
        final id = match['userId'];
        if (id is int) {
          ids.add(id);
        } else if (id != null) {
          final parsed = int.tryParse(id.toString());
          if (parsed != null) ids.add(parsed);
        }
      }
      if (ids.isNotEmpty) {
        await ApiService.sendMentionNotification(
          mentionedUserIds: ids,
          postId: widget.post.id,
          postContent: text,
        );
      }
    } catch (_) {
      // Non-critical — the comment already posted.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Comments'),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: _comments.isEmpty
                      ? Center(
                          child: Text(
                            'No comments yet',
                            style: theme.textTheme.bodyMedium,
                          ),
                        )
                      : ListView.builder(
                          itemCount: _comments.length,
                          itemBuilder: (context, index) {
                            return _CommentTile(
                              comment: _comments[index],
                              onReply: (commentId, username) {
                                setState(() {
                                  _replyingToCommentId = commentId;
                                  _replyingToUsername = username;
                                });
                                _commentController.clear();
                              },
                              onRefresh: _fetchComments,
                            );
                          },
                        ),
                ),
                if (_replyingToCommentId != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Replying to @${_replyingToUsername ?? 'User'}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontStyle: FontStyle.italic,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _replyingToCommentId = null;
                              _replyingToUsername = null;
                            });
                            _commentController.clear();
                          },
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ),
                Container(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: theme.dividerColor)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: theme.colorScheme.primary,
                        radius: 18,
                        backgroundImage: _currentUserProfile?.profilePictureUrl != null
                            ? NetworkImage(_currentUserProfile!.profilePictureUrl!)
                            : null,
                        child: _currentUserProfile?.profilePictureUrl == null
                            ? Text(
                                _currentUserProfile?.fullName.isNotEmpty == true
                                    ? _currentUserProfile!.fullName[0].toUpperCase()
                                    : 'M',
                                style: const TextStyle(color: Colors.white),
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _commentController,
                          decoration: InputDecoration(
                            hintText: _replyingToCommentId != null
                                ? 'Write a reply...'
                                : 'Write a comment...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide(color: theme.dividerColor),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                          maxLines: 1,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _isSubmitting ? null : _submitComment,
                        icon: _isSubmitting
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(
                                    theme.iconTheme.color,
                                  ),
                                ),
                              )
                            : Icon(Icons.send, color: theme.iconTheme.color),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _CommentTile extends StatefulWidget {
  final Comment comment;
  final Function(int, String) onReply;
  final Future<void> Function() onRefresh;

  const _CommentTile({
    required this.comment,
    required this.onReply,
    required this.onRefresh,
  });

  @override
  State<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<_CommentTile> {
  late bool _isLiked;
  late int _likesCount;
  bool _isLiking = false;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.comment.isLikedByCurrentUser;
    _likesCount = widget.comment.likes;
  }

  Future<void> _toggleLike() async {
    if (_isLiking) return;

    setState(() => _isLiking = true);
    try {
      if (_isLiked) {
        await PostInteractionService.unlikeComment(widget.comment.id);
      } else {
        await PostInteractionService.likeComment(widget.comment.id);
      }

      setState(() {
        _isLiked = !_isLiked;
        if (_isLiked) {
          _likesCount++;
        } else {
          _likesCount = (_likesCount > 0) ? _likesCount - 1 : 0;
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => _isLiking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: theme.colorScheme.primary,
                radius: 18,
                backgroundImage: widget.comment.authorProfilePictureUrl != null
                    ? NetworkImage(widget.comment.authorProfilePictureUrl!)
                    : null,
                child: widget.comment.authorProfilePictureUrl == null
                    ? Text(
                        widget.comment.authorName[0].toUpperCase(),
                        style: const TextStyle(color: Colors.white),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.comment.authorName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    MentionableText(
                      widget.comment.content,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          widget.comment.timeAgo,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: _toggleLike,
                          child: Row(
                            children: [
                              Icon(
                                _isLiked ? Icons.favorite : Icons.favorite_border,
                                size: 14,
                                color: _isLiked ? AppColors.danger : theme.textTheme.bodySmall?.color,
                              ),
                              const SizedBox(width: 4),
                              Text(
  _likesCount > 0 ? _likesCount.toString() : 'Like',
  style: theme.textTheme.bodySmall?.copyWith(
    color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
    fontWeight: _likesCount > 0 ? FontWeight.w600 : FontWeight.normal,
  ),
),

                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: () => widget.onReply(widget.comment.id, widget.comment.authorName),
                          child: Text(
                            'Reply',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
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
          if (widget.comment.replies.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 48, top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.comment.replies
                    .map((reply) => _ReplyTile(
                          reply: reply,
                          onRefresh: widget.onRefresh,
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReplyTile extends StatefulWidget {
  final Comment reply;
  final Future<void> Function() onRefresh;

  const _ReplyTile({
    required this.reply,
    required this.onRefresh,
  });

  @override
  State<_ReplyTile> createState() => _ReplyTileState();
}

class _ReplyTileState extends State<_ReplyTile> {
  late bool _isLiked;
  late int _likesCount;
  bool _isLiking = false;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.reply.isLikedByCurrentUser;
    _likesCount = widget.reply.likes;
  }

  Future<void> _toggleLike() async {
    if (_isLiking) return;

    setState(() => _isLiking = true);
    try {
      if (_isLiked) {
        await PostInteractionService.unlikeComment(widget.reply.id);
      } else {
        await PostInteractionService.likeComment(widget.reply.id);
      }

      setState(() {
        _isLiked = !_isLiked;
        if (_isLiked) {
          _likesCount++;
        } else {
          _likesCount = (_likesCount > 0) ? _likesCount - 1 : 0;
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => _isLiking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: theme.colorScheme.primary,
            radius: 14,
            backgroundImage: widget.reply.authorProfilePictureUrl != null
                ? NetworkImage(widget.reply.authorProfilePictureUrl!)
                : null,
            child: widget.reply.authorProfilePictureUrl == null
                ? Text(
                    widget.reply.authorName[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  )
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.reply.authorName,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                MentionableText(
                  widget.reply.content,
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      widget.reply.timeAgo,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: _toggleLike,
                      child: Row(
                        children: [
                          Icon(
                            _isLiked ? Icons.favorite : Icons.favorite_border,
                            size: 12,
                            color: _isLiked ? AppColors.danger : theme.textTheme.bodySmall?.color,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _likesCount > 0 ? _likesCount.toString() : 'Like',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
