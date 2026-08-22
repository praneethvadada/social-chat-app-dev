// STATIC MOCK
import 'package:flutter/material.dart';
import 'package:social_chat_app/src/theme/colors.dart';

class AvatarInitial extends StatelessWidget {
  final String initials;
  final double size;
  final bool showOnline;

  const AvatarInitial({super.key, required this.initials, this.size = 44, this.showOnline = false});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [primary, primary.withAlpha((0.7 * 255).round())], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          alignment: Alignment.center,
          child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ),
        if (showOnline)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: size * 0.28,
              height: size * 0.28,
              decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
            ),
          ),
      ],
    );
  }
}
