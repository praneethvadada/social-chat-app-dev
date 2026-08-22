import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/app_state_manager.dart';
import 'splash/splash_screen.dart';
import 'get_started/get_started_screen.dart';
import 'login/login_screen.dart';
import 'signup/signup_screen.dart';

/// Handles all authentication-related navigation
class AuthScreen extends ConsumerWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);
    
    switch (appState.authState) {
      case AuthState.splash:
        return const SplashScreen();
      case AuthState.getStarted:
        return const GetStartedScreen();
      case AuthState.login:
        return const LoginScreen();
      case AuthState.signup:
        return const SignupScreen();
      case AuthState.authenticated:
        // Should never reach here - handled by MainApp
        return const SplashScreen();
    }
  }
}
