import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_search.dart';

class SearchUtils {
  static const _recentKey = 'recent_searches';

  /// Loads recent searches from local storage.
  static Future<List<String>> loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_recentKey) ?? [];
  }

  /// Saves recent searches to local storage.
  static Future<void> saveRecentSearches(List<String> searches) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentKey, searches);
  }

  /// Adds a search to recent searches, keeping only unique and latest 10.
  static Future<void> addRecentSearch(String query) async {
    final recent = await loadRecentSearches();
    recent.remove(query);
    recent.insert(0, query);
    if (recent.length > 10) recent.length = 10;
    await saveRecentSearches(recent);
  }

  /// Clears all recent searches.
  static Future<void> clearRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recentKey);
  }
}
