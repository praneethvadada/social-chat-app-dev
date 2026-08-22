import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/navigation_state.dart';
import '../state/missed_calls_store.dart';
import '../screens/splash/splash_screen.dart';
import '../screens/login/login_screen.dart';
import '../screens/signup/signup_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/chats/chats_screen.dart';
import '../screens/calls/calls_screen.dart';
import '../screens/profile/profile_screen.dart';

/// Custom app shell - NO GoRouter, NO Navigator pushing
/// Pure state-based navigation like WhatsApp
/// 
/// Navigation flow:
/// Splash → (Check auth) → Login ↔ Signup
/// ↓
/// Main App (4 tabs in IndexedStack, no stacking)
class CustomAppShell extends StatefulWidget {
  const CustomAppShell({super.key});

  @override
  State<CustomAppShell> createState() => _CustomAppShellState();
}

class _CustomAppShellState extends State<CustomAppShell> {
  DateTime? _lastBackPressed;
  bool _isExitPromptShown = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<NavigationStateManager>(
      builder: (context, navState, _) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (!didPop) {
              print('[AppShell] Back pressed, auth state: ${navState.authState}');
              _handleBackButton(navState);
            }
          },
          child: Scaffold(
            body: _buildScreenForCurrentState(navState),
          ),
        );
      },
    );
  }

  /// Build the correct screen based on current auth state
  /// NO NAVIGATION STACK - just swapping widgets
  Widget _buildScreenForCurrentState(NavigationStateManager navState) {
    switch (navState.authState) {
      case AuthState.splash:
        return const SplashScreen();

      case AuthState.login:
        return const LoginScreen();

      case AuthState.signup:
        return const SignupScreen();

      case AuthState.authenticated:
        return _buildMainApp(navState);
    }
  }

  /// Build the main app with tabs (IndexedStack, NO stacking)
  Widget _buildMainApp(NavigationStateManager navState) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: navState.currentTab.index,
          children: [
            // Tab 0: Home
            _KeepAliveTab(child: const HomeScreen()),
            // Tab 1: Chats
            _KeepAliveTab(child: const ChatsScreen()),
            // Tab 2: Calls
            _KeepAliveTab(child: const CallsScreen()),
            // Tab 3: Profile
            _KeepAliveTab(child: const ProfileScreen()),
          ],
        ),
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: MissedCallsStore(),
        builder: (context, _) {
          final missed = MissedCallsStore().missedCount;
          return BottomNavigationBar(
            currentIndex: navState.currentTab.index,
            type: BottomNavigationBarType.fixed,
            items: [
              const BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
              const BottomNavigationBarItem(icon: Icon(Icons.chat_bubble), label: 'Chats'),
              BottomNavigationBarItem(
                icon: missed > 0
                    ? Badge(label: Text('$missed'), child: const Icon(Icons.call))
                    : const Icon(Icons.call),
                label: 'Calls',
              ),
              const BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
            ],
            onTap: (index) {
              navState.goToTab(AppTab.values[index]);
              if (AppTab.values[index] == AppTab.calls) {
                MissedCallsStore().markCallsTabViewed();
              }
            },
          );
        },
      ),
    );
  }

  /// Handle back button for entire app
  Future<bool> _handleBackButton(NavigationStateManager navState) async {
    // In auth flow (login/signup)
    if (!navState.isAuthenticated) {
      final handled = navState.handleAuthBackButton();
      if (handled) {
        return false; // Back button handled by going back in auth flow
      }
      // No more history, allow exit
      return true;
    }

    // In main app (tabs)
    if (navState.currentTab != AppTab.home) {
      navState.goToHome();
      return false; // Back button handled by going to home
    }

    // On home tab - require double-tap to exit
    final now = DateTime.now();
    if (_lastBackPressed == null || now.difference(_lastBackPressed!) > const Duration(seconds: 2)) {
      _lastBackPressed = now;
      if (!_isExitPromptShown && mounted) {
        _isExitPromptShown = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Press back again to exit'),
            duration: Duration(seconds: 2),
          ),
        ).closed.then((_) {
          _isExitPromptShown = false;
        });
      }
      return false; // Don't exit yet
    }

    // Double-tap confirmed - exit app
    return true;
  }
}

/// Wrapper to keep tab content alive
class _KeepAliveTab extends StatefulWidget {
  final Widget child;

  const _KeepAliveTab({required this.child});

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
