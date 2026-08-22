import '../models/user_profile.dart';
import 'api_service.dart';

class UserProfileCache {
  static final UserProfileCache _instance = UserProfileCache._internal();
  factory UserProfileCache() => _instance;
  UserProfileCache._internal();

  // In-memory cache of user profiles
  final Map<int, UserProfile> _cache = {};
  
  // In-flight requests to avoid duplicate API calls
  final Map<int, Future<UserProfile?>> _inFlightRequests = {};

  /// Get cached profile immediately if available, otherwise fetch
  Future<UserProfile?> getProfile(int userId) async {
    if (userId <= 0) return null;

    // Return immediately if cached
    if (_cache.containsKey(userId)) {
      print('[UserProfileCache] ✅ Returning CACHED profile for userId=$userId');
      return _cache[userId];
    }

    // If already fetching, return that future to avoid duplicate API calls
    if (_inFlightRequests.containsKey(userId)) {
      print('[UserProfileCache] 📡 Awaiting in-flight request for userId=$userId');
      return _inFlightRequests[userId];
    }

    // Start new fetch and cache the future
    print('[UserProfileCache] 🔄 Fetching profile for userId=$userId');
    final future = _fetchAndCache(userId);
    _inFlightRequests[userId] = future;
    
    try {
      final profile = await future;
      return profile;
    } finally {
      _inFlightRequests.remove(userId);
    }
  }

  /// Get profile immediately from cache without fetching
  UserProfile? getCachedOnly(int userId) {
    if (userId <= 0) return null;
    
    if (_cache.containsKey(userId)) {
      print('[UserProfileCache] ✅ getCachedOnly: Found cached profile for userId=$userId');
      return _cache[userId];
    }
    
    print('[UserProfileCache] ❌ getCachedOnly: No cached profile for userId=$userId');
    return null;
  }

  /// Pre-fetch and cache profile
  Future<UserProfile?> prefetchProfile(int userId) async {
    return getProfile(userId);
  }

  /// Internal method to fetch from API and cache
  Future<UserProfile?> _fetchAndCache(int userId) async {
    try {
      final data = await ApiService.getUserProfile(userId);
      final profile = UserProfile.fromJson(data);
      _cache[userId] = profile;
      print('[UserProfileCache] ✅ Cached profile for userId=$userId: ${profile.fullName}');
      return profile;
    } catch (e) {
      print('[UserProfileCache] ❌ Failed to fetch profile for userId=$userId: $e');
      return null;
    }
  }

  /// Manually cache a profile
  void setCached(int userId, UserProfile profile) {
    print('[UserProfileCache] 📌 Manually caching profile for userId=$userId: ${profile.fullName}');
    _cache[userId] = profile;
  }

  /// Clear cache
  void clearCache() {
    print('[UserProfileCache] 🗑️ Clearing all cached profiles');
    _cache.clear();
  }

  /// Clear specific user from cache
  void clearCacheForUser(int userId) {
    print('[UserProfileCache] 🗑️ Clearing cache for userId=$userId');
    _cache.remove(userId);
  }

  /// Get cache size
  int getCacheSize() => _cache.length;
}
