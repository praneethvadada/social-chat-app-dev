import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AuthState { splash, getStarted, login, signup, authenticated }

// Order matches the reference's dock exactly: Pulse, Discover, Connect, Me.
// Calls is reached from within Connect (see ChatsScreen's app bar) rather
// than occupying its own dock slot.
enum MainTab { home, discover, chats, profile }

/// Modal/overlay screens that can open on top of authenticated content
enum ModalScreen { none, settings, search, notifications, followers, createPost }

class AppNavigation {
  final AuthState authState;
  final MainTab currentTab;
  final bool showWelcome;
  final ModalScreen openModal;

  AppNavigation({
    required this.authState,
    required this.currentTab,
    required this.showWelcome,
    required this.openModal,
  });

  AppNavigation copyWith({
    AuthState? authState,
    MainTab? currentTab,
    bool? showWelcome,
    ModalScreen? openModal,
  }) {
    return AppNavigation(
      authState: authState ?? this.authState,
      currentTab: currentTab ?? this.currentTab,
      showWelcome: showWelcome ?? this.showWelcome,
      openModal: openModal ?? this.openModal,
    );
  }
}

class AppStateManager extends StateNotifier<AppNavigation> {
  AppStateManager()
      : super(AppNavigation(
          authState: AuthState.splash,
          currentTab: MainTab.home,
          showWelcome: false,
          openModal: ModalScreen.none,
        ));

  /// Go to splash (reset)
  void goToSplash() {
    state = state.copyWith(authState: AuthState.splash);
  }

  /// Go to get started screen
  void goToGetStarted() {
    state = state.copyWith(authState: AuthState.getStarted);
  }

  /// Go to login
  void goToLogin() {
    state = state.copyWith(authState: AuthState.login, showWelcome: false);
  }

  /// Go to signup
  void goToSignup() {
    state = state.copyWith(authState: AuthState.signup, showWelcome: false);
  }

  /// Mark user as authenticated and show welcome if first login
  void goToAuthenticated({bool showWelcome = false}) {
    state = state.copyWith(
      authState: AuthState.authenticated,
      currentTab: MainTab.home,
      showWelcome: showWelcome,
    );
  }

  /// Switch to a different tab (only when authenticated)
  void switchTab(MainTab tab) {
    if (state.authState == AuthState.authenticated) {
      state = state.copyWith(currentTab: tab);
    }
  }

  /// Go to home tab (only when authenticated)
  void goToHomeTab() {
    if (state.authState == AuthState.authenticated) {
      state = state.copyWith(currentTab: MainTab.home);
    }
  }

  /// Open a modal screen on top of authenticated content
  void openModal(ModalScreen modal) {
    if (state.authState == AuthState.authenticated) {
      state = state.copyWith(openModal: modal);
    }
  }

  /// Close the current modal screen
  void closeModal() {
    state = state.copyWith(openModal: ModalScreen.none);
  }

  /// Logout
  void logout() {
    state = state.copyWith(
      authState: AuthState.login,
      openModal: ModalScreen.none,
    );
  }

  /// Dismiss welcome screen and stay in authenticated state
  void dismissWelcome() {
    state = state.copyWith(showWelcome: false);
  }

  /// Back button pressed - handle based on current state
  void handleBackPress() {
    switch (state.authState) {
      case AuthState.splash:
        // Can't go back from splash
        break;
      case AuthState.getStarted:
        // Go back to splash (or let system close app)
        goToSplash();
        break;
      case AuthState.signup:
        // Go back to login from signup
        goToLogin();
        break;
      case AuthState.login:
        // Go back to get started from login
        goToGetStarted();
        break;
      case AuthState.authenticated:
        // If a modal is open, close it
        if (state.openModal != ModalScreen.none) {
          closeModal();
        } else if (state.currentTab != MainTab.home) {
          // If not on home tab, go to home tab
          goToHomeTab();
        }
        // Otherwise system will close the app
        break;
    }
  }
}

final appStateProvider =
    StateNotifierProvider<AppStateManager, AppNavigation>((ref) {
  return AppStateManager();
});
