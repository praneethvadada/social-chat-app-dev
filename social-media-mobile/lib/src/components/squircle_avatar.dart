import 'package:flutter/material.dart';
import '../theme/colors.dart';

/// Squircle avatar (asymmetric rounded corners) with an optional online
/// dot — the reference's avatar shape, used throughout chats/groups.
class SquircleAvatar extends StatelessWidget {
  final double size;
  final String? imageUrl;
  final String initials;
  final bool online;
  final IconData? icon;

  const SquircleAvatar({
    super.key,
    required this.size,
    this.imageUrl,
    this.initials = '',
    this.online = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.accentSubtle100,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(size * 0.33),
              topRight: Radius.circular(size * 0.33),
              bottomRight: Radius.circular(size * 0.33),
              bottomLeft: Radius.circular(size * 0.13),
            ),
            image: hasImage
                ? DecorationImage(image: NetworkImage(imageUrl!), fit: BoxFit.cover)
                : null,
          ),
          alignment: Alignment.center,
          child: hasImage
              ? null
              : (icon != null
                  ? Icon(icon, color: theme.colorScheme.primary, size: size * 0.46)
                  : Text(initials,
                      style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: size * 0.32))),
        ),
        if (online)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: size * 0.28,
              height: size * 0.28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary,
                border: Border.all(color: theme.scaffoldBackgroundColor, width: 2.5),
              ),
            ),
          ),
      ],
    );
  }
}
