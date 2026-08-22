import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_logo.dart';
import '../../components/primary_button.dart';
import '../../services/api_service.dart';
import '../../state/app_state_manager.dart';
import '../../theme/colors.dart';

class GetStartedScreen extends ConsumerStatefulWidget {
  const GetStartedScreen({super.key});

  @override
  ConsumerState<GetStartedScreen> createState() => _GetStartedScreenState();
}

class _GetStartedScreenState extends ConsumerState<GetStartedScreen> {
  @override
  void initState() {
    super.initState();
    _redirectIfLoggedIn();
  }

  Future<void> _redirectIfLoggedIn() async {
    final hasSession = await ApiService.hasSession();
    if (!mounted || !hasSession) return;
    try {
      ref.read(appStateProvider.notifier).goToAuthenticated();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const AppLogo(size: 110),
              const SizedBox(height: 28),
              Text(
                'Welcome to Social Chat',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                'Create an account or continue to explore the app. Fast, secure and private messaging.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.muted,
                    ),
              ),
              const SizedBox(height: 40),
              PrimaryButton(
                label: 'Get Started',
                onPressed: () {
                  ref.read(appStateProvider.notifier).goToSignup();
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
