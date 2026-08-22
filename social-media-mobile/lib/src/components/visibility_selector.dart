import 'package:flutter/material.dart';
import '../models/post.dart';
import 'package:social_chat_app/src/theme/colors.dart';

/// Public / Close Friends toggle — same choice already offered when creating
/// a regular post, now also available for Polls and Events.
class VisibilitySelector extends StatelessWidget {
  final PostVisibility value;
  final ValueChanged<PostVisibility> onChanged;

  const VisibilitySelector({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    Widget option(PostVisibility v, IconData icon, String label) {
      final selected = value == v;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(v),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? primary : Colors.transparent,
              borderRadius: BorderRadius.circular(25),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: selected ? Colors.white : AppColors.mutedSolid),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        color: selected ? Colors.white : AppColors.mutedSolid,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 13)),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Who can see this', style: TextStyle(color: AppColors.mutedSolid, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: AppColors.border!),
          ),
          child: Row(
            children: [
              option(PostVisibility.PUBLIC, Icons.public, 'Public'),
              option(PostVisibility.CLOSE_FRIENDS, Icons.star_rounded, 'Close Friends'),
            ],
          ),
        ),
      ],
    );
  }
}
