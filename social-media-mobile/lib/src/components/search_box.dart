import 'package:flutter/material.dart';

class SearchBox extends StatelessWidget {
  final String hint;

  const SearchBox({super.key, this.hint = 'Search chats...'});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.search, color: theme.iconTheme.color?.withValues(alpha: 0.7)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(hint, style: TextStyle(color: theme.textTheme.bodyMedium?.color)),
            ),
          ],
        ),
      ),
    );
  }
}
