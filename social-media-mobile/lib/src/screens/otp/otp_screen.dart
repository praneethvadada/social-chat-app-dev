import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_logo.dart';
import '../../components/primary_button.dart';
import '../../services/api_service.dart';
import '../../state/app_state_manager.dart';
import '../../theme/colors.dart';

class OtpScreen extends ConsumerStatefulWidget {
  final String email;
  final String username;
  final String fullName;
  final String password;

  const OtpScreen({
    super.key,
    required this.email,
    required this.username,
    required this.fullName,
    required this.password,
  });

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

  @override
  void initState() {
    super.initState();
    _otpControllers = List.generate(4, (_) => TextEditingController());
    _focusNodes = List.generate(4, (_) => FocusNode());

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
    if (value.length == 1 && index < 3) {
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

    if (otp.length != 4) {
      snack.showSnackBar(
        const SnackBar(content: Text('Please enter all 4 digits')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Call OTP verification endpoint
      final response = await ApiService.verifyOtp(
        email: widget.email,
        otp: otp,
      );

      if (response['success'] == true) {
        // OTP verified, now register the user
        try {
          await ApiService.register(
            widget.username,
            widget.email,
            widget.password,
            widget.fullName,
          );

          snack.showSnackBar(
            const SnackBar(
              content: Text('Account created and verified successfully!'),
            ),
          );

          // Navigate to authenticated state
          if (mounted) {
            ref.read(appStateProvider.notifier).goToAuthenticated();
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
      final response = await ApiService.resendOtp(email: widget.email);

      if (response['success'] == true) {
        snack.showSnackBar(
          const SnackBar(content: Text('OTP sent to your email')),
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
                          'Verify Your Email',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.text,
                              ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'We\'ve sent a 4-digit OTP to ${widget.email}',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: AppColors.muted,
                              ),
                        ),
                        const SizedBox(height: 32),

                        // OTP Input Boxes
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            4,
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
                                        color: AppColors.text,
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
                                        color: AppColors.border,
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
                                    fillColor: AppColors.inputBackground,
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
                                        ? AppColors.muted
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
                                  color: AppColors.muted,
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
