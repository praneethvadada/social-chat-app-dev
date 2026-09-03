import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider;
import '../state/app_state_manager.dart';
import '../state/chat_store.dart';
import '../screens/home/home_screen.dart';
import '../screens/search/search_screen.dart';
import '../screens/chats/chats_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/welcome/welcome_screen.dart';
import '../navigation/emerald_dock.dart';
import '../responsive/app_nav_rail.dart';
import '../responsive/breakpoints.dart';

/// Main app with bottom tab navigation
/// Uses IndexedStack to maintain state on all tabs (WhatsApp-style)
/// Watches AppStateManager for tab changes
class MainApp extends ConsumerWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);
    final stateManager = ref.read(appStateProvider.notifier);

    // Use appState's current tab, not constructor parameter
    final currentTabFromState = appState.currentTab;
    final showWelcomeFromState = appState.showWelcome;

    print('[MainApp] 🏗️ BUILD CALLED - currentTab=$currentTabFromState (index=${currentTabFromState.index})');

    // Stack for welcome screen overlay. Order matches MainTab / the
    // reference dock: Pulse, Discover, Connect, Me.
    final screens = [
      const HomeScreen(),
      const SearchScreen(isTab: true),
      const ChatsScreen(),
      const ProfileScreen(),
    ];

    final tabIndex = currentTabFromState.index;

    print('[MainApp] 🏗️ Building IndexedStack with index=$tabIndex (showing ${['HomeScreen', 'SearchScreen', 'ChatsScreen', 'ProfileScreen'][tabIndex]})');

    return WillPopScope(
      onWillPop: () async {
        // If on home tab, allow system to close app
        if (currentTabFromState == MainTab.home) {
          return true; // Allow back button to close app
        }
        // Otherwise, go to home tab
        stateManager.goToHomeTab();
        return false; // Prevent default back behavior
      },
      child: Stack(
        children: [
          Scaffold(
            extendBody: true,
            // Below 600px: exactly today's mobile UI (IndexedStack + the
            // floating EmeraldDock overlaid at the bottom), untouched. At
            // 600px+: a persistent left AppNavRail replaces the dock —
            // icon-only under 1280px, labelled at 1280px+ — per the
            // responsive design reference's breakpoint table.
            body: LayoutBuilder(
              builder: (context, constraints) {
                final content = IndexedStack(index: tabIndex, children: screens);

                if (constraints.maxWidth >= BreakpointWidths.tablet) {
                  final shell = Row(
                    children: [
                      provider.Consumer<ChatStore>(
                        builder: (context, chatStore, _) {
                          final labelled = constraints.maxWidth >= BreakpointWidths.desktop;
                          final railWidth = !labelled
                              ? 88.0
                              : (constraints.maxWidth >= BreakpointWidths.largeDesktop ? 264.0 : 240.0);
                          return AppNavRail(
                            currentIndex: tabIndex,
                            connectBadgeCount: chatStore.totalUnreadCount,
                            labelled: labelled,
                            width: railWidth,
                          );
                        },
                      ),
                      Expanded(child: content),
                    ],
                  );
                  // "Shell caps at 1680 and centres; the sidebar stays
                  // pinned left of the cap" (design reference) — past that
                  // width the extra space becomes even gutters either side,
                  // not a wider rail/content.
                  if (constraints.maxWidth <= BreakpointWidths.maxShellWidth) return shell;
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: BreakpointWidths.maxShellWidth),
                      child: shell,
                    ),
                  );
                }

                return Stack(
                  children: [
                    content,
                    // Floating pill dock with a raised center create button —
                    // rebuilds on ChatStore changes so the Connect badge stays
                    // in sync as messages arrive or are read.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: provider.Consumer<ChatStore>(
                        builder: (context, chatStore, _) {
                          return EmeraldDock(
                            currentIndex: tabIndex,
                            connectBadgeCount: chatStore.totalUnreadCount,
                            onTap: (index) {
                              final tab = MainTab.values[index];
                              stateManager.switchTab(tab);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          // Welcome screen overlay (if first login)
          if (showWelcomeFromState)
            GestureDetector(
              onTap: () => stateManager.dismissWelcome(),
              child: Container(
                color: Colors.black87,
                child: Center(
                  child: GestureDetector(
                    onTap: () {}, // Prevent dismiss on content tap
                    child: const WelcomeScreen(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
