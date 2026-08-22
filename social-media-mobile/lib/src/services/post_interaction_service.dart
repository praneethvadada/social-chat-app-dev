import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';
import '../models/comment.dart';

class PostInteractionService {
  static const String baseUrl = ApiService.baseUrl;

  static Future<String?> _getToken() => ApiService.getToken();

  static Future<Map<String, dynamic>> likePost(int postId) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    print('\n[LIKE POST] postId: $postId');
    final response = await http.post(
      Uri.parse('$baseUrl/social/likes/post/$postId'),
      headers: {'Authorization': 'Bearer $token'},
    );

    print('[LIKE POST] Response status: ${response.statusCode}');
    print('[LIKE POST] Response body: ${response.body}');
    
    if (response.statusCode != 200) {
      final message = ApiService.extractErrorMessage(response, 'Failed to like post');
      print('[LIKE POST] ❌ ERROR: $message');
      throw Exception(message);
    }
    
    // Fetch updated post data to get correct like count and likers
    print('[LIKE POST] ✅ Like created, fetching updated post data...');
    try {
      final updatedPost = await ApiService.getPost(postId);
      final result = {
        'likesCount': updatedPost.likes,
        'isLiked': updatedPost.isLiked,
        'sampleLikers': updatedPost.sampleLikers,
      };
      print('[LIKE POST] ✅ Post fetched - isLiked: ${result['isLiked']}, count: ${result['likesCount']}');
      return result;
    } catch (e) {
      print('[LIKE POST] ❌ Error fetching post: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> unlikePost(int postId) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    print('\n[UNLIKE POST] postId: $postId');
    final response = await http.delete(
      Uri.parse('$baseUrl/social/likes/post/$postId'),
      headers: {'Authorization': 'Bearer $token'},
    );

    print('[UNLIKE POST] Response status: ${response.statusCode}');
    print('[UNLIKE POST] Response body: ${response.body}');
    
    if (response.statusCode != 204 && response.statusCode != 200) {
      final message = ApiService.extractErrorMessage(response, 'Failed to unlike post');
      print('[UNLIKE POST] ❌ ERROR: $message');
      throw Exception(message);
    }
    
    // Fetch updated post data to get correct like count and likers
    print('[UNLIKE POST] ✅ Unlike removed, fetching updated post data...');
    try {
      final updatedPost = await ApiService.getPost(postId);
      final result = {
        'likesCount': updatedPost.likes,
        'isLiked': updatedPost.isLiked,
        'sampleLikers': updatedPost.sampleLikers,
      };
      print('[UNLIKE POST] ✅ Post fetched - isLiked: ${result['isLiked']}, count: ${result['likesCount']}');
      return result;
    } catch (e) {
      print('[UNLIKE POST] ❌ Error fetching post: $e');
      rethrow;
    }
  }

  static Future<void> savePost(int postId) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    print('\n[SAVE POST] postId: $postId');
    final response = await http.post(
      Uri.parse('$baseUrl/social/saves/$postId'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200) {
      final message = ApiService.extractErrorMessage(response, 'Failed to save post');
      throw Exception(message);
    }
    print('[SAVE POST] Success');
  }

  static Future<void> unsavePost(int postId) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    print('\n[UNSAVE POST] postId: $postId');
    final response = await http.delete(
      Uri.parse('$baseUrl/social/saves/$postId'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 204 && response.statusCode != 200) {
      final message = ApiService.extractErrorMessage(response, 'Failed to unsave post');
      throw Exception(message);
    }
    print('[UNSAVE POST] Success');
  }

  static Future<void> addComment(int postId, String content) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    print('\n[ADD COMMENT] postId: $postId, content: $content');
    final response = await http.post(
      Uri.parse('$baseUrl/social/comments'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'postId': postId,
        'content': content,
      }),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      final message = ApiService.extractErrorMessage(response, 'Failed to add comment');
      throw Exception(message);
    }
    print('[ADD COMMENT] Success');
  }

  static Future<List<Comment>> getComments(int postId) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    print('\n[GET COMMENTS] postId: $postId');
    final response = await http.get(
      Uri.parse('$baseUrl/social/comments/post/$postId?page=0&size=50'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      
      // Handle Spring Page response
      if (decoded is Map<String, dynamic> && decoded['content'] is List) {
        final List<dynamic> comments = decoded['content'] as List;
        print('[GET COMMENTS] Success, got ${comments.length} comments');
        return comments
            .map((json) => Comment.fromJson(json as Map<String, dynamic>))
            .toList();
      }
      
      // Handle bare list response
      if (decoded is List) {
        print('[GET COMMENTS] Success, got ${decoded.length} comments');
        return decoded
            .map((json) => Comment.fromJson(json as Map<String, dynamic>))
            .toList();
      }

      throw Exception('Unexpected comments response format');
    }

    final message = ApiService.extractErrorMessage(response, 'Failed to load comments');
    throw Exception(message);
  }

  static Future<void> likeComment(int commentId) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    print('\n[LIKE COMMENT] commentId: $commentId');
    final response = await http.post(
      Uri.parse('$baseUrl/social/likes/comment/$commentId'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200) {
      final message = ApiService.extractErrorMessage(response, 'Failed to like comment');
      throw Exception(message);
    }
    print('[LIKE COMMENT] Success');
  }

  static Future<void> unlikeComment(int commentId) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    print('\n[UNLIKE COMMENT] commentId: $commentId');
    final response = await http.delete(
      Uri.parse('$baseUrl/social/likes/comment/$commentId'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 204 && response.statusCode != 200) {
      final message = ApiService.extractErrorMessage(response, 'Failed to unlike comment');
      throw Exception(message);
    }
    print('[UNLIKE COMMENT] Success');
  }

  static Future<void> replyToComment(int postId, int commentId, String content) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    print('\n[REPLY COMMENT] postId: $postId, parentCommentId: $commentId, content: $content');
    final response = await http.post(
      Uri.parse('$baseUrl/social/comments'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'postId': postId,
        'content': content,
        'parentCommentId': commentId,
      }),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      final message = ApiService.extractErrorMessage(response, 'Failed to add reply');
      throw Exception(message);
    }
    print('[REPLY COMMENT] Success');
  }
}
