import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../config/api_config.dart';
import 'edit_profile_screen.dart';
import '../../services/api_service.dart';
import '../../services/post_service.dart';
import '../../services/status_api.dart';
import '../../models/post.dart';
import '../../models/status.dart';
import '../post_detail/post_detail_screen.dart';
import '../followers_list_screen.dart';
import '../../state/app_state_manager.dart';
import '../../state/saved_posts_notifier.dart';
import '../../utils/friendly_error.dart';
import '../../components/squircle_avatar.dart';
import '../../responsive/desktop_content_wrapper.dart';
import '../../responsive/breakpoints.dart';
import '../../models/group.dart';
import '../../services/group_api.dart';
import 'package:social_chat_app/src/theme/colors.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  @override
  bool get wantKeepAlive => true;

  static const double _coverHeight = 190;
  static const double _avatarSize = 96;

  bool _isLoading = true;
  String? _errorMessage;
  bool _isLoadingSavedPosts = false;
  bool _isLoadingMoments = false;
  bool _isUploadingCover = false;

  String _fullName = '';
  String _username = '';
  String _bio = '';
  String? _profilePicUrl;
  String? _coverPhotoUrl;
  int _postsCount = 0;
  int _followersCount = 0;
  int _followingCount = 0;
  int _userId = 0;
  List<Post> _userPosts = [];
  List<Post> _savedPosts = [];
  List<StatusItem> _moments = [];
  String? _location;
  String? _website;
  // Desktop details column only (see build()) — my groups, reusing the
  // exact same fetch Connect's group list uses.
  List<GroupSummary> _myGroups = [];

  // Tab selection: 0 = Posts, 1 = Moments, 2 = Saved
  int _selectedTab = 0;

  bool _isFirstBuild = true;
  String _lastLocation = '';

  @override
  void initState() {
    super.initState();
    _loadProfile();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Reset tab when app comes to foreground
    if (state == AppLifecycleState.resumed && !_isFirstBuild) {
      if (_selectedTab != 0) {
        setState(() => _selectedTab = 0);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Get current route location
    final currentLocation = _getCurrentLocation();

    // Detect navigation to profile screen
    if (!_isFirstBuild && currentLocation == '/profile' && _lastLocation != '/profile') {
      print('[ProfileScreen] Navigated to profile, resetting tab and reloading...');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          // Reset to Posts tab
          if (_selectedTab != 0) {
            setState(() => _selectedTab = 0);
          }
          // Reload profile data
          _loadProfile();
        }
      });
    }

    _lastLocation = currentLocation;
    _isFirstBuild = false;
  }

  String _getCurrentLocation() {
    try {
      final router = GoRouter.of(context);
      return (router as dynamic).location as String? ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      print('\n========== PROFILESCREEN _loadProfile ==========');
      // Fetch profile from backend
      final profile = await ApiService.getMyProfile();
      print('\n[PROFILE RECEIVED IN UI]');
      print('fullName: ${profile['fullName']}');
      print('username: ${profile['username']}');

      if (mounted) {
        setState(() {
          _fullName = profile['fullName'] ?? '';
          _username = profile['username'] ?? '';
          _bio = profile['bio'] ?? '';
          _profilePicUrl = profile['profilePictureUrl'];
          _coverPhotoUrl = profile['coverPhotoUrl'];
          _postsCount = profile['postsCount'] ?? 0;
          _followersCount = profile['followersCount'] ?? 0;
          _followingCount = profile['followingCount'] ?? 0;
          _userId = profile['userId'] ?? 0;
          _location = (profile['location'] as String?)?.trim();
          _website = (profile['website'] as String?)?.trim();
          _isLoading = false;
        });
        // Fetch user posts after profile loads
        if (_userId > 0) {
          _loadUserPosts();
        }
        _loadMyGroups();
      }
    } catch (e) {
      print('\n[ERROR IN _loadProfile]');
      print('Error: $e');
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
      final posts = await ApiService.getUserPosts(_userId);
      if (mounted) {
        setState(() {
          _userPosts = posts;
        });
      }
    } catch (e) {
      print('Error loading user posts: $e');
    }
  }

  /// Desktop details column only — same fetch Connect's "GROUP SPACES"
  /// section already uses (`GroupApi.fetchMyGroups`). Failure is silent (no
  /// error banner) since this is a secondary panel, not core profile data.
  Future<void> _loadMyGroups() async {
    try {
      final groups = await GroupApi.fetchMyGroups();
      if (mounted) setState(() => _myGroups = groups);
    } catch (e) {
      print('Error loading groups for profile details panel: $e');
    }
  }

  Future<void> _loadSavedPosts() async {
    setState(() {
      _isLoadingSavedPosts = true;
    });

    try {
      final posts = await ApiService.getSavedPosts();
      if (mounted) {
        setState(() {
          _savedPosts = posts;
          _isLoadingSavedPosts = false;
        });
      }
    } catch (e) {
      print('Error loading saved posts: $e');
      if (mounted) {
        setState(() {
          _isLoadingSavedPosts = false;
        });
      }
    }
  }

  /// Loads this user's own Moments: still-active statuses plus the private
  /// archive of expired ones, newest first — the archive endpoint only
  /// returns expired items, so the two lists never overlap.
  Future<void> _loadMoments() async {
    setState(() {
      _isLoadingMoments = true;
    });

    try {
      final results = await Future.wait([
        StatusApi.fetchFeed(),
        StatusApi.fetchArchive(),
      ]);
      final feed = results[0] as StatusFeed;
      final archive = results[1] as List<StatusItem>;
      final combined = <StatusItem>[...(feed.myStatus?.statuses ?? const []), ...archive];
      combined.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (mounted) {
        setState(() {
          _moments = combined;
          _isLoadingMoments = false;
        });
      }
    } catch (e) {
      print('Error loading moments: $e');
      if (mounted) {
        setState(() {
          _isLoadingMoments = false;
        });
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

  String? _resolveMediaUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    return url.startsWith('http') ? url : '${ApiConfig.serverUrl}/api/social$url';
  }

  Future<void> _editProfile() async {
    final result = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(
        builder: (context) => EditProfileScreen(
          currentFullName: _fullName,
          currentUsername: _username,
          currentBio: _bio,
          currentProfilePicUrl: _profilePicUrl,
        ),
      ),
    );

    // If profile was updated, reload from backend AND clear post cache to refresh author info
    if (result != null && mounted) {
      // Clear the post cache so posts reload with updated author info
      ref.read(postProvider.notifier).clearPosts();
      // Reload profile from backend
      await _loadProfile();
    }
  }

  Future<void> _shareProfile() async {
    if (_username.isEmpty) return;
    final link = '${ApiConfig.webDomain}/u/$_username';
    await Share.share('Check out my profile on SocialChat: $link', subject: '$_fullName on SocialChat');
  }

  Future<void> _changeCoverPhoto() async {
    final snack = ScaffoldMessenger.of(context);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 90,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/cover_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final tempFile = File(tempPath);
      await tempFile.writeAsBytes(bytes, flush: true);

      setState(() => _isUploadingCover = true);
      final url = await ApiService.uploadImage(tempFile.path);
      await ApiService.updateMyProfile(coverPhotoUrl: url);

      if (mounted) {
        setState(() {
          _coverPhotoUrl = url;
          _isUploadingCover = false;
        });
        snack.showSnackBar(const SnackBar(content: Text('Cover photo updated')));
      }
    } catch (e) {
      if (mounted) setState(() => _isUploadingCover = false);
      snack.showSnackBar(const SnackBar(content: Text('Failed to update cover photo')));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    // ✅ Listen for saved posts changes in build method (proper Riverpod usage)
    ref.listen(savedPostsNotifierProvider, (previous, next) {
      _loadSavedPosts();
    });

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadProfile();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: DesktopContentWrapper(
          // Wide enough for the 640ish post column + 320 details column
          // the design reference specifies for desktop, once both appear
          // side by side (see _buildTabsAndContent) — narrower widths
          // still get the single 700-wide reading column since the
          // details panel only shows at isDesktopClass (see below).
          maxWidth: context.isDesktopClass ? 1000 : 700,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Loading or Error State
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 120),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 120),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: AppColors.mutedSolid),
                        const SizedBox(height: 16),
                        Text(_errorMessage!, style: TextStyle(color: AppColors.mutedSolid)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadProfile,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Column(
                  children: [
                    _buildCoverAndAvatar(context, theme),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Share + Edit identity, mirroring the reference's
                          // top-right actions row just below the cover.
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              _roundActionButton(
                                theme: theme,
                                icon: Icons.ios_share_rounded,
                                onTap: _shareProfile,
                                tooltip: 'Share profile',
                              ),
                              const SizedBox(width: 10),
                              _pillActionButton(
                                theme: theme,
                                label: 'Edit identity',
                                onTap: _editProfile,
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  _fullName,
                                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text('@$_username', style: TextStyle(color: AppColors.mutedSolid, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 10),
                          Text(_bio.isEmpty ? 'No bio yet' : _bio, style: TextStyle(color: AppColors.mutedSolid, height: 1.4)),
                          const SizedBox(height: 18),

                          // Stats row
                          Row(
                            children: [
                              Expanded(child: _buildStatCard(theme, _postsCount.toString(), 'Posts', null)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildStatCard(theme, _followersCount.toString(), 'Followers', () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => FollowersListScreen(
                                        userId: _userId,
                                        title: 'Followers',
                                        isFollowing: true,
                                      ),
                                    ),
                                  );
                                  await _loadProfile();
                                }),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildStatCard(theme, _followingCount.toString(), 'Following', () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => FollowersListScreen(
                                        userId: _userId,
                                        title: 'Following',
                                        isFollowing: false,
                                      ),
                                    ),
                                  );
                                  await _loadProfile();
                                }),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                        ],
                      ),
                    ),

                    _buildTabsAndContent(context, theme, primary),
                  ],
                ),
            ],
          ),
          ),
        ),
      ),
    );
  }

  Widget _buildTab(ThemeData theme, Color primary, String label, int index) {
    final selected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedTab = index);
          if (index == 1 && _moments.isEmpty) _loadMoments();
          if (index == 2) _loadSavedPosts();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? primary : Colors.transparent,
            borderRadius: BorderRadius.circular(25),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? AppColors.onAccent : AppColors.mutedSolid,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  /// Tabs (Posts/Moments/Saved) + the grid for whichever tab is selected.
  /// At `isDesktopClass` (600px+) a details column (About + Groups) sits
  /// alongside it, matching the design reference's "640 post column and a
  /// 320 details column carrying about, groups and mutuals" — "mutuals"
  /// isn't included since there's no mutual-followers endpoint to back it
  /// with real data (not inventing a new backend call for a layout pass).
  Widget _buildTabsAndContent(BuildContext context, ThemeData theme, Color primary) {
    final tabsBar = Container(
      margin: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: AppColors.border!),
      ),
      child: Row(
        children: [
          _buildTab(theme, primary, 'Posts', 0),
          _buildTab(theme, primary, 'Moments', 1),
          _buildTab(theme, primary, 'Saved', 2),
        ],
      ),
    );
    final tabContent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18.0),
      child: _buildTabContent(),
    );

    if (!context.isDesktopClass) {
      return Column(children: [tabsBar, tabContent]);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Column(children: [tabsBar, tabContent])),
          SizedBox(
            width: 300,
            child: Padding(
              padding: const EdgeInsets.only(right: 18, left: 8, top: 4),
              child: _buildDetailsPanel(theme),
            ),
          ),
        ],
      ),
    );
  }

  /// Desktop details column: bio/location/link (already-loaded profile
  /// fields — this UI just didn't surface them before) + a real "GROUPS"
  /// list via [_myGroups].
  Widget _buildDetailsPanel(ThemeData theme) {
    Widget card({required String title, required Widget child}) => Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.cardColor,
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: AppColors.mutedSolid)),
              const SizedBox(height: 12),
              child,
            ],
          ),
        );

    final hasAbout = _bio.isNotEmpty || (_location?.isNotEmpty ?? false) || (_website?.isNotEmpty ?? false);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasAbout)
            card(
              title: 'ABOUT',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_bio.isNotEmpty) Text(_bio, style: TextStyle(color: AppColors.mutedSolid, height: 1.4)),
                  if (_location?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 10),
                    Row(children: [
                      Icon(Icons.location_on_outlined, size: 16, color: theme.iconTheme.color),
                      const SizedBox(width: 6),
                      Expanded(child: Text(_location!, style: const TextStyle(fontSize: 13))),
                    ]),
                  ],
                  if (_website?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      Icon(Icons.link, size: 16, color: theme.iconTheme.color),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(_website!,
                            style: TextStyle(fontSize: 13, color: theme.colorScheme.primary),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ]),
                  ],
                ],
              ),
            ),
          if (_myGroups.isNotEmpty)
            card(
              title: 'GROUPS',
              child: Column(
                children: _myGroups.take(5).map((g) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.accentSubtle100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Icon(Icons.groups_rounded, color: theme.colorScheme.primary, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(g.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                              Text('${g.memberCount} members',
                                  style: TextStyle(fontSize: 11.5, color: AppColors.mutedSolid)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  /// Cover banner + overlapping avatar + floating back/settings buttons,
  /// matching the reference design's profile header.
  Widget _buildCoverAndAvatar(BuildContext context, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final art = isDark ? AppColors.art : AppColorsLight.art;
    final art2 = isDark ? AppColors.art2 : AppColorsLight.art2;
    final gold = isDark ? AppColors.gold : AppColorsLight.gold;
    final accent = isDark ? AppColors.primary : AppColorsLight.primary;
    final resolvedCover = _resolveMediaUrl(_coverPhotoUrl);
    final hasCover = resolvedCover != null;

    return SizedBox(
      height: _coverHeight + _avatarSize / 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: _isUploadingCover ? null : _changeCoverPhoto,
            child: ClipRRect(
              child: Container(
                height: _coverHeight,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: hasCover
                      ? null
                      : RadialGradient(
                          center: const Alignment(-0.6, -1),
                          radius: 1.7,
                          colors: [art2, art],
                        ),
                  image: hasCover
                      ? DecorationImage(image: NetworkImage(resolvedCover), fit: BoxFit.cover)
                      : null,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (!hasCover) ...[
                      Positioned(bottom: -50, left: -30, child: _blob(160, gold.withValues(alpha: 0.35))),
                      Positioned(top: -60, right: -30, child: _blob(200, accent.withValues(alpha: 0.32))),
                    ] else
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.black.withValues(alpha: 0.0), Colors.black.withValues(alpha: 0.38)],
                          ),
                        ),
                      ),
                    if (_isUploadingCover)
                      Container(
                        color: Colors.black.withValues(alpha: 0.45),
                        child: const Center(child: CircularProgressIndicator(color: Colors.white)),
                      )
                    else
                      Positioned(
                        right: 14,
                        bottom: 14,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.4),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 18),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Floating back / settings controls over the cover.
          Positioned(
            top: 8,
            left: 8,
            child: SafeArea(
              bottom: false,
              child: _glassIconButton(
                icon: Icons.arrow_back,
                onTap: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  } else {
                    try {
                      GoRouter.of(context).go('/home');
                    } catch (_) {
                      Navigator.of(context).maybePop();
                    }
                  }
                },
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: SafeArea(
              bottom: false,
              child: _glassIconButton(
                icon: Icons.settings,
                onTap: () {
                  ref.read(appStateProvider.notifier).openModal(ModalScreen.settings);
                },
              ),
            ),
          ),

          // Avatar, overlapping the bottom edge of the cover.
          Positioned(
            left: 18,
            top: _coverHeight - _avatarSize / 2,
            child: GestureDetector(
              onTap: _editProfile,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: theme.scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: SquircleAvatar(
                      size: _avatarSize,
                      imageUrl: _resolveMediaUrl(_profilePicUrl),
                      initials: _getInitials(_fullName),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      decoration: BoxDecoration(color: theme.cardColor, shape: BoxShape.circle),
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: theme.colorScheme.primary,
                        child: const Icon(Icons.edit, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _blob(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    );
  }

  Widget _glassIconButton({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Colors.black.withValues(alpha: 0.35),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  Widget _roundActionButton({
    required ThemeData theme,
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    return Material(
      color: theme.cardColor,
      shape: CircleBorder(side: BorderSide(color: AppColors.border!)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip ?? '',
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, size: 18, color: theme.iconTheme.color),
          ),
        ),
      ),
    );
  }

  Widget _pillActionButton({
    required ThemeData theme,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.border!),
          ),
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
        ),
      ),
    );
  }

  Widget _buildStatCard(ThemeData theme, String value, String label, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border!),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value, style: const TextStyle(color: AppColors.primary, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: onTap != null ? AppColors.primary : AppColors.mutedSolid,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTab) {
      case 1:
        return _buildMomentsGrid();
      case 2:
        return _buildPostsGrid(_savedPosts, 'No saved posts', loading: _isLoadingSavedPosts);
      case 0:
      default:
        return _buildPostsGrid(_userPosts, 'No posts yet');
    }
  }

  Widget _buildPostsGrid(List<Post> posts, String emptyMessage, {bool loading = false}) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (posts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32.0),
        child: Center(
          child: Text(
            emptyMessage,
            style: TextStyle(color: AppColors.mutedSolid, fontSize: 16),
          ),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: posts.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) {
        return _buildPostTile(posts[index]);
      },
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

  Widget _buildMomentsGrid() {
    if (_isLoadingMoments) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_moments.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32.0),
        child: Center(
          child: Text('No moments yet', style: TextStyle(color: AppColors.mutedSolid, fontSize: 16)),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: _moments.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 0.68,
      ),
      itemBuilder: (context, index) {
        return _buildMomentTile(_moments[index]);
      },
    );
  }

  Color _momentBg(StatusItem s) {
    final hex = s.backgroundColor;
    if (hex != null && hex.startsWith('#') && hex.length == 7) {
      return Color(int.parse('FF${hex.substring(1)}', radix: 16));
    }
    return AppColors.art;
  }

  Widget _buildMomentTile(StatusItem s) {
    final mediaUrl = _resolveMediaUrl(s.mediaUrl);
    final isActive = s.expiresAt.isAfter(DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (s.isText || mediaUrl == null)
                  Container(
                    color: _momentBg(s),
                    padding: const EdgeInsets.all(8),
                    alignment: Alignment.center,
                    child: Text(
                      s.content ?? '',
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  )
                else
                  Image.network(
                    mediaUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: AppColors.border,
                      child: const Icon(Icons.broken_image, color: AppColors.mutedSolid),
                    ),
                  ),
                if (isActive)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text('Live',
                          style: TextStyle(color: AppColors.onAccent, fontSize: 9, fontWeight: FontWeight.w700)),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            Icon(Icons.visibility, size: 11, color: AppColors.mutedSolid),
            const SizedBox(width: 3),
            Text('${s.viewCount}', style: TextStyle(fontSize: 10, color: AppColors.mutedSolid)),
          ],
        ),
      ],
    );
  }
}
