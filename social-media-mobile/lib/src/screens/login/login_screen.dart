import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider;
import '../../components/app_logo.dart';
import '../../components/custom_text_field.dart';
import '../../theme/colors.dart';
import '../../services/api_service.dart';
import '../../services/chat_websocket_service.dart';
import '../../services/call_signaling_service.dart';
import '../../services/group_call_signaling_service.dart';
import '../../services/post_service.dart';
import '../../state/app_state_manager.dart';
import '../../state/chat_store.dart';
import '../forgot_password/forgot_password_screen.dart';
import '../../services/firebase_messaging_service.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _userCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _isLoading = false;

  late final AnimationController _animController;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
    _slide = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _fade = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _animController.forward();
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
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final snack = ScaffoldMessenger.of(context);
    if (_userCtrl.text.isEmpty || _passCtrl.text.isEmpty) {
      snack.showSnackBar(const SnackBar(content: Text('Please enter credentials')));
      return;
    }
    setState(() => _isLoading = true);
    try {
      // Clear cached data from previous user before login
      ref.read(postProvider.notifier).clearPosts();
      provider.Provider.of<ChatStore>(context, listen: false).clear();
      
      await ApiService.login(_userCtrl.text, _passCtrl.text);

      // After login, fetch the latest profile from social-service
      // to ensure username/fullName are up to date and not stale
      try {
        final profile = await ApiService.getMyProfile();
        await ApiService.updateStoredProfile(
          username: profile['username'] as String?,
          fullName: profile['fullName'] as String?,
        );
        print('[LOGIN] Profile synced: ${profile['username']}');
      } catch (e) {
        print('[LOGIN] Profile sync failed: $e');
        // Ignore profile refresh failures; proceed to home
      }

      // Initialize WebSocket connection with new session
      try {
        print('[LOGIN] 🔌 Initializing WebSocket connection');
        final token = await ApiService.getToken();
        final userId = await ApiService.getUserId();
        if (token != null && userId != null && userId > 0) {
          // Give the store this session's identity BEFORE messages start
          // arriving. Without it the store cannot tell sent from received, so
          // unread counts would be misattributed to the sender.
          if (mounted) {
            provider.Provider.of<ChatStore>(context, listen: false)
                .setCurrentUserId(userId);
          }

          await ChatWebSocketService().connect(token, userId);
          print('[LOGIN] ✅ WebSocket connected');
        }
      } catch (e) {
        print('[LOGIN] ⚠️ WebSocket connection failed: $e');
      }

      // Re-initialize CallSignalingService to ensure handler is registering with new WebSocket connection
      try {
        print('[LOGIN] 🔄 Re-initializing CallSignalingService');
        // Access the singleton instance which will register handler with current WebSocket
        // ignore: unused_local_variable
        final cs = CallSignalingService();
        await cs.refreshUserSession(); // ✅ Ensure we have the correct user ID
        print('[LOGIN] ✅ CallSignalingService ready for incoming calls');
      } catch (e) {
        print('[LOGIN] ⚠️ CallSignalingService init failed: $e');
      }

      try {
        await GroupCallSignalingService().refreshUserSession();
      } catch (e) {
        print('[LOGIN] ⚠️ GroupCallSignalingService init failed: $e');
      }

      // ✅ Force FCM token sync for new user
      try {
        await FirebaseMessagingService.syncTokenAfterLogin();
      } catch (e) {
        print('[LOGIN] ⚠️ Token sync failed (non-critical): $e');
      }

      snack.showSnackBar(const SnackBar(content: Text('Logged in successfully')));
      // Use AppStateManager instead of GoRouter
      ref.read(appStateProvider.notifier).goToAuthenticated();
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      snack.showSnackBar(SnackBar(content: Text(msg.isNotEmpty ? msg : 'Login failed')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final contentWidth = width > 520 ? 520.0 : width * 0.94;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RepaintBoundary(
          child: Center(
            child: SlideTransition(
              position: _slide,
              child: FadeTransition(
                opacity: _fade,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: contentWidth),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const SizedBox(height: 8),
                        const AppLogo(size: 86),
                        const SizedBox(height: 12),
                        Text('SocialChat', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text('Connect with friends and share moments', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted)),
                        const SizedBox(height: 22),
                        CustomTextField(controller: _userCtrl, hintText: 'Email, Phone, or Username', keyboardType: TextInputType.text),
                        const SizedBox(height: 14),
                        CustomTextField(
                          controller: _passCtrl,
                          hintText: 'Password',
                          obscureText: _obscure,
                          suffix: IconButton(
                            icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: AppColors.muted),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        const SizedBox(height: 18),
                        // Gradient login button with shadow
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withAlpha((0.18 * 255).round()), offset: const Offset(0, 6), blurRadius: 12),
                            ],
                            gradient: LinearGradient(colors: [AppColors.primary, AppColors.primaryVariant], begin: Alignment.topLeft, end: Alignment.bottomRight),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: _isLoading ? null : _login,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(color: Colors.white),
                                        )
                                      : const Text('Login', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const ForgotPasswordScreen(),
                                ),
                              );
                            },
                            child: const Text('Forgot Password?'),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text("Don't have an account?", style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: () {
                            ref.read(appStateProvider.notifier).goToSignup();
                          },
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: AppColors.primary.withAlpha((0.9 * 255).round())),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                          child: Text('Sign Up', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
