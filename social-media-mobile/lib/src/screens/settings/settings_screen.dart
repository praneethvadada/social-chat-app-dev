import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider;
import '../../theme/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/chat_websocket_service.dart';  // ✅ For sending offline status
import '../../services/post_service.dart';
import '../../state/app_state_manager.dart';
import '../../state/chat_store.dart';
import 'notification_settings_screen.dart';
import 'privacy_settings_screen.dart';
import 'security_settings_screen.dart';
import '../../responsive/breakpoints.dart';
import '../../services/call_signaling_service.dart';
import '../../services/firebase_messaging_service.dart';
import '../../state/call_state_manager.dart';
import 'package:social_chat_app/src/theme/colors.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // Desktop index+detail split (see build()) — which section is showing in
  // the right-hand pane. 0=Notifications, 1=Privacy, 2=Security, null=none
  // selected yet. Stays null forever below `isDesktopClass`; mobile/tablet
  // never reads this, it keeps using plain push navigation.
  int? _selectedSection;

  void _openSection(BuildContext context, int index) {
    if (context.isDesktopClass) {
      setState(() => _selectedSection = index);
      return;
    }
    final screen = switch (index) {
      0 => const NotificationSettingsScreen(),
      1 => PrivacySettingsScreen(),
      _ => const SecuritySettingsScreen(),
    };
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final primary = Theme.of(context).colorScheme.primary;
    
    Future<void> handleLogout() async {
      final messenger = ScaffoldMessenger.of(context);
      final appNotifier = ref.read(appStateProvider.notifier);
      try {
        // ✅ Step 1: Send offline status to server BEFORE disconnecting
        print('[LOGOUT] 🔴 Step 1: Sending OFFLINE status to server...');
        try {
          final wsService = ChatWebSocketService();
          wsService.sendPresenceUpdate(false);  // Send offline to /app/presence.update
          print('[LOGOUT] ✅ Offline status sent - waiting for delivery...');
          
          // ✅ CRITICAL: Wait for message to actually transmit through STOMP
          // sendPresenceUpdate() is synchronous but STOMP takes time to send
          await Future.delayed(const Duration(milliseconds: 300));
          print('[LOGOUT] ✅ Offline status should be delivered to server');
        } catch (e) {
          print('[LOGOUT] ⚠️  Failed to send offline status: $e');
        }
        
        // ✅ Step 2: Clear WebSocket credentials to prevent reconnect/presence
        print('[LOGOUT] 🔴 Step 2: Clearing WebSocket session...');
        try {
          final wsService = ChatWebSocketService();
          await wsService.clear();
          print('[LOGOUT] ✅ WebSocket cleared - no reconnect will occur');
        } catch (e) {
          print('[LOGOUT] ⚠️  Failed to clear WebSocket: $e');
        }
        
        // ✅ Step 3: Clear all cached state BEFORE logout API call
        print('[LOGOUT] 🔴 Step 3: Clearing local state...');
        ref.read(postProvider.notifier).clearPosts();
        provider.Provider.of<ChatStore>(context, listen: false).clear();
        CallSignalingService().clearSession(); // ✅ Clear cached user ID for calls
        await CallStateManager().reset(); // ✅ End any call state and clear overlays
        await FirebaseMessagingService.disablePushOnLogout(); // ✅ Stop push + calls
        print('[LOGOUT] ✅ Local state cleared - ChatStore offline');
        
        // ✅ Step 4: Logout from API
        print('[LOGOUT] 🔴 Step 4: Logging out from API...');
        await ApiService.logout();
        print('[LOGOUT] ✅ API logout complete');
        messenger.showSnackBar(const SnackBar(content: Text('Logged out')));
      } catch (e) {
        print('[LOGOUT] Error during logout: $e');
        messenger.showSnackBar(SnackBar(content: Text('Logout error, session cleared: $e')));
      } finally {
        // Close the settings modal first, then redirect to get-started screen
        appNotifier.closeModal();
        // Give a brief delay to allow modal to close before redirecting
        await Future.delayed(const Duration(milliseconds: 300));
        appNotifier.goToGetStarted();
      }
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          ref.read(appStateProvider.notifier).closeModal();
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: primary),
                      onPressed: () {
                        ref.read(appStateProvider.notifier).closeModal();
                      },
                    ),
                    Expanded(
                      child: Center(
                        child: Text('Settings', style: TextStyle(color: primary, fontSize: 22, fontWeight: FontWeight.w800)),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.settings, color: primary),
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (!context.isDesktopClass) ...[
                const SizedBox(height: 18),
                _buildIndexTiles(context, isDark, primary, handleLogout),
                const SizedBox(height: 12),
                const Expanded(child: SizedBox()),
              ] else
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 320,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.only(top: 18, bottom: 18),
                          child: _buildIndexTiles(context, isDark, primary, handleLogout),
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: _selectedSection == null
                            ? Center(
                                child: Text('Select a setting',
                                    style: TextStyle(color: AppColors.mutedSolid, fontSize: 15)),
                              )
                            : switch (_selectedSection!) {
                                0 => const NotificationSettingsScreen(embedded: true),
                                1 => PrivacySettingsScreen(embedded: true),
                                _ => const SecuritySettingsScreen(embedded: true),
                              },
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The Dark Mode / Notifications / Privacy / Security / Logout tile list
  /// — the "index" half of the desktop split, and the whole thing on
  /// mobile/tablet.
  Widget _buildIndexTiles(BuildContext context, bool isDark, Color primary, VoidCallback handleLogout) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          _buildTile(
            context,
            leading: Icons.dark_mode,
            title: 'Dark Mode',
            subtitle: 'Switch theme',
            trailing: Switch.adaptive(
              value: isDark,
              onChanged: (v) async {
                final userId = await ApiService.getUserId();
                ref.read(themeModeProvider.notifier).setThemeMode(
                      v ? ThemeMode.dark : ThemeMode.light,
                      userId: userId,
                    );
              },
              activeColor: primary,
            ),
          ),
          const SizedBox(height: 12),
          _buildTile(
            context,
            leading: Icons.notifications,
            title: 'Notifications',
            subtitle: 'Mentions, likes & follows',
            trailing: const Icon(Icons.chevron_right),
            selected: _selectedSection == 0,
            onTap: () => _openSection(context, 0),
          ),
          const SizedBox(height: 12),
          _buildTile(
            context,
            leading: Icons.lock,
            title: 'Privacy',
            subtitle: 'Account privacy and settings',
            trailing: const Icon(Icons.chevron_right),
            selected: _selectedSection == 1,
            onTap: () => _openSection(context, 1),
          ),
          const SizedBox(height: 12),
          _buildTile(
            context,
            leading: Icons.security,
            title: 'Security',
            subtitle: 'Logged-in devices and account security',
            trailing: const Icon(Icons.chevron_right),
            selected: _selectedSection == 2,
            onTap: () => _openSection(context, 2),
          ),
          const SizedBox(height: 12),
          _buildTile(
            context,
            leading: Icons.logout,
            title: 'Logout',
            subtitle: 'Sign out of this device',
            iconBgColor: AppColors.danger,
            onTap: handleLogout,
          ),
        ],
      ),
    );
  }

  Widget _buildTile(BuildContext context, {
    required IconData leading,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    Color iconBgColor = AppColors.primary,
    // Desktop index only — highlights whichever section is open in the
    // detail pane. Always false on mobile/tablet (nothing sets it there).
    bool selected = false,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? primary.withValues(alpha: 0.1) : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: selected ? Border.all(color: primary, width: 1.5) : null,
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(leading, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(subtitle, style: TextStyle(color: AppColors.mutedSolid, fontSize: 13)),
                  ]
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }
}

// Helper for reading theme cardColor in a pure widget helper when context isn't available.
// There's no global navigatorKey in project; using a cheap workaround by importing material's default context
// but to keep this file self-contained we avoid using global keys and instead use Theme.of(context) when possible.
