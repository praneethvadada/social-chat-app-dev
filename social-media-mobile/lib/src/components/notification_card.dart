import 'package:flutter/material.dart';
import '../config/api_config.dart';
import '../models/notification_item.dart';
import '../services/api_service.dart';
import '../utils/time_utils.dart';
import 'package:social_chat_app/src/theme/colors.dart';

/// A single row inside the Activity list's grouped panel — matches the
/// reference's "Your circle" rows: avatar, actor + action text, timestamp,
/// and a contextual trailing action (Follow back for follow notifications).
class NotificationCard extends StatefulWidget {
  final NotificationItem item;

  const NotificationCard({super.key, required this.item});

  @override
  State<NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<NotificationCard> {
  bool _following = false;
  bool _requested = false;
  bool _busy = false;

  Future<void> _followBack() async {
    final actorId = widget.item.actorId;
    if (actorId == null || _busy) return;
    setState(() => _busy = true);
    try {
      bool private = false;
      try {
        final profile = await ApiService.getUserProfile(actorId);
        private = profile['isPrivate'] as bool? ?? false;
      } catch (_) {}
      if (private) {
        await ApiService.sendFollowRequest(actorId);
        if (mounted) setState(() => _requested = true);
      } else {
        await ApiService.followUser(actorId);
        if (mounted) setState(() => _following = true);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Failed to follow back')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  IconData _iconForType(NotificationType t) {
    switch (t) {
      case NotificationType.like:
        return Icons.favorite;
      case NotificationType.mention:
        return Icons.alternate_email;
      case NotificationType.follow:
        return Icons.person_add;
      case NotificationType.comment:
        return Icons.chat_bubble;
      case NotificationType.reply:
        return Icons.reply;
      case NotificationType.follow_request_received:
        return Icons.person_add;
      case NotificationType.follow_request_accepted:
        return Icons.check_circle;
    }
  }

  Color _colorForType(NotificationType t) {
    switch (t) {
      case NotificationType.like:
        return AppColors.danger;
      case NotificationType.follow:
      case NotificationType.follow_request_received:
      case NotificationType.follow_request_accepted:
        return AppColors.gold;
      default:
        return AppColors.primary;
    }
  }

  String _getInitials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return parts[0][0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final theme = Theme.of(context);
    final pic = item.actorProfilePictureUrl;
    final hasPic = pic != null && pic.isNotEmpty;
    final resolvedPic = hasPic
        ? (pic.startsWith('http') ? pic : '${ApiConfig.serverUrl}/api/social$pic')
        : null;
    final isFollowType = item.type == NotificationType.follow ||
        item.type == NotificationType.follow_request_received;
    final showFollowBack = isFollowType && !_following && !_requested && item.actorId != null;

    return Container(
      color: item.highlighted ? AppColors.accentSubtle100 : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: theme.colorScheme.primary,
                backgroundImage: resolvedPic != null ? NetworkImage(resolvedPic) : null,
                child: resolvedPic == null
                    ? Text(_getInitials(item.actorName),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))
                    : null,
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: _colorForType(item.type),
                    shape: BoxShape.circle,
                    border: Border.all(color: theme.cardColor, width: 2),
                  ),
                  child: Icon(_iconForType(item.type), size: 10, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                          text: item.actorName,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: ' ${item.message}'),
                    ],
                    style: TextStyle(color: theme.textTheme.bodyMedium?.color, fontSize: 13.5),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                TimeAgoWidget(timestamp: item.time, style: TextStyle(color: AppColors.mutedSolid, fontSize: 12)),
              ],
            ),
          ),
          if (showFollowBack) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _followBack,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Follow back',
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
          ] else if (_following || _requested) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.border!),
              ),
              child: Text(_requested ? 'Requested' : 'Following',
                  style: TextStyle(color: AppColors.mutedSolid, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      ),
    );
  }
}
