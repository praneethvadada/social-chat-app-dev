import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../components/app_logo.dart';
import '../components/avatar_initial.dart';
import '../navigation/emerald_dock.dart';
import '../navigation/nav_items.dart';
import '../services/api_service.dart';
import '../state/app_state_manager.dart';
import '../theme/colors.dart';

/// Desktop/tablet replacement for the mobile bottom `EmeraldDock`: an
/// icon-only rail from 600–1279px, a labelled sidebar with counts from
/// 1280px up (per the design reference's breakpoint table). Drives the
/// exact same navigation primitives the mobile dock and `HomeScreen`'s app
/// bar already use (`AppStateManager.switchTab` / `.openModal`) — this is a
/// second presentation of existing navigation, not a new mechanism.
class AppNavRail extends ConsumerWidget {
  final int currentIndex;
  final int connectBadgeCount;
  final bool labelled;

  /// 88 (icon-only), 240 (desktop tier, 1280–1679) or 264 (largeDesktop,
  /// ≥1680) per the breakpoint table — the caller (`MainApp`) already knows
  /// which tier it's in, so it passes the exact width rather than this
  /// widget re-deriving it.
  final double width;

  const AppNavRail({
    super.key,
    required this.currentIndex,
    required this.labelled,
    this.connectBadgeCount = 0,
    this.width = 88,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surface : AppColorsLight.surface;
    final border = isDark ? AppColors.border : AppColorsLight.border;
    final accent = isDark ? AppColors.primary : AppColorsLight.primary;
    final accentTonal = isDark ? AppColors.accentSubtle100 : AppColorsLight.accentSubtle100;
    final accentFg = isDark ? AppColors.accentLight700 : AppColorsLight.accent700;
    final mutedFg = isDark ? AppColors.mutedSolid : AppColorsLight.muted;
    const onAccent = AppColors.onAccent;
    final stateManager = ref.read(appStateProvider.notifier);

    Widget item({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      bool active = false,
      int badgeCount = 0,
    }) {
      final content = Row(
        mainAxisSize: labelled ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon, size: 22, color: active ? accentFg : mutedFg),
              if (badgeCount > 0)
                Positioned(
                  top: -4,
                  right: -8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
                    decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(999)),
                    child: Text(
                      badgeCount > 99 ? '99+' : '$badgeCount',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: onAccent, fontSize: 9, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
            ],
          ),
          if (labelled) ...[
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                color: active ? accentFg : mutedFg,
              ),
            ),
          ],
        ],
      );

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: labelled ? 14 : 0, vertical: 11),
              alignment: labelled ? Alignment.centerLeft : Alignment.center,
              decoration: BoxDecoration(
                color: active ? accentTonal : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: content,
            ),
          ),
        ),
      );
    }

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: surface,
        border: Border(right: BorderSide(color: border)),
      ),
      child: SafeArea(
        right: false,
        bottom: false,
        child: Column(
          crossAxisAlignment: labelled ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(labelled ? 22 : 0, 22, labelled ? 22 : 0, 18),
              child: labelled
                  ? const Row(children: [AppLogo(size: 28), SizedBox(width: 10), _Wordmark()])
                  : const AppLogo(size: 28),
            ),
            for (final navItem in primaryNavItems)
              item(
                icon: navItem.icon,
                label: navItem.label,
                active: navItem.index == currentIndex,
                badgeCount: navItem.index == 2 ? connectBadgeCount : 0,
                onTap: () => stateManager.switchTab(MainTab.values[navItem.index]),
              ),
            item(
              icon: Icons.notifications_rounded,
              label: 'Notifications',
              onTap: () => stateManager.openModal(ModalScreen.notifications),
            ),
            item(
              icon: Icons.bookmark_rounded,
              label: 'Saved',
              // No standalone Saved screen yet — the Saved tab lives inside
              // Me/Profile (see profile_screen.dart's tab bar), so this
              // takes you there rather than inventing a new destination.
              onTap: () => stateManager.switchTab(MainTab.profile),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: labelled ? 12 : 0),
              child: _CreateButton(
                labelled: labelled,
                accent: accent,
                onAccent: onAccent,
                onTap: () => EmeraldDock.showCreateSheet(
                  context,
                  ref,
                  onNavigateToConnect: () => stateManager.switchTab(MainTab.chats),
                ),
              ),
            ),
            const Spacer(),
            _UserRow(labelled: labelled, onTapSettings: () => stateManager.openModal(ModalScreen.settings)),
          ],
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();
  @override
  Widget build(BuildContext context) {
    return Text(
      'RChat',
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

class _CreateButton extends StatelessWidget {
  final bool labelled;
  final Color accent;
  final Color onAccent;
  final VoidCallback onTap;
  const _CreateButton({required this.labelled, required this.accent, required this.onAccent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (!labelled) {
      return Material(
        color: accent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Icon(Icons.add_rounded, color: onAccent, size: 22),
          ),
        ),
      );
    }
    return Material(
      color: accent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_rounded, color: onAccent, size: 20),
              const SizedBox(width: 8),
              Text('Create', style: TextStyle(color: onAccent, fontWeight: FontWeight.w700, fontSize: 14.5)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom "you" chip — new UI, the mobile dock has no equivalent. Icon-only
/// mode just shows the avatar (tap → Me tab, matching the Me nav item
/// above it); labelled mode adds the username + a settings gear, matching
/// the design's "YO  You  @yourhandle  [settings]" sidebar footer.
class _UserRow extends ConsumerWidget {
  final bool labelled;
  final VoidCallback onTapSettings;
  const _UserRow({required this.labelled, required this.onTapSettings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themed = ThemedColors.of(context);
    return FutureBuilder<String?>(
      future: ApiService.getUsername(),
      builder: (context, snapshot) {
        final username = snapshot.data;
        final initials = (username != null && username.isNotEmpty)
            ? username.substring(0, username.length >= 2 ? 2 : 1).toUpperCase()
            : '..';

        if (!labelled) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: GestureDetector(
              onTap: () => ref.read(appStateProvider.notifier).switchTab(MainTab.profile),
              child: AvatarInitial(initials: initials, size: 34),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => ref.read(appStateProvider.notifier).switchTab(MainTab.profile),
                child: AvatarInitial(initials: initials, size: 34),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      username ?? '',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: themed.text),
                    ),
                    Text(
                      username != null ? '@$username' : '',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: themed.mutedSolid),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.settings_outlined, size: 20, color: themed.mutedSolid),
                tooltip: 'Settings',
                onPressed: onTapSettings,
              ),
            ],
          ),
        );
      },
    );
  }
}
