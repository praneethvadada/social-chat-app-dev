import 'package:flutter/material.dart';

import '../../models/status.dart';
import '../../services/status_api.dart';
import '../../utils/time_utils.dart';
import 'create_status_screen.dart';
import 'status_archive_screen.dart';
import 'status_viewer_screen.dart';
import 'package:social_chat_app/src/theme/colors.dart';

/// "Moments" strip — rounded gradient cards (Add moment + one per author),
/// matching the reference's Moments row exactly (not a circular story ring).
class StatusRingRow extends StatefulWidget {
  const StatusRingRow({super.key});

  @override
  State<StatusRingRow> createState() => StatusRingRowState();
}

class StatusRingRowState extends State<StatusRingRow> {
  StatusFeed? _feed;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  /// Public so the host screen can refresh on pull-to-refresh.
  Future<void> refresh() async {
    try {
      final feed = await StatusApi.fetchFeed();
      if (mounted) setState(() { _feed = feed; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openViewer(List<UserStatusGroup> groups, int index) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => StatusViewerScreen(groups: groups, initialGroupIndex: index),
    ));
    refresh(); // ring state changes once viewed
  }

  /// Long-press My Status: add another, or open the private archive (§R).
  Future<void> _myStatusMenu() async {
    await showModalBottomSheet(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Add status'),
              onTap: () {
                Navigator.pop(sheet);
                _addStatus();
              },
            ),
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('Status archive'),
              subtitle: const Text('Your expired statuses - only you can see these'),
              onTap: () {
                Navigator.pop(sheet);
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const StatusArchiveScreen()));
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addStatus() async {
    final posted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreateStatusScreen()),
    );
    if (posted == true) refresh();
  }

  /// Mirrors the reference's grad(i) helper — a fixed palette of 5 tonal
  /// gradients cycled by index, using accent + gold tokens.
  static List<Color> _gradient(BuildContext context, int i) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.primary : AppColorsLight.primary;
    final accentVariant = isDark ? AppColors.primaryVariant : AppColorsLight.primaryVariant;
    final gold = isDark ? AppColors.gold : AppColorsLight.gold;
    final goldLight = isDark ? AppColors.goldLight700 : AppColorsLight.gold700;
    final art = isDark ? AppColors.art : AppColorsLight.art;
    final palette = [
      [accent, accentVariant],
      [gold, goldLight],
      [accentVariant, gold],
      [goldLight, accent],
      [accentVariant, art],
    ];
    return palette[i % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = theme.colorScheme.primary;

    final mine = _feed?.myStatus;
    final others = _feed?.recent ?? const <UserStatusGroup>[];

    // Nothing to show and nothing loading: keep the strip (Add Status is the CTA).
    if (_loading && _feed == null) {
      return const SizedBox(height: 172);
    }

    return SizedBox(
      height: 172,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          if (mine == null)
            _AddMomentCard(onTap: _addStatus)
          else
            _MomentCard(
              gradient: _gradient(context, 0),
              initials: _initials('Me'),
              name: 'My Status',
              time: getTimeAgo(mine.latestAt ?? mine.statuses.last.createdAt),
              imageUrl: !mine.statuses.last.isText ? mine.statuses.last.mediaUrl : null,
              textContent: mine.statuses.last.isText ? mine.statuses.last.content : null,
              backgroundHex: mine.statuses.last.backgroundColor,
              ringColor: accent,
              onTap: () => _openViewer([mine], 0),
              onLongPress: _myStatusMenu,
            ),
          for (int i = 0; i < others.length; i++)
            _MomentCard(
              gradient: _gradient(context, i + 1),
              initials: _initials(others[i].displayName),
              name: others[i].displayName,
              time: getTimeAgo(others[i].latestAt ?? others[i].statuses.last.createdAt),
              imageUrl: others[i].profilePictureUrl ??
                  (!others[i].statuses.last.isText ? others[i].statuses.last.mediaUrl : null),
              textContent: others[i].statuses.last.isText ? others[i].statuses.last.content : null,
              backgroundHex: others[i].statuses.last.backgroundColor,
              ringColor: others[i].allSeen ? null : accent,
              onTap: () => _openViewer(others, i),
            ),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}

/// The reference's dashed "Add moment" card — same 120x172 footprint as the
/// real cards, not a small circular button.
class _AddMomentCard extends StatelessWidget {
  final VoidCallback onTap;
  const _AddMomentCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 120,
        height: 172,
        margin: const EdgeInsets.only(right: 13),
        child: CustomPaint(
          painter: _DashedRRectPainter(color: theme.dividerColor, radius: 22),
          child: Container(
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(22),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.add, color: theme.colorScheme.primary, size: 20),
                ),
                const SizedBox(height: 9),
                Text(
                  'Add moment',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: theme.textTheme.bodyMedium?.color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MomentCard extends StatelessWidget {
  final List<Color> gradient;
  final String initials;
  final String name;
  final String time;
  final String? imageUrl;
  final String? textContent;
  final String? backgroundHex;
  final Color? ringColor;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _MomentCard({
    required this.gradient,
    required this.initials,
    required this.name,
    required this.time,
    this.imageUrl,
    this.textContent,
    this.backgroundHex,
    this.ringColor,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    Color? bgColorOverride;
    if (backgroundHex != null && backgroundHex!.startsWith('#') && backgroundHex!.length == 7) {
      bgColorOverride = Color(int.parse('FF${backgroundHex!.substring(1)}', radix: 16));
    }

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: 120,
        height: 172,
        margin: const EdgeInsets.only(right: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: ringColor != null ? Border.all(color: ringColor!, width: 2.5) : null,
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 14, offset: const Offset(0, 6)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imageUrl != null && imageUrl!.isNotEmpty)
                Image.network(
                  imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _gradientBg(),
                )
              else if (bgColorOverride != null)
                Container(color: bgColorOverride)
              else
                _gradientBg(),
              if (textContent != null && textContent!.isNotEmpty && (imageUrl == null || imageUrl!.isEmpty))
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Center(
                    child: Text(
                      textContent!,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              // Initials badge, top-left.
              Positioned(
                top: 9,
                left: 9,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initials,
                    style: const TextStyle(color: Color(0xFF074E36), fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                ),
              ),
              // Name + time scrim, bottom.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(11, 26, 11, 11),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xB8140F08)],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        time,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gradientBg() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  _DashedRRectPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    const dashWidth = 6.0;
    const dashSpace = 5.0;
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
