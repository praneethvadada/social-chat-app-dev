import 'package:flutter/material.dart';
import 'package:provider/provider.dart' as provider;
import '../../components/avatar_initial.dart';
import '../../services/api_service.dart';
import '../../state/chat_store.dart';
import '../../theme/colors.dart';
import '../search/hashtag_results_screen.dart';

/// Right-hand context panel shown next to the Pulse feed from 1024px up
/// (per the design reference: "the feed sits in a 620–700px reading column
/// with trending, suggestions and online contacts to its right"). Reuses
/// the exact same endpoints `search_screen.dart` already calls for its own
/// trending/suggested-people sections (`getTrendingHashtags`,
/// `getSuggestedUsers`) plus `ChatStore`'s existing presence map for
/// "online now" — no new backend calls invented for this panel.
class HomeContextPanel extends StatefulWidget {
  const HomeContextPanel({super.key});

  @override
  State<HomeContextPanel> createState() => _HomeContextPanelState();
}

class _HomeContextPanelState extends State<HomeContextPanel> {
  List<Map<String, dynamic>> _trending = [];
  List<Map<String, dynamic>> _people = [];
  List<Map<String, dynamic>> _following = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        ApiService.getTrendingHashtags(limit: 4).catchError((_) => <Map<String, dynamic>>[]),
        ApiService.getSuggestedUsers(size: 5).catchError((_) => <Map<String, dynamic>>[]),
        _loadFollowing(),
      ]);
      if (!mounted) return;
      setState(() {
        _trending = results[0];
        _people = results[1];
        _following = results[2];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _loadFollowing() async {
    try {
      final userId = await ApiService.getUserId();
      if (userId == null) return [];
      return await ApiService.getFollowing(userId);
    } catch (_) {
      return [];
    }
  }

  void _openHashtag(String tag) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => HashtagResultsScreen(tag: tag)));
  }

  Future<void> _follow(int userId, int index) async {
    setState(() => _people.removeAt(index));
    try {
      await ApiService.followUser(userId);
    } catch (_) {
      // Best-effort — the panel is a secondary surface; a failed follow
      // here isn't worth a blocking error, the user can retry from Discover.
    }
  }

  @override
  Widget build(BuildContext context) {
    final themed = ThemedColors.of(context);
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.only(top: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final onlineFollowing = provider.Consumer<ChatStore>(
      builder: (context, chatStore, _) {
        final online = _following.where((u) {
          final id = (u['userId'] as num?)?.toInt();
          return id != null && chatStore.isUserOnline(id);
        }).take(4).toList();
        if (online.isEmpty) return const SizedBox.shrink();
        return _Section(
          title: 'Online now',
          child: Column(
            children: online.map((u) => _PersonRow(user: u, trailing: _onlineDot(themed))).toList(),
          ),
        );
      },
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_trending.isNotEmpty)
            _Section(
              title: 'Trending near you',
              child: Column(
                children: [
                  for (final t in _trending)
                    _TrendRow(
                      tag: t['tag']?.toString() ?? '',
                      count: (t['postCount'] as num?)?.toInt() ?? 0,
                      onTap: () => _openHashtag(t['tag']?.toString() ?? ''),
                    ),
                ],
              ),
            ),
          if (_people.isNotEmpty) ...[
            const SizedBox(height: 24),
            _Section(
              title: 'People to know',
              child: Column(
                children: [
                  for (int i = 0; i < _people.length; i++)
                    _PersonRow(
                      user: _people[i],
                      trailing: _FollowButton(onTap: () {
                        final id = (_people[i]['userId'] as num?)?.toInt();
                        if (id != null) _follow(id, i);
                      }),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          onlineFollowing,
        ],
      ),
    );
  }

  Widget _onlineDot(ThemedColors themed) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: themed.success, shape: BoxShape.circle),
      );
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final themed = ThemedColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: themed.mutedSolid),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: themed.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: themed.border),
          ),
          child: child,
        ),
      ],
    );
  }
}

class _TrendRow extends StatelessWidget {
  final String tag;
  final int count;
  final VoidCallback onTap;
  const _TrendRow({required this.tag, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final themed = ThemedColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('#$tag', style: TextStyle(fontWeight: FontWeight.w700, color: themed.text, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text('$count posts today', style: TextStyle(fontSize: 12, color: themed.mutedSolid)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: themed.mutedSolid),
          ],
        ),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  final Map<String, dynamic> user;
  final Widget trailing;
  const _PersonRow({required this.user, required this.trailing});

  @override
  Widget build(BuildContext context) {
    final themed = ThemedColors.of(context);
    final name = (user['fullName']?.toString().isNotEmpty ?? false)
        ? user['fullName'].toString()
        : (user['username']?.toString() ?? 'User');
    final initials = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          AvatarInitial(initials: initials, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: themed.text)),
                if (user['username'] != null)
                  Text('@${user['username']}', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: themed.mutedSolid)),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

class _FollowButton extends StatelessWidget {
  final VoidCallback onTap;
  const _FollowButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Material(
      color: primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text('Follow', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: primary)),
        ),
      ),
    );
  }
}
