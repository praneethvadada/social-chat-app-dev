import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_logo.dart';
import '../../components/custom_text_field.dart';
import '../../components/two_step_card.dart';
import '../../theme/colors.dart';
import '../../services/api_service.dart';
import '../../state/app_state_manager.dart';
import 'otp_screen.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _fullNameCtrl = TextEditingController();
  final TextEditingController _usernameCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
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
    _fullNameCtrl.dispose();
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final full = _fullNameCtrl.text.trim();
    final user = _usernameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final pass = _passwordCtrl.text;
    final snack = ScaffoldMessenger.of(context);
    
    if (full.isEmpty || user.isEmpty || email.isEmpty || pass.isEmpty) {
      snack.showSnackBar(const SnackBar(content: Text('Please fill all fields')));
      return;
    }
    if (pass.length < 6) {
      snack.showSnackBar(const SnackBar(content: Text('Password must be at least 6 characters')));
      return;
    }
    
    setState(() => _isLoading = true);
    
    try {
      // Check if email and username are available BEFORE sending OTP
      final checkResponse = await ApiService.checkAvailability(email: email, username: user);
      
      if (checkResponse['emailExists'] == true) {
        snack.showSnackBar(const SnackBar(content: Text('Email already exists')));
        setState(() => _isLoading = false);
        return;
      }
      
      if (checkResponse['usernameExists'] == true) {
        snack.showSnackBar(const SnackBar(content: Text('Username already exists')));
        setState(() => _isLoading = false);
        return;
      }
      
      // Send OTP to email after validation
      final otpResponse = await ApiService.sendOtp(email: email);
      
      if (otpResponse['success'] == true) {
        snack.showSnackBar(
          const SnackBar(content: Text('OTP sent to your email')),
        );
        
        // Navigate to OTP verification screen
        // Pass user data without creating account yet
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => OtpScreen(
                email: email,
                username: user,
                fullName: full,
                password: pass,
              ),
            ),
          );
        }
      } else {
        snack.showSnackBar(
          SnackBar(
            content: Text(
              otpResponse['message'] ?? 'Failed to send OTP',
            ),
          ),
        );
      }
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      snack.showSnackBar(
        SnackBar(
          content: Text(msg.isNotEmpty ? msg : 'Failed to send OTP'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final maxWidth = MediaQuery.of(context).size.width > 520 ? 520.0 : MediaQuery.of(context).size.width * 0.94;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RepaintBoundary(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: SlideTransition(
                    position: _slide,
                    child: FadeTransition(
                      opacity: _fade,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const AppLogo(size: 92),
                          const SizedBox(height: 18),
                          Text(
                            'SocialChat',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Connect with friends and share moments',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                          ),
                          const SizedBox(height: 22),
                          CustomTextField(controller: _fullNameCtrl, hintText: 'Full Name', keyboardType: TextInputType.name),
                          const SizedBox(height: 12),
                          CustomTextField(controller: _usernameCtrl, hintText: 'Username', keyboardType: TextInputType.text),
                          const SizedBox(height: 12),
                          CustomTextField(controller: _emailCtrl, hintText: 'Email', keyboardType: TextInputType.emailAddress),
                          const SizedBox(height: 12),
                          CustomTextField(
                            controller: _passwordCtrl,
                            hintText: 'Password',
                            obscureText: _obscure,
                            suffix: IconButton(
                              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: AppColors.muted),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const TwoStepCard(),
                          const SizedBox(height: 22),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                elevation: 10,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(color: Colors.white),
                                    )
                                  : const Text('Sign Up', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                            ),
                          ),
                          const SizedBox(height: 16),
                          GestureDetector(
                            onTap: () {
                              ref.read(appStateProvider.notifier).goToLogin();
                            },
                            child: Text('Already have an account? Login', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.primary)),
                          ),
                          SizedBox(height: mq.size.height * 0.06),
                        ],
                      ),
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
