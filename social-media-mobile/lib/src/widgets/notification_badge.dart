import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/notification_service.dart';
import 'package:social_chat_app/src/theme/colors.dart';

/// Notification badge widget that shows unread notification count
/// Shows a red badge with count if there are unread notifications
class NotificationBadge extends StatelessWidget {
  final Widget child;
  final EdgeInsets badgeOffset;

  const NotificationBadge({
    Key? key,
    required this.child,
    this.badgeOffset = const EdgeInsets.only(top: -5, right: -5),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<NotificationService>(
      builder: (context, notificationService, _) {
        final count = notificationService.unreadCount;
        
        return Stack(
          children: [
            child,
            if (count > 0)
              Positioned(
                top: badgeOffset.top,
                right: badgeOffset.right,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 20,
                    minHeight: 20,
                  ),
                  child: Text(
                    count > 99 ? '99+' : count.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
