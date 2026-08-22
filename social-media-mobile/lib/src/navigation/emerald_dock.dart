import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../screens/status/create_status_screen.dart';
import '../screens/create_post/create_poll_screen.dart';
import '../screens/create_post/create_event_screen.dart';
import '../components/create_note_dialog.dart';
import '../state/app_state_manager.dart';
import '../theme/colors.dart';

/// Emerald Luxe floating dock — a pill-shaped floating bar (not a full-width
/// Material bottom bar) with two tabs on each side and a raised circular
/// create button breaking through the top edge, matching the reference's
/// "MOBILE FLOATING DOCK" exactly. Shared by every navigation shell in the
/// app so there is exactly one dock implementation.
class EmeraldDock extends ConsumerWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final int connectBadgeCount;

  const EmeraldDock({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.connectBadgeCount = 0,
  });

  // Matches the reference's dock exactly: [Pulse, Discover] | [Connect, Me],
  // split around the center FAB. Indices match MainTab's declared order.
  static const _left = <_DockItemData>[
    _DockItemData(icon: Icons.show_chart_rounded, label: 'Pulse', index: 0),
    _DockItemData(icon: Icons.explore_rounded, label: 'Discover', index: 1),
  ];
  static const _right = <_DockItemData>[
    _DockItemData(icon: Icons.chat_bubble_rounded, label: 'Connect', index: 2),
    _DockItemData(icon: Icons.person_rounded, label: 'Me', index: 3),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.background : AppColorsLight.background;
    final surface = isDark ? AppColors.surface : AppColorsLight.surface;
    final border = isDark ? AppColors.border : AppColorsLight.border;
    final accent = isDark ? AppColors.primary : AppColorsLight.primary;
    final accentTonal = isDark ? AppColors.accentSubtle100 : AppColorsLight.accentSubtle100;
    final accentFg = isDark ? AppColors.accentLight700 : AppColorsLight.accent700;
    final mutedFg = isDark ? AppColors.mutedSolid : AppColorsLight.muted;
    const onAccent = AppColors.onAccent;

    Widget dockButton(_DockItemData item) {
      final active = item.index == currentIndex;
      final badge = item.index == 2 && connectBadgeCount > 0;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(item.index),
        child: Container(
          width: 56,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? accentTonal : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(item.icon, size: 21, color: active ? accentFg : mutedFg),
                  if (badge)
                    Positioned(
                      top: -3,
                      right: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                        decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(999)),
                        child: Text(
                          connectBadgeCount > 99 ? '99+' : '$connectBadgeCount',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: onAccent, fontSize: 8, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                item.label,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: active ? accentFg : mutedFg,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 14 + MediaQuery.of(context).padding.bottom),
      child: Center(
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: surface.withValues(alpha: 0.96),
                border: Border.all(color: border),
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ..._left.map(dockButton),
                  const SizedBox(width: 64),
                  ..._right.map(dockButton),
                ],
              ),
            ),
            Positioned(
              top: -24,
              child: GestureDetector(
                onTap: () => _openCreateSheet(context, ref),
                child: Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: bg, width: 4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.add_rounded, color: onAccent, size: 27),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openCreateSheet(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Create something', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CreateOption(
                      icon: Icons.auto_awesome_rounded,
                      label: 'Moment',
                      onTap: () {
                        Navigator.of(ctx).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const CreateStatusScreen()),
                        );
                      },
                    ),
                    _CreateOption(
                      icon: Icons.bar_chart_rounded,
                      label: 'Poll',
                      onTap: () {
                        Navigator.of(ctx).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const CreatePollScreen()),
                        );
                      },
                    ),
                    _CreateOption(
                      icon: Icons.image_rounded,
                      label: 'Post',
                      onTap: () {
                        Navigator.of(ctx).pop();
                        ref.read(appStateProvider.notifier).openModal(ModalScreen.createPost);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CreateOption(
                      icon: Icons.event_rounded,
                      label: 'Event',
                      onTap: () {
                        Navigator.of(ctx).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const CreateEventScreen()),
                        );
                      },
                    ),
                    _CreateOption(
                      icon: Icons.chat_bubble_rounded,
                      label: 'Message',
                      onTap: () {
                        Navigator.of(ctx).pop();
                        onTap(2); // Connect tab
                      },
                    ),
                    _CreateOption(
                      icon: Icons.sticky_note_2_rounded,
                      label: 'Note',
                      onTap: () {
                        Navigator.of(ctx).pop();
                        showDialog(context: context, builder: (_) => const CreateNoteDialog());
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CreateOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _CreateOption({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              color: AppColors.accentSubtle100,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 26),
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Theme.of(context).textTheme.bodyMedium?.color)),
        ],
      ),
    );
  }
}

class _DockItemData {
  final IconData icon;
  final String label;
  final int index;
  const _DockItemData({required this.icon, required this.label, required this.index});
}
