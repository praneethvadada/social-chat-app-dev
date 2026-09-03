import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_logo.dart';
import '../../components/primary_button.dart';
import '../../services/api_service.dart';
import '../../services/call_signaling_service.dart';
import '../../services/mobile_storage_gate.dart';
import '../../state/app_state_manager.dart';
import '../../theme/colors.dart';
import '../../theme/theme_provider.dart';
import '../../services/firebase_messaging_service.dart';

class OtpScreen extends ConsumerStatefulWidget {
  /// Provide exactly one of [email] or [phoneNumber] — matches whichever
  /// identifier SignupScreen sent the OTP to. Email OTPs are 4 digits,
  /// phone OTPs are 6 (see PhoneOtpService.otpLength on the backend) — the
  /// box row and every length check below derive from this, not a constant.
  final String? email;
  final String? phoneNumber;
  final String username;
  final String fullName;
  final String password;

  const OtpScreen({
    super.key,
    this.email,
    this.phoneNumber,
    required this.username,
    required this.fullName,
    required this.password,
  }) : assert((email != null) != (phoneNumber != null), 'Provide exactly one of email or phoneNumber');

  bool get isPhone => phoneNumber != null;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen>
    with SingleTickerProviderStateMixin {
  late final List<TextEditingController> _otpControllers;
  late final List<FocusNode> _focusNodes;
  bool _isLoading = false;
  bool _isResendingOtp = false;
  int _resendCountdown = 0;

  late final AnimationController _animController;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  int get _otpLength => widget.isPhone ? 6 : 4;

  static const String _phoneSignupPurpose = 'PHONE_SIGNUP';

  @override
  void initState() {
    super.initState();
    _otpControllers = List.generate(_otpLength, (_) => TextEditingController());
    _focusNodes = List.generate(_otpLength, (_) => FocusNode());

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _slide = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _fade = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _animController.forward();

    // Auto-focus first input
    Future.delayed(const Duration(milliseconds: 300), () {
      _focusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    _animController.dispose();
    super.dispose();
  }

  void _onOtpInputChange(String value, int index) {
    if (value.length == 1 && index < _otpLength - 1) {
      // Move to next field
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      // Move to previous field on delete
      _focusNodes[index - 1].requestFocus();
    }
  }

  String _getOtpCode() {
    return _otpControllers.map((c) => c.text).join();
  }

  Future<void> _verifyOtp() async {
    final otp = _getOtpCode();
    final snack = ScaffoldMessenger.of(context);

    if (otp.length != _otpLength) {
      snack.showSnackBar(
        SnackBar(content: Text('Please enter all $_otpLength digits')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Call OTP verification endpoint
      final response = widget.isPhone
          ? await ApiService.verifyPhoneOtp(
              phoneNumber: widget.phoneNumber!,
              otp: otp,
              purpose: _phoneSignupPurpose,
            )
          : await ApiService.verifyOtp(
              email: widget.email!,
              otp: otp,
            );

      if (response['success'] == true) {
        // OTP verified, now register the user
        try {
          await ApiService.register(
            username: widget.username,
            password: widget.password,
            fullName: widget.fullName,
            email: widget.email,
            phoneNumber: widget.phoneNumber,
          );

          snack.showSnackBar(
            const SnackBar(
              content: Text('Account created and verified successfully!'),
            ),
          );

          // ✅ Force FCM token sync for new user (Fix for call reception)
          try {
            await FirebaseMessagingService.syncTokenAfterLogin();
            await CallSignalingService().refreshUserSession(); // ✅ Update cached user ID
          } catch (e) {
            print('[OTP] ⚠️ Token sync failed (non-critical): $e');
          }

          // Brand-new account -> no saved theme preference yet, so this
          // applies Light Mode (and overwrites the pre-home mirror in case
          // a different previous user on this device had set Dark Mode).
          try {
            final newUserId = await ApiService.getUserId();
            if (newUserId != null) {
              await ref.read(themeModeProvider.notifier).applyUserPreferenceOnLogin(newUserId);
            }
          } catch (e) {
            print('[OTP] ⚠️ Failed to apply per-user theme: $e');
          }

          // Phase 3: brand-new account, so nobody could already own local
          // chat storage — this device just becomes the first (and only)
          // owner, no conflict prompt possible. Mobile only.
          if (!kIsWeb) {
            try {
              await MobileStorageGate.checkOnLogin();
            } catch (e) {
              print('[OTP] ⚠️ Mobile storage claim failed: $e');
            }
          }

          // Navigate to authenticated state and home page
          if (mounted) {
            ref.read(appStateProvider.notifier).goToAuthenticated();
            // Small delay to ensure state is updated before navigation
            await Future.delayed(const Duration(milliseconds: 500));
            if (mounted) {
              Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
            }
          }
        } catch (e) {
          snack.showSnackBar(
            SnackBar(
              content: Text(
                'Registration failed: ${e.toString().replaceFirst('Exception: ', '')}',
              ),
            ),
          );
        }
      } else {
        snack.showSnackBar(
          SnackBar(
            content: Text(response['message'] ?? 'Invalid OTP'),
          ),
        );
      }
    } catch (e) {
      snack.showSnackBar(
        SnackBar(content: Text('Verification failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _resendOtp() async {
    final snack = ScaffoldMessenger.of(context);

    setState(() => _isResendingOtp = true);

    try {
      final response = widget.isPhone
          ? await ApiService.resendPhoneOtp(phoneNumber: widget.phoneNumber!, purpose: _phoneSignupPurpose)
          : await ApiService.resendOtp(email: widget.email!);

      if (response['success'] == true) {
        snack.showSnackBar(
          SnackBar(content: Text(widget.isPhone ? 'OTP sent to your phone' : 'OTP sent to your email')),
        );

        // Start countdown
        setState(() => _resendCountdown = 60);
        Future.doWhile(() async {
          await Future.delayed(const Duration(seconds: 1));
          setState(() => _resendCountdown--);
          return _resendCountdown > 0;
        });
      } else {
        snack.showSnackBar(
          SnackBar(
            content: Text(response['message'] ?? 'Failed to resend OTP'),
          ),
        );
      }
    } catch (e) {
      snack.showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isResendingOtp = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final contentWidth = width > 520 ? 520.0 : width * 0.94;
    final destination = widget.isPhone ? widget.phoneNumber! : widget.email!;
    final themed = ThemedColors.of(context);

    return Scaffold(
      // No explicit backgroundColor — see login_screen.dart for why.
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 24,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const SizedBox(height: 12),
                        const AppLogo(size: 90),
                        const SizedBox(height: 28),
                        Text(
                          widget.isPhone ? 'Verify Your Phone Number' : 'Verify Your Email',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: themed.text,
                              ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'We\'ve sent a $_otpLength-digit OTP to $destination',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: themed.muted,
                              ),
                        ),
                        const SizedBox(height: 32),

                        // OTP Input Boxes
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            _otpLength,
                            (index) => Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8.0),
                              child: SizedBox(
                                width: 56,
                                height: 70,
                                child: TextField(
                                  controller: _otpControllers[index],
                                  focusNode: _focusNodes[index],
                                  onChanged: (value) =>
                                      _onOtpInputChange(value, index),
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  maxLength: 1,
                                  readOnly: _isLoading,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: themed.text,
                                      ),
                                  decoration: InputDecoration(
                                    counterText: '',
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                      horizontal: 12,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: themed.muted.withValues(alpha: 0.3),
                                        width: 2,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: AppColors.primary,
                                        width: 2,
                                      ),
                                    ),
                                    filled: true,
                                    fillColor: themed.background,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Verify Button
                        PrimaryButton(
                          label: _isLoading ? 'Verifying...' : 'Verify OTP',
                          onPressed: _isLoading ? null : _verifyOtp,
                        ),

                        const SizedBox(height: 20),

                        // Resend OTP
                        if (_resendCountdown == 0)
                          GestureDetector(
                            onTap:
                                _isResendingOtp ? null : _resendOtp,
                            child: Text(
                              'Didn\'t receive OTP? Resend',
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: _isResendingOtp
                                        ? themed.muted
                                        : AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          )
                        else
                          Text(
                            'Resend OTP in ${_resendCountdown}s',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: themed.muted,
                                ),
                          ),
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
