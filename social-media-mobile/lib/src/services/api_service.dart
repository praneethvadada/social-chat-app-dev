// ...existing code...
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/post.dart';
import '../config/api_config.dart';
import '../models/message.dart';
import 'message_persistence_service.dart';

class ApiService {
  /// Delete a notification by its ID
  static Future<void> deleteNotification(String notificationId) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.delete(
      Uri.parse('$baseUrl/social/notifications/$notificationId'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      final message = _extractErrorMessage(response, 'Failed to delete notification');
      throw Exception(message);
    }
  }

    /// Send a mention notification to a user
    /// Send mention notifications to multiple users for a post
    static Future<void> sendMentionNotification({
      required List<int> mentionedUserIds,
      required int postId,
      required String postContent,
    }) async {
      final token = await getToken();
      if (token == null) throw Exception('Not authenticated');

      final response = await http.post(
        Uri.parse('$baseUrl/social/notifications/mention'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'mentionedUserIds': mentionedUserIds,
          'postId': postId,
          'postContent': postContent,
        }),
      );
      if (response.statusCode != 200 && response.statusCode != 201) {
        final message = _extractErrorMessage(response, 'Failed to send mention notification');
        throw Exception(message);
      }
    }
  // Use your computer's IP address instead of localhost for physical device testing
  static const String baseUrl = ApiConfig.baseUrl;
  static const String _tokenKey = 'accessToken';
  static const String _userIdKey = 'userId';
  static const String _usernameKey = 'username';
  static const String _emailKey = 'email';
  static const String _fullNameKey = 'fullName';

  static String _extractErrorMessage(http.Response response, String fallback) {
    try {
      if (response.body.isNotEmpty) {
        final decoded = json.decode(response.body);
        if (decoded is Map<String, dynamic>) {
          if (decoded['message'] is String && (decoded['message'] as String).isNotEmpty) {
            return decoded['message'] as String;
          }
          if (decoded['error'] is String && (decoded['error'] as String).isNotEmpty) {
            return decoded['error'] as String;
          }
          if (decoded['errors'] is List && (decoded['errors'] as List).isNotEmpty) {
            final first = (decoded['errors'] as List).first;
            if (first is String && first.isNotEmpty) return first;
          }
        }
        if (decoded is String && decoded.isNotEmpty) return decoded;
      }
    } catch (_) {
      // Ignore parse issues, fall back to provided message.
    }
    return fallback;
  }

  // Public wrapper for error extraction so other services can reuse it
  static String extractErrorMessage(http.Response response, String fallback) {
    return _extractErrorMessage(response, fallback);
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token != null) {
      print('[TOKEN RETRIEVED] ${token.substring(0, min(20, token.length))}...');
    } else {
      print('[TOKEN RETRIEVED] null');
    }
    return token;
  }

  static Future<void> setToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  static Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_userIdKey);
  }

  static Future<String?> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_usernameKey);
  }

  static Future<String?> getEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_emailKey);
  }

  static Future<String?> getFullName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_fullNameKey);
  }

  static Future<void> _setSession({required String token, required int userId, String? username, String? email, String? fullName}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setInt(_userIdKey, userId);
    if (username != null) await prefs.setString(_usernameKey, username);
    if (email != null) await prefs.setString(_emailKey, email);
    if (fullName != null) await prefs.setString(_fullNameKey, fullName);
  }
  
  static Future<void> updateStoredProfile({String? username, String? fullName}) async {
    final prefs = await SharedPreferences.getInstance();
    if (username != null) await prefs.setString(_usernameKey, username);
    if (fullName != null) await prefs.setString(_fullNameKey, fullName);
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = await getUserId();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_usernameKey);
    await prefs.remove(_emailKey);
    await prefs.remove(_fullNameKey);
    // Clear user-specific privacy settings
    if (userId != null) {
      await prefs.remove('isPrivate_$userId');
      await prefs.remove('showActivityStatus_$userId');
      await prefs.remove('showReadReceipts_$userId');
    }
    // Also clear old global keys for migration
    await prefs.remove('isPrivate');
    await prefs.remove('showActivityStatus');
    await prefs.remove('showReadReceipts');
  }

  static Future<bool> hasSession() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  /// ✅ NEW: Validate that stored token matches the authenticated user
  /// This prevents loading stale/friend's credentials after hot restart
  static Future<bool> validateStoredSession() async {
    try {
      final token = await getToken();
      final storedUserId = await getUserId();
      
      if (token == null || storedUserId == null) {
        print('[SESSION VALIDATION] No stored session');
        return false;
      }

      // Verify token is still valid by fetching current user profile
      print('[SESSION VALIDATION] Validating token for userId=$storedUserId...');
      final response = await http.get(
        Uri.parse('$baseUrl/social/profiles/me'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final currentUserId = data['userId'];
        
        // ✅ CRITICAL: Verify stored userId matches API response userId
        if (currentUserId == storedUserId) {
          print('[SESSION VALIDATION] ✅ Token valid for userId=$currentUserId');
          // Refresh the cached profile from this same response instead of
          // making a second call just to read username/fullName.
          await updateStoredProfile(
            username: data['username'] as String?,
            fullName: data['fullName'] as String?,
          );
          return true;
        } else {
          print('[SESSION VALIDATION] ❌ SECURITY: Token mismatch! Stored=$storedUserId, API=$currentUserId');
          print("[SESSION VALIDATION] 🔴 Clearing stale session (likely friend's credentials)");
          await clearSession();
          return false;
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        print('[SESSION VALIDATION] ❌ Token expired or invalid (status=${response.statusCode})');
        await clearSession();
        return false;
      } else {
        // Only 401/403 prove the token is bad. A 5xx or anything else means
        // the server is unhappy, not that we are logged out - keep the
        // session rather than throwing the user back to the login screen.
        print('[SESSION VALIDATION] ⚠️ Unexpected status: ${response.statusCode}'
              ' - keeping session');
        return true;
      }
    } catch (e) {
      print('[SESSION VALIDATION] ❌ Error validating session: $e');
      // On network error, assume session might be valid (user might be offline)
      return true;
    }
  }

  static Future<void> logout() async {
    final token = await getToken();
    final userId = await getUserId();

    print('[LOGOUT] Initiating logout for userId: $userId');
    
    if (token == null) {
      await clearSession();
      return;
    }

    final headers = {
      'Authorization': 'Bearer $token',
      if (userId != null) 'X-User-Id': userId.toString(),
    };

    try {
      await clearFCMToken();
      final response = await http.post(Uri.parse('$baseUrl/auth/logout'), headers: headers);
      if (response.statusCode >= 400) {
        // Swallow failures but still clear client session to avoid a stuck login state.
        print('[LOGOUT] Server logout returned ${response.statusCode}, but clearing local session');
      }
    } catch (e) {
      print('[LOGOUT] Network error during logout: $e');
    } finally {
      // Clear cached messages
      await MessagePersistenceService().clearAll();
      await clearSession();
      print('[LOGOUT] Local session and cached messages cleared');
    }
  }

  /// Clear FCM token on backend to stop push notifications after logout
  static Future<void> clearFCMToken() async {
    try {
      final authToken = await getToken();
      final userId = await getUserId();
      if (authToken == null || userId == null) {
        print('[API] ℹ️ Cannot clear FCM token (not authenticated or userId missing)');
        return;
      }

      final response = await http.post(
        Uri.parse('$baseUrl/auth/users/$userId/fcm-token'),
        headers: {
          'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({'fcmToken': ''}),
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        print('[API] ✅ FCM token cleared on backend');
      } else {
        print('[API] ⚠️ Failed to clear FCM token: ${response.statusCode}');
      }
    } catch (e) {
      print('[API] ❌ Error clearing FCM token: $e');
    }
  }

  static Future<List<Post>> getPosts() async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    print('\n========== FETCHING USER FEED ==========');  // ✅ CHANGED: Now fetching personal feed
    final response = await http.get(
      Uri.parse('$baseUrl/social/posts/feed?page=0&size=20'),  // ✅ CHANGED: Using /feed instead of /explore
      headers: {'Authorization': 'Bearer $token'},
    );

    print('Response Status: ${response.statusCode}');
    print('Response Body: ${response.body}');

    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);

      // Accept both Spring Page responses and bare lists.
      if (decoded is Map<String, dynamic> && decoded['content'] is List) {
        final List<dynamic> data = decoded['content'] as List;
        print('Found ${data.length} posts in feed Page response');  // ✅ CHANGED: Updated message
        return data.map((json) => Post.fromJson(json as Map<String, dynamic>)).toList();
      }

      if (decoded is List) {
        print('Found ${decoded.length} posts in feed List response');  // ✅ CHANGED: Updated message
        return decoded.map((json) => Post.fromJson(json as Map<String, dynamic>)).toList();
      }

      throw Exception('Unexpected feed response');  // ✅ CHANGED: Updated message
    }

    final message = _extractErrorMessage(response, 'Failed to load feed (code ${response.statusCode})');  // ✅ CHANGED: Updated message
    throw Exception(message);
  }

  // ✅ ADDED: Separate method for explore functionality (public posts from all users)
  static Future<List<Post>> getExplorePosts() async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    print('\n========== FETCHING EXPLORE POSTS ==========');
    final response = await http.get(
      Uri.parse('$baseUrl/social/posts/explore?page=0&size=20'),
      headers: {'Authorization': 'Bearer $token'},
    );

    print('Response Status: ${response.statusCode}');
    print('Response Body: ${response.body}');

    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);

      if (decoded is Map<String, dynamic> && decoded['content'] is List) {
        final List<dynamic> data = decoded['content'] as List;
        print('Found ${data.length} explore posts in Page response');
        return data.map((json) => Post.fromJson(json as Map<String, dynamic>)).toList();
      }

      if (decoded is List) {
        print('Found ${decoded.length} explore posts in List response');
        return decoded.map((json) => Post.fromJson(json as Map<String, dynamic>)).toList();
      }

      throw Exception('Unexpected explore response');
    }

    final message = _extractErrorMessage(response, 'Failed to load explore posts (code ${response.statusCode})');
    throw Exception(message);
  }

  /// Top hashtags across recent public posts, with post counts — computed
  /// live from post content (no dedicated hashtag table).
  static Future<List<Map<String, dynamic>>> getTrendingHashtags({int limit = 10}) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('$baseUrl/social/posts/hashtags/trending?limit=$limit'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final decoded = json.decode(response.body) as List;
      return decoded.cast<Map<String, dynamic>>();
    }
    final message = _extractErrorMessage(response, 'Failed to load trending hashtags');
    throw Exception(message);
  }

  static Future<List<Post>> getPostsByHashtag(String tag, {int page = 0, int size = 20}) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    final cleanTag = tag.replaceFirst('#', '');
    final response = await http.get(
      Uri.parse('$baseUrl/social/posts/hashtag/$cleanTag?page=$page&size=$size'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      final List<dynamic> data = decoded is Map<String, dynamic> && decoded['content'] is List
          ? decoded['content'] as List
          : (decoded is List ? decoded : const []);
      return data.map((json) => Post.fromJson(json as Map<String, dynamic>)).toList();
    }
    final message = _extractErrorMessage(response, 'Failed to load #$cleanTag posts');
    throw Exception(message);
  }

  /// Users you might want to follow (users you don't currently follow).
  static Future<List<Map<String, dynamic>>> getSuggestedUsers({int page = 0, int size = 20}) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('$baseUrl/social/profiles/suggested?page=$page&size=$size'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      final List<dynamic> data = decoded is Map<String, dynamic> && decoded['content'] is List
          ? decoded['content'] as List
          : (decoded is List ? decoded : const []);
      return data.cast<Map<String, dynamic>>();
    }
    final message = _extractErrorMessage(response, 'Failed to load suggested users');
    throw Exception(message);
  }

  static Future<String> uploadImage(String filePath) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    print('\n========== UPLOADING FILE ==========');
    print('File path: $filePath');

    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/social/files/upload'));
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(await http.MultipartFile.fromPath('file', filePath));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    print('Upload Status: ${response.statusCode}');
    print('Upload Response: ${response.body}');

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final fileUrl = data['fileUrl'] as String;
      print('File URL: $fileUrl');
      return fileUrl;
    }

    final message = _extractErrorMessage(response, 'Failed to upload file (code ${response.statusCode})');
    throw Exception(message);
  }

  // Generic uploader for any media type; reuses the same endpoint
  static Future<String> uploadMedia(String filePath) async {
    return uploadImage(filePath);
  }

  static Future<Post> createPost(String content, List<String> imageUrls, {String visibility = 'PUBLIC'}) async {
    final token = await getToken();
    print('[CREATE POST] Token: ${token?.substring(0, 20)}...');
    if (token == null) throw Exception('Not authenticated');

    print('[CREATE POST] 🔒 Creating post with visibility: $visibility');

    final requestBody = {
      'content': content.trim(),
      'imageUrls': imageUrls,
      'visibility': visibility,  // Backend will set isPublic based on visibility
    };
    
    print('[CREATE POST] 📤 Request body: ${json.encode(requestBody)}');

    final response = await http.post(
      Uri.parse('$baseUrl/social/posts'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode(requestBody),
    );

    print('[CREATE POST] 📥 Response status: ${response.statusCode}');
    print('[CREATE POST] 📥 Response body: ${response.body}');

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final post = Post.fromJson(data as Map<String, dynamic>);
      print('[CREATE POST] ✅ Created post with visibility: ${post.visibility}');
      return post;
    }

    final message = _extractErrorMessage(response, 'Failed to create post (code ${response.statusCode})');
    throw Exception(message);
  }

  static Future<Post> createPoll(
    String question,
    List<String> options, {
    String visibility = 'PUBLIC',
    int? correctOptionIndex,
  }) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    final requestBody = {
      'content': question.trim(),
      'postType': 'POLL',
      'pollOptions': options,
      'visibility': visibility,
      if (correctOptionIndex != null) 'correctOptionIndex': correctOptionIndex,
    };

    final response = await http.post(
      Uri.parse('$baseUrl/social/posts'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode(requestBody),
    );

    if (response.statusCode == 200) {
      return Post.fromJson(json.decode(response.body) as Map<String, dynamic>);
    }
    final message = _extractErrorMessage(response, 'Failed to create poll (code ${response.statusCode})');
    throw Exception(message);
  }

  static Future<Post> createEvent(
    String title, {
    required DateTime startTime,
    String? location,
    String visibility = 'PUBLIC',
  }) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    final requestBody = {
      'content': title.trim(),
      'postType': 'EVENT',
      'eventStartTime': startTime.toUtc().toIso8601String(),
      if (location != null && location.trim().isNotEmpty) 'eventLocation': location.trim(),
      'visibility': visibility,
    };

    final response = await http.post(
      Uri.parse('$baseUrl/social/posts'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode(requestBody),
    );

    if (response.statusCode == 200) {
      return Post.fromJson(json.decode(response.body) as Map<String, dynamic>);
    }
    final message = _extractErrorMessage(response, 'Failed to create event (code ${response.statusCode})');
    throw Exception(message);
  }

  static Future<Post> votePoll(int postId, int optionId) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.post(
      Uri.parse('$baseUrl/social/posts/$postId/vote'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({'optionId': optionId}),
    );

    if (response.statusCode == 200) {
      return Post.fromJson(json.decode(response.body) as Map<String, dynamic>);
    }
    final message = _extractErrorMessage(response, 'Failed to vote (code ${response.statusCode})');
    throw Exception(message);
  }

  static Future<Post> rsvpEvent(int postId, String status) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.post(
      Uri.parse('$baseUrl/social/posts/$postId/rsvp'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({'status': status}),
    );

    if (response.statusCode == 200) {
      return Post.fromJson(json.decode(response.body) as Map<String, dynamic>);
    }
    final message = _extractErrorMessage(response, 'Failed to RSVP (code ${response.statusCode})');
    throw Exception(message);
  }

  static Future<void> deletePost(int postId) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.delete(
      Uri.parse('$baseUrl/social/posts/$postId'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200 || response.statusCode == 204) {
      return;
    }

    final message = _extractErrorMessage(response, 'Failed to delete post (code ${response.statusCode})');
    throw Exception(message);
  }

  static Future<Post> updatePost(
    int postId, 
    String content, 
    List<String> imageUrls, 
    {String visibility = 'PUBLIC'}
  ) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.put(
      Uri.parse('$baseUrl/social/posts/$postId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'content': content.trim(),
        'imageUrls': imageUrls,
        'visibility': visibility,
      }),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return Post.fromJson(data as Map<String, dynamic>);
    }
    final message = _extractErrorMessage(response, 'Failed to update post (code ${response.statusCode})');
    throw Exception(message);
  }

  /// Fetch a single post by id
  static Future<Post> getPost(int postId) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    print('[GET POST] Fetching post $postId...');
    final response = await http.get(
      Uri.parse('$baseUrl/social/posts/$postId'),
      headers: {'Authorization': 'Bearer $token'},
    );

    print('[GET POST] Status: ${response.statusCode}');
    print('[GET POST] Body: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}...');
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      print('[GET POST] Parsed data - isLikedByCurrentUser: ${data['isLikedByCurrentUser']}, likesCount: ${data['likesCount']}');
      final post = Post.fromJson(data as Map<String, dynamic>);
      print('[GET POST] Post object - isLiked: ${post.isLiked}, likes: ${post.likes}');
      return post;
    }

    final message = _extractErrorMessage(response, 'Failed to load post');
    print('[GET POST] ❌ Error: $message');
    throw Exception(message);
  }

  static Future<Map<String, dynamic>> login(String emailOrUsername, String password) async {
    print('\n========== MOBILE APP LOGIN ==========');
    print('Email/Username: $emailOrUsername');

    // Anything email- or phone-shaped goes through the backend's unified
    // `identifier` field (resolves email vs E.164 phone, enforces the
    // verified-identifier check either way); anything else is treated as a
    // username exactly as before — zero change to existing username login.
    final trimmed = emailOrUsername.trim();
    final isEmail = trimmed.contains('@');
    final isPhoneLike = trimmed.startsWith('+');

    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        if (isEmail || isPhoneLike) 'identifier': trimmed else 'username': trimmed,
        'password': password,
      }),
    );

    print('Response Status: ${response.statusCode}');
    print('Response Body: ${response.body}');

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final accessToken = data['accessToken'];
      final userId = data['userId'];
      final username = data['username'];
      final userEmail = data['email'];
      final fullName = data['fullName'];
      
      print('\n[RESPONSE EXTRACTED]');
      print('userId: $userId');
      print('username: $username');
      print('email: $userEmail');
      print('fullName: $fullName');
      
      if (accessToken != null && userId != null) {
        print('\n[STORING IN SHAREDPREFERENCES]');
        await _setSession(
          token: accessToken,
          userId: userId is int ? userId : int.parse(userId.toString()),
          username: username,
          email: userEmail,
          fullName: fullName,
        );
        print('Stored successfully');
      }
      return data;
    } else {
      final fallback = (response.statusCode == 401 || response.statusCode == 403 || response.statusCode == 400)
          ? 'Invalid email or password'
          : 'Login failed (code ${response.statusCode})';
      final message = _extractErrorMessage(response, fallback);
      throw Exception(message);
    }
  }

  /// Provide exactly one of [email] or [phoneNumber] — matches the backend's
  /// XOR signup requirement. Whichever you pass must already be OTP-verified
  /// (see sendOtp/verifyOtp for email, sendPhoneOtp/verifyPhoneOtp for phone)
  /// or the backend rejects the request with VERIFICATION_REQUIRED.
  static Future<Map<String, dynamic>> register({
    required String username,
    required String password,
    required String fullName,
    String? email,
    String? phoneNumber,
  }) async {
    assert((email != null) != (phoneNumber != null), 'Provide exactly one of email or phoneNumber');
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'username': username,
        if (email != null) 'email': email,
        if (phoneNumber != null) 'phoneNumber': phoneNumber,
        'password': password,
        'fullName': fullName,
      }),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final accessToken = data['accessToken'];
      final userId = data['userId'];
      final username = data['username'];
      final userEmail = data['email'];
      final userFullName = data['fullName'];
      if (accessToken != null && userId != null) {
        await _setSession(
          token: accessToken,
          userId: userId is int ? userId : int.parse(userId.toString()),
          username: username,
          email: userEmail,
          fullName: userFullName,
        );
      }
      return data;
    } else {
      String fallback;
      if (response.statusCode == 409) {
        fallback = 'Account already exists';
      } else if (response.statusCode == 400) {
        fallback = 'Invalid signup details, please check your info';
      } else {
        fallback = 'Signup failed (code ${response.statusCode})';
      }
      final message = _extractErrorMessage(response, fallback);
      throw Exception(message);
    }
  }

  /// Check if email and username are available
  static Future<Map<String, dynamic>> checkAvailability({String? email, String? username}) async {
    final Map<String, dynamic> params = {};
    if (email != null) params['email'] = email;
    if (username != null) params['username'] = username;
    
    final uri = Uri.parse('$baseUrl/auth/check-availability').replace(queryParameters: params);
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      // If endpoint doesn't exist, return empty result (fallback for older backend versions)
      return {'emailExists': false, 'usernameExists': false};
    }
  }

  /// Send OTP to email for verification
  static Future<Map<String, dynamic>> sendOtp({required String email}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/send-otp'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': email}),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      String fallback = 'Failed to send OTP';
      if (response.statusCode == 400) {
        fallback = 'Invalid email address';
      } else if (response.statusCode == 429) {
        fallback = 'Too many OTP requests. Please try again later';
      }
      final message = _extractErrorMessage(response, fallback);
      throw Exception(message);
    }
  }

  /// Verify OTP code
  static Future<Map<String, dynamic>> verifyOtp({
    required String email,
    required String otp,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/verify-otp'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'email': email,
        'otp': otp,
      }),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      String fallback = 'OTP verification failed';
      if (response.statusCode == 400) {
        fallback = 'Invalid or expired OTP';
      } else if (response.statusCode == 404) {
        fallback = 'OTP not found. Please request a new one';
      }
      final message = _extractErrorMessage(response, fallback);
      return {'success': false, 'message': message};
    }
  }

  /// Resend OTP to email
  static Future<Map<String, dynamic>> resendOtp({required String email}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/resend-otp'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': email}),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      String fallback = 'Failed to resend OTP';
      if (response.statusCode == 429) {
        fallback = 'Too many requests. Please try again later';
      }
      final message = _extractErrorMessage(response, fallback);
      throw Exception(message);
    }
  }

  /// Content-Type, plus Authorization if a session token exists. The phone
  /// OTP endpoints below are path-shared between an unauthenticated purpose
  /// (PHONE_SIGNUP, used during signup — no token exists yet) and an
  /// authenticated one (PHONE_VERIFICATION, for linking a phone to an
  /// already-logged-in account) — this lets one set of methods serve both
  /// without the caller needing to build headers itself.
  static Future<Map<String, String>> _authHeadersOptional() async {
    final headers = {'Content-Type': 'application/json'};
    final token = await getToken();
    if (token != null) headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  /// Send an OTP to a phone number. purpose is 'PHONE_SIGNUP' (pre-registration,
  /// no auth needed) or 'PHONE_VERIFICATION' (linking to an already-logged-in
  /// account, requires a Bearer token — sent automatically if one exists,
  /// see _authHeadersOptional above).
  static Future<Map<String, dynamic>> sendPhoneOtp({required String phoneNumber, required String purpose}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/phone/send-otp'),
      headers: await _authHeadersOptional(),
      body: json.encode({'phoneNumber': phoneNumber, 'purpose': purpose}),
    );

    if (response.statusCode == 200) {
      return {'success': true, ...json.decode(response.body) as Map<String, dynamic>};
    } else {
      String fallback = 'Failed to send OTP';
      if (response.statusCode == 400) {
        fallback = 'Invalid phone number';
      } else if (response.statusCode == 409) {
        fallback = 'This phone number is already registered';
      } else if (response.statusCode == 429) {
        fallback = 'Too many OTP requests. Please try again later';
      }
      final message = _extractErrorMessage(response, fallback);
      return {'success': false, 'message': message};
    }
  }

  /// Verify a phone OTP code. See sendPhoneOtp for `purpose`.
  static Future<Map<String, dynamic>> verifyPhoneOtp({
    required String phoneNumber,
    required String otp,
    required String purpose,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/phone/verify-otp'),
      headers: await _authHeadersOptional(),
      body: json.encode({'phoneNumber': phoneNumber, 'otp': otp, 'purpose': purpose}),
    );

    if (response.statusCode == 200) {
      return {'success': true, ...json.decode(response.body) as Map<String, dynamic>};
    } else {
      String fallback = 'OTP verification failed';
      if (response.statusCode == 400) {
        fallback = 'Invalid or expired OTP';
      }
      final message = _extractErrorMessage(response, fallback);
      return {'success': false, 'message': message};
    }
  }

  /// Resend a phone OTP. See sendPhoneOtp for `purpose`.
  static Future<Map<String, dynamic>> resendPhoneOtp({required String phoneNumber, required String purpose}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/phone/resend-otp'),
      headers: await _authHeadersOptional(),
      body: json.encode({'phoneNumber': phoneNumber, 'purpose': purpose}),
    );

    if (response.statusCode == 200) {
      return {'success': true, ...json.decode(response.body) as Map<String, dynamic>};
    } else {
      String fallback = 'Failed to resend OTP';
      if (response.statusCode == 429) {
        fallback = 'Too many requests. Please try again later';
      }
      final message = _extractErrorMessage(response, fallback);
      return {'success': false, 'message': message};
    }
  }

  /// Request password reset OTP
  static Future<Map<String, dynamic>> requestPasswordReset(String email) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/password-reset/request'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': email}),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      String fallback = 'Failed to send reset code';
      if (response.statusCode == 404) {
        fallback = 'Email not found';
      } else if (response.statusCode == 400) {
        fallback = 'Invalid email address';
      }
      final message = _extractErrorMessage(response, fallback);
      throw Exception(message);
    }
  }

  /// Verify password reset OTP
  static Future<Map<String, dynamic>> verifyPasswordResetOtp({
    required String email,
    required String otp,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/password-reset/verify-otp'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'email': email,
        'otp': otp,
      }),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      String fallback = 'OTP verification failed';
      if (response.statusCode == 400) {
        fallback = 'Invalid or expired OTP';
      } else if (response.statusCode == 404) {
        fallback = 'OTP not found. Please request a new one';
      }
      final message = _extractErrorMessage(response, fallback);
      return {'success': false, 'message': message};
    }
  }

  /// Reset password with email and new password
  static Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String newPassword,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/password-reset/reset'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'email': email,
        'newPassword': newPassword,
      }),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      String fallback = 'Failed to reset password';
      if (response.statusCode == 400) {
        fallback = 'Password reset session expired. Please start over';
      } else if (response.statusCode == 404) {
        fallback = 'Reset session not found';
      }
      final message = _extractErrorMessage(response, fallback);
      throw Exception(message);
    }
  }

  /// Resend password reset OTP
  static Future<Map<String, dynamic>> resendPasswordResetOtp(String email) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/password-reset/resend-otp'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': email}),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      String fallback = 'Failed to resend OTP';
      if (response.statusCode == 429) {
        fallback = 'Too many requests. Please try again later';
      }
      final message = _extractErrorMessage(response, fallback);
      throw Exception(message);
    }
  }

  /// Delete user account
  static Future<void> deleteAccount(String password) async {
    final email = await getEmail();
    if (email == null) throw Exception('Email not found');

    // 🔴 FIX: Include JWT token in Authorization header
    final token = await getToken();
    final headers = {
      'Content-Type': 'application/json',
    };
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    final response = await http.delete(
      Uri.parse('$baseUrl/auth/account'),
      headers: headers,
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );

    if (response.statusCode == 200) {
      // Clear local storage after successful deletion
      await clearSession();
      return;
    } else if (response.statusCode == 401) {
      throw Exception('Invalid password');
    } else if (response.statusCode == 404) {
      throw Exception('User not found');
    } else {
      final body = response.body;
      try {
        final json = jsonDecode(body);
        final message = json['error'] ?? json['message'] ?? 'Failed to delete account';
        throw Exception(message);
      } catch (e) {
        throw Exception('Failed to delete account');
      }
    }
  }

  static Future<Map<String, dynamic>> getMyProfile() async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    print('\n========== MOBILE APP GETMYPROFILE ==========');
    print('Calling: $baseUrl/social/profiles/me');
    
    final response = await http.get(
      Uri.parse('$baseUrl/social/profiles/me'),
      headers: {'Authorization': 'Bearer $token'},
    );

    print('Response Status: ${response.statusCode}');
    print('Response Body: ${response.body}');

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      print('\n[PROFILE FETCHED]');
      print('userId: ${data['userId']}');
      print('username: ${data['username']}');
      print('email: ${data['email']}');
      print('fullName: ${data['fullName']}');
      print('isPrivate: ${data['isPrivate']}');
      return data;
    } else {
      final message = _extractErrorMessage(response, 'Failed to load profile');
      throw Exception(message);
    }
  }

  static Future<Map<String, dynamic>> updateMyProfile({
    String? username,
    String? fullName,
    String? bio,
    String? profilePictureUrl,
    String? coverPhotoUrl,
    String? location,
    String? website,
    bool? isPrivate,
    bool? showReadReceipts,
    bool? showActivityStatus,
  }) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    final body = <String, dynamic>{};
    if (username != null) body['username'] = username;
    if (fullName != null) body['fullName'] = fullName;
    if (bio != null) body['bio'] = bio;
    if (profilePictureUrl != null) body['profilePictureUrl'] = profilePictureUrl;
    if (coverPhotoUrl != null) body['coverPhotoUrl'] = coverPhotoUrl;
    if (location != null) body['location'] = location;
    if (website != null) body['website'] = website;
    if (isPrivate != null) body['isPrivate'] = isPrivate;
    if (showReadReceipts != null) body['showReadReceipts'] = showReadReceipts;
    if (showActivityStatus != null) body['showActivityStatus'] = showActivityStatus;

    print('\n========== UPDATE MY PROFILE ==========');
    print('Calling: $baseUrl/social/profiles/me');
    print('Request Body: ${json.encode(body)}');
    print('Token: ${token.substring(0, 20)}...');

    final response = await http.put(
      Uri.parse('$baseUrl/social/profiles/me'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode(body),
    );

    print('Response Status: ${response.statusCode}');
    print('Response Body: ${response.body}');

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      print('[PROFILE UPDATE SUCCESS]');
      print('Updated username: ${data['username']}');
      print('Updated fullName: ${data['fullName']}');
      return data;
    } else {
      final message = _extractErrorMessage(response, 'Failed to update profile');
      throw Exception(message);
    }
  }

  static Future<List<Post>> getUserPosts(int userId) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    print('\n========== FETCHING USER POSTS ==========');
    final response = await http.get(
      Uri.parse('$baseUrl/social/posts/user/$userId?page=0&size=50'),
      headers: {'Authorization': 'Bearer $token'},
    );

    print('Response Status: ${response.statusCode}');
    print('Response Body: ${response.body}');

    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);

      if (decoded is Map<String, dynamic> && decoded['content'] is List) {
        final List<dynamic> data = decoded['content'] as List;
        print('Found ${data.length} user posts in Page response');
        return data.map((json) => Post.fromJson(json as Map<String, dynamic>)).toList();
      }

      if (decoded is List) {
        print('Found ${decoded.length} user posts in List response');
        return decoded.map((json) => Post.fromJson(json as Map<String, dynamic>)).toList();
      }

      throw Exception('Unexpected user posts response');
    }

    final message = _extractErrorMessage(response, 'Failed to load user posts (code ${response.statusCode})');
    throw Exception(message);
  }

  static Future<List<Post>> getSavedPosts() async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    print('\n========== FETCHING SAVED POSTS ==========');
    final response = await http.get(
      Uri.parse('$baseUrl/social/saves?page=0&size=50'),
      headers: {'Authorization': 'Bearer $token'},
    );

    print('Response Status: ${response.statusCode}');
    print('Response Body: ${response.body}');

    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);

      if (decoded is Map<String, dynamic> && decoded['content'] is List) {
        final List<dynamic> data = decoded['content'] as List;
        print('Found ${data.length} saved posts in Page response');
        return data.map((json) => Post.fromJson(json as Map<String, dynamic>)).toList();
      }

      if (decoded is List) {
        print('Found ${decoded.length} saved posts in List response');
        return decoded.map((json) => Post.fromJson(json as Map<String, dynamic>)).toList();
      }

      throw Exception('Unexpected saved posts response');
    }

    final message = _extractErrorMessage(response, 'Failed to load saved posts (code ${response.statusCode})');
    throw Exception(message);
  }

  static Future<Map<String, dynamic>> getUserProfile(int userId) async {
    // Guard against invalid userId
    if (userId <= 0) {
      print('[ApiService] ⚠️ Invalid userId: $userId - skipping profile fetch');
      throw Exception('Invalid userId: $userId');
    }
    
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    print('\n========== FETCHING USER PROFILE ==========');
    print('userId: $userId');
    
    final response = await http.get(
      Uri.parse('$baseUrl/social/profiles/user/$userId'),
      headers: {'Authorization': 'Bearer $token'},
    );

    print('Response Status: ${response.statusCode}');
    print('Response Body: ${response.body}');

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      print('Profile fetched: ${data['fullName']}');
      print('isPrivate: ${data['isPrivate']}');
      print('isFollowing: ${data['isFollowing']}');
      return data;
    } else {
      final message = _extractErrorMessage(response, 'Failed to load user profile');
      throw Exception(message);
    }
  }

  static Future<void> followUser(int userId) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.post(
      Uri.parse('$baseUrl/social/followers/$userId'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      final message = _extractErrorMessage(response, 'Failed to follow user');
      throw Exception(message);
    }
  }

  /// Send a follow request to the given user. Backend should create a
  /// follow-request entry that the target user can accept/decline.
  static Future<void> sendFollowRequest(int userId) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.post(
      Uri.parse('$baseUrl/social/follow-requests/$userId'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      final message = _extractErrorMessage(response, 'Failed to send follow request');
      throw Exception(message);
    }
  }

  /// Check if current user has a pending follow request to the given user
  static Future<bool> hasFollowRequest(int userId) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/social/follow-requests/check/$userId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('[FOLLOW REQUEST CHECK] userId: $userId, hasRequest: ${data['hasPendingRequest'] ?? data == true}');
        return data['hasPendingRequest'] == true || data == true;
      }
      return false;
    } catch (e) {
      print('[FOLLOW REQUEST CHECK ERROR] $e');
      return false;
    }
  }

  /// Get incoming follow requests for current authenticated user.
  static Future<List<Map<String, dynamic>>> getFollowRequests() async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('$baseUrl/social/follow-requests'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data is List) return data.cast<Map<String, dynamic>>();
      if (data is Map && data.containsKey('content')) return (data['content'] as List).cast<Map<String, dynamic>>();
      return [];
    }
    final message = _extractErrorMessage(response, 'Failed to load follow requests');
    throw Exception(message);
  }

  /// Respond to a follow request. If [accept] is true, the requester should
  /// become a follower; otherwise the request is declined/removed.
  static Future<void> respondFollowRequest(int requestId, bool accept) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    final action = accept ? 'accept' : 'decline';
    final response = await http.post(
      Uri.parse('$baseUrl/social/follow-requests/$requestId/$action'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      final message = _extractErrorMessage(response, 'Failed to respond to follow request');
      throw Exception(message);
    }
  }

  static Future<void> unfollowUser(int userId) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.delete(
      Uri.parse('$baseUrl/social/followers/$userId'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      final message = _extractErrorMessage(response, 'Failed to unfollow user');
      throw Exception(message);
    }
  }

  static Future<bool> checkFollowStatus(int userId) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('$baseUrl/social/followers/check/$userId'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['isFollowing'] == true || data == true;
    }
    return false;
  }

  static Future<List<Map<String, dynamic>>> getFollowers(int userId) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('$baseUrl/social/followers/user/$userId'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data is Map && data.containsKey('content')) {
        final content = data['content'] as List;
        return content.cast<Map<String, dynamic>>();
      }
      if (data is List) {
        return data.cast<Map<String, dynamic>>();
      }
      throw Exception('Unexpected response format');
    } else {
      final message = _extractErrorMessage(response, 'Failed to load followers');
      throw Exception(message);
    }
  }

  static Future<List<Map<String, dynamic>>> getFollowing(int userId) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('$baseUrl/social/followers/user/$userId/following'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data is Map && data.containsKey('content')) {
        final content = data['content'] as List;
        return content.cast<Map<String, dynamic>>();
      }
      if (data is List) {
        return data.cast<Map<String, dynamic>>();
      }
      throw Exception('Unexpected response format');
    } else {
      final message = _extractErrorMessage(response, 'Failed to load following');
      throw Exception(message);
    }
  }

  /// Get persisted notifications for the current user
  static Future<List<Map<String, dynamic>>> getNotifications({int page = 0, int size = 50}) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('$baseUrl/social/notifications?page=$page&size=$size'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data is Map && data.containsKey('content')) {
        return (data['content'] as List).cast<Map<String, dynamic>>();
      }
      if (data is List) return data.cast<Map<String, dynamic>>();
      return [];
    }

    final message = _extractErrorMessage(response, 'Failed to load notifications');
    throw Exception(message);
  }

  static Future<List<Conversation>> getConversations() async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('$baseUrl/social/messages/conversations'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      List<dynamic> conversations = [];
      
      if (data is Map && data.containsKey('content')) {
        conversations = data['content'] as List;
      } else if (data is List) {
        conversations = data;
      } else {
        throw Exception('Unexpected response format');
      }
      
      return conversations
          .map((json) => Conversation.fromJson(json as Map<String, dynamic>))
          .toList();
    } else {
      final message = _extractErrorMessage(response, 'Failed to load conversations');
      throw Exception(message);
    }
  }

  static Future<List<Map<String, dynamic>>> getConversation(int otherUserId, {int page = 0, int size = 50}) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('$baseUrl/social/messages/conversation/$otherUserId?page=$page&size=$size'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data is Map && data.containsKey('content')) {
        final content = data['content'] as List;
        return content.cast<Map<String, dynamic>>();
      }
      if (data is List) {
        return data.cast<Map<String, dynamic>>();
      }
      throw Exception('Unexpected response format');
    } else {
      final message = _extractErrorMessage(response, 'Failed to load conversation');
      throw Exception(message);
    }
  }

  /// Get unread message count for a specific conversation from server
  /// Used as fallback when local data is not available
  static Future<int> getUnreadCountForConversation(int otherUserId) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/social/messages/conversation/$otherUserId/unread-count'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // Handle both direct int and wrapped response
        if (data is int) {
          return data;
        }
        if (data is Map && data.containsKey('count')) {
          return data['count'] as int? ?? 0;
        }
        if (data is Map && data.containsKey('unreadCount')) {
          return data['unreadCount'] as int? ?? 0;
        }
        return 0;
      } else {
        print('[API] Failed to get unread count: ${response.statusCode}');
        return 0;
      }
    } catch (e) {
      print('[API] Error getting unread count: $e');
      return 0;
    }
  }

  /// Send a direct message. When [replyToStatusId] is set the DM carries a
  /// snapshot reference to the status being replied to (S3) - a snapshot, not
  /// a live link, because statuses expire after 24h and live in another service.
  static Future<Map<String, dynamic>> sendMessage(int recipientId, String content,
      {String? mediaUrl,
      int? replyToStatusId,
      String? replyToStatusType,
      String? replyToStatusPreview,
      String? statusReaction}) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    // Prevent sending messages to self
    final myUserId = await getUserId();
    if (myUserId != null && myUserId == recipientId) {
      throw Exception('You cannot send messages to yourself');
    }

    final response = await http.post(
      Uri.parse('$baseUrl/social/messages'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'receiverId': recipientId,
        'content': content,
        if (mediaUrl != null) 'mediaUrl': mediaUrl,
        if (replyToStatusId != null) 'replyToStatusId': replyToStatusId,
        if (replyToStatusType != null) 'replyToStatusType': replyToStatusType,
        if (replyToStatusPreview != null)
          'replyToStatusPreview': replyToStatusPreview,
        if (statusReaction != null) 'statusReaction': statusReaction,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return json.decode(response.body);
    } else {
      final message = _extractErrorMessage(response, 'Failed to send message');
      throw Exception(message);
    }
  }

  static Future<void> markConversationAsRead(int otherUserId) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.put(
      Uri.parse('$baseUrl/social/messages/conversation/$otherUserId/read'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      final message = _extractErrorMessage(response, 'Failed to mark messages as read');
      throw Exception(message);
    }
  }

  static Future<void> markMessageAsRead(int messageId) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.put(
      Uri.parse('$baseUrl/social/messages/$messageId/read'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      final message = _extractErrorMessage(response, 'Failed to mark message as read');
      throw Exception(message);
    }
  }

  static Future<List<Map<String, dynamic>>> searchUsers(String query, {int page = 0, int size = 20}) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('$baseUrl/social/profiles/search?query=$query&page=$page&size=$size'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      List<dynamic> users = [];
      
      if (data is Map && data.containsKey('content')) {
        users = data['content'] as List;
      } else if (data is List) {
        users = data;
      } else {
        throw Exception('Unexpected response format');
      }
      
      return users.cast<Map<String, dynamic>>();
    } else {
      final message = _extractErrorMessage(response, 'Failed to search users');
      throw Exception(message);
    }
  }

  static Future<Map<String, dynamic>> startNewChat(int recipientId, String firstMessage, {String? mediaUrl}) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    // Prevent starting a chat with self
    final myUserId = await getUserId();
    if (myUserId != null && myUserId == recipientId) {
      throw Exception('You cannot start a chat with yourself');
    }

    final response = await http.post(
      Uri.parse('$baseUrl/social/messages'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'receiverId': recipientId,
        'content': firstMessage,
        if (mediaUrl != null) 'mediaUrl': mediaUrl,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return json.decode(response.body);
    } else {
      final message = _extractErrorMessage(response, 'Failed to start chat');
      throw Exception(message);
    }
  }

  static Future<void> deleteConversation(int otherUserId) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.delete(
      Uri.parse('$baseUrl/social/messages/conversation/$otherUserId'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      final message = _extractErrorMessage(response, 'Failed to delete conversation');
      throw Exception(message);
    }
  }

  // ===================== CLOSE FRIENDS =====================

  static Future<List<Map<String, dynamic>>> getCloseFriends() async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    final url = '$baseUrl/social/close-friends';
    print('[CLOSE_FRIENDS] GET URL: $url');
    print('[CLOSE_FRIENDS] Token present: ${token.isNotEmpty}');

    final response = await http.get(
      Uri.parse(url),
      headers: {'Authorization': 'Bearer $token'},
    );

    print('[CLOSE_FRIENDS] GET Status: ${response.statusCode}');
    print('[CLOSE_FRIENDS] GET Response: ${response.body}');

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((item) => item as Map<String, dynamic>).toList();
    } else {
      final message = _extractErrorMessage(response, 'Failed to load close friends');
      print('[CLOSE_FRIENDS] GET Error: $message');
      throw Exception(message);
    }
  }

  static Future<void> addCloseFriend(int userId) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    print('[CLOSE_FRIENDS] Adding close friend: $userId');
    print('[CLOSE_FRIENDS] URL: $baseUrl/social/close-friends/$userId');

    final response = await http.post(
      Uri.parse('$baseUrl/social/close-friends/$userId'),
      headers: {'Authorization': 'Bearer $token'},
    );

    print('[CLOSE_FRIENDS] Response status: ${response.statusCode}');
    print('[CLOSE_FRIENDS] Response body: ${response.body}');

    if (response.statusCode != 200) {
      final message = _extractErrorMessage(response, 'Failed to add close friend');
      throw Exception(message);
    }
  }

  static Future<void> removeCloseFriend(int userId) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.delete(
      Uri.parse('$baseUrl/social/close-friends/$userId'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200) {
      final message = _extractErrorMessage(response, 'Failed to remove close friend');
      throw Exception(message);
    }
  }

  static Future<bool> isCloseFriend(int userId) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('$baseUrl/social/close-friends/check/$userId'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['isCloseFriend'] as bool? ?? false;
    } else {
      final message = _extractErrorMessage(response, 'Failed to check close friend status');
      throw Exception(message);
    }
  }

  static Future<int> getCloseFriendsCount() async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('$baseUrl/social/close-friends/count'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['count'] as int? ?? 0;
    } else {
      final message = _extractErrorMessage(response, 'Failed to get close friends count');
      throw Exception(message);
    }
  }

  // ==================== BLOCK USER METHODS ====================

  static Future<void> blockUser(int userId, {String? reason}) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    print('\n========== BLOCKING USER ==========');
    print('userId: $userId');
    
    final body = reason != null ? {'reason': reason} : null;
    
    final response = await http.post(
      Uri.parse('$baseUrl/social/blocks/$userId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: body != null ? json.encode(body) : null,
    );

    print('Response Status: ${response.statusCode}');
    
    if (response.statusCode == 200) {
      print('User blocked successfully');
    } else {
      final message = _extractErrorMessage(response, 'Failed to block user');
      throw Exception(message);
    }
  }

  static Future<void> unblockUser(int userId) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    print('\n========== UNBLOCKING USER ==========');
    print('userId: $userId');
    
    final response = await http.delete(
      Uri.parse('$baseUrl/social/blocks/$userId'),
      headers: {'Authorization': 'Bearer $token'},
    );

    print('Response Status: ${response.statusCode}');
    
    if (response.statusCode == 200) {
      print('User unblocked successfully');
    } else {
      final message = _extractErrorMessage(response, 'Failed to unblock user');
      throw Exception(message);
    }
  }

  static Future<bool> isBlocked(int userId) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('$baseUrl/social/blocks/check/$userId'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['isBlocked'] as bool? ?? false;
    } else {
      final message = _extractErrorMessage(response, 'Failed to check block status');
      throw Exception(message);
    }
  }

  static Future<List<Map<String, dynamic>>> getBlockedUsers({int page = 0, int size = 20}) async {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');

    print('\n========== FETCHING BLOCKED USERS ==========');
    
    final response = await http.get(
      Uri.parse('$baseUrl/social/blocks/my-list?page=$page&size=$size'),
      headers: {'Authorization': 'Bearer $token'},
    );

    print('Response Status: ${response.statusCode}');
    
    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      
      if (decoded is Map<String, dynamic> && decoded['content'] is List) {
        final List<dynamic> data = decoded['content'] as List;
        print('Found ${data.length} blocked users');
        return data.map((e) => e as Map<String, dynamic>).toList();
      }
      
      if (decoded is List) {
        return decoded.map((e) => e as Map<String, dynamic>).toList();
      }
      
      throw Exception('Unexpected blocked users response');
    }
    
    final message = _extractErrorMessage(response, 'Failed to load blocked users');
    throw Exception(message);
  }

  /// Save FCM token to backend for push notifications
  static Future<void> saveFCMToken(String token) async {
    try {
      print('[API] DEBUG: saveFCMToken() called with token length: ${token.length}');
      
      final authToken = await getToken();
      print('[API] DEBUG: Auth token retrieved: ${authToken != null ? 'YES' : 'NO'}');
      
      if (authToken == null) {
        print('[API] ℹ️ Not authenticated, skipping FCM token save');
        return;
      }

      // Get current user ID from token
      final userId = await getUserId();
      print('[API] DEBUG: User ID retrieved: $userId');
      
      if (userId == null) {
        print('[API] ❌ Cannot determine user ID for FCM token save');
        return;
      }

      print('[API] 🔄 Saving FCM token to backend for user $userId...');
      print('[API] DEBUG: Endpoint URL: $baseUrl/auth/users/$userId/fcm-token');
      print('[API] DEBUG: Request body: {"fcmToken": "${token.length > 20 ? token.substring(0, 20) : token}..."}');

      final response = await http.post(
        Uri.parse('$baseUrl/auth/users/$userId/fcm-token'),
        headers: {
          'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({'fcmToken': token}),
      );

      print('[API] DEBUG: Response status code: ${response.statusCode}');
      print('[API] DEBUG: Response body (first 200 chars): ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        print('[API] ✅ FCM token saved successfully');
      } else {
        print('[API] ⚠️ Failed to save FCM token: ${response.statusCode}');
        print('[API] Response: ${response.body}');
      }
    } catch (e) {
      print('[API] ❌ Error saving FCM token: $e');
      print('[API] DEBUG: Exception type: ${e.runtimeType}');
      print('[API] DEBUG: Stack: ${StackTrace.current}');
    }
  }
}
