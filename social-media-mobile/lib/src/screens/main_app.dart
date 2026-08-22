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
            body: Stack(
              children: [
                IndexedStack(
                  index: tabIndex,
                  children: screens,
                ),
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
