import 'package:go_router/go_router.dart';
import '../screens/splash/splash_screen.dart';
import '../navigation/root_navigator_key.dart';
import '../screens/get_started/get_started_screen.dart';
import '../screens/welcome/welcome_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/chats/chats_screen.dart';
import '../screens/chats/chat_screen.dart';
import '../models/chat.dart';
import '../models/post.dart'; // PostVisibility, used by the create-post route
import '../screens/calls/calls_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/create_post/create_post_screen.dart';
import '../app_shell.dart';
import '../screens/signup/signup_screen.dart';
import '../screens/login/login_screen.dart';
import '../screens/search/search_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/requests/requests_screen.dart';
import '../screens/settings/settings_screen.dart';

class AppRoutes {
  AppRoutes._();
  static const String splash = 'splash';
  static const String getStarted = 'get_started';
  static const String signup = 'signup';
  static const String login = 'login';
  static const String welcome = 'welcome';
  static const String home = 'home';
  static const String chats = 'chats';
  static const String calls = 'calls';
  static const String profile = 'profile';
  static const String search = 'search';
  static const String notifications = 'notifications';
}

class AppRouter {
  AppRouter._();

  static String _stateLocation(GoRouterState state) {
    try {
      final dyn = state as dynamic;
      if (dyn.location is String && (dyn.location as String).isNotEmpty) return dyn.location as String;
    } catch (_) {}
    try {
      final dyn = state as dynamic;
      if (dyn.uri != null) return dyn.uri.toString();
    } catch (_) {}
    try {
      if (state.name != null && state.name!.isNotEmpty) return '/${state.name}';
    } catch (_) {}
    return state.toString();
  }

  static final GoRouter router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        name: AppRoutes.splash,
        path: '/',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        name: AppRoutes.getStarted,
        path: '/get-started',
        builder: (context, state) => const GetStartedScreen(),
      ),
      GoRoute(
        name: AppRoutes.signup,
        path: '/signup',
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        name: AppRoutes.login,
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        name: AppRoutes.welcome,
        path: '/welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child, routeLocation: _stateLocation(state)),
        routes: [
          GoRoute(
            name: AppRoutes.home,
            path: '/home',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            name: AppRoutes.chats,
            path: '/chats',
            builder: (context, state) => const ChatsScreen(),
          ),
          GoRoute(
            name: 'chat_detail',
            path: '/chats/:id',
            builder: (context, state) {
              // ...existing code...
              String id = '';
              try {
                final dyn = state as dynamic;
                if (dyn.params != null && dyn.params is Map && dyn.params['id'] != null) {
                  id = dyn.params['id'] as String;
                } else if (dyn.pathParameters != null && dyn.pathParameters is Map && dyn.pathParameters['id'] != null) {
                  id = dyn.pathParameters['id'] as String;
                }
              } catch (_) {}
              if (id.isEmpty) id = '';
              final chat = (mockChats.isNotEmpty) ? mockChats.firstWhere((c) => c.id == id, orElse: () => mockChats.first) : throw StateError('No mock chats available');
              return ChatScreen(chat: chat);
            },
          ),
          GoRoute(
            name: AppRoutes.calls,
            path: '/calls',
            builder: (context, state) => const CallsScreen(),
          ),
          GoRoute(
            name: AppRoutes.profile,
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
          GoRoute(
            name: AppRoutes.search,
            path: '/search',
            builder: (context, state) => const SearchScreen(),
          ),
          GoRoute(
            name: AppRoutes.notifications,
            path: '/notifications',
            builder: (context, state) => const NotificationsScreen(),
          ),
          GoRoute(
            name: 'settings',
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
          GoRoute(
            name: 'requests',
            path: '/requests',
            builder: (context, state) => const RequestsScreen(),
          ),
          GoRoute(
            name: 'create',
            path: '/create',
            builder: (context, state) {
              final extra = (state.extra is Map<String, dynamic>) ? state.extra as Map<String, dynamic> : null;
              return CreatePostScreen(
                editingPostId: extra != null ? extra['editingPostId'] as int? : null,
                initialContent: extra != null ? extra['initialContent'] as String? : null,
                initialImageUrls: extra != null ? extra['initialImageUrls'] as List<String>? : null,
                initialVisibility: extra != null ? extra['initialVisibility'] as PostVisibility? : null,
              );
            },
          ),
        ],
      ),
    ],
  );
}
