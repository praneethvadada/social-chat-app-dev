import 'dart:async';
import 'package:flutter/foundation.dart';
import 'chat_websocket_service.dart';

/// Service to manage real-time notifications globally
/// Listens to WebSocket notifications and notifies interested widgets
class NotificationService extends ChangeNotifier {
  static final NotificationService _instance = NotificationService._internal();
  
  late ChatWebSocketService _chatWebSocket;
  StreamSubscription? _notificationSubscription;
  
  // Notification count (for badge)
  int _unreadCount = 0;
  int get unreadCount => _unreadCount;
  
  // Recent notifications list
  final List<Map<String, dynamic>> _recentNotifications = [];
  List<Map<String, dynamic>> get recentNotifications => _recentNotifications;
  
  // Notification types to track
  static const String TYPE_FOLLOW = 'FOLLOW';
  static const String TYPE_LIKE = 'LIKE';
  static const String TYPE_COMMENT = 'COMMENT';
  static const String TYPE_MENTION = 'MENTION';
  static const String TYPE_MESSAGE = 'MESSAGE';

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal() {
    print('[NotificationService] Initialized');
    _chatWebSocket = ChatWebSocketService();
  }

  /// Initialize notification service after WebSocket is connected
  void initialize() {
    print('[NotificationService] Initializing - subscribing to real-time notifications');
    
    // Listen to WebSocket notification stream
    _notificationSubscription = _chatWebSocket.notificationStream?.listen(
      (notification) {
        _handleIncomingNotification(notification);
      },
      onError: (error) {
        print('[NotificationService] Error in notification stream: $error');
      },
      onDone: () {
        print('[NotificationService] Notification stream closed');
        _notificationSubscription = null;
      },
    );
  }

  /// Handle incoming notification from WebSocket
  void _handleIncomingNotification(Map<String, dynamic> notification) {
    try {
      final type = notification['type'] as String?;
      final actorId = notification['actorId'] as int?;
      final actorUsername = notification['actorUsername'] as String? ?? 'Unknown';
      
      print('[NotificationService] Received notification: type=$type from user=$actorId ($actorUsername)');
      
      // Add to recent notifications
      _recentNotifications.insert(0, notification);
      if (_recentNotifications.length > 50) {
        _recentNotifications.removeLast(); // Keep only last 50
      }
      
      // Increment unread count
      _unreadCount++;
      print('[NotificationService] Unread count: $_unreadCount');
      
      // Notify all listeners (UI widgets will rebuild)
      notifyListeners();
      
      // Log different notification types
      switch (type) {
        case TYPE_FOLLOW:
          print('[🔔 NOTIFICATION] $actorUsername started following you!');
          break;
        case TYPE_LIKE:
          print('[🔔 NOTIFICATION] $actorUsername liked your post!');
          break;
        case TYPE_COMMENT:
          print('[🔔 NOTIFICATION] $actorUsername commented on your post!');
          break;
        case TYPE_MENTION:
          print('[🔔 NOTIFICATION] $actorUsername mentioned you!');
          break;
        default:
          print('[🔔 NOTIFICATION] New notification: $type from $actorUsername');
      }
    } catch (e) {
      print('[NotificationService] Error handling notification: $e');
    }
  }

  /// Mark notifications as read
  void markAsRead() {
    if (_unreadCount > 0) {
      _unreadCount = 0;
      notifyListeners();
      print('[NotificationService] Notifications marked as read');
    }
  }

  /// Clear all notifications
  void clearAll() {
    _recentNotifications.clear();
    _unreadCount = 0;
    notifyListeners();
    print('[NotificationService] All notifications cleared');
  }

  /// Cleanup resources
  void dispose() {
    _notificationSubscription?.cancel();
    print('[NotificationService] Disposed');
    super.dispose();
  }
}
