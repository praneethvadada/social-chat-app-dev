import 'package:flutter/material.dart';
import 'package:social_chat_app/src/theme/colors.dart';
import '../../components/phone_number_field.dart';
import '../../models/two_factor_status.dart';
import '../../services/api_service.dart';

/// Settings → Security → "Email & Phone". Lets a user who signed up with
/// only one identifier (email XOR phone, enforced at registration) add the
/// other one afterward — both backend endpoints (POST /auth/send-otp +
/// POST /auth/email/link for email, POST /auth/phone/send-otp +
/// /verify-otp with purpose=PHONE_VERIFICATION for phone) have existed
/// since the phone-signup work, just with no UI ever calling them for this
/// purpose. Reuses GET /security/2fa's status response (TwoFactorStatus) —
/// it already carries exactly emailVerified/maskedEmail/phoneVerified/
/// maskedPhone, a settings-display shape, not a 2FA-specific one; see that
/// DTO's own doc comment.
class AccountIdentifiersScreen extends StatefulWidget {
  const AccountIdentifiersScreen({super.key});

  @override
  State<AccountIdentifiersScreen> createState() => _AccountIdentifiersScreenState();
}

class _AccountIdentifiersScreenState extends State<AccountIdentifiersScreen> {
  late Future<TwoFactorStatus> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = ApiService.getTwoFactorStatus();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = ApiService.getTwoFactorStatus();
    });
    await _future;
  }

  String _friendlyError(Object e) => e.toString().replaceFirst('Exception: ', '');

  // ---- Add email ----

  Future<void> _addEmail() async {
    final messenger = ScaffoldMessenger.of(context);
    final email = await _promptForValue(
      title: 'Add an email',
      hint: 'you@example.com',
      keyboardType: TextInputType.emailAddress,
    );
    if (email == null || email.isEmpty || !mounted) return;

    setState(() => _busy = true);
    try {
      // sendOtp throws on failure (pre-existing signup-flow contract,
      // unchanged here — same endpoint, same behavior either caller uses it for).
      await ApiService.sendOtp(email: email);
      if (!mounted) return;

      final otp = await _promptForOtp(sentTo: email);
      if (otp == null || otp.isEmpty || !mounted) return;

      final result = await ApiService.linkEmail(email: email, otp: otp);
      if (result['success'] != true) {
        messenger.showSnackBar(SnackBar(content: Text(result['message'] as String? ?? 'Failed to link email')));
        return;
      }
      messenger.showSnackBar(const SnackBar(content: Text('Email added to your account')));
      await _refresh();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- Add phone ----

  Future<void> _addPhone() async {
    final messenger = ScaffoldMessenger.of(context);
    final phone = await _promptForPhone();
    if (phone == null || phone.isEmpty || !mounted) return;

    setState(() => _busy = true);
    try {
      final sendResult = await ApiService.sendPhoneOtp(phoneNumber: phone, purpose: 'PHONE_VERIFICATION');
      if (sendResult['success'] != true) {
        messenger.showSnackBar(SnackBar(content: Text(sendResult['message'] as String? ?? 'Failed to send code')));
        return;
      }
      if (!mounted) return;

      final otp = await _promptForOtp(sentTo: phone);
      if (otp == null || otp.isEmpty || !mounted) return;

      final verifyResult = await ApiService.verifyPhoneOtp(phoneNumber: phone, otp: otp, purpose: 'PHONE_VERIFICATION');
      if (verifyResult['success'] != true) {
        messenger.showSnackBar(SnackBar(content: Text(verifyResult['message'] as String? ?? 'Failed to verify code')));
        return;
      }
      messenger.showSnackBar(const SnackBar(content: Text('Phone number added to your account')));
      await _refresh();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- Shared dialogs (mirror TwoFactorAuthScreen's own dialog style) ----

  Future<String?> _promptForValue({
    required String title,
    required String hint,
    required TextInputType keyboardType,
  }) {
    final controller = TextEditingController();
    final themed = ThemedColors.of(context);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: themed.surface,
        title: Text(title, style: TextStyle(color: themed.text)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: keyboardType,
          style: TextStyle(color: themed.text),
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Send Code'),
          ),
        ],
      ),
    );
  }

  /// Same shape as _promptForValue above, but with a proper country-code
  /// flag picker (defaults to India) instead of making the user type the
  /// whole "+91..." prefix by hand.
  Future<String?> _promptForPhone() {
    final controller = TextEditingController(); // holds the full E.164 value
    final themed = ThemedColors.of(context);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: themed.surface,
        title: Text('Add a phone number', style: TextStyle(color: themed.text)),
        content: PhoneNumberField(controller: controller, hintText: 'Phone number'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Send Code'),
          ),
        ],
      ),
    );
  }

  Future<String?> _promptForOtp({required String sentTo}) {
    final controller = TextEditingController();
    final themed = ThemedColors.of(context);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: themed.surface,
        title: Text('Enter the code', style: TextStyle(color: themed.text)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('We sent a code to $sentTo.', style: TextStyle(color: themed.muted)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              style: TextStyle(color: themed.text),
              decoration: const InputDecoration(hintText: 'Code'),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Email & Phone')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<TwoFactorStatus>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                children: [
                  const SizedBox(height: 80),
                  Center(child: Text('Failed to load status: ${snapshot.error}')),
                ],
              );
            }
            final status = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Add a backup way to sign in and recover your account.',
                  style: TextStyle(color: AppColors.mutedSolid, fontSize: 13),
                ),
                const SizedBox(height: 16),
                _IdentifierTile(
                  icon: Icons.email_outlined,
                  label: 'Email',
                  verified: status.emailVerified,
                  maskedValue: status.maskedEmail,
                  busy: _busy,
                  onAdd: _addEmail,
                ),
                const SizedBox(height: 12),
                _IdentifierTile(
                  icon: Icons.phone_android,
                  label: 'Phone',
                  verified: status.phoneVerified,
                  maskedValue: status.maskedPhone,
                  busy: _busy,
                  onAdd: _addPhone,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _IdentifierTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool verified;
  final String? maskedValue;
  final bool busy;
  final VoidCallback onAdd;

  const _IdentifierTile({
    required this.icon,
    required this.label,
    required this.verified,
    required this.maskedValue,
    required this.busy,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: verified ? AppColors.success : AppColors.mutedSolid,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 4),
                Text(
                  verified ? (maskedValue ?? 'Verified') : 'Not added yet',
                  style: TextStyle(color: AppColors.mutedSolid, fontSize: 13),
                ),
              ],
            ),
          ),
          if (verified)
            const Icon(Icons.check_circle, color: AppColors.success)
          else
            TextButton(
              onPressed: busy ? null : onAdd,
              child: const Text('Add'),
            ),
        ],
      ),
    );
  }
}
