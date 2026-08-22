import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppShell extends StatefulWidget {
  final Widget child;
  final String? routeLocation;

  const AppShell({super.key, required this.child, this.routeLocation});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  DateTime? _lastBackPressed;

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.routeLocation != null && widget.routeLocation != oldWidget.routeLocation) {
      if (mounted) setState(() {});
    }
  }

  

  int _currentIndexFromLocation(String loc) {
    if (loc.startsWith('/chats')) return 1;
    if (loc.startsWith('/calls')) return 2;
    if (loc.startsWith('/profile')) return 3;
    return 0;
  }

  String _getRouterLocation(BuildContext context) {
    try {
      final router = GoRouter.of(context);
      final dyn = router as dynamic;
      if (dyn.location is String) return dyn.location as String;
    } catch (_) {}

    try {
      final router = GoRouter.of(context);
      final rd = (router as dynamic).routerDelegate;
      final cfg = rd.currentConfiguration;
      if (cfg != null) {
        if (cfg is String) return cfg;
        if (cfg is List && cfg.isNotEmpty) {
          final last = cfg.last;
          try {
            if (last is String) return last;
            final dynLast = last as dynamic;
            if (dynLast.location is String) return dynLast.location as String;
            if (dynLast.fullpath is String) return dynLast.fullpath as String;
            if (dynLast.path is String) return dynLast.path as String;
            if (dynLast.uri != null) return dynLast.uri.toString();
            if (dynLast.name is String) return '/${dynLast.name}';
          } catch (_) {}
        }
        try {
          final dynCfg = cfg as dynamic;
          if (dynCfg.location is String) return dynCfg.location as String;
          if (dynCfg.fullpath is String) return dynCfg.fullpath as String;
          if (dynCfg.path is String) return dynCfg.path as String;
          if (dynCfg.uri != null) return dynCfg.uri.toString();
        } catch (_) {}
      }
    } catch (_) {}

    return ModalRoute.of(context)?.settings.name ?? '/home';
  }
  String _normalizeLocation(String loc) {
    try {
      if (loc.startsWith('/chats')) return '/chats';
      if (loc.startsWith('/calls')) return '/calls';
      if (loc.startsWith('/profile')) return '/profile';
      if (loc.startsWith('/search')) return '/search';
      if (loc.startsWith('/notifications')) return '/notifications';
    } catch (_) {}
    return '/home';
  }

  @override
  Widget build(BuildContext context) {
    final location = (widget.routeLocation != null && widget.routeLocation!.isNotEmpty)
      ? widget.routeLocation!
      : _getRouterLocation(context);

    final currentIndex = _currentIndexFromLocation(location);
    final primary = Theme.of(context).colorScheme.primary;
    final iconColor = Theme.of(context).iconTheme.color ?? Colors.black;
    // Hide global overlay icons (search/notifications/requests) on chat detail and other screens
    final hideOverlayFor = [
      '/search',
      '/notifications',
      '/chats/',      // covers routes like /chats/:id
      '/chats',       // also hide on chats root to prevent overlay in stack pushes
      '/chat_detail', // covers name-based locations some go_router versions emit
      '/profile',
      '/requests',
      '/settings',
      '/create',
    ];
    final showTopIcons = !hideOverlayFor.any((p) => location.startsWith(p));

    return WillPopScope(
      onWillPop: () async {
        final router = GoRouter.of(context);
        String currentLocRaw;
        try {
          currentLocRaw = (router as dynamic).location as String;
        } catch (_) {
          currentLocRaw = _getRouterLocation(context);
        }
        final currentLoc = _normalizeLocation(currentLocRaw);

        // Double-back to exit on home
        if (currentLoc == '/home') {
          final now = DateTime.now();
          if (_lastBackPressed == null || now.difference(_lastBackPressed!) > const Duration(seconds: 2)) {
            _lastBackPressed = now;
            try {
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Press back again to exit')));
            } catch (_) {}
            return false;
          }
          return true; // allow exit
        }

        // Otherwise, allow Navigator to pop if possible
        try {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
            return false;
          }
        } catch (_) {}

        // Fallback: navigate to home
        try {
          router.go('/home');
        } catch (_) {}
        return false;
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: <Widget>[
              Positioned.fill(child: widget.child),
              // Removed global overlay icons (search, notifications, requests) to avoid duplication on home screen
              // no debug overlays in production-ready shell
            ],
          ),
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: currentIndex,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          selectedItemColor: primary,
          unselectedItemColor: Theme.of(context).unselectedWidgetColor,
          selectedLabelStyle: const TextStyle(fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          onTap: (i) {
            final router = GoRouter.of(context);
            final target = i == 0 ? '/home' : (i == 1 ? '/chats' : (i == 2 ? '/calls' : '/profile'));
            final current = location;
            if (current == target) return;
            try {
              (router as dynamic).push(target);
            } catch (e) {
              try {
                router.push(target);
              } catch (_) {
                try {
                  (router as dynamic).go(target);
                } catch (_) {}
              }
            }
          },
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline), label: 'Chats'),
            BottomNavigationBarItem(icon: Icon(Icons.call), label: 'Calls'),
            BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}
