import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class CallNotificationService {
  static final CallNotificationService _instance = CallNotificationService._internal();
  factory CallNotificationService() => _instance;
  CallNotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  
  // Callback when notification is tapped
  Function(String payload)? onNotificationTapped;

  Future<void> initialize() async {
    print('[CallNotificationService] Initializing...');
    
    // Android initialization
    const AndroidInitializationSettings androidInitializationSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS initialization
    const DarwinInitializationSettings iosInitializationSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: androidInitializationSettings,
      iOS: iosInitializationSettings,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        print('[CallNotificationService] Notification tapped: ${response.payload}');
        onNotificationTapped?.call(response.payload ?? '');
      },
    );
    
    print('[CallNotificationService] ✅ Initialized successfully');
  }

  Future<void> showMinimizedCallNotification({
    required String userName,
    required bool isVideo,
    required String callId,
  }) async {
    print('[CallNotificationService] Showing minimized call notification: userName=$userName isVideo=$isVideo');
    
    const AndroidNotificationDetails androidNotificationDetails =
        AndroidNotificationDetails(
          'call_channel',
          'Active Calls',
          channelDescription: 'Notifications for active calls',
          importance: Importance.max,
          priority: Priority.high,
          ongoing: true,
          autoCancel: false,
        );

    const DarwinNotificationDetails iosNotificationDetails =
        DarwinNotificationDetails(
          presentSound: false,
          presentBadge: false,
        );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
      iOS: iosNotificationDetails,
    );

    final title = isVideo ? '📹 Video Call' : '📞 Audio Call';
    final body = 'In call with $userName - tap to resume';

    await _flutterLocalNotificationsPlugin.show(
      callId.hashCode, // Notification ID based on call ID
      title,
      body,
      notificationDetails,
      payload: callId, // Pass call ID as payload to identify which call
    );
  }

  Future<void> cancelCallNotification(String callId) async {
    print('[CallNotificationService] Canceling notification for call: $callId');
    await _flutterLocalNotificationsPlugin.cancel(callId.hashCode);
  }

  Future<void> cancelAllNotifications() async {
    print('[CallNotificationService] Canceling all notifications');
    await _flutterLocalNotificationsPlugin.cancelAll();
  }
}
