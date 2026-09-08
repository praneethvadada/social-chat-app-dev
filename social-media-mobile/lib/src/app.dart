import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider;
import 'navigation/root_navigator_key.dart';
import 'state/app_state_manager.dart';
import 'state/call_state_manager.dart';
import 'services/api_service.dart';
import 'screens/splash/splash_screen.dart';
import 'screens/get_started/get_started_screen.dart';
import 'screens/login/login_screen.dart';
import 'screens/signup/signup_screen.dart';
import 'screens/main_app.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/search/search_screen.dart';
import 'screens/notifications/notifications_screen.dart';
import 'screens/followers_list_screen.dart';
import 'screens/create_post/create_post_screen.dart';
import 'theme/app_theme.dart';
import 'theme/theme_provider.dart';
import 'services/call_overlay_manager.dart';
import 'widgets/minimized_call_overlay.dart';

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    // Use selector to watch only modal state, not full appNav (avoids full rebuilds)
    final openModal = ref.watch(appStateProvider.select((nav) => nav.openModal));
    
    return provider.Consumer<CallStateManager>(
      builder: (context, callManager, _) {
        final isMinimized = callManager.isMinimized;
        final callState = callManager.currentState;
        final callPayload = callManager.activeCallPayload;
        
        // Show minimized overlay when call is active (any state except idle/ended) AND minimized
        final showMinimizedOverlay = isMinimized && 
                                     (callState == CallState.outgoingCalling ||
                                      callState == CallState.incomingRinging ||
                                      callState == CallState.inCall) && 
                                     callPayload != null;
        
        print('[MyApp] 🔍 isMinimized=$isMinimized, callState=$callState, showMinimizedOverlay=$showMinimizedOverlay');
        
        return MaterialApp(
          title: 'Revolution Chat',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          navigatorKey: rootNavigatorKey,
          home: Stack(
            children: [
              _buildAuthScreen(ref.watch(appStateProvider)),
              // Modal screens stack on top
              if (openModal != ModalScreen.none)
                _buildModalScreen(context, openModal, ref),
              // Minimized call overlay widgets (spread into Stack as direct children)
              if (showMinimizedOverlay)
                ...buildMinimizedCallOverlay(
                  context: context,
                  callPayload: callPayload!,
                  isVideo: callPayload['isVideo'] as bool? ?? false,
                ),
            ],
          ),
          // Animate theme transitions for a smooth toggle
          builder: (context, child) {
            final themeData = themeMode == ThemeMode.dark ? AppTheme.darkTheme : AppTheme.lightTheme;
            return AnimatedTheme(
              data: themeData,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOut,
              child: child ?? const SizedBox(),
            );
          },
        );
      },
    );
  }

  /// Build the appropriate screen based on auth state (NO STACKING!)
  /// This replaces GoRouter with state-based navigation
  Widget _buildAuthScreen(AppNavigation appNav) {
    print('[MyApp] 🔐 _buildAuthScreen: authState=${appNav.authState}');
    
    switch (appNav.authState) {
      case AuthState.splash:
        print('[MyApp] 🔐 Building: SplashScreen');
        return const SplashScreen();
      
      case AuthState.getStarted:
        print('[MyApp] 🔐 Building: GetStartedScreen');
        return const GetStartedScreen();
      
      case AuthState.login:
        print('[MyApp] 🔐 Building: LoginScreen');
        return const LoginScreen();
      
      case AuthState.signup:
        print('[MyApp] 🔐 Building: SignupScreen');
        return const SignupScreen();
      
      case AuthState.authenticated:
        print('[MyApp] 🔐 Building: MainApp (authenticated) - MainApp watches AppStateManager internally');
        // MainApp watches appStateProvider internally, so we don't pass currentTab/showWelcome
        return const MainApp();
    }
  }

  /// Build modal screens that appear on top of authenticated content.
  ///
  /// Below 1024px: today's exact behaviour — a full-bleed sheet over a dark
  /// scrim. At 1024px+: per the design reference ("Notifications is a full
  /// screen on mobile and a 560px panel inside the desktop shell — not a
  /// stretched list"), the same content renders inside a capped, centred,
  /// rounded panel over a lighter scrim instead of taking the whole window.
  Widget _buildModalScreen(BuildContext context, ModalScreen modal, WidgetRef ref) {
    print('[MyApp] 📱 Opening modal: $modal');

    final width = MediaQuery.of(context).size.width;
    final isDesktopPanel = width >= 1024;

    final content = _buildModalContent(modal);

    return GestureDetector(
      onTap: () => ref.read(appStateProvider.notifier).closeModal(),
      child: Material(
        color: Colors.black.withAlpha(isDesktopPanel ? 64 : 102),
        child: Center(
          child: GestureDetector(
            onTap: () {}, // Prevent closing when tapping the screen content
            child: isDesktopPanel
                ? ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 560,
                      maxHeight: MediaQuery.of(context).size.height * 0.86,
                    ),
                    child: Material(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(20),
                      clipBehavior: Clip.antiAlias,
                      elevation: 16,
                      shadowColor: Colors.black45,
                      child: content,
                    ),
                  )
                : SizedBox.expand(child: content),
          ),
        ),
      ),
    );
  }

  /// Build the content of the modal
  Widget _buildModalContent(ModalScreen modal) {
    switch (modal) {
      case ModalScreen.none:
        return const SizedBox.shrink();
      case ModalScreen.settings:
        return const SettingsScreen();
      case ModalScreen.search:
        return const SearchScreen();
      case ModalScreen.notifications:
        return const NotificationsScreen();
      case ModalScreen.followers:
        // 🔴 FIX: Show followers screen with follow requests integrated
        return FutureBuilder<int?>(
          future: ApiService.getUserId(),
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data != null) {
              return FollowersListScreen(
                userId: snapshot.data!,
                title: 'Followers',
                isFollowing: false,
              );
            }
            return const Center(child: CircularProgressIndicator());
          },
        );
      case ModalScreen.createPost:
        return const CreatePostScreen();
    }
  }
}
