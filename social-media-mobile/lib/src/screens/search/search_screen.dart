import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/post.dart';
import '../../models/user_search.dart';
import '../../components/search_row.dart';
import '../../services/api_service.dart';
import '../../state/app_state_manager.dart';
import '../../utils/search_utils.dart';
import '../../responsive/breakpoints.dart';
import '../../responsive/desktop_content_wrapper.dart';

import '../user_profile_screen.dart';
import 'hashtag_results_screen.dart';
import 'package:social_chat_app/src/theme/colors.dart';

class SearchScreen extends ConsumerStatefulWidget {
  /// True when hosted as the persistent Discover tab (no back button, no
  /// PopScope interception — the dock's global back handling applies
  /// instead). False when pushed as a standalone modal.
  final bool isTab;

  const SearchScreen({super.key, this.isTab = false});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _controller = TextEditingController();
  List<UserSearch> _searchResults = [];
  List<String> _recentSearches = [];
  bool _isLoading = false;
  Timer? _debounce;
  String _lastQuery = '';

  // Discover content — real data, fetched once and pull-to-refreshable.
  List<Map<String, dynamic>> _trending = [];
  List<Map<String, dynamic>> _suggested = [];
  List<Post> _explorePosts = [];
  bool _discoverLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecent();
    _controller.addListener(_onChange);
    _loadDiscoverContent();
  }

  Future<void> _loadRecent() async {
    final recent = await SearchUtils.loadRecentSearches();
    setState(() => _recentSearches = recent);
  }

  Future<void> _loadDiscoverContent() async {
    setState(() => _discoverLoading = true);
    final results = await Future.wait([
      ApiService.getTrendingHashtags(limit: 8).catchError((_) => <Map<String, dynamic>>[]),
      ApiService.getSuggestedUsers(size: 10).catchError((_) => <Map<String, dynamic>>[]),
      ApiService.getExplorePosts().catchError((_) => <Post>[]),
    ]);
    if (!mounted) return;
    setState(() {
      _trending = results[0] as List<Map<String, dynamic>>;
      _suggested = results[1] as List<Map<String, dynamic>>;
      _explorePosts = (results[2] as List<Post>).where((p) => p.imageUrls.isNotEmpty).toList();
      _discoverLoading = false;
    });
  }

  void _onChange() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final q = _controller.text.trim();
      if (q.isEmpty) {
        setState(() => _searchResults = []);
        return;
      }
      _performSearch(q);
    });
  }

  Future<void> _performSearch(String query) async {
    if (query == _lastQuery) return;
    setState(() {
      _isLoading = true;
      _lastQuery = query;
    });
    try {
      final results = await ApiService.searchUsers(query);
      setState(() {
        _searchResults = results
            .map((u) => UserSearch(
                  userId: u['userId'] ?? 0,
                  username: u['username'] ?? '',
                  fullName: u['fullName'] ?? '',
                ))
            .toList();
      });
    } catch (e) {
      setState(() => _searchResults = []);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Search failed: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onChange);
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _onSearchSubmit(String query) async {
    if (query.trim().isEmpty) return;
    await SearchUtils.addRecentSearch(query.trim());
    await _loadRecent();
    _performSearch(query.trim());
  }

  Future<void> _clearRecentSearches() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Recent Searches'),
        content:
            const Text('Are you sure you want to clear your search history?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirmed == true) {
      await SearchUtils.clearRecentSearches();
      await _loadRecent();
    }
  }

  void _openHashtag(String tag) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => HashtagResultsScreen(tag: tag)),
    );
  }

  void _openProfile(int userId, {String? username}) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => UserProfileScreen(userId: userId, userName: username)),
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final showResults = _controller.text.trim().isNotEmpty;

    void handleBack() {
      ref.read(appStateProvider.notifier).closeModal();
    }

    final scaffold = Scaffold(
        body: SafeArea(
          child: DesktopContentWrapper(
            // Discover is a dashboard, not a reading column — the design
            // reference caps it at 1120, wider than the 640/700 feed cap
            // every other screen uses.
            maxWidth: 1120,
            child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    if (!widget.isTab) ...[
                      GestureDetector(
                        onTap: handleBack,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: theme.dividerColor),
                            color: theme.cardColor,
                          ),
                          child: Icon(Icons.arrow_back, size: 20, color: theme.iconTheme.color),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Text('Discover', style: theme.textTheme.headlineMedium),
                    ),
                    if (_recentSearches.isNotEmpty && !showResults)
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: AppColors.danger),
                        tooltip: 'Clear recent searches',
                        onPressed: _clearRecentSearches,
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                child: Container(
                  height: 54,
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'Search people, topics, places…',
                      prefixIcon: Icon(Icons.search,
                          color: theme.iconTheme.color?.withValues(alpha: 0.8)),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    style: TextStyle(
                        color: theme.textTheme.bodyMedium?.color),
                    textInputAction: TextInputAction.search,
                    onSubmitted: _onSearchSubmit,
                  ),
                ),
              ),
              if (!showResults) ...[
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadDiscoverContent,
                    child: _discoverLoading
                        ? const Center(child: CircularProgressIndicator())
                        : ListView(
                            padding: const EdgeInsets.only(bottom: 110, top: 4),
                            children: [
                              if (_recentSearches.isNotEmpty) ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                                  child: Text('Recent',
                                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                                ),
                                SizedBox(
                                  height: 38,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    itemCount: _recentSearches.length,
                                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                                    itemBuilder: (c, i) {
                                      final q = _recentSearches[i];
                                      return GestureDetector(
                                        onTap: () {
                                          _controller.text = q;
                                          _onSearchSubmit(q);
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 14),
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: theme.cardColor,
                                            border: Border.all(color: theme.dividerColor),
                                            borderRadius: BorderRadius.circular(999),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.history, size: 14, color: theme.iconTheme.color),
                                              const SizedBox(width: 6),
                                              Text(q, style: const TextStyle(fontSize: 13)),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],

                              // Trending hero — the top hashtag by post count.
                              // At tablet+ this sits beside the rest of the
                              // trending list (2/3 + 1/3) instead of a
                              // stacked hero-then-pills column, matching the
                              // design reference's "trending hero 2/3, topic
                              // list 1/3" dashboard treatment.
                              if (_trending.isNotEmpty) ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 13),
                                  child: Text('Trending near you', style: theme.textTheme.headlineSmall),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  child: context.isDesktopClass && _trending.length > 1
                                      ? Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              flex: 2,
                                              child: _TrendingHero(
                                                tag: _trending.first['tag']?.toString() ?? '',
                                                count: (_trending.first['postCount'] as num?)?.toInt() ?? 0,
                                                onTap: () => _openHashtag(_trending.first['tag']?.toString() ?? ''),
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              flex: 1,
                                              child: _TopicsList(
                                                tags: _trending.skip(1).toList(),
                                                onTap: _openHashtag,
                                              ),
                                            ),
                                          ],
                                        )
                                      : _TrendingHero(
                                          tag: _trending.first['tag']?.toString() ?? '',
                                          count: (_trending.first['postCount'] as num?)?.toInt() ?? 0,
                                          onTap: () => _openHashtag(_trending.first['tag']?.toString() ?? ''),
                                        ),
                                ),
                                const SizedBox(height: 28),
                              ],

                              // Topic pills — remaining trending hashtags.
                              // Mobile/tablet only; desktop shows the same
                              // hashtags in the TOPICS RISING list above.
                              if (_trending.length > 1 && !context.isDesktopClass) ...[
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  child: Wrap(
                                    spacing: 9,
                                    runSpacing: 9,
                                    children: _trending.skip(1).map((t) {
                                      final tag = t['tag']?.toString() ?? '';
                                      return GestureDetector(
                                        onTap: () => _openHashtag(tag),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: theme.cardColor,
                                            border: Border.all(color: theme.dividerColor),
                                            borderRadius: BorderRadius.circular(999),
                                          ),
                                          child: Text('#$tag',
                                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                                const SizedBox(height: 28),
                              ],

                              // People to know — real follow suggestions.
                              // Horizontal scroll row on mobile (unchanged);
                              // a proper grid (2-up tablet, 4-up desktop)
                              // once there's room, per the design reference.
                              if (_suggested.isNotEmpty) ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 13),
                                  child: Text('People to know', style: theme.textTheme.headlineSmall),
                                ),
                                if (context.isDesktopClass)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    child: GridView.builder(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: context.hasContextPanel ? 4 : 2,
                                        mainAxisSpacing: 14,
                                        crossAxisSpacing: 14,
                                        childAspectRatio: 0.92,
                                      ),
                                      itemCount: _suggested.length,
                                      itemBuilder: (c, i) => _PersonCard(
                                        user: _suggested[i],
                                        onOpenProfile: _openProfile,
                                        expand: true,
                                      ),
                                    ),
                                  )
                                else
                                  SizedBox(
                                    height: 224,
                                    child: ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      itemCount: _suggested.length,
                                      separatorBuilder: (_, __) => const SizedBox(width: 14),
                                      itemBuilder: (c, i) => _PersonCard(
                                        user: _suggested[i],
                                        onOpenProfile: _openProfile,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 28),
                              ],

                              // Fresh from creators — real explore posts with media.
                              if (_explorePosts.isNotEmpty) ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 13),
                                  child: Text('Fresh from creators', style: theme.textTheme.headlineSmall),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  child: GridView.builder(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    // 2-up on mobile/tablet, 4-up once the
                                    // panel itself is wide enough to hold
                                    // four tiles at a readable size — matches
                                    // the design reference's discovery grid.
                                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: context.hasContextPanel ? 4 : 2,
                                      mainAxisSpacing: 14,
                                      crossAxisSpacing: 14,
                                      childAspectRatio: 0.78,
                                    ),
                                    itemCount: _explorePosts.length,
                                    itemBuilder: (c, i) => _CreatorTile(post: _explorePosts[i]),
                                  ),
                                ),
                              ],

                              if (_trending.isEmpty && _suggested.isEmpty && _explorePosts.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(32),
                                  child: Center(
                                    child: Text('Nothing to discover yet — check back soon',
                                        style: theme.textTheme.bodyMedium),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
              ] else ...[
                if (_isLoading) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: _searchResults.isEmpty
                      ? Center(
                          child: Text('No users found',
                              style: theme.textTheme.bodyMedium))
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 80, top: 4),
                          itemBuilder: (c, i) {
                            final u = _searchResults[i];
                            return _AnimatedListItem(
                              delay: Duration(milliseconds: 50 * i),
                              child: SearchRow(
                                user: u,
                                onTap: () async {
                                  try {
                                    final router = Navigator.of(context);
                                    await router.push(
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            UserProfileScreen(userId: u.userId),
                                      ),
                                    );
                                  } catch (_) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content:
                                              Text('Failed to open profile')),
                                    );
                                  }
                                },
                              ),
                            );
                          },
                          separatorBuilder: (c, i) => const Divider(height: 1),
                          itemCount: _searchResults.length,
                        ),
                ),
              ],
            ],
            ),
          ),
        ),
    );

    if (widget.isTab) return scaffold;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          handleBack();
        }
      },
      child: scaffold,
    );
  }
}

/// Big gradient hero card for the #1 trending hashtag — mirrors the
/// reference's "Trending near you" hero exactly, with real post counts.
class _TrendingHero extends StatelessWidget {
  final String tag;
  final int count;
  final VoidCallback onTap;
  const _TrendingHero({required this.tag, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark ? AppColors.primary : AppColorsLight.primary;
    final accentVariant = isDark ? AppColors.primaryVariant : AppColorsLight.primaryVariant;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 190,
        width: double.infinity,
        padding: const EdgeInsets.all(26),
        alignment: Alignment.bottomLeft,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [accent, accentVariant],
          ),
          boxShadow: [
            BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.local_fire_department, size: 14, color: Color(0xFF074E36)),
                  SizedBox(width: 5),
                  Text('Trending', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF074E36))),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text('#$tag',
                style: GoogleFonts.getFont('Caprasimo',
                    fontSize: 28, color: Colors.white, height: 1.1)),
            const SizedBox(height: 8),
            Text('$count ${count == 1 ? 'post' : 'posts'} talking about this',
                style: TextStyle(fontSize: 13.5, color: Colors.white.withValues(alpha: 0.85))),
          ],
        ),
      ),
    );
  }
}

/// Desktop-only companion to [_TrendingHero] — the remaining trending
/// hashtags as a compact vertical list ("TOPICS RISING" in the design
/// reference) instead of the mobile/tablet Wrap of pills, since a Wrap
/// doesn't read well squeezed into a narrow 1/3-width column.
class _TopicsList extends StatelessWidget {
  final List<Map<String, dynamic>> tags;
  final void Function(String tag) onTap;
  const _TopicsList({required this.tags, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < tags.length; i++) ...[
            if (i > 0) Divider(height: 1, color: theme.dividerColor),
            InkWell(
              onTap: () => onTap(tags[i]['tag']?.toString() ?? ''),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('#${tags[i]['tag']?.toString() ?? ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                          const SizedBox(height: 2),
                          Text('${(tags[i]['postCount'] as num?)?.toInt() ?? 0} posts today',
                              style: TextStyle(fontSize: 11.5, color: AppColors.mutedSolid)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 18, color: theme.iconTheme.color),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "People to know" card — squircle avatar, name, meta, Follow button with
/// optimistic state, matching the reference's discover person card.
class _PersonCard extends StatefulWidget {
  final Map<String, dynamic> user;
  final void Function(int userId, {String? username}) onOpenProfile;
  /// True when placed as a grid cell (tablet/desktop "People to know" grid)
  /// instead of the mobile horizontal-scroll row — fills the cell's width
  /// instead of the fixed 172px card width the scroll row needs.
  final bool expand;
  const _PersonCard({required this.user, required this.onOpenProfile, this.expand = false});

  @override
  State<_PersonCard> createState() => _PersonCardState();
}

class _PersonCardState extends State<_PersonCard> {
  bool _following = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _following = widget.user['isFollowing'] == true;
  }

  Future<void> _toggleFollow() async {
    final id = widget.user['userId'];
    final userId = id is int ? id : int.tryParse(id?.toString() ?? '');
    if (userId == null || _busy) return;
    setState(() => _busy = true);
    final wasFollowing = _following;
    setState(() => _following = !wasFollowing);
    try {
      if (wasFollowing) {
        await ApiService.unfollowUser(userId);
      } else {
        await ApiService.followUser(userId);
      }
    } catch (_) {
      if (mounted) setState(() => _following = wasFollowing);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = (widget.user['fullName']?.toString().isNotEmpty ?? false)
        ? widget.user['fullName'].toString()
        : (widget.user['username']?.toString() ?? 'User');
    final username = widget.user['username']?.toString() ?? '';
    final initials = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    final idRaw = widget.user['userId'];
    final userId = idRaw is int ? idRaw : int.tryParse(idRaw?.toString() ?? '') ?? 0;

    return GestureDetector(
      onTap: () => widget.onOpenProfile(userId, username: username),
      child: Container(
        width: widget.expand ? double.infinity : 172,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        decoration: BoxDecoration(
          color: theme.cardColor,
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.accentSubtle100,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                  bottomLeft: Radius.circular(8),
                ),
              ),
              alignment: Alignment.center,
              child: Text(initials,
                  style: TextStyle(
                      color: theme.colorScheme.primary, fontWeight: FontWeight.w800, fontSize: 20)),
            ),
            const SizedBox(height: 12),
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 2),
            Text('@$username',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: AppColors.mutedSolid)),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: _toggleFollow,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 9),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _following ? Colors.transparent : theme.colorScheme.primary,
                  border: Border.all(color: _following ? theme.dividerColor : theme.colorScheme.primary),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _following ? 'Following' : 'Follow',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: _following ? theme.textTheme.bodyMedium?.color : AppColors.onAccent,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Fresh from creators" grid tile — a real post's media thumbnail, author
/// chip, and a play badge for videos.
class _CreatorTile extends StatelessWidget {
  final Post post;
  const _CreatorTile({required this.post});

  bool get _isVideo {
    final url = post.imageUrls.first.toLowerCase();
    return url.endsWith('.mp4') || url.endsWith('.webm') || url.endsWith('.mov');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(22),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _isVideo
                    ? Container(color: AppColors.accentSubtle200)
                    : Image.network(
                        post.imageUrls.first,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(color: AppColors.accentSubtle200),
                      ),
                if (_isVideo)
                  const Center(
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.white70,
                      child: Icon(Icons.play_arrow, color: Color(0xFF074E36)),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  post.content.isNotEmpty ? post.content : post.authorName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: AppColors.accentSubtle100,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      alignment: Alignment.center,
                      child: Text(post.initials,
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: theme.colorScheme.primary)),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('@${post.authorName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: AppColors.mutedSolid)),
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

class _AnimatedListItem extends StatefulWidget {
  final Widget child;
  final Duration delay;

  const _AnimatedListItem({required this.child, this.delay = Duration.zero});

  @override
  State<_AnimatedListItem> createState() => _AnimatedListItemState();
}

class _AnimatedListItemState extends State<_AnimatedListItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 300));
  late final Animation<Offset> _offset =
      Tween(begin: const Offset(0, 0.04), end: Offset.zero)
          .animate(CurvedAnimation(parent: _ctl, curve: Curves.easeOut));
  late final Animation<double> _opacity =
      CurvedAnimation(parent: _ctl, curve: Curves.easeOut);

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _ctl.forward();
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}
