import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ThemeMode provider with PER-USER persistence.
///
/// Two SharedPreferences layers:
/// - `theme_mode_active` (global, no user scoping) mirrors whatever theme
///   is currently being shown. Pre-home pages (splash/get-started/login/
///   signup) read this at app startup, before any user is known — it's
///   what makes "Pre-Home Pages show Dark Mode after this user logs out"
///   work with no separate logout-time logic: it's simply never changed on
///   logout, so it still holds whatever that user last selected.
/// - `theme_mode_user_<userId>` (per-user) is one specific user's own
///   saved preference, looked up via [applyUserPreferenceOnLogin] right
///   after a successful login/register (defaulting to Light if that user
///   has never set one) — this is what stops one user's Dark Mode choice
///   from leaking onto a different user who later logs into the same
///   device: at THEIR login, the active mirror gets overwritten with
///   THEIR OWN preference (or Light), not left at whatever the previous
///   user set.
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  static const String _activeKey = 'theme_mode_active';
  static const String _userKeyPrefix = 'theme_mode_user_';

  // Default Light — matches "new/unrecognized user -> Light Mode" and
  // "default is Light until there's an existing saved preference".
  ThemeModeNotifier() : super(ThemeMode.light) {
    _loadActiveThemeMode();
  }

  Future<void> _loadActiveThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_activeKey);
      state = saved == 'dark' ? ThemeMode.dark : ThemeMode.light;
      print('[ThemeProvider] 💡 Loaded active theme mode: $state');
    } catch (e) {
      print('[ThemeProvider] ⚠️ Failed to load theme mode: $e');
    }
  }

  /// Explicit user action (Settings -> Dark Mode switch). Always updates
  /// the active/pre-home mirror; additionally saves as this user's own
  /// preference when [userId] is supplied (i.e. someone is logged in).
  Future<void> setThemeMode(ThemeMode mode, {int? userId}) async {
    state = mode;
    final value = mode == ThemeMode.dark ? 'dark' : 'light';
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_activeKey, value);
      if (userId != null) {
        await prefs.setString('$_userKeyPrefix$userId', value);
      }
      print('[ThemeProvider] 💾 Saved theme mode: $mode (userId=$userId)');
    } catch (e) {
      print('[ThemeProvider] ⚠️ Failed to save theme mode: $e');
    }
  }

  /// Call once, right after a successful login/register when userId first
  /// becomes known. Applies that user's own saved preference (Light if
  /// they've never set one) and syncs the active/pre-home mirror to match.
  Future<void> applyUserPreferenceOnLogin(int userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('$_userKeyPrefix$userId');
      final mode = saved == 'dark' ? ThemeMode.dark : ThemeMode.light;
      state = mode;
      await prefs.setString(_activeKey, mode == ThemeMode.dark ? 'dark' : 'light');
      print('[ThemeProvider] 👤 Applied theme for userId=$userId: $mode');
    } catch (e) {
      print('[ThemeProvider] ⚠️ Failed to apply per-user theme: $e');
    }
  }

  void toggleTheme({int? userId}) {
    final newMode = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    setThemeMode(newMode, userId: userId);
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (ref) => ThemeModeNotifier(),
);
