import 'package:shared_preferences/shared_preferences.dart';

class BadgePrefs {
  static const String _notifKey = 'lastNotifVisit';
  static const String _followReqKey = 'lastFollowReqVisit';

  static Future<void> setLastNotifVisit(DateTime dt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_notifKey, dt.millisecondsSinceEpoch);
  }

  static Future<DateTime?> getLastNotifVisit() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_notifKey);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Future<void> setLastFollowReqVisit(DateTime dt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_followReqKey, dt.millisecondsSinceEpoch);
  }

  static Future<DateTime?> getLastFollowReqVisit() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_followReqKey);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }
}
