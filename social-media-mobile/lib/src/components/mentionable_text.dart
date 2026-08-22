import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../services/api_service.dart';
import '../screens/user_profile_screen.dart';
import '../screens/search/hashtag_results_screen.dart';

/// Renders text with #hashtags and @mentions as tappable, accent-colored
/// spans — #hashtag opens the hashtag results screen, @mention resolves the
/// username and opens that user's profile. Plain text renders unchanged.
class MentionableText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  const MentionableText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
  });

  static final RegExp _tokenPattern = RegExp(r'(#\w+|@\w+)');

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final accent = Theme.of(context).colorScheme.primary;
    final matches = _tokenPattern.allMatches(text);

    if (matches.isEmpty) {
      return Text(text, style: baseStyle, maxLines: maxLines, overflow: overflow);
    }

    final spans = <InlineSpan>[];
    int cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      final token = match.group(0)!;
      final isHashtag = token.startsWith('#');
      spans.add(
        TextSpan(
          text: token,
          style: TextStyle(color: accent, fontWeight: FontWeight.w700),
          recognizer: TapGestureRecognizer()
            ..onTap = () => isHashtag
                ? _openHashtag(context, token.substring(1))
                : _openMentionedProfile(context, token.substring(1)),
        ),
      );
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return Text.rich(
      TextSpan(style: baseStyle, children: spans),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
    );
  }

  void _openHashtag(BuildContext context, String tag) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => HashtagResultsScreen(tag: tag)),
    );
  }

  Future<void> _openMentionedProfile(BuildContext context, String username) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final results = await ApiService.searchUsers(username);
      final match = results.firstWhere(
        (u) => (u['username']?.toString().toLowerCase() ?? '') == username.toLowerCase(),
        orElse: () => const {},
      );
      final userId = match['userId'];
      if (userId == null) {
        messenger.showSnackBar(SnackBar(content: Text('@$username not found')));
        return;
      }
      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => UserProfileScreen(
            userId: userId is int ? userId : int.tryParse(userId.toString()) ?? 0,
            userName: match['username']?.toString(),
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text('@$username not found')));
    }
  }
}

/// Extracts unique @usernames from free text, for resolving mentions before
/// sending a mention notification.
List<String> extractMentionedUsernames(String text) {
  final matches = RegExp(r'@(\w+)').allMatches(text);
  final seen = <String>{};
  for (final m in matches) {
    final u = m.group(1);
    if (u != null && u.isNotEmpty) seen.add(u);
  }
  return seen.toList();
}
