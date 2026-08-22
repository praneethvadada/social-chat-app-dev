class ChatModel {
  final String id;
  final String name;
  final String lastMessage;
  final String time;
  final int unreadCount;
  final bool online;

  const ChatModel({required this.id, required this.name, required this.lastMessage, required this.time, this.unreadCount = 0, this.online = false});
}

const mockChats = <ChatModel>[
  ChatModel(id: 'ch1', name: 'Sarah Wilson', lastMessage: 'Hey! How was your day? I was thinking...', time: '2:30 PM', unreadCount: 3, online: true),
  ChatModel(id: 'ch2', name: 'Mike Johnson', lastMessage: "Let's catch up later today.", time: '1:15 PM', unreadCount: 0, online: false),
  ChatModel(id: 'ch3', name: 'Emma Davis', lastMessage: 'Great job on the presentation!', time: '11:20 AM', unreadCount: 0, online: false),
  ChatModel(id: 'ch4', name: 'David Evans', lastMessage: 'Can you review the doc?', time: 'Yesterday', unreadCount: 1, online: false),
];
