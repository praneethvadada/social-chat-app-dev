import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/status.dart';
import 'api_service.dart';

/// REST client for 24-hour statuses (S1).
/// Routes through the gateway: /api/social/statuses/** -> social-service.
class StatusApi {
  static String get _base => '${ApiConfig.baseUrl}/social/statuses';

  static Future<Map<String, String>> _headers() async {
    final token = await ApiService.getToken();
    if (token == null) throw Exception('Not authenticated');
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  static Future<StatusFeed> fetchFeed() async {
    final response =
        await http.get(Uri.parse('$_base/feed'), headers: await _headers());
    if (response.statusCode != 200) {
      throw Exception('Failed to load statuses (${response.statusCode})');
    }
    return StatusFeed.fromJson(jsonDecode(response.body));
  }

  static Future<StatusItem> createText({
    required String content,
    String? backgroundColor,
    String privacyType = 'CONTACTS',
    List<int> audienceUserIds = const [],
  }) async {
    return _create({
      'type': 'TEXT',
      'content': content,
      if (backgroundColor != null) 'backgroundColor': backgroundColor,
      'privacyType': privacyType,
      'audienceUserIds': audienceUserIds,
    });
  }

  static Future<StatusItem> createMedia({
    required String mediaUrl,
    required bool isVideo,
    String? caption,
    String privacyType = 'CONTACTS',
    List<int> audienceUserIds = const [],
  }) async {
    return _create({
      'type': isVideo ? 'VIDEO' : 'IMAGE',
      'mediaUrl': mediaUrl,
      if (caption != null && caption.isNotEmpty) 'content': caption,
      'privacyType': privacyType,
      'audienceUserIds': audienceUserIds,
    });
  }

  /// S4 (§R): my expired statuses. Owner-scoped by the backend.
  static Future<List<StatusItem>> fetchArchive() async {
    final response =
        await http.get(Uri.parse('$_base/archive'), headers: await _headers());
    if (response.statusCode != 200) {
      throw Exception('Failed to load archive (${response.statusCode})');
    }
    return (jsonDecode(response.body) as List)
        .map((e) => StatusItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<StatusItem> _create(Map<String, dynamic> body) async {
    final response = await http.post(
      Uri.parse(_base),
      headers: await _headers(),
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to post status (${response.statusCode})');
    }
    return StatusItem.fromJson(jsonDecode(response.body));
  }

  /// S3: set my reaction, or pass null/'' to clear it.
  /// One status by id, wrapped in its author group. Used when tapping the
  /// status reference on a chat bubble.
  ///
  /// Returns null when the status is gone (expired or deleted) or the caller
  /// may not see it, so callers can show a plain message instead of an error.
  static Future<UserStatusGroup?> fetchOne(int statusId) async {
    final res = await http.get(Uri.parse('$_base/statuses/$statusId'),
        headers: await _headers());
    if (res.statusCode == 404 || res.statusCode == 403) return null;
    if (res.statusCode != 200) {
      throw Exception(ApiService.extractErrorMessage(res, 'Could not open status'));
    }
    return UserStatusGroup.fromJson(json.decode(res.body));
  }

  static Future<void> react(int statusId, String? reaction) async {
    final response = await http.post(
      Uri.parse('$_base/$statusId/reaction'),
      headers: await _headers(),
      body: jsonEncode({'reaction': reaction ?? ''}),
    );
    if (response.statusCode != 200) {
      throw Exception('Could not react');
    }
  }

  /// Viewers of one of MY statuses. The backend rejects this for anyone else.
  static Future<List<StatusViewer>> fetchViewers(int statusId) async {
    final response = await http.get(Uri.parse('$_base/$statusId/viewers'),
        headers: await _headers());
    if (response.statusCode != 200) {
      throw Exception('Failed to load viewers (${response.statusCode})');
    }
    return (jsonDecode(response.body) as List)
        .map((e) => StatusViewer.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Best-effort: a failed view-mark must never break the viewer UI.
  static Future<void> markViewed(int statusId) async {
    try {
      await http.post(Uri.parse('$_base/$statusId/view'),
          headers: await _headers());
    } catch (_) {}
  }

  static Future<void> delete(int statusId) async {
    final response = await http.delete(Uri.parse('$_base/$statusId'),
        headers: await _headers());
    if (response.statusCode != 200) {
      throw Exception('Failed to delete status (${response.statusCode})');
    }
  }
}
