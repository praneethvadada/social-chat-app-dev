import 'package:flutter/material.dart';
import 'avatar_initial.dart';
import '../models/user_search.dart';
import 'package:social_chat_app/src/theme/colors.dart';

class SearchRow extends StatelessWidget {
  final UserSearch user;
  final VoidCallback? onTap;

  const SearchRow({super.key, required this.user, this.onTap});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (onTap != null) onTap!();
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                AvatarInitial(initials: user.initials, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.username, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(user.fullName, style: TextStyle(color: AppColors.mutedSolid, fontSize: 13)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () {
                    if (onTap != null) onTap!();
                  },
                  icon: const Icon(Icons.search),
                  tooltip: 'View',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
