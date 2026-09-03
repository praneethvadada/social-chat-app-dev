import 'package:flutter/material.dart';
import 'package:social_chat_app/src/theme/colors.dart';
import '../../models/two_factor_status.dart';
import '../../services/api_service.dart';

/// Settings → Security → "Two-Factor Authentication" (spec Phase 6 —
/// configuration only; the login-time challenge is Phase 7). Enabling or
/// switching method requires a fresh OTP to the target channel (proves
/// control of it right now); disabling requires the current password
/// instead (proves account ownership) — see TwoFactorAuthService's own doc
/// comment on the backend for the full reasoning.
class TwoFactorAuthScreen extends StatefulWidget {
  const TwoFactorAuthScreen({super.key});

  @override
  State<TwoFactorAuthScreen> createState() => _TwoFactorAuthScreenState();
}

class _TwoFactorAuthScreenState extends State<TwoFactorAuthScreen> {
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

  Future<void> _setUpOrChangeMethod(TwoFactorStatus status) async {
    final messenger = ScaffoldMessenger.of(context);
    final method = await _pickMethod(status);
    if (method == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await ApiService.sendTwoFactorOtp(method);
      if (!mounted) return;
      final otp = await _promptForOtp(method);
      if (otp == null || !mounted) return;

      if (status.enabled) {
        await ApiService.changeTwoFactorMethod(method: method, otp: otp);
      } else {
        await ApiService.enableTwoFactor(method: method, otp: otp);
      }
      messenger.showSnackBar(SnackBar(
        content: Text(status.enabled ? 'Two-factor method changed' : 'Two-factor authentication enabled'),
      ));
      await _refresh();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disable() async {
    final messenger = ScaffoldMessenger.of(context);
    final password = await _promptForPassword();
    if (password == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await ApiService.disableTwoFactor(password);
      messenger.showSnackBar(const SnackBar(content: Text('Two-factor authentication disabled')));
      await _refresh();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyError(Object e) => e.toString().replaceFirst('Exception: ', '');

  Future<String?> _pickMethod(TwoFactorStatus status) {
    final themed = ThemedColors.of(context);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: themed.surface,
        title: Text('Choose a method', style: TextStyle(color: themed.text)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MethodTile(
              icon: Icons.email_outlined,
              label: 'Email',
              subtitle: status.emailVerified ? status.maskedEmail : 'No verified email on this account',
              enabled: status.emailVerified,
              onTap: () => Navigator.of(dialogContext).pop('EMAIL'),
            ),
            const SizedBox(height: 8),
            _MethodTile(
              icon: Icons.phone_android,
              label: 'Phone',
              subtitle: status.phoneVerified ? status.maskedPhone : 'No verified phone on this account',
              enabled: status.phoneVerified,
              onTap: () => Navigator.of(dialogContext).pop('PHONE'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
        ],
      ),
    );
  }

  Future<String?> _promptForOtp(String method) {
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
            Text(
              method == 'EMAIL'
                  ? 'We sent a code to your email.'
                  : 'We sent a code to your phone.',
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

  Future<String?> _promptForPassword() {
    final controller = TextEditingController();
    final themed = ThemedColors.of(context);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: themed.surface,
        title: Text('Confirm your password', style: TextStyle(color: themed.text)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Turning off two-factor authentication requires your password.', style: TextStyle(color: themed.muted)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              style: TextStyle(color: themed.text),
              decoration: const InputDecoration(hintText: 'Password'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text('Turn Off', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Two-Factor Authentication')),
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
                Container(
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
                          color: status.enabled ? AppColors.success : AppColors.mutedSolid,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          status.enabled ? Icons.verified_user : Icons.gpp_maybe_outlined,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              status.enabled ? 'Two-factor authentication is on' : 'Two-factor authentication is off',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              status.enabled
                                  ? 'Via ${status.method == 'EMAIL' ? status.maskedEmail : status.maskedPhone}'
                                  : 'Add an extra step when signing in.',
                              style: TextStyle(color: AppColors.mutedSolid, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _busy ? null : () => _setUpOrChangeMethod(status),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(status.enabled ? 'Change method' : 'Set up two-factor authentication'),
                  ),
                ),
                if (status.enabled) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _busy ? null : _disable,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: BorderSide(color: AppColors.danger),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Turn off'),
                    ),
                  ),
                ],
                if (!status.emailVerified && !status.phoneVerified) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Verify an email or phone number on your account before setting up two-factor authentication.',
                    style: TextStyle(color: AppColors.mutedSolid, fontSize: 12),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool enabled;
  final VoidCallback onTap;

  const _MethodTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: enabled ? AppColors.primary : AppColors.mutedSolid),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: enabled ? null : AppColors.mutedSolid)),
                  if (subtitle != null)
                    Text(subtitle!, style: TextStyle(fontSize: 12, color: AppColors.mutedSolid)),
                ],
              ),
            ),
            if (enabled) const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
