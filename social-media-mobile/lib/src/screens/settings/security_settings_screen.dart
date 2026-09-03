import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:social_chat_app/src/theme/colors.dart';
import 'account_identifiers_screen.dart';
import 'devices_screen.dart';
import 'mobile_storage_screen.dart';
import 'security_activity_screen.dart';
import 'two_factor_auth_screen.dart';

/// Settings → Security hub. Phase 1 shipped "Currently Logged-In Devices";
/// Phase 3 adds "Mobile Chat Storage" (mobile-only — it has nothing to show
/// on web, where local chat storage doesn't exist); Phase 6 adds "Two-Factor
/// Authentication" (configuration only — the login-time challenge is
/// Phase 7); Phase 8 adds "Security Activity" (the audit-trail viewer);
/// "Email & Phone" (post-Phase-10) lets a user who signed up with only one
/// identifier add the other — the backend has supported this since the
/// phone-signup work, this is just its first UI entry point.
class SecuritySettingsScreen extends StatelessWidget {
  /// True when shown as the detail pane of the desktop Settings
  /// index+detail split instead of pushed as its own route — hides the
  /// back arrow, which would have nothing to pop. Note: tiles below still
  /// push their destinations full-screen even when embedded (Devices, 2FA,
  /// etc. aren't part of the split) — a disclosed, intentionally scoped
  /// boundary, not a bug.
  final bool embedded;
  const SecuritySettingsScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: !embedded, title: const Text('Security')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildTile(
              context,
              leading: Icons.devices,
              title: 'Currently Logged-In Devices',
              subtitle: 'See and manage where you\'re signed in',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const DevicesScreen()),
                );
              },
            ),
            if (!kIsWeb) ...[
              const SizedBox(height: 12),
              _buildTile(
                context,
                leading: Icons.storage,
                title: 'Mobile Chat Storage',
                subtitle: 'See which phone is saving your chats locally',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const MobileStorageScreen()),
                  );
                },
              ),
            ],
            const SizedBox(height: 12),
            _buildTile(
              context,
              leading: Icons.alternate_email,
              title: 'Email & Phone',
              subtitle: 'Add a backup way to sign in and recover your account',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const AccountIdentifiersScreen()),
                );
              },
            ),
            const SizedBox(height: 12),
            _buildTile(
              context,
              leading: Icons.shield_outlined,
              title: 'Two-Factor Authentication',
              subtitle: 'Add an extra step when signing in',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const TwoFactorAuthScreen()),
                );
              },
            ),
            const SizedBox(height: 12),
            _buildTile(
              context,
              leading: Icons.history,
              title: 'Security Activity',
              subtitle: 'Recent logins, device and account changes',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const SecurityActivityScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTile(
    BuildContext context, {
    required IconData leading,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(leading, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(subtitle, style: TextStyle(color: AppColors.mutedSolid, fontSize: 13)),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
