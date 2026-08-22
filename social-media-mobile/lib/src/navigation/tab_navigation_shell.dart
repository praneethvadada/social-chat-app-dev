import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../screens/home/home_screen.dart';
import '../screens/chats/chats_screen.dart';
import '../screens/calls/calls_screen.dart';
import '../screens/profile/profile_screen.dart';
import 'emerald_dock.dart';

/// Custom shell that keeps all tab screens in memory using IndexedStack
/// This preserves scroll position, form state, and WebSocket listeners
/// 
/// Back button behavior (WhatsApp-like):
/// - On home tab (index 0): Double-tap to exit
/// - On other tabs: Single tap to return to home
class TabNavigationShell extends StatefulWidget {
  final StatefulNavigationShell navigationShell;

  const TabNavigationShell({
    super.key,
    required this.navigationShell,
  });

  @override
  State<TabNavigationShell> createState() => _TabNavigationShellState();
}

class _TabNavigationShellState extends State<TabNavigationShell> {
  DateTime? _lastBackPressed;

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        print('[TabNav] Back gesture/button detected');
        _handleTabBackPress();
        return false; // We handle the back press, prevent default behavior
      },
      child: Scaffold(
        extendBody: true,
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              IndexedStack(
                index: widget.navigationShell.currentIndex,
                children: [
                  // Tab 0: Home
                  _buildTabContent(
                    child: const HomeScreen(),
                    onNavigate: () => widget.navigationShell.goBranch(0),
                  ),
                  // Tab 1: Chats
                  _buildTabContent(
                    child: const ChatsScreen(),
                    onNavigate: () => widget.navigationShell.goBranch(1),
                  ),
                  // Tab 2: Calls
                  _buildTabContent(
                    child: const CallsScreen(),
                    onNavigate: () => widget.navigationShell.goBranch(2),
                  ),
                  // Tab 3: Profile
                  _buildTabContent(
                    child: const ProfileScreen(),
                    onNavigate: () => widget.navigationShell.goBranch(3),
                  ),
                ],
              ),
              // Floating pill dock with a raised center create button —
              // sits over the content (like the reference's position:fixed
              // dock), not docked as a full-width Material bottom bar.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: EmeraldDock(
                  currentIndex: widget.navigationShell.currentIndex,
                  onTap: (int index) {
                    widget.navigationShell.goBranch(
                      index,
                      // Preserve existing routes when switching tabs
                      initialLocation: index == widget.navigationShell.currentIndex,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Handle back press when we're at the root of current tab
  void _handleTabBackPress() {
    final currentIndex = widget.navigationShell.currentIndex;
    print('[TabNav] Back pressed at root of tab $currentIndex');

    if (currentIndex == 0) {
      // Home tab: require double-tap to exit
      final now = DateTime.now();
      if (_lastBackPressed == null || now.difference(_lastBackPressed!) > const Duration(seconds: 2)) {
        _lastBackPressed = now;
        print('[TabNav] First back press - showing exit prompt');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Press back again to exit'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        // Double-tap confirmed
        print('[TabNav] Double back press - exiting app');
        if (mounted) {
          SystemNavigator.pop();
        }
      }
    } else {
      // On other tabs: navigate to home
      print('[TabNav] Not on home tab, going to home');
      widget.navigationShell.goBranch(0);
    }
  }

  /// Handle back button press - works on any tab
  void _handleBackPress() {
    final currentIndex = widget.navigationShell.currentIndex;
    print('[TabNav] Back pressed on tab $currentIndex');

    if (currentIndex == 0) {
      // Home tab: require double-tap to exit
      final now = DateTime.now();
      if (_lastBackPressed == null || now.difference(_lastBackPressed!) > const Duration(seconds: 2)) {
        _lastBackPressed = now;
        print('[TabNav] First back press - showing exit prompt');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Press back again to exit'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        // Double-tap confirmed, exit
        if (mounted) {
          SystemNavigator.pop();
        }
      }
    } else {
      // On other tabs: navigate to home
      print('[TabNav] Not on home tab, going to home');
      widget.navigationShell.goBranch(0);
    }
  }

  /// [UNUSED] - Kept for reference - we now always intercept back button
  bool _canPop() {
    final currentIndex = widget.navigationShell.currentIndex;
    return currentIndex == 0;
  }

  /// Wraps tab content to keep it alive
  Widget _buildTabContent({
    required Widget child,
    required VoidCallback onNavigate,
  }) {
    return _KeepAliveWidget(child: child);
  }
}

/// Keeps a widget's state alive across navigation
class _KeepAliveWidget extends StatefulWidget {
  final Widget child;

  const _KeepAliveWidget({required this.child});

  @override
  State<_KeepAliveWidget> createState() => _KeepAliveWidgetState();
}

class _KeepAliveWidgetState extends State<_KeepAliveWidget>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
