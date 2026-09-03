import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_logo.dart';
import '../../services/api_service.dart';
import '../../state/app_state_manager.dart';
import '../../theme/colors.dart';
import '../../utils/animations.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600), // Faster fade-in
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();

    // Decide target up front to avoid showing auth screens when already logged in.
    // If session exists, validate it by fetching profile from server.
    Future<void>(() async {
      final hasSession = await ApiService.hasSession();

      // validateStoredSession only drops the session when the server actually
      // rejects the token (401/403) or it belongs to a different user. A
      // timeout, an unreachable backend or a 5xx keeps you logged in - being
      // offline is not the same as being signed out, and this screen re-runs
      // on every hot restart.
      final isValidSession =
          hasSession ? await ApiService.validateStoredSession() : false;
      
      // Short delay to show logo while background init runs
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      
      // Use AppStateManager instead of GoRouter
      final stateManager = ref.read(appStateProvider.notifier);
      if (isValidSession) {
        stateManager.goToAuthenticated();
      } else {
        stateManager.goToGetStarted();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themed = ThemedColors.of(context);
    return Scaffold(
      // No explicit backgroundColor — see login_screen.dart for why.
      body: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: themed.accentSubtle100,
                    shape: BoxShape.circle,
                    border: Border.all(color: themed.border),
                  ),
                  child: const AppLogo(size: 88),
                ),
                const SizedBox(height: 20),
                Text(
                  'SOCIAL CHAT',
                  style: TextStyle(
                    color: themed.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: 4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
