enum NotificationType { like, mention, follow, comment, reply, follow_request_received, follow_request_accepted }

class NotificationItem {
  final String id;
  final NotificationType type;
  final String actorName;
  final int? actorId; // user who triggered the notification
  final String? actorProfilePictureUrl;
  final int? postId;  // post related to the notification (if any)
  final String message;
  final DateTime time;
  final bool highlighted;

  const NotificationItem({
    required this.id,
    required this.type,
    required this.actorName,
    this.actorId,
    this.actorProfilePictureUrl,
    this.postId,
    required this.message,
    required this.time,
    this.highlighted = false,
  });
}

final mockNotifications = <NotificationItem>[
  NotificationItem(
    id: 'n1',
    type: NotificationType.like,
    actorName: 'Mike Johnson',
    actorId: 101,
    postId: 201,
    message: 'liked your post',
    time: DateTime.now().subtract(const Duration(hours: 3)),
    highlighted: true,
  ),
  NotificationItem(
    id: 'n2',
    type: NotificationType.mention,
    actorName: 'Sarah Wilson',
    actorId: 102,
    postId: 202,
    message: 'mentioned you in a comment',
    time: DateTime.now().subtract(const Duration(hours: 5)),
  ),
  NotificationItem(
    id: 'n3',
    type: NotificationType.follow,
    actorName: 'Emma Davis',
    actorId: 103,
    postId: null,
    message: 'started following you',
    time: DateTime.now().subtract(const Duration(days: 1)),
  ),
  NotificationItem(
    id: 'n4',
    type: NotificationType.comment,
    actorName: 'Olivia Brown',
    actorId: 104,
    postId: 204,
    message: 'commented: Nice photo!',
    time: DateTime.now().subtract(const Duration(hours: 8)),
  ),
];
