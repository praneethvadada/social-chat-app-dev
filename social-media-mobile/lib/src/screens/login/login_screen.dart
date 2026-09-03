import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider;
import '../../components/app_logo.dart';
import '../../components/custom_text_field.dart';
import '../../components/phone_number_field.dart';
import '../../components/segment_tabs.dart';
import '../../theme/colors.dart';
import '../../theme/theme_provider.dart';
import '../../services/api_service.dart';
import '../../services/chat_websocket_service.dart';
import '../../services/call_signaling_service.dart';
import '../../services/group_call_signaling_service.dart';
import '../../services/post_service.dart';
import '../../services/mobile_storage_gate.dart';
import '../../models/mobile_storage_status.dart';
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
  // Holds the full E.164 value (e.g. "+919876543210"), kept in sync by
  // PhoneNumberField itself — never touched directly, see _login() below.
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _isLoading = false;

  /// 0 = Email/Username (the existing, unchanged single free-text field —
  /// login has never had a phone-specific mode before this), 1 = Phone
  /// (the new country-picker field). Mirrors signup's own _method toggle
  /// exactly, including the "reuses PhoneNumberField" part — same
  /// component, same default-India/Canada-second behavior, same styling.
  int _loginMethod = 0;
  bool _phoneValid = false;

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
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final snack = ScaffoldMessenger.of(context);
    // Phone mode's identifier comes from _phoneCtrl (the full E.164 value
    // PhoneNumberField keeps in sync); Email/Username mode is _userCtrl,
    // completely unchanged from before this feature existed.
    final identifier = _loginMethod == 1 ? _phoneCtrl.text : _userCtrl.text;

    if (identifier.isEmpty || _passCtrl.text.isEmpty) {
      snack.showSnackBar(const SnackBar(content: Text('Please enter credentials')));
      return;
    }
    // Client-side pre-check only (PhoneNumberField's own best-effort,
    // per-selected-country validation) — must not allow submission with an
    // obviously-invalid number. The backend's own libphonenumber-based
    // validator remains the real, authoritative check either way; this
    // just avoids a pointless round trip for input that's clearly wrong.
    if (_loginMethod == 1 && !_phoneValid) {
      snack.showSnackBar(const SnackBar(content: Text('Enter a valid phone number for the selected country')));
      return;
    }
    setState(() => _isLoading = true);
    try {
      // Clear cached data from previous user before login
      ref.read(postProvider.notifier).clearPosts();
      provider.Provider.of<ChatStore>(context, listen: false).clear();

      var result = await ApiService.login(identifier, _passCtrl.text);

      // Phase 7: correct credentials, but the account has 2FA enabled — no
      // session was created yet (see ApiService.login/AuthService.login on
      // the backend). Challenge the user for the OTP before proceeding
      // exactly as a normal login would.
      if (result['twoFactorRequired'] == true) {
        final challengeToken = result['challengeToken'] as String?;
        if (challengeToken == null) {
          throw Exception('Two-factor challenge was missing a token');
        }
        if (!mounted) return;
        final otp = await _promptForTwoFactorOtp(result['method'] as String?, challengeToken);
        if (otp == null) {
          // User cancelled — not a failure, just stop here quietly.
          return;
        }
        result = await ApiService.verifyTwoFactorLogin(challengeToken: challengeToken, otp: otp);
      }

      // Post-Phase-10: correct credentials (and 2FA, if it applied), but the
      // account is already active on a different web browser — no session
      // was created yet. Confirm-before-kick: ask before logging that other
      // device out, rather than doing it silently (the previous behavior).
      if (result['webSessionConflict'] == true) {
        final challengeToken = result['challengeToken'] as String?;
        if (challengeToken == null) {
          throw Exception('Web session conflict was missing a token');
        }
        if (!mounted) return;
        final confirmed = await _promptForWebSessionTakeover(result);
        if (!confirmed) {
          // User cancelled — not a failure, just stop here quietly.
          return;
        }
        await ApiService.confirmWebSessionTakeover(challengeToken);
      }

      await _completeLoginFlow(snack);
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      snack.showSnackBar(SnackBar(content: Text(msg.isNotEmpty ? msg : 'Login failed')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Everything that happens once credentials (and, if enabled, the 2FA
  /// challenge) are fully satisfied — identical regardless of which path
  /// got here, so both share this single tail.
  Future<void> _completeLoginFlow(ScaffoldMessengerState snack) async {
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
          // Apply THIS user's own saved theme preference (Light if they've
          // never set one) — must happen at login so a device previously
          // used by a different user doesn't leak that user's Dark Mode
          // choice onto this one.
          try {
            await ref.read(themeModeProvider.notifier).applyUserPreferenceOnLogin(userId);
          } catch (e) {
            print('[LOGIN] ⚠️ Failed to apply per-user theme: $e');
          }

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

      // Phase 3: single-active-mobile-device local chat storage. Mobile
      // only — matches Phase 2's own kIsWeb gating on the local DB itself.
      // Auto-claims silently when nobody owns it yet; prompts only when
      // another device actively does.
      if (!kIsWeb) {
        try {
          final storageResult = await MobileStorageGate.checkOnLogin();
          if (storageResult.conflictWith != null && mounted) {
            await _showMobileStorageConflictDialog(storageResult.conflictWith!);
          }
        } catch (e) {
          print('[LOGIN] ⚠️ Mobile storage check failed: $e');
        }
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
  }

  /// Prompts for the 2FA login OTP (with a resend option), returning the
  /// entered code or null if the user cancelled. Distinct from the Settings
  /// 2FA OTP dialog (TwoFactorAuthScreen) — this one operates on a login
  /// challengeToken, not an authenticated session.
  Future<String?> _promptForTwoFactorOtp(String? method, String challengeToken) {
    final controller = TextEditingController();
    final themed = ThemedColors.of(context);
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          bool resending = false;
          return AlertDialog(
            backgroundColor: themed.surface,
            title: Text('Enter the code', style: TextStyle(color: themed.text)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  method == 'PHONE'
                      ? 'We sent a code to your phone.'
                      : 'We sent a code to your email.',
                  style: TextStyle(color: themed.muted),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: themed.text),
                  decoration: const InputDecoration(hintText: 'Code'),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: resending
                        ? null
                        : () async {
                            setDialogState(() => resending = true);
                            try {
                              await ApiService.resendTwoFactorLoginOtp(challengeToken);
                              if (dialogContext.mounted) {
                                ScaffoldMessenger.of(dialogContext)
                                    .showSnackBar(const SnackBar(content: Text('Code resent')));
                              }
                            } catch (e) {
                              if (dialogContext.mounted) {
                                ScaffoldMessenger.of(dialogContext).showSnackBar(
                                    SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
                              }
                            } finally {
                              setDialogState(() => resending = false);
                            }
                          },
                    child: Text(resending ? 'Sending…' : 'Resend code'),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
                child: const Text('Verify'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Post-Phase-10: the account is already active on a DIFFERENT web
  /// browser (single-active-web-session, spec's WhatsApp-Web-style rule).
  /// Unlike the mobile storage dialog below, login here has NOT succeeded
  /// yet — nothing happens to the other device unless the user explicitly
  /// confirms. Returns true if they chose to log the other device out and
  /// continue, false if they cancelled.
  Future<bool> _promptForWebSessionTakeover(Map<String, dynamic> conflict) {
    final themed = ThemedColors.of(context);
    final browser = conflict['browserName'] as String?;
    final os = conflict['osName'] as String?;
    final deviceModel = conflict['deviceModel'] as String?;
    final label = [
      if (browser != null && browser.isNotEmpty) browser,
      if (os != null && os.isNotEmpty) 'on $os',
      if ((browser == null || browser.isEmpty) && (os == null || os.isEmpty) && deviceModel != null) deviceModel,
    ].join(' ');
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: themed.surface,
        title: Text('Already signed in elsewhere', style: TextStyle(color: themed.text)),
        content: Text(
          label.isEmpty
              ? 'Your account is currently active on another browser. Continuing here will sign that one out.'
              : 'Your account is currently active on: $label. Continuing here will sign that device out.',
          style: TextStyle(color: themed.muted),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Log out that device & continue', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    ).then((value) => value ?? false);
  }

  /// Spec §12 mockup: another phone already owns this account's local chat
  /// storage. Login itself still succeeds either way — this only decides
  /// whether *this* device also starts writing chats locally.
  Future<void> _showMobileStorageConflictDialog(MobileStorageOwnerDevice other) async {
    final themed = ThemedColors.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: themed.surface,
        title: Text('Chat Storage In Use', style: TextStyle(color: themed.text)),
        content: Text(
          "This account's chat storage is currently active on another phone "
          '(${other.displayName}). You can keep using this device without local '
          'chat storage, or transfer it here.',
          style: TextStyle(color: themed.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Cancel', style: TextStyle(color: themed.muted)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              final success = await MobileStorageGate.transfer();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(success
                      ? 'Chat storage transferred to this device'
                      : 'Failed to transfer chat storage'),
                ));
              }
            },
            child: const Text('Transfer Chat Storage To This Phone'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final contentWidth = width > 520 ? 520.0 : width * 0.94;
    final themed = ThemedColors.of(context);
    return Scaffold(
      // No explicit backgroundColor — inherits Theme.of(context)
      // .scaffoldBackgroundColor, which is already theme-aware (see
      // AppTheme.lightTheme/darkTheme). Previously hardcoded to
      // AppColors.background (always dark), which is why this screen never
      // respected Light Mode.
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
                        Text('Connect with friends and share moments', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: themed.muted)),
                        const SizedBox(height: 22),
                        // Email/Username stays the existing single free-text
                        // field, completely unchanged (still resolves email
                        // vs username exactly as before). Phone is the new
                        // country-picker field — see PhoneNumberField's own
                        // doc comment for the full design (default India,
                        // Canada second, per-country validation, no way to
                        // double-enter the country code since the user only
                        // ever types the local digits).
                        SegmentTabs(
                          labels: const ['Email/Username', 'Phone'],
                          currentIndex: _loginMethod,
                          onChanged: (i) => setState(() => _loginMethod = i),
                        ),
                        const SizedBox(height: 12),
                        if (_loginMethod == 0)
                          CustomTextField(controller: _userCtrl, hintText: 'Email or Username', keyboardType: TextInputType.text)
                        else
                          PhoneNumberField(
                            controller: _phoneCtrl,
                            hintText: 'Phone number',
                            onValidityChanged: (valid) => setState(() => _phoneValid = valid),
                          ),
                        const SizedBox(height: 14),
                        CustomTextField(
                          controller: _passCtrl,
                          hintText: 'Password',
                          obscureText: _obscure,
                          suffix: IconButton(
                            icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: themed.muted),
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
