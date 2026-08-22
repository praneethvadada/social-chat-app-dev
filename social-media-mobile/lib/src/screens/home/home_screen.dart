import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/post_card.dart';
import '../../models/post.dart';
import '../../services/post_service.dart';
import '../../services/api_service.dart';
import '../../components/unread_badge.dart';
import '../../services/badge_prefs.dart';
import '../../services/notification_service.dart';
import '../../state/app_state_manager.dart';
import '../status/status_ring_row.dart';
import '../../utils/friendly_error.dart';
import '../../theme/colors.dart';
import '../../theme/theme_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  // Lets pull-to-refresh also refresh the status ring strip.
  final GlobalKey<StatusRingRowState> _statusRingKey = GlobalKey<StatusRingRowState>();
    int _followerRequestCount = 0;

    @override
    void didChangeDependencies() {
      super.didChangeDependencies();
      _loadCounts();
    }

    Future<void> _loadCounts() async {
      try {
        // 🔴 FIX: Notifications now come from NotificationService singleton
        // No need to load from API - NotificationService handles real-time updates
        // Just load follower requests separately
        await _loadFollowerRequests();
      } catch (e) {
        print('[HomeScreen] Error loading counts: $e');
        if (mounted) {
          setState(() {
            _followerRequestCount = 0;
          });
        }
      }
    }
  bool _hasTriggeredLoad = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // 🔴 FIX: Listen to NotificationService singleton for real-time updates
    // When notifications arrive, also refresh follower request count
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final notificationService = NotificationService();
        notificationService.addListener(_onNotificationsChanged);
      } catch (e) {
        print('[HomeScreen] Error adding notification listener: $e');
      }
    });
  }

  /// Called when NotificationService changes (new notifications or follower requests)
  /// Called when NotificationService changes (new notifications arrive)
  void _onNotificationsChanged() {
    if (mounted) {
      // Reload follower requests to keep badge in sync when notifications arrive
      _loadFollowerRequests();
      
      // Force rebuild to show updated notification badge from singleton
      setState(() {
        // Trigger rebuild - notification count comes from NotificationService singleton
      });
    }
  }

  /// Load only follower request count (used as listener callback)
  Future<void> _loadFollowerRequests() async {
    try {
      final requests = await ApiService.getFollowRequests();
      final lastFollowReqVisit = await BadgePrefs.getLastFollowReqVisit();
      int followReqCount = 0;
      for (final r in requests) {
        final createdAt = r['createdAt'];
        if (createdAt != null) {
          final dt = DateTime.tryParse(createdAt);
          if (dt != null && (lastFollowReqVisit == null || dt.isAfter(lastFollowReqVisit))) {
            followReqCount++;
          }
        }
      }
      if (mounted) {
        setState(() {
          _followerRequestCount = followReqCount;
        });
      }
    } catch (e) {
      print('[HomeScreen] Error loading follower requests: $e');
      if (mounted) {
        setState(() {
          _followerRequestCount = 0;
        });
      }
    }
  }

  @override
  void dispose() {
    // 🔴 FIX: Remove notification listener when widget is disposed
    try {
      final notificationService = NotificationService();
      notificationService.removeListener(_onNotificationsChanged);
    } catch (e) {
      // Ignore errors during dispose
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 🔴 FIX: Disable automatic refresh on app lifecycle
    // Posts should only refresh on manual pull-to-refresh, not when:
    // - Opening settings/notifications (lifecycle pause)
    // - Toggling bluetooth/internet (lifecycle pause)
    // - Opening system dialogs (lifecycle pause)
    // Users can manually pull-to-refresh if they want new posts
    //
    // OLD BEHAVIOR: Auto-refresh after 3+ seconds in background
    // NEW BEHAVIOR: Never auto-refresh, only on manual pull-to-refresh
  }

  @override
  Widget build(BuildContext context) {
    final postsAsync = ref.watch(postProvider);
    final theme = Theme.of(context);

    // Auto-load posts ONCE if cache is empty AND not already loading
    if (!_hasTriggeredLoad && postsAsync is AsyncData<List<Post>> && postsAsync.value.isEmpty) {
      _hasTriggeredLoad = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            ref.read(postProvider.notifier).loadPosts();
          }
        });
      });
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(68),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Text(
                  'SocialChat',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                // Search icon
                IconButton(
                  icon: const Icon(Icons.search, size: 28),
                  tooltip: 'Search',
                  onPressed: () {
                    ref.read(appStateProvider.notifier).openModal(ModalScreen.search);
                  },
                ),
                const SizedBox(width: 8),
                // Notifications icon (bell) - gets unread count from NotificationService singleton
                Builder(
                  builder: (context) {
                    // Get current notification count from singleton
                    final notificationService = NotificationService();
                    final notifCount = notificationService.unreadCount;
                    
                    return Stack(
                      alignment: Alignment.topRight,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.notifications, size: 28),
                          tooltip: 'Notifications',
                          onPressed: () async {
                            if (mounted) {
                              await BadgePrefs.setLastNotifVisit(DateTime.now());
                              ref.read(appStateProvider.notifier).openModal(ModalScreen.notifications);
                              // 🔴 FIX: Mark notifications as read via NotificationService
                              notificationService.markAsRead();
                            }
                          },
                        ),
                        if (notifCount > 0)
                          Positioned(
                            right: 2,
                            top: 2,
                            child: UnreadBadge(count: notifCount),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(width: 8),
                // Theme toggle — mirrors the reference's mobile top bar
                // (logo mark + search + bell + light/dark switch). Follow
                // requests moved into the Notifications screen's app bar.
                IconButton(
                  icon: Icon(
                    ref.watch(themeModeProvider) == ThemeMode.dark
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                    size: 24,
                  ),
                  tooltip: 'Toggle theme',
                  onPressed: () => ref.read(themeModeProvider.notifier).toggleTheme(),
                ),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await ref.read(postProvider.notifier).loadPosts();
            await _statusRingKey.currentState?.refresh();
          },
          child: CustomScrollView(
            key: const PageStorageKey<String>('home_feed_scroll'),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _PulseHeader(
                  postCount: postsAsync is AsyncData<List<Post>> ? postsAsync.value.length : 0,
                  notificationCount: NotificationService().unreadCount,
                  requestCount: _followerRequestCount,
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Moments', style: theme.textTheme.headlineSmall),
                      Text('Last 24 hours',
                          style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(child: StatusRingRow(key: _statusRingKey)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
                  child: Text('In the flow', style: theme.textTheme.headlineSmall),
                ),
              ),
              postsAsync.when(
                loading: () => const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, stack) {
                  // Never show the raw exception - it means nothing to the
                  // user and leaks our host/port. The detail is logged.
                  final friendly = FriendlyError.from(error);
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(friendly.icon, size: 64, color: AppColors.mutedSolid),
                            const SizedBox(height: 16),
                            Text(
                              friendly.title,
                              style: TextStyle(
                                  fontSize: 18, color: AppColors.text),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              friendly.message,
                              style: TextStyle(
                                  fontSize: 13, color: AppColors.mutedSolid),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () =>
                                  ref.read(postProvider.notifier).loadPosts(),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
                data: (posts) {
                  if (posts.isEmpty) {
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.post_add, size: 64, color: AppColors.mutedSolid),
                            const SizedBox(height: 16),
                            Text(
                              'No posts available',
                              style: TextStyle(fontSize: 18, color: AppColors.mutedSolid),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
                    sliver: SliverList.builder(
                      itemCount: posts.length,
                      itemBuilder: (context, index) {
                        final post = posts[index];
                        return PostCard(post: post, index: index);
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Your Pulse" header: eyebrow date label + big display title + a real-data
/// stats summary card, mirroring the reference's Pulse header exactly.
class _PulseHeader extends StatelessWidget {
  final int postCount;
  final int notificationCount;
  final int requestCount;

  const _PulseHeader({
    required this.postCount,
    required this.notificationCount,
    required this.requestCount,
  });

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const _weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final now = DateTime.now();
    final todayLabel =
        '${_weekdays[now.weekday - 1]}, ${_months[now.month - 1]} ${now.day}'.toUpperCase();

    // The stats card is always the deep "art" tone — dark even on the light
    // theme — matching the reference's summaryBg (a radial gradient over
    // --art-2/--art) regardless of app appearance.
    final art = isDark ? AppColors.art : AppColorsLight.art;
    final art2 = isDark ? AppColors.art2 : AppColorsLight.art2;
    const artText = Color(0xFFF4F7F5);
    final artMuted = artText.withValues(alpha: 0.6);
    final accent = isDark ? AppColors.primary : AppColorsLight.primary;
    final gold = isDark ? AppColors.gold : AppColorsLight.gold;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            todayLabel,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text('Your Pulse', style: theme.textTheme.displaySmall),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: RadialGradient(
                center: const Alignment(-0.7, -1),
                radius: 1.6,
                colors: [art2, art],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Here's what's moving in your circle",
                  style: TextStyle(
                    color: artMuted,
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _stat(context, postCount.toString(), 'posts in feed', accent, artText, artMuted),
                    const SizedBox(width: 26),
                    _stat(context, notificationCount.toString(), 'new activity', gold, artText, artMuted),
                    const SizedBox(width: 26),
                    _stat(context, requestCount.toString(), 'requests', artText, artText, artMuted),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String value, String label, Color valueColor, Color artText, Color artMuted) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontFamily: Theme.of(context).textTheme.displaySmall?.fontFamily,
            fontSize: 26,
            color: valueColor,
            height: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 11.5, color: artMuted),
        ),
      ],
    );
  }
}
