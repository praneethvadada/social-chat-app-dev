import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:video_player/video_player.dart';

import '../../config/api_config.dart';
import '../../components/media_picker.dart';
import '../../components/media_preview_carousel.dart';
import '../../models/selected_media.dart';
import '../../models/post.dart';
import '../../services/media_service.dart';
import '../../services/post_service.dart';
import '../../services/api_service.dart';
import '../../models/user_search.dart';
import '../../components/tag_people_dialog.dart';
import '../../state/app_state_manager.dart';
import 'package:social_chat_app/src/theme/colors.dart';

class CreatePostScreen extends ConsumerStatefulWidget {
  final int? editingPostId;
  final String? initialContent;
  final List<String>? initialImageUrls; // Add this to pass existing media URLs
  final PostVisibility? initialVisibility; // Add this to preserve visibility when editing
  const CreatePostScreen({
    super.key, 
    this.editingPostId, 
    this.initialContent,
    this.initialImageUrls,
    this.initialVisibility,
  });

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _mediaPicker = MediaPicker();
  final List<SelectedMedia> _selected = [];
  bool _uploading = false;
  double _progress = 0.0;
  List<UserSearch> _taggedUsers = [];

  // @mention autocomplete: active only while the caret sits inside an
  // unfinished "@token" (no whitespace since the @). Results come from the
  // same search endpoint used by the Tag People dialog.
  List<Map<String, dynamic>> _mentionResults = [];
  bool _mentionSearching = false;
  int? _mentionStart;
  Timer? _mentionDebounce;

  // Close Friends feature - visibility state
  PostVisibility _selectedVisibility = PostVisibility.PUBLIC;
  
  // Track existing media URLs (for editing)
  List<String> _existingMediaUrls = [];
  
  // User profile data
  String _fullName = '';
  String? _profilePicUrl;

  void _onContentChanged() {
    if (mounted) setState(() {});
    _detectMentionQuery();
  }

  /// Looks backward from the caret for an unfinished "@token" (an @ not
  /// preceded by a word character, with no whitespace between it and the
  /// caret) and kicks off a debounced user search for it. Clears the
  /// dropdown as soon as that condition no longer holds.
  void _detectMentionQuery() {
    final text = _controller.text;
    final caret = _controller.selection.baseOffset;
    if (caret < 0 || caret > text.length) {
      _clearMentionState();
      return;
    }

    int at = -1;
    for (int i = caret - 1; i >= 0; i--) {
      final ch = text[i];
      if (ch == '@') {
        final before = i == 0 ? '' : text[i - 1];
        if (!RegExp(r'[A-Za-z0-9_]').hasMatch(before)) {
          at = i;
        }
        break;
      }
      if (RegExp(r'\s').hasMatch(ch)) break;
    }

    if (at == -1) {
      _clearMentionState();
      return;
    }

    final query = text.substring(at + 1, caret);
    if (query.contains(RegExp(r'\s'))) {
      _clearMentionState();
      return;
    }

    _mentionStart = at;
    _mentionDebounce?.cancel();
    _mentionDebounce = Timer(const Duration(milliseconds: 250), () => _searchMentions(query));
  }

  void _clearMentionState() {
    _mentionDebounce?.cancel();
    if (_mentionStart != null || _mentionResults.isNotEmpty) {
      setState(() {
        _mentionStart = null;
        _mentionResults = [];
        _mentionSearching = false;
      });
    }
  }

  Future<void> _searchMentions(String query) async {
    if (!mounted || _mentionStart == null) return;
    setState(() => _mentionSearching = true);
    try {
      final results = query.isEmpty
          ? await ApiService.getSuggestedUsers(size: 8)
          : await ApiService.searchUsers(query, size: 8);
      final currentUserId = await ApiService.getUserId();
      if (!mounted || _mentionStart == null) return;
      setState(() {
        _mentionResults = results.where((u) => u['userId'] != currentUserId).toList();
        _mentionSearching = false;
      });
    } catch (_) {
      if (mounted) setState(() => _mentionSearching = false);
    }
  }

  void _insertMention(Map<String, dynamic> user) {
    final start = _mentionStart;
    if (start == null) return;
    final username = user['username']?.toString() ?? '';
    final caret = _controller.selection.baseOffset;
    final text = _controller.text;
    final safeCaret = caret >= 0 && caret <= text.length ? caret : text.length;
    final newText = text.replaceRange(start, safeCaret, '@$username ');
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + username.length + 2),
    );
    _clearMentionState();
  }

  @override
  void dispose() {
    _mentionDebounce?.cancel();
    _controller.removeListener(_onContentChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Rebuild as the user types so the Post button enables/disables on text
    // alone (needed now that text-only posts are allowed). Also keeps the
    // character counter in sync.
    _controller.addListener(_onContentChanged);
    if (widget.initialContent != null) {
      _controller.text = widget.initialContent!;
    }
    // Load existing media URLs for editing
    if (widget.initialImageUrls != null) {
      _existingMediaUrls = List.from(widget.initialImageUrls!);
    }
    // Load existing visibility for editing (CRITICAL FIX)
    if (widget.initialVisibility != null) {
      _selectedVisibility = widget.initialVisibility!;
    }
    _loadUserProfile();
  }
  
  Future<void> _loadUserProfile() async {
    try {
      final profile = await ApiService.getMyProfile();
      if (mounted) {
        setState(() {
          _fullName = profile['fullName'] ?? '';
          _profilePicUrl = profile['profilePictureUrl'];
        });
      }
    } catch (e) {
      print('Error loading profile: $e');
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

  Future<void> _openPickerSheet() async {
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Pick Photos'),
              onTap: () async {
                Navigator.of(c).pop();
                final items = await _mediaPicker.pickImages();
                if (items.isNotEmpty) setState(() => _selected.addAll(items));
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_library),
              title: const Text('Pick Video'),
              onTap: () async {
                Navigator.of(c).pop();
                final item = await _mediaPicker.pickVideo();
                if (item != null) setState(() => _selected.add(item));
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () async {
                Navigator.of(c).pop();
                final item = await _mediaPicker.takePhoto();
                if (item != null) setState(() => _selected.add(item));
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Take Video'),
              onTap: () async {
                Navigator.of(c).pop();
                final item = await _mediaPicker.takeVideo();
                if (item != null) setState(() => _selected.add(item));
              },
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.of(c).pop(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _post() async {
    final content = _controller.text.trim();
    
    // A post needs text OR media - text-only posts are allowed.
    // This mirrors the backend rule (PostRequest: hasContent || hasImages).
    final hasMedia = _selected.isNotEmpty || _existingMediaUrls.isNotEmpty;
    if (content.isEmpty && !hasMedia) {
      Fluttertoast.showToast(
          msg: 'Write something or attach a photo or video');
      return;
    }

    setState(() {
      _uploading = true;
      _progress = 0.0;
    });

    // Upload selected media
    final List<String> uploadedUrls = [];
    if (_selected.isNotEmpty) {
      final total = _selected.length;
      var completed = 0;

      for (final m in _selected) {
        try {
          final url = await MediaService.uploadMedia(m, (p) {
            setState(() {
              _progress = (completed + p) / total;
            });
          });
          uploadedUrls.add(url);
          completed++;
        } catch (e) {
          Fluttertoast.showToast(msg: 'Failed to upload media: $e');
          setState(() {
            _uploading = false;
            _progress = 0.0;
          });
          return;
        }
      }
    }

    var success = false;
    try {
      final actorName = await ApiService.getFullName() ?? 'Someone';
      if (widget.editingPostId != null) {
        // For editing, use newly uploaded media OR keep existing if no new media
        final List<String> finalUrls = uploadedUrls.isNotEmpty 
            ? uploadedUrls  // Use new media (replaces old)
            : _existingMediaUrls; // Keep existing media if no new uploads
        
        await ref.read(postProvider.notifier).editPost(
          widget.editingPostId!,
          content: content,
          imageUrls: finalUrls,
          visibility: _selectedVisibility.name,
        );
      } else {
        final currentUserId = await ApiService.getUserId();
        final filteredTaggedUserIds = _taggedUsers
            .map((u) => u.userId)
            .where((id) => id > 0 && id != (currentUserId ?? -1))
            .toList();
        await ref.read(postProvider.notifier).addPost(
              content: content,
              imageUrls: uploadedUrls,
              taggedUserIds: filteredTaggedUserIds,
              actorName: actorName,
              visibility: _selectedVisibility.name,
            );
      }
      success = true;
      Fluttertoast.showToast(msg: widget.editingPostId != null ? 'Post updated successfully' : 'Posted successfully');
      
      // ✅ Auto-refresh posts to show new post with correct timestamp
      if (mounted) {
        ref.read(postProvider.notifier).refreshPosts();
      }
      
      if (mounted) {
        // If editing, navigate back to previous screen then go to home
        if (widget.editingPostId != null) {
          Navigator.of(context).popUntil((route) => route.isFirst);
          ref.read(appStateProvider.notifier).goToHomeTab();
        } else {
          // For new posts, just close the modal/screen
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          } else {
            ref.read(appStateProvider.notifier).closeModal();
          }
        }
      }
    } catch (e) {
      Fluttertoast.showToast(msg: 'Failed to post: $e');
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _progress = 0.0;
          if (success) {
            _selected.clear();
            _controller.clear();
          }
        });
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    // Enabled when there is text OR media (same rule for new posts and edits),
    // so text-only posts are possible.
    final hasMedia = _existingMediaUrls.isNotEmpty || _selected.isNotEmpty;
    final hasText = _controller.text.trim().isNotEmpty;
    final canPost = (hasText || hasMedia) && !_uploading;

    void _handleBack() {
      // Check if we can pop (opened via Navigator.push)
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        // Opened as modal, close the modal
        ref.read(appStateProvider.notifier).closeModal();
      }
    }

    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: SafeArea(
            child: Container(
              color: theme.cardColor,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back,
                        color: theme.iconTheme.color ?? Colors.black87),
                    onPressed: _handleBack,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Center(
                      child: Text(
                        widget.editingPostId != null ? 'Edit Post' : 'Create Post',
                        style: TextStyle(
                          color: primary, 
                          fontWeight: FontWeight.w700
                        )
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: ElevatedButton(
                      onPressed: canPost && !_uploading ? _post : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 10),
                      ),
                      child: _uploading
                          ? SizedBox(
                              width: 100,
                              child: LinearProgressIndicator(
                                  value: _progress,
                                  color: Colors.white,
                                  backgroundColor:
                                      primary.withAlpha((0.3 * 255).round())),
                            )
                          : const Text('Post'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar with profile picture
                    _profilePicUrl != null && _profilePicUrl!.isNotEmpty
                        ? CircleAvatar(
                            radius: 22,
                            backgroundImage: NetworkImage(
                              _profilePicUrl!.startsWith('http')
                                  ? _profilePicUrl!
                                  : '${ApiConfig.serverUrl}/api/social$_profilePicUrl',
                            ),
                          )
                        : CircleAvatar(
                            radius: 22,
                            backgroundColor: primary,
                            child: Text(
                              _getInitials(_fullName),
                              style: TextStyle(
                                color: theme.textTheme.bodyLarge?.color ??
                                    Colors.white),
                            )),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _controller,
                            maxLines: null,
                            minLines: 5,
                            decoration: InputDecoration(
                              hintText: "What's on your mind?",
                              border: InputBorder.none,
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Wrap(
                                spacing: 8,
                                children: _taggedUsers
                                    .map((u) => Chip(label: Text(u.fullName)))
                                    .toList(),
                              ),
                              Text('${_controller.text.length}/280',
                                  style: TextStyle(
                                      color: theme.textTheme.bodySmall?.color,
                                      fontSize: 12)),
                            ],
                          )
                        ],
                      ),
                    )
                  ],
                ),
                if (_mentionStart != null) _buildMentionSuggestions(theme),
                const SizedBox(height: 12),

                // Display existing media when editing
                if (widget.editingPostId != null && _existingMediaUrls.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current Media',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: theme.textTheme.bodyLarge?.color,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 120,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _existingMediaUrls.length,
                          itemBuilder: (context, index) {
                            final url = _existingMediaUrls[index];
                            final isVideo = url.toLowerCase().endsWith('.mp4') ||
                                url.toLowerCase().endsWith('.mov') ||
                                url.toLowerCase().endsWith('.webm');
                            
                            return Container(
                              width: 120,
                              margin: const EdgeInsets.only(right: 8),
                              child: Stack(
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: AppColors.border),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: isVideo
                                          ? Container(
                                              color: Colors.black,
                                              child: const Center(
                                                child: Icon(
                                                  Icons.play_circle_filled,
                                                  color: Colors.white,
                                                  size: 40,
                                                ),
                                              ),
                                            )
                                          : Image.network(
                                              url,
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error, stackTrace) {
                                                return Container(
                                                  color: AppColors.surface2,
                                                  child: const Center(
                                                    child: Icon(Icons.broken_image),
                                                  ),
                                                );
                                              },
                                            ),
                                    ),
                                  ),
                                  // Delete button
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _existingMediaUrls.removeAt(index);
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: AppColors.danger,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.close,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),

                // Media area
                if (widget.editingPostId != null && _existingMediaUrls.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Upload New Media (Replaces Current)',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                  ),
                GestureDetector(
                  onTap: _openPickerSheet,
                  child: DottedBox(
                    child: SizedBox(
                      height: 140,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.cloud_upload,
                                size: 36,
                                color: theme.iconTheme.color?.withValues(alpha: 0.5)),
                            const SizedBox(height: 8),
                            Text('Add photos or videos',
                                style: TextStyle(
                                    color: theme.textTheme.bodyMedium?.color)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                MediaPreviewCarousel(
                  items: _selected,
                  onRemove: (m) {
                    setState(() => _selected.removeWhere((e) => e.id == m.id));
                  },
                  onTap: (m) {
                    if (m.type == MediaType.video) {
                      showDialog(
                          context: context,
                          builder: (_) => VideoPreviewDialog(file: m.file));
                    }
                  },
                ),

                const SizedBox(height: 18),

                // action chips
                Row(
                  children: [
                    ActionPill(
                        label: 'Photo',
                        color: AppColors.accentSubtle100,
                        onTap: () async {
                          final items = await _mediaPicker.pickImages();
                          if (items.isNotEmpty)
                            setState(() => _selected.addAll(items));
                        }),
                    const SizedBox(width: 8),
                    ActionPill(
                        label: 'Video',
                        color: AppColors.accentSubtle100,
                        onTap: () async {
                          final item = await _mediaPicker.pickVideo();
                          if (item != null) setState(() => _selected.add(item));
                        }),
                    const SizedBox(width: 8),
                    ActionPill(
                        label: 'Tag',
                        color: AppColors.goldSubtle100,
                        onTap: _openTagDialog),
                  ],
                ),

                const SizedBox(height: 12),

                // Visibility selector (Close Friends feature)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.public, size: 20, color: AppColors.mutedSolid),
                      const SizedBox(width: 12),
                      const Text(
                        'Visibility:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<PostVisibility>(
                            value: _selectedVisibility,
                            isExpanded: true,
                            items: [
                              DropdownMenuItem(
                                value: PostVisibility.PUBLIC,
                                child: Row(
                                  children: [
                                    Icon(Icons.public, size: 18, color: primary),
                                    const SizedBox(width: 8),
                                    const Text('Public'),
                                  ],
                                ),
                              ),
                              DropdownMenuItem(
                                value: PostVisibility.CLOSE_FRIENDS,
                                child: Row(
                                  children: [
                                    Icon(Icons.star, size: 18, color: AppColors.primary),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Close Friends',
                                      style: TextStyle(color: AppColors.primary),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _selectedVisibility = value;
                                });
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMentionSuggestions(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: _mentionSearching
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                  child: SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          : _mentionResults.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('No matching users',
                      style: TextStyle(color: AppColors.mutedSolid, fontSize: 13)),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _mentionResults.length,
                  itemBuilder: (context, index) {
                    final u = _mentionResults[index];
                    final pic = u['profilePictureUrl']?.toString();
                    final hasPic = pic != null && pic.isNotEmpty;
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: theme.colorScheme.primary,
                        backgroundImage: hasPic
                            ? NetworkImage(
                                pic.startsWith('http') ? pic : '${ApiConfig.serverUrl}/api/social$pic')
                            : null,
                        child: hasPic
                            ? null
                            : Text(
                                _getInitials(u['fullName']?.toString() ?? u['username']?.toString() ?? '?'),
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                              ),
                      ),
                      title: Text(u['fullName']?.toString().isNotEmpty == true
                          ? u['fullName'].toString()
                          : '@${u['username']}'),
                      subtitle: Text('@${u['username']}'),
                      onTap: () => _insertMention(u),
                    );
                  },
                ),
    );
  }

  Future<void> _openTagDialog() async {
    final sel = await showDialog<List<UserSearch>>(
      context: context,
      builder: (c) => TagPeopleDialog(initiallyTagged: _taggedUsers),
    );
    if (sel != null) setState(() => _taggedUsers = sel);
  }
}

class DottedBox extends StatelessWidget {
  final Widget child;
  const DottedBox({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: theme.dividerColor, width: 1.5, style: BorderStyle.solid)),
      child: child,
    );
  }
}

class ActionPill extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const ActionPill(
      {super.key,
      required this.label,
      required this.color,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    final luminance = color.computeLuminance();
    final textColor = luminance > 0.6 ? Colors.black : Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(12)),
        child: Text(label,
            style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class VideoPreviewDialog extends StatefulWidget {
  final File file;
  const VideoPreviewDialog({super.key, required this.file});
  @override
  State<VideoPreviewDialog> createState() => _VideoPreviewDialogState();
}

class _VideoPreviewDialogState extends State<VideoPreviewDialog> {
  late VideoPlayerController _ctl;
  @override
  void initState() {
    super.initState();
    _ctl = VideoPlayerController.file(widget.file)
      ..initialize().then((_) {
        setState(() {});
        _ctl.play();
      });
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: AspectRatio(
        aspectRatio: _ctl.value.aspectRatio,
        child: VideoPlayer(_ctl),
      ),
    );
  }
}
