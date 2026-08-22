import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider;
import 'src/app.dart';
import 'src/services/chat_websocket_service.dart';
import 'src/services/api_service.dart';
import 'src/services/call_signaling_service.dart';
import 'src/services/call_overlay_manager.dart';
import 'src/services/group_call_signaling_service.dart';
import 'src/services/group_call_overlay_manager.dart';
import 'src/services/call_notification_platform.dart';
import 'src/services/notification_service.dart';
import 'src/services/connectivity_service.dart';
import 'src/services/message_queue_service.dart';
import 'src/services/firebase_messaging_service.dart';
import 'src/state/chat_store.dart';
import 'src/state/call_state_manager.dart';
import 'src/state/missed_calls_store.dart';
import 'src/database/database_helper.dart';
import 'src/services/sqlite_persistence_helper.dart';
import 'src/services/sqlite_loader_service.dart';

/// App lifecycle observer to handle presence updates (PHASE 3 - NEW)
class _AppLifecycleObserver extends WidgetsBindingObserver {
  final ChatWebSocketService _wsService = ChatWebSocketService();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        print('[AppLifecycle] APP RESUMED - Sending ONLINE status');
        _wsService.sendPresenceUpdate(true);
        
        // 🔴 BUG FIX #3: Check if there's a pending incoming call when app resumes
        print('[AppLifecycle] 📞 Checking for pending incoming calls...');
        if (CallStateManager().currentState == CallState.incomingRinging) {
          print('[AppLifecycle] 📞 PENDING INCOMING CALL FOUND - showing IncomingCallScreen');
          // The CallOverlayManager should already be displaying it, but ensure it's visible
        }
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        print('[AppLifecycle] APP PAUSED/DETACHED - Sending OFFLINE status');
        _wsService.sendPresenceUpdate(false);
        break;
      case AppLifecycleState.hidden:
        // NOTE: Don't send offline on 'hidden' - it fires too frequently during normal navigation
        // Only paused/detached indicate the app is actually in background
        print('[AppLifecycle] APP HIDDEN - Ignoring (only paused/detached trigger offline)');
        break;
      case AppLifecycleState.inactive:
        // NOTE: Don't send offline on 'inactive' - it fires during dialogs, permission prompts, etc.
        print('[AppLifecycle] APP INACTIVE - Ignoring (transitional state)');
        break;
    }
  }
}

/// Background initialization service - runs after UI is shown
Future<void> _initializeAppInBackground(ChatStore chatStore) async {
  print('\n\n===== [BACKGROUND_INIT] ===== Starting background initialization =====');

  // ✅ Initialize connectivity monitoring
  try {
    final connectivityService = ConnectivityService();
    await connectivityService.initialize();
    print('[BACKGROUND_INIT] ✅ ConnectivityService initialized');
  } catch (e) {
    print('[BACKGROUND_INIT] ⚠️ ConnectivityService error: $e');
  }

  // Attempt to initialize WebSocket if there is an existing session
  try {
    print('[BACKGROUND_INIT] 🔄 Checking for existing session...');
    final token = await ApiService.getToken();
    final userId = await ApiService.getUserId();
    
    if (token != null && userId != null && userId > 0) {
      print('[BACKGROUND_INIT] 🔐 Validating stored session...');
      final isValidSession = await ApiService.validateStoredSession();
      
      if (!isValidSession) {
        print('[BACKGROUND_INIT] ❌ Session validation FAILED');
      } else {
        try {
          print('[BACKGROUND_INIT] 🟡 Connecting WebSocket for user=$userId...');
          final wsService = ChatWebSocketService();
          await wsService.connect(token, userId);
          print('[BACKGROUND_INIT] ✅ WebSocket CONNECTED');
          
          chatStore.setUserOnline(userId, true);
          
          // Initialize SQLite persistence
          try {
            print('[BACKGROUND_INIT] 🗄️  Initializing SQLite...');
            final dbHelper = DatabaseHelper();
            await dbHelper.database;
            
            chatStore.setCurrentUserId(userId);
            
            final persistenceHelper = SQLitePersistenceHelper();
            persistenceHelper.attachToChatService(
              wsService.messageStream,
              wsService.readReceiptStream,
            );
            
            print('[BACKGROUND_INIT] 📂 Loading chat data from SQLite...');
            final loaderService = SQLiteLoaderService();
            await loaderService.loadChatDataFromSQLite(chatStore, userId);
            print('[BACKGROUND_INIT] ✅ Chat data loaded (${chatStore.allConversations.length} conversations)');
            
            print('[BACKGROUND_INIT] 📋 Initializing message queue...');
            final messageQueueService = MessageQueueService();
            final connectivityService = ConnectivityService();
            await messageQueueService.initialize(wsService, connectivityService);
            print('[BACKGROUND_INIT] ✅ Message queue initialized');
          } catch (e) {
            print('[BACKGROUND_INIT] ⚠️ SQLite error: $e');
          }
          
          try {
            NotificationService().initialize();
            print('[BACKGROUND_INIT] ✅ NotificationService initialized');
          } catch (e) {
            print('[BACKGROUND_INIT] ⚠️ NotificationService error: $e');
          }
        } catch (e) {
          print('[BACKGROUND_INIT] ❌ WebSocket connection failed: $e');
        }
      }
    } else {
      print('[BACKGROUND_INIT] ⚠️ No existing session');
    }
  } catch (e) {
    print('[BACKGROUND_INIT] ❌ Error: $e');
  }

  print('[BACKGROUND_INIT] ===== Background initialization complete =====\n');
}

Future<void> main() async {
  // ⚡ MINIMAL INITIALIZATION - Show UI immediately!
  WidgetsFlutterBinding.ensureInitialized();
  print('\n\n===== [MAIN] ===== APP STARTING (Fast Mode) =====');

  // Initialize FCM early so foreground/background handlers are always ready.
  try {
    await FirebaseMessagingService.initializeFirebase();
    print('[MAIN] ✅ Firebase Messaging initialized at startup');
  } catch (e) {
    print('[MAIN] ⚠️ Firebase init error at startup: $e');
  }

  // Only initialize critical services that must run before UI
  try {
    WidgetsBinding.instance.addObserver(_AppLifecycleObserver());
    print('[MAIN] ✅ Lifecycle observer registered');
  } catch (e) {
    print('[MAIN] ⚠️ Lifecycle observer error: $e');
  }

  try {
    CallOverlayManager();
    print('[MAIN] ✅ CallOverlayManager initialized');
  } catch (e) {
    print('[MAIN] ⚠️ CallOverlayManager error: $e');
  }

  try {
    GroupCallOverlayManager();
    print('[MAIN] ✅ GroupCallOverlayManager initialized');
  } catch (e) {
    print('[MAIN] ⚠️ GroupCallOverlayManager error: $e');
  }

  // Create global ChatStore instance
  final chatStore = ChatStore();
  print('[MAIN] ✅ ChatStore created');

  try {
    ChatWebSocketService().setChatStore(chatStore);
    print('[MAIN] ✅ ChatStore injected');
  } catch (e) {
    print('[MAIN] ❌ ChatStore injection failed: $e');
  }

  try {
    // ignore: unused_local_variable
    final cs = CallSignalingService();
    print('[MAIN] ✅ CallSignalingService initialized');
  } catch (e) {
    print('[MAIN] ❌ CallSignalingService failed: $e');
  }

  try {
    // ignore: unused_local_variable
    final gcs = GroupCallSignalingService();
    print('[MAIN] ✅ GroupCallSignalingService initialized');
  } catch (e) {
    print('[MAIN] ❌ GroupCallSignalingService failed: $e');
  }

  try {
    MissedCallsStore().init();
    print('[MAIN] ✅ MissedCallsStore initialized');
  } catch (e) {
    print('[MAIN] ⚠️ MissedCallsStore error: $e');
  }

  try {
    CallNotificationPlatform.initializeMethodHandlers();
    CallNotificationPlatform.signalFlutterReady();
    print('[MAIN] ✅ Native method handlers initialized');
  } catch (e) {
    print('[MAIN] ⚠️ Native handlers error: $e');
  }

  try {
    final cm = CallStateManager();
    if (cm.currentState != CallState.idle) {
      print('[MAIN] ⚠️ Resetting orphaned call state...');
      cm.reset();
    }
  } catch (e) {
    print('[MAIN] ⚠️ CallStateManager error: $e');
  }

  print('[MAIN] ===== UI READY - Showing splash screen =====\n');

  // ⚡ START THE APP IMMEDIATELY - Show UI now!
  runApp(
    provider.MultiProvider(
      providers: [
        provider.ChangeNotifierProvider.value(value: chatStore),
        provider.ChangeNotifierProvider.value(value: CallStateManager()),
        provider.ChangeNotifierProvider.value(value: NotificationService()),
      ],
      child: const ProviderScope(child: MyApp()),
    ),
  );

  // 🔥 Do heavy initialization in background AFTER UI is shown
  _initializeAppInBackground(chatStore).catchError((e) {
    print('[MAIN] ❌ Background initialization error: $e');
  });
}
