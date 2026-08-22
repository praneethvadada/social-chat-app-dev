import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Notifier to trigger saved posts refresh across the app
class SavedPostsNotifier extends StateNotifier<int> {
  SavedPostsNotifier() : super(0);
  
  /// Call this to trigger a refresh of saved posts
  void notifySaveChanged() {
    state++;
  }
}

/// Provider for saved posts refresh notifications
final savedPostsNotifierProvider = StateNotifierProvider<SavedPostsNotifier, int>((ref) {
  return SavedPostsNotifier();
});
