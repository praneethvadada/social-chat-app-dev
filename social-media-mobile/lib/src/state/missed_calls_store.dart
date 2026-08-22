import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/call_api.dart';
import '../services/call_signaling_service.dart';

/// Drives the badge on the Calls tab in the bottom navigation bar — the
/// count of calls missed by the current user since they last opened the
/// Calls tab. Purely client-local (a SharedPreferences "last viewed"
/// timestamp compared against GET /calls/history), no cross-device sync —
/// consistent with multi-device fan-out being out of scope for this pass.
class MissedCallsStore extends ChangeNotifier {
  static final MissedCallsStore _instance = MissedCallsStore._internal();
  factory MissedCallsStore() => _instance;
  MissedCallsStore._internal();

  static const _lastViewedKey = 'calls_tab_last_viewed_at';

  int _missedCount = 0;
  int get missedCount => _missedCount;
  bool get hasMissedCalls => _missedCount > 0;

  StreamSubscription? _historySub;
  bool _initialized = false;

  /// Call once at app startup — computes the initial count and subscribes
  /// to call-history-changed events so the badge stays live thereafter.
  void init() {
    if (_initialized) return;
    _initialized = true;
    refresh();
    _historySub = CallSignalingService().onCallHistoryUpdated.listen((_) => refresh());
  }

  Future<void> refresh() async {
    try {
      final myId = await ApiService.getUserId();
      if (myId == null) return;

      final prefs = await SharedPreferences.getInstance();
      final lastViewedMillis = prefs.getInt(_lastViewedKey) ?? 0;
      final lastViewed = DateTime.fromMillisecondsSinceEpoch(lastViewedMillis);

      final history = await CallApi.fetchCallHistory();
      final count = history.where((c) => c.isMissedBy(myId) && c.createdAt.isAfter(lastViewed)).length;

      if (count != _missedCount) {
        _missedCount = count;
        notifyListeners();
      }
    } catch (e) {
      print('[MissedCallsStore] refresh failed: $e');
    }
  }

  /// Call when the user opens the Calls tab — clears the badge.
  Future<void> markCallsTabViewed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastViewedKey, DateTime.now().millisecondsSinceEpoch);
    if (_missedCount != 0) {
      _missedCount = 0;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _historySub?.cancel();
    super.dispose();
  }
}
