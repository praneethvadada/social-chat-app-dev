import 'package:flutter/foundation.dart';

/// Represents the current authentication state
enum AuthState { splash, login, signup, authenticated }

/// Represents the current main app tab
enum AppTab { home, chats, calls, profile }

/// Global navigation state manager - NO ROUTING, PURE STATE
/// Mimics WhatsApp's architecture: state changes, not route pushes
class NavigationStateManager extends ChangeNotifier {
  static final NavigationStateManager _instance = NavigationStateManager._internal();

  factory NavigationStateManager() => _instance;

  NavigationStateManager._internal();

  // Current authentication state
  AuthState _authState = AuthState.splash;
  
  // Current main app tab (only relevant when authenticated)
  AppTab _currentTab = AppTab.home;
  
  // Auth navigation history (for back button in auth flow)
  final List<AuthState> _authHistory = [];

  // Getters
  AuthState get authState => _authState;
  AppTab get currentTab => _currentTab;
  bool get isAuthenticated => _authState == AuthState.authenticated;

  // ============ AUTH NAVIGATION (LOGIN/SIGNUP) ============

  /// Navigate to login screen
  void goToLogin() {
    print('[NavState] Going to login');
    _authHistory.add(_authState);
    _authState = AuthState.login;
    notifyListeners();
  }

  /// Navigate to signup screen
  void goToSignup() {
    print('[NavState] Going to signup');
    _authHistory.add(_authState);
    _authState = AuthState.signup;
    notifyListeners();
  }

  /// User logged in or signed up successfully
  void setAuthenticated() {
    print('[NavState] User authenticated, clearing auth history');
    _authState = AuthState.authenticated;
    _authHistory.clear();
    _currentTab = AppTab.home;
    notifyListeners();
  }

  /// Logout user
  void logout() {
    print('[NavState] User logged out');
    _authState = AuthState.login;
    _authHistory.clear();
    _currentTab = AppTab.home;
    notifyListeners();
  }

  /// Handle back button in auth flow (login/signup)
  bool handleAuthBackButton() {
    if (!isAuthenticated && _authHistory.isNotEmpty) {
      final previousState = _authHistory.removeLast();
      print('[NavState] Going back in auth flow to $previousState');
      _authState = previousState;
      notifyListeners();
      return true; // Back button was handled
    }
    return false; // No history, app should exit
  }

  // ============ TAB NAVIGATION (MAIN APP) ============

  /// Switch to a specific tab
  void goToTab(AppTab tab) {
    if (_authState != AuthState.authenticated) {
      print('[NavState] Cannot switch tabs, not authenticated');
      return;
    }

    if (_currentTab == tab) {
      print('[NavState] Already on tab $tab');
      return;
    }

    print('[NavState] Switching to tab $tab');
    _currentTab = tab;
    notifyListeners();
  }

  /// Go to home tab
  void goToHome() => goToTab(AppTab.home);

  /// Go to chats tab
  void goToChats() => goToTab(AppTab.chats);

  /// Go to calls tab
  void goCalls() => goToTab(AppTab.calls);

  /// Go to profile tab
  void goToProfile() => goToTab(AppTab.profile);

  /// Handle back button in main app (tabs)
  bool handleMainAppBackButton() {
    if (!isAuthenticated) {
      return false; // Not in main app
    }

    if (_currentTab != AppTab.home) {
      print('[NavState] Not on home tab, going to home');
      _currentTab = AppTab.home;
      notifyListeners();
      return true; // Back button was handled
    }

    // On home tab - require double-tap to exit
    return false; // Let system handle app exit
  }

  // ============ RESET ============

  /// Reset all navigation state (used for testing/logout)
  void reset() {
    _authState = AuthState.splash;
    _currentTab = AppTab.home;
    _authHistory.clear();
    notifyListeners();
  }
}
