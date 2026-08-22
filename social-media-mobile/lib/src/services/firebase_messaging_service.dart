import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:typed_data';
import '../../firebase_options.dart';
import 'api_service.dart';
import '../state/call_state_manager.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/message.dart';
import '../models/post.dart';
import '../screens/chats/chat_screen.dart';
import '../screens/post_detail/post_detail_screen.dart';
import '../screens/profile/user_profile_screen.dart';
import '../navigation/root_navigator_key.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Handle background messages - MUST be top-level function with @pragma
/// This is called by native Firebase code
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('[FCM] 🔔🔔🔔 BACKGROUND MESSAGE HANDLER CALLED 🔔🔔🔔');
  print('[FCM] messageId: ${message.messageId}');
  print('[FCM] notification: ${message.notification}');
  print('[FCM] data: ${message.data}');
  
  // Initialize Firebase if needed
  try {
    await Firebase.initializeApp();
  } catch (e) {
    print('[FCM] Firebase already initialized or error: $e');
  }
  
  // Show notification for background messages
  try {
    await FirebaseMessagingService._handleBackgroundMessage(message);
    print('[FCM] ✅ Background message handled successfully');
  } catch (e) {
    print('[FCM] ❌ Error handling background message: $e');
  }
}

/// Firebase Cloud Messaging Service
/// Handles push notifications for both Android and iOS
@pragma('vm:entry-point')
class FirebaseMessagingService {
  static final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static bool _isInitialized = false;
  
  // Track active call notifications by caller ID
  static Map<int, Map<String, dynamic>> _activeCallNotifications = {}; // callerId -> {notificationId, callerName}

  // ✅ NEW: Track active chat ID to suppress notifications when user is in the chat
  static int? _currentActiveChatId;

  static void setContextActiveChatId(int? chatId) {
    _currentActiveChatId = chatId;
    print('[FCM] 🗣️ Context Active Chat set to: $_currentActiveChatId');
  }

  /// Force sync FCM token after login (Critical for switching accounts)
  static Future<void> syncTokenAfterLogin() async {
    print('[FCM] 🔄 ========== STARTING TOKEN SYNC AFTER LOGIN ==========');
    try {
      // Ensure token generation is enabled (it may be disabled on logout)
      print('[FCM] 🔄 Step 1: Enabling auto-init...');
      await _firebaseMessaging.setAutoInitEnabled(true);
      print('[FCM] ✅ Auto-init enabled');

      // Ensure handlers/channels are restored when user logs in again without app restart
      print('[FCM] 🔄 Step 2: Checking if Firebase initialized...');
      if (!_isInitialized) {
        print('[FCM] ⚠️ Not initialized yet, calling initializeFirebase()...');
        await initializeFirebase();
        print('[FCM] ✅ Firebase initialized');
      } else {
        print('[FCM] ℹ️ Already initialized');
      }

      // Give Play Services a moment to initialize (especially on real devices)
      print('[FCM] 🔄 Step 2.5: Waiting for Play Services to initialize (2 seconds)...');
      await Future.delayed(const Duration(seconds: 2));
      print('[FCM] ✅ Wait complete');

      print('[FCM] 🔄 Step 3: Getting FCM token (with retry)...');
      String? token;
      int retries = 0;
      const maxRetries = 3;
      
      while (retries < maxRetries && (token == null || token.isEmpty)) {
        try {
          retries++;
          print('[FCM] 🔄 Token fetch attempt $retries/$maxRetries...');
          token = await _firebaseMessaging.getToken();
          
          if (token != null && token.isNotEmpty) {
            print('[FCM] ✅ Token retrieved on attempt $retries: ${token.length} chars');
            print('[FCM] Token preview: ${token.substring(0, 20)}...');
            break; // Success, exit loop
          } else {
            print('[FCM] ⚠️ Attempt $retries returned null/empty token');
            if (retries < maxRetries) {
              print('[FCM] ⏳ Waiting 1.5 seconds before retry...');
              await Future.delayed(const Duration(milliseconds: 1500));
            }
          }
        } catch (e) {
          print('[FCM] ⚠️ Attempt $retries failed: $e');
          if (retries < maxRetries) {
            print('[FCM] ⏳ Waiting 1.5 seconds before retry...');
            await Future.delayed(const Duration(milliseconds: 1500));
          }
        }
      }

      // Fallback: force token regeneration if still null/empty
      if (token == null || token.isEmpty) {
        print('[FCM] ⚠️ All retries exhausted, attempting token regeneration...');
        try {
          await _firebaseMessaging.deleteToken();
          print('[FCM] ✅ Old token deleted');
          await Future.delayed(const Duration(seconds: 1));
          token = await _firebaseMessaging.getToken();
          print('[FCM] 🔑 New token after delete: ${token != null ? 'YES (${token.length} chars)' : 'NULL'}');
          if (token != null) {
            print('[FCM] Token preview: ${token.substring(0, 20)}...');
          }
        } catch (regenerateError) {
          print('[FCM] ❌ Token regeneration failed: $regenerateError');
        }
      }

      if (token != null && token.isNotEmpty) {
        print('[FCM] 🔄 Step 4: Sending token to backend...');
        print('[FCM] Token length: ${token.length}');
        await ApiService.saveFCMToken(token);
        print('[FCM] ✅ ========== TOKEN SYNC COMPLETE ==========');
      } else {
        print('[FCM] ❌ NO TOKEN AVAILABLE AFTER ALL ATTEMPTS! Cannot sync');
        print('[FCM] ⚠️ Fallback: Generating local UUID as placeholder token...');
        
        // Fallback: Generate a local UUID if Firebase fails completely (better than nothing)
        try {
          // Use device ID + timestamp as fallback token
          final deviceId = await _getDeviceId();
          final fallbackToken = 'local_${deviceId}_${DateTime.now().millisecondsSinceEpoch}';
          print('[FCM] 🆔 Generated fallback token: $fallbackToken');
          await ApiService.saveFCMToken(fallbackToken);
          print('[FCM] ✅ Fallback token saved');
        } catch (fallbackError) {
          print('[FCM] ❌ Fallback also failed: $fallbackError');
        }
        
        print('[FCM] ❌ ========== TOKEN SYNC FAILED ==========');
      }
    } catch (e) {
      print('[FCM] ❌ ERROR DURING TOKEN SYNC: $e');
      print('[FCM] ❌ Stack trace: ${StackTrace.current}');
      print('[FCM] ❌ ========== TOKEN SYNC FAILED WITH EXCEPTION ==========');
    }
  }

  /// Get device ID as fallback
  static Future<String> _getDeviceId() async {
    try {
      // Try to get device ID from SharedPreferences if we've cached it
      final prefs = await SharedPreferences.getInstance();
      String? cachedId = prefs.getString('_device_id');
      if (cachedId != null && cachedId.isNotEmpty) {
        return cachedId;
      }
      
      // Generate a new one
      final uuid = const Uuid().v4();
      await prefs.setString('_device_id', uuid);
      return uuid;
    } catch (e) {
      print('[FCM] ⚠️ Could not get device ID: $e');
      return 'unknown_device';
    }
  }

  /// Initialize Firebase and FCM
  static Future<void> initializeFirebase() async {
    print('[FCM] 🚀🚀🚀 initializeFirebase() CALLED 🚀🚀🚀');
    
    if (_isInitialized) {
      print('[FCM] ℹ️ Firebase already initialized, skipping...');
      return;
    }

    try {
      print('[FCM] 🔄 Initializing Firebase...');
      print('[FCM] DEBUG: About to call Firebase.initializeApp()');

      // Initialize Firebase with platform-specific options
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      print('[FCM] ✅ Firebase initialized');
      print('[FCM] DEBUG: Firebase.initializeApp() completed successfully');

      // Ensure auto-init is enabled so token generation works after login
      await _firebaseMessaging.setAutoInitEnabled(true);

      // Request notification permissions
      await _requestNotificationPermissions();

      // Initialize local notifications (for displaying UI)
      await _initializeLocalNotifications();

      // Setup message handlers
      _setupMessageHandlers();
      
      // Set background message handler - MUST be called before any background messages
      print('[FCM] 🔧 Setting background message handler...');
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      print('[FCM] ✅ Background message handler registered');

      // Get FCM token and send to backend
      await _getFCMTokenAndSync();

      _isInitialized = true;
      print('[FCM] ✅ Firebase Messaging Service initialized successfully');
    } catch (e) {
      print('[FCM] ❌ Error initializing Firebase: $e');
      rethrow;
    }
  }

  /// Request notification permissions (iOS 10+, Android 13+)
  static Future<void> _requestNotificationPermissions() async {
    try {
      print('[FCM] 🔐 Requesting notification permissions...');

      final settings = await _firebaseMessaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      print('[FCM] 📍 Permission status: ${settings.authorizationStatus}');

      // Check if authorized
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('[FCM] ✅ Notifications authorized');
      } else if (settings.authorizationStatus ==
          AuthorizationStatus.provisional) {
        print('[FCM] ⚠️ Provisional notification permission granted');
      } else {
        print('[FCM] ❌ Notification permission denied');
      }
    } catch (e) {
      print('[FCM] ❌ Error requesting permissions: $e');
    }
  }

  /// Initialize local notifications for displaying notification UI
  static Future<void> _initializeLocalNotifications() async {
    try {
      print('[FCM] 🔄 Initializing local notifications...');

      // Android setup
      const AndroidInitializationSettings androidInitSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      // iOS setup
      const DarwinInitializationSettings iosInitSettings =
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const InitializationSettings initSettings = InitializationSettings(
        android: androidInitSettings,
        iOS: iosInitSettings,
      );

      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _handleNotificationTap,
        onDidReceiveBackgroundNotificationResponse: _handleNotificationTap,
      );

      // Explicit Android 13+ runtime permission request (device-level notifications)
      final androidImpl = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      final granted = await androidImpl?.requestNotificationsPermission();
      print('[FCM] 🔐 Android notifications permission granted: $granted');

      print('[FCM] ✅ Local notifications initialized');

      // Create notification channels for Android
      await _createNotificationChannels();
    } catch (e) {
      print('[FCM] ❌ Error initializing local notifications: $e');
    }
  }

  /// Create Android notification channels
  static Future<void> _createNotificationChannels() async {
    try {
      const AndroidNotificationChannel defaultChannel =
          AndroidNotificationChannel(
        'default_channel',
        'Default Notifications',
        description: 'Default notification channel',
        importance: Importance.high,
        sound: RawResourceAndroidNotificationSound('notification'),
      );

      const AndroidNotificationChannel chatChannel =
          AndroidNotificationChannel(
        'chat_channel',
        'Chat Messages',
        description: 'Notifications for new chat messages',
        importance: Importance.high,
        sound: RawResourceAndroidNotificationSound('notification'),
      );

      const AndroidNotificationChannel interactionChannel =
          AndroidNotificationChannel(
        'interaction_channel',
        'Interactions',
        description:
            'Notifications for likes, comments, mentions, and follows',
        importance: Importance.high,
        sound: RawResourceAndroidNotificationSound('notification'),
      );

      const AndroidNotificationChannel callChannel =
          AndroidNotificationChannel(
        'call_channel',
        'Calls',
        description: 'Notifications for incoming calls',
        importance: Importance.max,
        sound: RawResourceAndroidNotificationSound('notification'),
        enableVibration: true,
        enableLights: true,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(defaultChannel);

      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(chatChannel);

      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(interactionChannel);

      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(callChannel);

      print('[FCM] ✅ Android notification channels created');
    } catch (e) {
      print('[FCM] ⚠️ Error creating notification channels: $e');
    }
  }

  /// Setup message handlers for different states
  static void _setupMessageHandlers() {
    print('[FCM] 🔧 ========== SETTING UP MESSAGE HANDLERS ==========');

    // Handle foreground messages (app is open)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('[FCM] 📬 ========== FOREGROUND MESSAGE RECEIVED ==========');
      print('[FCM] Message ID: ${message.messageId}');
      print('[FCM] Title: ${message.notification?.title}');
      print('[FCM] Body: ${message.notification?.body}');
      print('[FCM] Data keys: ${message.data.keys.toList()}');
      print('[FCM] Data: ${message.data}');
      print('[FCM] Message type: ${message.data['type'] ?? 'UNKNOWN'}');
      print('[FCM] ℹ️ Will now show local notification...');

      // Show our local notification (don't rely on system notification)
      _showLocalNotification(
        message.notification?.title ?? 'Notification',
        message.notification?.body ?? '',
        message.data,
        message.notification?.android?.smallIcon,
      );
      print('[FCM] ✅ Foreground message processed');
    });

    // Handle background message tap (app is in background/terminated)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('[FCM] 📲 ========== APP OPENED FROM NOTIFICATION ==========');
      print('[FCM] Message ID: ${message.messageId}');
      print('[FCM] Data: ${message.data}');
      _handleMessageOpenedApp(message);
      print('[FCM] ✅ Message opened app callback processed');
    });

    print('[FCM] 🔧 ========== MESSAGE HANDLERS SETUP COMPLETE ==========');

    // Background handler is registered once in initializeFirebase()
    // using top-level _firebaseMessagingBackgroundHandler.


    print('[FCM] ✅ Message handlers registered');
  }

  /// Handle notification tap
  static void _handleNotificationTap(NotificationResponse response) {
    print('[FCM] 👆 Notification tapped');
    print('[FCM] 👆 Payload: ${response.payload}');
    print('[FCM] 👆 ID: ${response.id}');
    print('[FCM] 👆 Action ID: ${response.actionId}');

    // Parse payload
    final payloadString = response.payload;
    if (payloadString != null) {
      try {
        final payload = jsonDecode(payloadString) as Map<String, dynamic>;
        
        // Handle Call Notification Taps (Native Overlay usually handles this, but just in case)
        if (payload['type'] == 'incoming_call' || payload['type'] == 'CALL_INVITE') {
             CallStateManager().setIncomingCall(payload);
             return;
        }
        
        // Handle Navigation for other types
        _navigateBasedOnPayload(payload);
        
      } catch (e) {
        print('[FCM] ❌ Error parsing payload: $e');
      }
    }
  }

  /// Handle message when app is opened from notification
  /// Handle message when app is opened from notification
  static void _handleMessageOpenedApp(RemoteMessage message) {
    print('[FCM] 🔗 Handling message opened app: ${message.data}');
    _navigateBasedOnPayload(message.data);
  }

  /// Shared navigation logic for notification taps (foreground & background)
  static Future<void> _navigateBasedOnPayload(Map<String, dynamic> data) async {
    final context = rootNavigatorKey.currentContext;
    if (context == null) {
      print('[FCM] ❌ No context available for navigation');
      return;
    }

    try {
      final type = data['type']?.toString();
      final senderIdStr = data['senderId']?.toString() ?? data['userId']?.toString();
      final postIdStr = data['postId']?.toString();
      
      print('[FCM] 🧭 Processing navigation for type: $type');

      if (type == 'chat' || type == 'MESSAGE' || type == 'new_message') {
        final senderId = int.tryParse(senderIdStr ?? '0') ?? 0;
        if (senderId > 0) {
          print('[FCM] 🧭 Navigating to chat with user $senderId');
          // Fetch basic profile to build conversation
          final profile = await ApiService.getUserProfile(senderId);
          
          final conversation = Conversation(
            userId: senderId,
            username: profile['username'] ?? 'Unknown',
            fullName: profile['fullName'] ?? profile['username'] ?? 'Unknown',
            profilePictureUrl: profile['profilePictureUrl'],
            unreadCount: 0,
            isOnline: false, 
          );
          
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ChatDetailScreen(conversation: conversation))
          );
        }
      } else if (type == 'like' || type == 'comment' || type == 'mention' || type == 'reply' || 
                 type == 'LIKE' || type == 'COMMENT' || type == 'REPLY') {
        final postId = int.tryParse(postIdStr ?? '0') ?? 0;
        if (postId > 0) {
          print('[FCM] 🧭 Navigating to post $postId');
          final post = await ApiService.getPost(postId);
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => PostDetailScreen(post: post))
          );
        }
      } else if (type == 'follow' || type == 'follow_request' || type == 'FOLLOW') {
        final userId = int.tryParse(senderIdStr ?? '0') ?? 0;
        if (userId > 0) {
          print('[FCM] 🧭 Navigating to profile $userId');
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => UserProfileScreen(userId: userId))
          );
        }
      }
    } catch (e) {
      print('[FCM] ❌ Error navigating from notification: $e');
    }
  }

  /// Handle background message
  @pragma('vm:entry-point')
  static Future<void> _handleBackgroundMessage(RemoteMessage message) async {
    print('[FCM] 🔔 Background message received: ${message.messageId}');
    print('[FCM] Title: ${message.notification?.title}');
    print('[FCM] Body: ${message.notification?.body}');
    print('[FCM] Data: ${message.data}');

    // Show local notification even in background
    await _showLocalNotification(
      message.notification?.title ?? 'Notification',
      message.notification?.body ?? '',
      message.data,
      message.notification?.android?.smallIcon,
    );
  }

  /// Show local notification
  @pragma('vm:entry-point')
  static Future<void> _showLocalNotification(
    String title,
    String body,
    Map<String, dynamic> data,
    String? smallIcon,
  ) async {
    try {
      // ⏭️ SKIP CALL NOTIFICATIONS - Only show native foreground service notification
      // CALL_INVITE, CALL_ACCEPT, CALL_REJECT, CALL_END should use native Android service only
      final notificationType = data['type']?.toString().toUpperCase() ?? '';
      final titleLower = title.toLowerCase();
      final bodyLower = body.toLowerCase();
      
      print('[FCM] 🔔 ========== _showLocalNotification() ==========');
      print('[FCM] Type: $notificationType');
      print('[FCM] Title: "$title"');
      print('[FCM] Body: "$body"');
      print('[FCM] Data: $data');
      
      // � BUG FIX #3: COMPLETELY BLOCK ALL call-related Firebase notifications
      // Any message even remotely related to calls gets blocked completely
      final isCallNotification = 
          // Direct type checks
          notificationType.contains('CALL') ||
          notificationType.contains('RING') ||
          data['type'] == 'CALL_INVITE' || 
          data['type'] == 'incoming_call' || 
          data['type'] == 'CALL_ACCEPT' || 
          data['type'] == 'CALL_REJECT' || 
          data['type'] == 'CALL_END' ||
          data['type'] == 'CALL_STARTED' ||
          data['type'] == 'CALL_MISSED' ||
          data['call_type'] != null ||
          
          // Action field checks
          data['action'] == 'INCOMING_CALL' ||
          data['action'] == 'CALL_INVITE' ||
          data['action']?.toString().toUpperCase().contains('CALL') == true ||
          
          // Content-based checks (title)
          titleLower.contains('incoming call') ||
          titleLower.contains('call started') ||
          titleLower.contains('calling') ||
          titleLower.contains('call') && titleLower.contains('from') ||
          titleLower.contains('ringing') ||
          titleLower.contains('📞') ||
          titleLower.contains('☎️') ||
          titleLower.contains('📱') && bodyLower.contains('call') ||
          
          // Content-based checks (body)
          bodyLower.contains('is calling') ||
          bodyLower.contains('incoming call') ||
          bodyLower.contains('call started') ||
          bodyLower.contains('calling you') ||
          bodyLower.contains('ringing') ||
          bodyLower.contains('📞') ||
          bodyLower.contains('☎️') ||
          bodyLower.contains('miss a call') ||
          bodyLower.contains('ended') && bodyLower.contains('call');
      
      if (isCallNotification) {
        print('[FCM] 🚫🚫🚫 BUG FIX #3: COMPLETELY BLOCKING all call Firebase notifications');
        print('[FCM] Blocking type=$notificationType, title=$title, body=$body');
        print('[FCM] ⏭️ ONLY native Android notification will show - NO Flutter notification');
        print('[FCM] This ensures ZERO Firebase duplicates for calls');
        return; // Don't show ANYTHING - native service handles it ALL
      }

      // ✅ NEW: Suppress CHAT notifications if user is already in that chat
      // This prevents "corruptly delivering" (double notifications or unnecessary alerts) when active
      if (_currentActiveChatId != null && 
         (data['type'] == 'chat' || data['type'] == 'MESSAGE' || data['type'] == 'new_message')) {
            final senderId = int.tryParse(data['senderId']?.toString() ?? '0');
            print('[FCM] 📱 Chat message check: senderId=$senderId, activeChatId=$_currentActiveChatId');
            if (senderId != 0 && senderId == _currentActiveChatId) {
                print('[FCM] 🔕 SUPPRESSED: User is viewing this chat - no notification needed');
                // We still let the data process if needed but we DO NOT show the local notification
                return;
            } else {
              print('[FCM] ✅ Different sender - will show notification');
            }
      }

      print('[FCM] ✅ Passing suppression checks - showing notification');

      // Determine channel and sound based on notification type
      String channelId = 'default_channel';
      String channelName = 'Notifications';
      AndroidNotificationDetails androidDetails;
      
      // ✅ For message notifications, use senderName and messagePreview from data
      String displayTitle = title;
      String displayBody = body;
      
      if (data['type'] == 'MESSAGE' || data['type'] == 'new_message') {
        channelId = 'chat_channel';
        channelName = 'Chat Messages';
        
        // Extract sender name and message preview from data
        final senderName = data['senderName'] as String? ?? 'New Message';
        final messagePreview = data['messagePreview'] as String? ?? '';
        
        displayTitle = senderName;
        displayBody = messagePreview;
        
        print('[FCM] 💬 Message notification: sender=$senderName, preview=$messagePreview');
      } else if (data['type'] == 'FOLLOW' || data['type'] == 'LIKE' || data['type'] == 'COMMENT' || data['type'] == 'REPLY') {
        channelId = 'interaction_channel';
        channelName = 'Interactions';
      }
      
      androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: 'Notifications channel',
        importance: Importance.high,
        priority: Priority.high,
        sound: RawResourceAndroidNotificationSound('notification'),
        enableVibration: true,
        playSound: true,
        enableLights: true,
        visibility: NotificationVisibility.public,
      );
      
      print('[FCM] DEBUG: Using channel: $channelId ($channelName)');

      const DarwinNotificationDetails iosDetails =
          DarwinNotificationDetails(
        sound: 'default.caf',
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.active,
      );

      final NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Use timestamp-based notification ID for other notifications (can stack)
      int notificationId = DateTime.now().millisecond;

      print('[FCM] DEBUG: About to show notification with ID: $notificationId');
      print('[FCM] 🔔 Title: "$displayTitle" | Body: "$displayBody"');
      await _localNotifications.show(
        notificationId,
        displayTitle,
        displayBody,
        notificationDetails,
        payload: jsonEncode(data),
      );

      print('[FCM] ✅ Local notification shown with sound on channel: $channelId');
    } catch (e) {
      print('[FCM] ❌ Error showing notification: $e');
      print('[FCM] DEBUG: Exception type: ${e.runtimeType}');
    }
  }

  /// Update notification to show missed call status
  @pragma('vm:entry-point')
  static Future<void> updateNotificationToMissedCall(int callerId) async {
    try {
      print('[FCM] 📵 Updating notification to MISSED CALL for caller: $callerId');
      var notifInfo = _activeCallNotifications[callerId];
      
      if (notifInfo == null) {
        print('[FCM] ⚠️ No notification found for caller $callerId');
        return;
      }
      
      int notificationId = notifInfo['notificationId'];
      String callerName = notifInfo['callerName'] ?? 'Unknown';
      
      // Show updated notification for missed call
      final NotificationDetails notificationDetails = NotificationDetails(
        android: AndroidNotificationDetails(
          'missed_calls_channel',
          'Missed Calls',
          channelDescription: 'Notifications for missed calls',
          importance: Importance.high,
          priority: Priority.high,
          sound: RawResourceAndroidNotificationSound('notification'),
          enableVibration: false,
          playSound: false,
          enableLights: true,
          visibility: NotificationVisibility.public,
          autoCancel: true,
        ),
        iOS: const DarwinNotificationDetails(
          sound: 'default.caf',
          presentAlert: true,
          presentBadge: true,
          presentSound: false,
        ),
      );
      
      await _localNotifications.show(
        notificationId,
        'Missed Call',
        'Missed call from $callerName',
        notificationDetails,
      );
      
      print('[FCM] ✅ Notification updated to MISSED CALL - ID: $notificationId');
    } catch (e) {
      print('[FCM] ❌ Error updating notification to missed call: $e');
    }
  }

  /// Cancel/dismiss call notification when call ends
  static Future<void> cancelCallNotification(int callerId) async {
    try {
      print('[FCM] 🔔 Attempting to cancel call notification for caller: $callerId');
      print('[FCM] DEBUG: Active notifications: ${_activeCallNotifications.keys.toList()}');
      
      var notifInfo = _activeCallNotifications[callerId];
      if (notifInfo != null) {
        int notificationId = notifInfo['notificationId'];
        String callerName = notifInfo['callerName'] ?? 'Unknown';
        print('[FCM] 🔔 Cancelling notification ID: $notificationId (caller: $callerId - $callerName)');
        await _localNotifications.cancel(notificationId);
        _activeCallNotifications.remove(callerId);
        print('[FCM] ✅ Call notification cancelled for caller: $callerId');
        print('[FCM] DEBUG: Remaining active notifications: ${_activeCallNotifications.keys.toList()}');
      } else {
        print('[FCM] ⚠️ No notification found for caller: $callerId');
        print('[FCM] DEBUG: Currently tracking: ${_activeCallNotifications.entries.map((e) => '${e.key}->${e.value['notificationId']}').toList()}');
      }
    } catch (e) {
      print('[FCM] ❌ Error cancelling notification: $e');
    }
  }
  
  /// Cancel all call notifications (for emergency cleanup)
  static Future<void> cancelAllCallNotifications() async {
    try {
      print('[FCM] 🔔🔔🔔 cancelAllCallNotifications() CALLED 🔔🔔🔔');
      print('[FCM] DEBUG: Currently tracking ${_activeCallNotifications.length} notifications');
      print('[FCM] DEBUG: Notifications to clear: ${_activeCallNotifications.entries.map((e) => '${e.key}->${e.value['notificationId']}').toList()}');
      
      for (var entry in _activeCallNotifications.entries) {
        int notificationId = entry.value['notificationId'];
        int callerId = entry.key;
        String callerName = entry.value['callerName'] ?? 'Unknown';
        
        print('[FCM] 🔔 Cancelling notification ID: $notificationId (caller: $callerId - $callerName)');
        await _localNotifications.cancel(notificationId);
        print('[FCM] ✅ Cancelled notification ID: $notificationId');
      }
      
      print('[FCM] DEBUG: Clearing map...');
      _activeCallNotifications.clear();
      print('[FCM] ✅ All call notifications cleared - Map is now empty');
      print('[FCM] DEBUG: Active notifications remaining: ${_activeCallNotifications.length}');
    } catch (e) {
      print('[FCM] ❌ Error cancelling all notifications: $e');
      print('[FCM] DEBUG: Exception type: ${e.runtimeType}');
    }
  }

  /// Disable push notifications on logout and clear device token
  static Future<void> disablePushOnLogout() async {
    try {
      print('[FCM] 🔕 disablePushOnLogout() called');
      await _localNotifications.cancelAll();
      await cancelAllCallNotifications();
      await _firebaseMessaging.deleteToken();
      await _firebaseMessaging.setAutoInitEnabled(false);
      _isInitialized = false;
      print('[FCM] ✅ Push disabled and token cleared');
    } catch (e) {
      print('[FCM] ❌ Error disabling push on logout: $e');
    }
  }

  /// Show missed call notification (when receiver doesn't answer)
  @pragma('vm:entry-point')
  static Future<void> showMissedCallNotification({
    required int callerId,
    required String callerName,
  }) async {
    try {
      print('[FCM] 📵 showMissedCallNotification CALLED for caller: $callerId ($callerName)');
      
      // Fixed notification ID to prevent stacking
      int notificationId = 10000 + (callerId % 10000);
      
      // Store in tracking map
      _activeCallNotifications[callerId] = {
        'notificationId': notificationId,
        'callerName': callerName,
      };
      print('[FCM] ✅ Storing missed call notification - ID: $notificationId, Caller: $callerName');
      
      final NotificationDetails notificationDetails = NotificationDetails(
        android: AndroidNotificationDetails(
          'missed_calls_channel',
          'Missed Calls',
          channelDescription: 'Notifications for missed calls',
          importance: Importance.high,
          priority: Priority.high,
          sound: RawResourceAndroidNotificationSound('notification'),
          enableVibration: false,
          playSound: false,
          enableLights: true,
          visibility: NotificationVisibility.public,
          autoCancel: true,
        ),
        iOS: const DarwinNotificationDetails(
          sound: 'default.caf',
          presentAlert: true,
          presentBadge: true,
          presentSound: false,
        ),
      );
      
      await _localNotifications.show(
        notificationId,
        'Missed Call',
        'Missed call from $callerName',
        notificationDetails,
      );
      
      print('[FCM] ✅ Missed call notification shown - ID: $notificationId');
    } catch (e) {
      print('[FCM] ❌ Error showing missed call notification: $e');
    }
  }

  /// Get FCM token and send to backend
  static Future<void> _getFCMTokenAndSync() async {
    try {
      print('[FCM] 🔑 Getting FCM token...');
      print('[FCM] DEBUG: _firebaseMessaging instance: ${_firebaseMessaging.hashCode}');

      final token = await _firebaseMessaging.getToken();
      print('[FCM] 🔑 FCM Token generated: $token');
      print('[FCM] DEBUG: Token is null? ${token == null}');
      print('[FCM] DEBUG: Token is empty? ${token?.isEmpty ?? 'N/A'}');
      print('[FCM] DEBUG: Token length: ${token?.length ?? 0}');

      if (token != null && token.isNotEmpty) {
        print('[FCM] ✅ Valid token received, attempting to save to backend...');
        // Send token to backend
        try {
          print('[FCM] DEBUG: Calling ApiService.saveFCMToken()...');
          await ApiService.saveFCMToken(token);
          print('[FCM] ✅ FCM token saved to backend');
        } catch (e) {
          print('[FCM] ⚠️ Failed to save token to backend: $e');
          print('[FCM] DEBUG: Exception type: ${e.runtimeType}');
          print('[FCM] DEBUG: Full stack: ${StackTrace.current}');
        }
      } else {
        print('[FCM] ❌ Token is null or empty! Cannot save.');
      }

      // Listen for token refresh
      print('[FCM] DEBUG: Setting up token refresh listener...');
      _firebaseMessaging.onTokenRefresh.listen((newToken) {
        print('[FCM] 🔄 FCM Token refreshed: $newToken');
        print('[FCM] DEBUG: Refresh token length: ${newToken.length}');
        // Update token on backend
        ApiService.saveFCMToken(newToken).catchError((e) {
          print('[FCM] ⚠️ Failed to update token on refresh: $e');
          print('[FCM] DEBUG: Refresh exception type: ${e.runtimeType}');
        });
      });

      print('[FCM] ✅ FCM token sync completed');
    } catch (e) {
      print('[FCM] ❌ Error getting FCM token: $e');
      print('[FCM] DEBUG: Fatal exception type: ${e.runtimeType}');
      print('[FCM] DEBUG: Stack trace: ${StackTrace.current}');
    }
  }

  /// Send a test notification (for testing purposes)
  static Future<void> sendTestNotification({
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    await _showLocalNotification(
      title,
      body,
      data ?? {},
      null,
    );
  }
}
