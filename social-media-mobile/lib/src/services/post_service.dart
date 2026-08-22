import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import '../models/post.dart';
import '../models/user_profile.dart';
import 'api_service.dart';

class PostNotifier extends StateNotifier<AsyncValue<List<Post>>> {
  PostNotifier() : super(const AsyncValue.data([]));

  Future<void> loadPosts() async {
    state = const AsyncValue.loading();
    try {
      final posts = await ApiService.getPosts();
      state = AsyncValue.data(posts);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  Future<Post> addPost({
    required String content,
    List<String> imageUrls = const [],
    List<int> taggedUserIds = const [],
    String? actorName,
    String visibility = 'PUBLIC',  // NEW: privacy setting
  }) async {
    final previous = state;
    try {
      final post = await ApiService.createPost(content, imageUrls, visibility: visibility);
      // Send mention notifications for all tagged users in one call
      if (taggedUserIds.isNotEmpty) {
        await ApiService.sendMentionNotification(
          mentionedUserIds: taggedUserIds,
          postId: post.id,
          postContent: content,
        );
      }
      state = state.whenData((posts) => [post, ...posts]);
      return post;
    } catch (e) {
      state = previous;
      rethrow;
    }
  }
  
  Future<Post> addPoll({
    required String question,
    required List<String> options,
    String visibility = 'PUBLIC',
    int? correctOptionIndex,
  }) async {
    final previous = state;
    try {
      final post = await ApiService.createPoll(
        question,
        options,
        visibility: visibility,
        correctOptionIndex: correctOptionIndex,
      );
      state = state.whenData((posts) => [post, ...posts]);
      return post;
    } catch (e) {
      state = previous;
      rethrow;
    }
  }

  Future<Post> addEvent({
    required String title,
    required DateTime startTime,
    String? location,
    String visibility = 'PUBLIC',
  }) async {
    final previous = state;
    try {
      final post = await ApiService.createEvent(title, startTime: startTime, location: location, visibility: visibility);
      state = state.whenData((posts) => [post, ...posts]);
      return post;
    } catch (e) {
      state = previous;
      rethrow;
    }
  }

  Future<void> votePoll(int postId, int optionId) async {
    final previous = state;
    try {
      final updated = await ApiService.votePoll(postId, optionId);
      state = state.whenData((posts) => posts.map((p) => p.id == postId ? updated : p).toList());
    } catch (e) {
      state = previous;
      rethrow;
    }
  }

  Future<void> rsvpEvent(int postId, String status) async {
    final previous = state;
    try {
      final updated = await ApiService.rsvpEvent(postId, status);
      state = state.whenData((posts) => posts.map((p) => p.id == postId ? updated : p).toList());
    } catch (e) {
      state = previous;
      rethrow;
    }
  }

  Future<void> removePost(int postId) async {
    final previous = state;
    try {
      await ApiService.deletePost(postId);
      state = state.whenData((posts) => posts.where((p) => p.id != postId).toList());
    } catch (e) {
      state = previous;
      rethrow;
    }
  }

  Future<Post> editPost(
    int postId, {
    required String content, 
    List<String> imageUrls = const [], 
    String visibility = 'PUBLIC',
  }) async {
    final previous = state;
    try {
      final updated = await ApiService.updatePost(postId, content, imageUrls, visibility: visibility);
      state = state.whenData((posts) => posts.map((p) => p.id == postId ? updated : p).toList());
      return updated;
    } catch (e) {
      state = previous;
      rethrow;
    }
  }
  
  void clearPosts() {
    state = const AsyncValue.data([]);
  }

  Future<void> refreshPosts() async {
    state = const AsyncValue.loading();
    try {
      final posts = await ApiService.getPosts();
      state = AsyncValue.data(posts);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  /// Update a post's like state without refetching all posts
  void updatePostLikeState({
    required int postId,
    required bool isLiked,
    required int likesCount,
    required List<UserProfile> sampleLikers,
  }) {
    state = state.whenData((posts) {
      return posts.map((post) {
        if (post.id == postId) {
          return post.copyWith(
            isLiked: isLiked,
            likes: likesCount,
            sampleLikers: sampleLikers,
          );
        }
        return post;
      }).toList();
    });
  }
}

final postProvider = StateNotifierProvider<PostNotifier, AsyncValue<List<Post>>>((ref) => PostNotifier());
