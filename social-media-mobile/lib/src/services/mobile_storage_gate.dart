import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/mobile_storage_status.dart';
import 'api_service.dart';
import '../database/database_helper.dart';

/// Phase 3: single-active-mobile-device local chat storage authorization.
/// Two entry points, matching the two places the spec calls out:
/// - [checkOnLogin] — interactive, fresh login/signup only. Auto-claims if
///   nobody owns it yet; returns the conflicting owner's info if someone
///   else does, so the caller can show the "chat storage is active on
///   another phone" prompt (spec §12) before deciding whether to run local
///   storage on this device.
/// - [silentCheck] — resumed session at app cold-start. No auto-claim, no
///   prompting (spec §18: "do not continuously show intrusive
///   notifications") — just reports current ownership so main.dart can
///   decide whether to run the local DB subsystem this session.
///
/// Both are no-ops on web (`null`/owner=false) — local storage is
/// mobile-only by design (spec §5), matching the backend's own
/// MOBILE_ONLY_FEATURE rejection.
class MobileStorageGate {
  /// Silent, non-destructive on uncertainty: null means "couldn't
  /// determine" (network/server error) — callers should leave existing
  /// local-storage behavior untouched rather than treat a transient
  /// failure as "not the owner" and wipe cached data over a blip.
  static Future<bool?> silentCheck() async {
    if (kIsWeb) return false;
    try {
      final status = await ApiService.getMobileStorageStatus();
      if (!status.isOwner) {
        await _clearLocalStorageIfPresent();
      }
      return status.isOwner;
    } catch (e) {
      print('[MobileStorageGate] Silent check failed (leaving state untouched): $e');
      return null;
    }
  }

  /// Interactive login/signup flow. Returns null on web or on error
  /// (caller proceeds as if unowned/no conflict — local storage simply
  /// won't be enabled this session, matching main.dart's existing
  /// SQLite-error-tolerant behavior). Auto-claims when there's no existing
  /// owner so the common single-device case needs no prompt at all.
  static Future<MobileStorageLoginResult> checkOnLogin() async {
    if (kIsWeb) return const MobileStorageLoginResult(isOwner: false, conflictWith: null);

    try {
      final status = await ApiService.getMobileStorageStatus();
      if (status.isOwner) {
        return const MobileStorageLoginResult(isOwner: true, conflictWith: null);
      }
      if (status.ownerDevice == null) {
        // Nobody owns it yet — the common case, first device on this account.
        final claimed = await ApiService.claimMobileStorage();
        return MobileStorageLoginResult(isOwner: claimed.isOwner, conflictWith: null);
      }
      // Someone else owns it — caller must ask the user before proceeding.
      return MobileStorageLoginResult(isOwner: false, conflictWith: status.ownerDevice);
    } catch (e) {
      print('[MobileStorageGate] Login check failed: $e');
      return const MobileStorageLoginResult(isOwner: false, conflictWith: null);
    }
  }

  /// User chose "Transfer Chat Storage To This Phone" on the conflict prompt.
  static Future<bool> transfer() async {
    try {
      final status = await ApiService.transferMobileStorage();
      return status.isOwner;
    } catch (e) {
      print('[MobileStorageGate] Transfer failed: $e');
      return false;
    }
  }

  /// Local chat data must not linger once this device is confirmed to no
  /// longer own storage — see the architecture plan's Q1 decision
  /// (immediate deletion, not retain-encrypted). No-op on web (nothing to
  /// clear there per Phase 2's kIsWeb guard).
  static Future<void> _clearLocalStorageIfPresent() async {
    if (kIsWeb) return;
    try {
      await DatabaseHelper().clearAll();
    } catch (e) {
      print('[MobileStorageGate] Failed to clear local storage after losing ownership: $e');
    }
  }
}

class MobileStorageLoginResult {
  final bool isOwner;
  final MobileStorageOwnerDevice? conflictWith;

  const MobileStorageLoginResult({required this.isOwner, required this.conflictWith});
}
