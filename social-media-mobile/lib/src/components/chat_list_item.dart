import 'package:flutter/material.dart';
import 'avatar_initial.dart';
import 'package:go_router/go_router.dart';
import '../screens/chats/chat_screen.dart';
import '../components/unread_badge.dart';
import '../models/chat.dart';
import 'package:social_chat_app/src/theme/colors.dart';

class ChatListItem extends StatefulWidget {
  final ChatModel chat;
  final int index;

  const ChatListItem({super.key, required this.chat, required this.index});

  @override
  State<ChatListItem> createState() => _ChatListItemState();
}

class _ChatListItemState extends State<ChatListItem> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;
  late final Animation<Offset> _offset;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
    final curve = CurvedAnimation(parent: _ctl, curve: Curves.easeOut);
    _offset = Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero).animate(curve);
    _opacity = Tween<double>(begin: 0, end: 1).animate(curve);
    Future.delayed(Duration(milliseconds: 60 * widget.index), () {
      if (mounted) _ctl.forward();
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.chat;
    return RepaintBoundary(
      child: FadeTransition(
        opacity: _opacity,
        child: SlideTransition(
          position: _offset,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            leading: AvatarInitial(initials: _initials(c.name), size: 48, showOnline: c.online),
            title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(c.lastMessage, maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(child: Text(c.time, style: TextStyle(color: AppColors.mutedSolid, fontSize: 12))),
                const SizedBox(height: 6),
                UnreadBadge(count: c.unreadCount),
              ],
            ),
            onTap: () {
              try {
                GoRouter.of(context).push('/chats/${widget.chat.id}');
              } catch (_) {
                try {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(chat: widget.chat)));
                } catch (_) {}
              }
            },
            dense: true,
            horizontalTitleGap: 12,
            minVerticalPadding: 6,
            tileColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            enabled: true,
          ),
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.split(' ');
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}
