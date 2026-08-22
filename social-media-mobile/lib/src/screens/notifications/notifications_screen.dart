import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/notification_item.dart';
import '../../utils/timestamp_parser.dart';
import '../../components/segment_tabs.dart';
import '../../components/notification_card.dart';
import '../../services/api_service.dart';
import '../../services/chat_websocket_service.dart';
import '../../state/app_state_manager.dart';
import '../user_profile_screen.dart';
import '../post_detail/post_detail_screen.dart';
import 'package:social_chat_app/src/theme/colors.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen>
    with AutomaticKeepAliveClientMixin {
  int _tab = 0;
  late List<NotificationItem> _items;
  late OnNotificationReceived _notifListener;

  @override
  void initState() {
    super.initState();
    _items = [];

    // Load persisted notifications
    ApiService.getNotifications().then((list) {
      setState(() {
        _items = list.map((m) => _mapToItem(m)).toList();
      });
    }).catchError((e) {
      print('[Notifications] Failed to load: $e');
    });

    // Subscribe to realtime notifications after websocket ready
    _notifListener = (notif) {
      setState(() {
        _items.insert(0, _mapToItem(notif));
      });
    };
    ChatWebSocketService().readyFuture.then((_) {
      try {
        ChatWebSocketService().subscribeToNotifications(_notifListener);
      } catch (e) {
        print('[Notifications] subscribeToNotifications failed: $e');
      }
    }).catchError((e) {
      print('[Notifications] websocket ready failed: $e');
    });
  }

  @override
  void dispose() {
    ChatWebSocketService().unsubscribeFromNotifications(_notifListener);
    super.dispose();
  }

  NotificationItem _mapToItem(Map<String, dynamic> m) {
    final id = m['id']?.toString() ?? UniqueKey().toString();
    final typeStr = (m['type'] as String?) ?? 'like';
    NotificationType type;
    switch (typeStr.toLowerCase()) {
      case 'follow':
        type = NotificationType.follow;
        break;
      case 'mention':
        type = NotificationType.mention;
        break;
      case 'comment':
        type = NotificationType.comment;
        break;
      case 'reply':
        type = NotificationType.reply;
        break;
      case 'follow_request_received':
        type = NotificationType.follow_request_received;
        break;
      case 'follow_request_accepted':
        type = NotificationType.follow_request_accepted;
        break;
      default:
        type = NotificationType.like;
    }

    final actorName =
        m['actorFullName'] ?? m['actorUsername'] ?? m['actorName'] ?? 'Someone';
    final actorId = m['actorId'] is int
        ? m['actorId']
        : int.tryParse(m['actorId']?.toString() ?? '');
    final actorProfilePictureUrl = m['actorProfilePictureUrl']?.toString();
    // Accept postId from either 'postId' or 'targetId' (backend uses 'targetId')
    int? postId;
    if (m['postId'] != null) {
      postId = m['postId'] is int
          ? m['postId']
          : int.tryParse(m['postId'].toString());
    } else if (m['targetId'] != null) {
      postId = m['targetId'] is int
          ? m['targetId']
          : int.tryParse(m['targetId'].toString());
    }
    final message = m['content'] ?? m['body'] ?? m['message'] ?? '';
    DateTime time = TimestampParser.parseDynamic(m['createdAt']);
    final isRead = m['isRead'] as bool? ?? false;

    return NotificationItem(
      id: id,
      type: type,
      actorName: actorName,
      actorId: actorId,
      actorProfilePictureUrl: actorProfilePictureUrl,
      postId: postId,
      message: message,
      time: time,
      highlighted: !isRead,
    );
  }

  List<NotificationItem> get _filtered {
    if (_tab == 0) return _items;
    if (_tab == 1)
      return _items.where((i) => i.type == NotificationType.mention).toList();
    return _items
        .where((i) =>
            i.type == NotificationType.follow ||
            i.type == NotificationType.follow_request_received ||
            i.type == NotificationType.follow_request_accepted)
        .toList();
  }

  void _dismissItem(NotificationItem item) {
    setState(() => _items.removeWhere((i) => i.id == item.id));
    // Delete from backend
    ApiService.deleteNotification(item.id).catchError((e) {
      // Optionally show error or log
      print('[Notification] Failed to delete from backend: $e');
    });
  }

  @override
  bool get wantKeepAlive => true;

  static const _sectionHeadings = ['Your circle', '@ Mentions', 'Follows'];
  static const _sectionIcons = [Icons.favorite_border, Icons.alternate_email, Icons.people_alt_outlined];

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    void _handleBack() {
      ref.read(appStateProvider.notifier).closeModal();
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleBack();
        }
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 12, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _handleBack,
                      icon: Icon(Icons.arrow_back, color: theme.iconTheme.color),
                      tooltip: 'Back',
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('WHAT YOU MISSED',
                              style: TextStyle(
                                  color: primary,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2)),
                          const SizedBox(height: 2),
                          Text('Activity', style: theme.textTheme.headlineSmall),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Follow requests',
                      icon: Icon(Icons.person_add_alt_1, color: theme.iconTheme.color),
                      onPressed: () => ref.read(appStateProvider.notifier).openModal(ModalScreen.followers),
                    ),
                  ],
                ),
              ),
              Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: SegmentTabs(
                      labels: const ['All', '@ Mentions', 'Follows'],
                      currentIndex: _tab,
                      onChanged: (i) => setState(() => _tab = i))),
              Expanded(
                child: _filtered.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.notifications_none_rounded,
                                  size: 44, color: AppColors.mutedSolid),
                              const SizedBox(height: 12),
                              Text('Nothing here yet',
                                  style: TextStyle(color: AppColors.mutedSolid, fontSize: 15)),
                            ],
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(18, 10, 18, 90),
                        children: [
                          Row(
                            children: [
                              Icon(_sectionIcons[_tab], size: 18, color: primary),
                              const SizedBox(width: 8),
                              Text(_sectionHeadings[_tab],
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Container(
                            decoration: BoxDecoration(
                              color: theme.cardColor,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: theme.dividerColor),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              children: List.generate(_filtered.length, (idx) {
                                final item = _filtered[idx];
                                return Dismissible(
                                  key: ValueKey(item.id),
                                  direction: DismissDirection.endToStart,
                                  onDismissed: (d) => _dismissItem(item),
                                  background: Container(
                                    color: AppColors.danger,
                                    padding: const EdgeInsets.only(right: 20),
                                    alignment: Alignment.centerRight,
                                    child: const Icon(Icons.archive, color: Colors.white),
                                  ),
                                  child: Column(
                                    children: [
                                      GestureDetector(
                                        onTap: () async {
                                          // Navigation logic based on notification type
                                          if ((item.type == NotificationType.follow ||
                                                  item.type ==
                                                      NotificationType
                                                          .follow_request_received ||
                                                  item.type ==
                                                      NotificationType
                                                          .follow_request_accepted) &&
                                              item.actorId != null) {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    UserProfileScreen(userId: item.actorId!),
                                              ),
                                            );
                                          } else if ((item.type == NotificationType.like ||
                                                  item.type == NotificationType.mention ||
                                                  item.type == NotificationType.comment ||
                                                  item.type == NotificationType.reply) &&
                                              item.postId != null) {
                                            try {
                                              final post =
                                                  await ApiService.getPost(item.postId!);
                                              if (!mounted) return;
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) => PostDetailScreen(post: post),
                                                ),
                                              );
                                            } catch (e) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text('Failed to load post.')),
                                              );
                                            }
                                          }
                                        },
                                        child: NotificationCard(item: item),
                                      ),
                                      if (idx < _filtered.length - 1)
                                        Divider(height: 1, color: theme.dividerColor),
                                    ],
                                  ),
                                );
                              }),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
