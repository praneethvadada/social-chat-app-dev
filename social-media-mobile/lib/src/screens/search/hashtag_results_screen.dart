import 'package:flutter/material.dart';
import '../../components/post_card.dart';
import '../../models/post.dart';
import '../../services/api_service.dart';
import '../../theme/colors.dart';

/// All public posts carrying a given #hashtag — reached by tapping a
/// hashtag anywhere in the app (post text, Discover's trending topics).
class HashtagResultsScreen extends StatefulWidget {
  final String tag;
  const HashtagResultsScreen({super.key, required this.tag});

  @override
  State<HashtagResultsScreen> createState() => _HashtagResultsScreenState();
}

class _HashtagResultsScreenState extends State<HashtagResultsScreen> {
  late Future<List<Post>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService.getPostsByHashtag(widget.tag);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: theme.dividerColor),
                        color: theme.cardColor,
                      ),
                      child: Icon(Icons.arrow_back, size: 20, color: theme.iconTheme.color),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('#${widget.tag}', style: theme.textTheme.headlineMedium),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Post>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text('Could not load #${widget.tag}',
                          style: TextStyle(color: AppColors.mutedSolid)),
                    );
                  }
                  final posts = snapshot.data ?? const [];
                  if (posts.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.tag, size: 48, color: theme.iconTheme.color?.withValues(alpha: 0.5)),
                            const SizedBox(height: 12),
                            Text('No posts yet with #${widget.tag}',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium),
                          ],
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    itemCount: posts.length,
                    itemBuilder: (context, index) => PostCard(post: posts[index], index: index),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
