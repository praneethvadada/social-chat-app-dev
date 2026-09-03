import 'package:stomp_dart_client/stomp.dart';
import 'package:stomp_dart_client/stomp_config.dart';
import 'package:stomp_dart_client/stomp_frame.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' show min;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import '../models/message.dart';
import '../navigation/root_navigator_key.dart';
import '../state/app_state_manager.dart';
import '../state/chat_store.dart';
import 'api_service.dart';
import 'chat_sync_service.dart';
import 'mobile_storage_gate.dart';

/// Typedef for notification listeners (required by other code)
typedef OnConnectionChanged = void Function(bool isConnected);
typedef OnNotificationReceived = void Function(Map<String, dynamic> notification);

enum MessageState { sending, sent, delivered, failed }

class ChatWebSocketService {
  static final ChatWebSocketService _instance = ChatWebSocketService._internal();
  
  late StompClient _stompClient;
  bool _isConnected = false;
  bool _isConnecting = false;
  Completer<void>? _connectCompleter;
  ChatStore? _chatStore;
  int _currentUserId = 0;
  String? _currentToken;
  final ChatSyncService _chatSyncService = ChatSyncService();
  
  // Message state tracking: clientMessageId → MessageState
  final Map<String, MessageState> _messageStates = {};

  // Pending server-acknowledgement timers: clientMessageId → Timer.
  // A message stays in `sending` (⏱) until the server acks it; if the ack never
  // arrives within _ackTimeout the message is marked FAILED so silent drops are
  // visible to the user instead of being disguised as delivered.
  final Map<String, Timer> _ackTimers = {};
  static const Duration _ackTimeout = Duration(seconds: 10);

  // Periodic presence heartbeat. Keeps the server's in-memory presence fresh so
  // its stale-sweep only reaps genuinely-dead sessions, not idle-but-connected
  // users. Must be shorter than the server's 45s stale cutoff.
  Timer? _presenceHeartbeatTimer;
  static const Duration _presenceHeartbeatInterval = Duration(seconds: 25);
  
  // Offline queue: messages pending delivery when not connected
  final List<Map<String, dynamic>> _offlineQueue = [];
  static const int _maxOfflineQueueSize = 100;
  
  // Subscriptions tracking (to avoid duplicate subscriptions)
  final Set<String> _activeSubscriptions = {};
  
  // Store actual subscription handlers to prevent garbage collection
  final Map<String, dynamic> _subscriptionHandlers = {};
  
  // Message deduplication - track recently processed message IDs to avoid duplicates
  final Set<String> _recentlyProcessedMessages = {};
  static const int _maxRecentMessagesTracked = 200;
  
  // Connection change listeners
  final List<void Function(bool)> _connectionListeners = [];
  
  // Notification listeners for follow, likes, comments, etc
  final List<OnNotificationReceived> _notificationListeners = [];
  
  // Notification stream for services to listen to real-time notifications
  final _notificationController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get notificationStream => _notificationController.stream;
  
  // Error stream for UI to show user-facing errors
  final _errorController = StreamController<String>.broadcast();
  Stream<String> get errorStream => _errorController.stream;
  
  // Message stream for SQLite persistence helper (write-behind cache)
  final _messageController = StreamController<Message>.broadcast();
  Stream<Message> get messageStream => _messageController.stream;
  
  // Read receipt stream for SQLite persistence helper
  final _readReceiptController = StreamController<ReadReceipt>.broadcast();
  Stream<ReadReceipt> get readReceiptStream => _readReceiptController.stream;
  
  // Ready future for services waiting for connection
  Future<void> get readyFuture => _connectCompleter?.future ?? Future.value();

  // Public getter to check if ChatStore is initialized
  ChatStore? get chatStore => _chatStore;

  factory ChatWebSocketService() {
    return _instance;
  }

  ChatWebSocketService._internal() {
    print('[ChatWebSocketService] INITIALIZED');
  }

  void setChatStore(ChatStore store) {
    _chatStore = store;
    if (_currentUserId != 0) {
      _chatStore?.setCurrentUserId(_currentUserId);
    }
    print('[ChatWebSocketService] ChatStore injected');
  }

  bool get isConnected => _isConnected;

  void addConnectionListener(void Function(bool) listener) {
    _connectionListeners.add(listener);
  }

  /// Connect WebSocket with authentication token
  Future<void> connect(String token, int userId) async {
    print('[ChatWebSocketService] 🔵 CONNECT CALLED: connected=$_isConnected connecting=$_isConnecting userId=$userId requestedUserId=$userId');
    
    // If already connected with a DIFFERENT userId, disconnect and reconnect with new user
    if (_isConnected && _currentUserId != userId) {
      print('[ChatWebSocketService] ⚠️ User changed from $_currentUserId to $userId - disconnecting and reconnecting');
      try {
        await disconnect();
        print('[ChatWebSocketService] ✅ Disconnected from previous user');
      } catch (e) {
        print('[ChatWebSocketService] ❌ Error disconnecting: $e');
      }
    }
    
    if (_isConnected && _currentUserId == userId) {
      print('[ChatWebSocketService] 🟢 Already connected with same userId, returning');
      return;
    }
    
    if (_isConnecting) {
      print('[ChatWebSocketService] 🟡 Already connecting, waiting for completion...');
      return await _connectCompleter?.future;
    }
    
    _isConnecting = true;
    _currentUserId = userId;
    _currentToken = token;
    
    final wsUrl = ApiConfig.wsUrl;
    print('[ChatWebSocketService] 🟡 CONNECTING to $wsUrl for user=$_currentUserId');
    print('[ChatWebSocketService] 🟡 Token present: ${token.isNotEmpty}');

    final connectHeaders = {
      'Authorization': 'Bearer $token',
    };

    _connectCompleter = Completer<void>();

    try {
      print('[ChatWebSocketService] 🟡 Creating StompClient...');
      _stompClient = StompClient(
        config: StompConfig.SockJS(
          url: wsUrl,
          webSocketConnectHeaders: connectHeaders,
          stompConnectHeaders: connectHeaders,
          onConnect: _onConnect,
          onDisconnect: _onDisconnect,
          onStompError: _onStompError,
          onWebSocketError: _onWebSocketError,
          beforeConnect: () async {
            print('[ChatWebSocketService] beforeConnect hook called');
          },
          // === CRITICAL FIX: Add heartbeat configuration ===
          // Heartbeats keep the connection alive and ensure frames are received
          heartbeatIncoming: const Duration(milliseconds: 10000),
          heartbeatOutgoing: const Duration(milliseconds: 10000),
          // === CRITICAL FIX: Add debug message callback to see all frames ===
          onDebugMessage: (String message) {
            // Log all STOMP frames for debugging - include read-receipts
            if (message.contains('MESSAGE') && (message.contains('/queue/messages') || message.contains('typing') || message.contains('/queue/typing') || message.contains('read-receipts'))) {
              print('[ChatWebSocketService] 🔍 RAW STOMP FRAME: $message');
            }
          },
          // === CRITICAL FIX: Catch unhandled messages ===
          onUnhandledMessage: (StompFrame frame) {
            print('[CHECKPOINT-001] onUnhandledMessage CALLED');
            final destination = frame.headers['destination'] ?? '';
            final subscription = frame.headers['subscription'] ?? '';
            
            print('\n[ChatWebSocketService] ⚠️⚠️⚠️ UNHANDLED MESSAGE ARRIVED ⚠️⚠️⚠️');
            print('[ChatWebSocketService]    ├─ Destination: $destination');
            print('[ChatWebSocketService]    ├─ Subscription: $subscription');
            print('[ChatWebSocketService]    ├─ Frame command: ${frame.command}');
            print('[ChatWebSocketService]    ├─ All headers: ${frame.headers}');
            print('[ChatWebSocketService]    └─ Body preview: ${frame.body?.substring(0, min(150, frame.body?.length ?? 0))}');
            
            // ⭐ CRITICAL: Check for read-receipt messages FIRST (highest priority)
            print('[CHECKPOINT-002] Checking if destination or subscription contains read-receipts');
            print('[CHECKPOINT-003] destination.contains(read-receipts)=${destination.contains('read-receipts')}');
            print('[CHECKPOINT-004] subscription.contains(read-receipts)=${subscription.contains('read-receipts')}');
            
            if (destination.contains('read-receipts') || subscription.contains('read-receipts')) {
              print('[CHECKPOINT-005] READ RECEIPT CONDITION MATCHED!');
              print('[ChatWebSocketService] 🚨🚨🚨 UNHANDLED READ RECEIPT DETECTED - PROCESSING MANUALLY 🚨🚨🚨');
              try {
                print('[CHECKPOINT-006] Attempting to decode frame body');
                final data = jsonDecode(frame.body ?? '{}') as Map<String, dynamic>;
                print('[CHECKPOINT-007] JSON decode SUCCEEDED');
                print('[ChatWebSocketService] ✅ Parsed read receipt: $data');
                print('[CHECKPOINT-008] Calling _handleReadReceipt(data)');
                _handleReadReceipt(data);
                print('[CHECKPOINT-009] _handleReadReceipt returned successfully');
                print('[ChatWebSocketService] ✅ Read receipt processing COMPLETE');
              } catch (e, st) {
                print('[CHECKPOINT-010] EXCEPTION in onUnhandledMessage: $e');
                print('[ChatWebSocketService] ❌ ERROR processing read receipt: $e');
                print('[ChatWebSocketService] ❌ Stack: $st');
              }
              print('[CHECKPOINT-011] Returning from onUnhandledMessage after handling read receipt');
              return;
            }
            print('[CHECKPOINT-012] No read-receipt match, checking for other message types');
            
            // CRITICAL: Check for typing messages
            if (destination.contains('typing') || subscription.contains('typing')) {
              print('[ChatWebSocketService] 🚨 UNHANDLED TYPING MESSAGE DETECTED! Processing manually...');
              _onTypingIndicator(frame);
              return;
            }
            
            // Try to handle it manually if it's a message
            if (destination.contains('/queue/messages') || destination.contains('messages')) {
              print('[ChatWebSocketService] 🔄 Attempting to manually process unhandled message...');
              _handleMessageQueueFrame(frame);
            }
          },
          onUnhandledReceipt: (StompFrame frame) {
            print('[ChatWebSocketService] 📨 UNHANDLED RECEIPT: ${frame.headers}');
          },
          // Reconnect configuration
          reconnectDelay: const Duration(milliseconds: 5000),
        ),
      );

      print('[ChatWebSocketService] 🟡 Calling activate()...');
      _stompClient.activate();
      
      print('[ChatWebSocketService] 🟡 Waiting for connection with 15s timeout...');
      // Wait for connection to complete
      await _connectCompleter?.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          print('[ChatWebSocketService] ⏱️ CONNECTION TIMEOUT after 15 seconds');
          throw Exception('WebSocket connection timeout - _onConnect was never called');
        },
      );
      
      print('[ChatWebSocketService] ✅ Connection established successfully');
    } catch (e) {
      _isConnecting = false;
      _isConnected = false;
      print('[ChatWebSocketService] ❌ Connection failed: $e');
      print('[ChatWebSocketService] ❌ Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  void _onConnect(StompFrame frame) {
    print('\n\n🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢');
    print('[ChatWebSocketService] ✅ CONNECTED TO STOMP BROKER');
    print('[ChatWebSocketService] 📊 Frame headers: ${frame.headers}');
    print('[ChatWebSocketService] ✅ Current user ID: $_currentUserId');
    print('🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢\n');
    
    _isConnected = true;
    _isConnecting = false;

    // Complete the completer only if it hasn't been completed yet
    if (_connectCompleter != null && !_connectCompleter!.isCompleted) {
      _connectCompleter?.complete();
    }
    _notifyConnectionListeners(true);

    // Start periodic presence heartbeat so the server keeps us "online".
    _startPresenceHeartbeat();
    
    // Subscribe to personal message queue
    print('[ChatWebSocketService] 🔔 Subscribing to message queue for user=$_currentUserId...');
    _subscribeToMessageQueue();
    
    // === CRITICAL FIX: Also subscribe to explicit user destination as backup ===
    print('[ChatWebSocketService] 🔔 Subscribing to explicit user destination as backup...');
    _subscribeToExplicitUserDestination();
    
    // Subscribe to typing indicators
    print('[ChatWebSocketService] 🔔 Subscribing to typing indicators...');
    _subscribeToTypingIndicators();
    
    // === DEBUG: Add catch-all frame listener to see what frames come in ===
    print('[ChatWebSocketService] 🔔 Setting up frame listener to debug all frames...');
    
    // Subscribe to typing indicators
    print('[ChatWebSocketService] 🔔 Subscribing to typing indicators for user=$_currentUserId...');
    _subscribeToTypingIndicators();
    
    // Subscribe to notifications (follow, like, comment, etc)
    print('[ChatWebSocketService] 🔔 Subscribing to notifications for user=$_currentUserId...');
    _subscribeToNotifications();
    
    // Subscribe to incoming call signals
    print('[ChatWebSocketService] 🔔 Subscribing to incoming calls for user=$_currentUserId...');
    _subscribeToIncomingCalls();
    
    // ✅ NEW: Subscribe to presence updates (personal queue for initial status)
    print('[ChatWebSocketService] 🔔 Subscribing to presence updates for user=$_currentUserId...');
    _subscribeToPresenceUpdates();
    // NOTE: _subscribeToUserPresenceQueue() removed - _subscribeToPresenceUpdates() already subscribes to /user/queue/presence
    
    // ✅ TEMPORARY: Subscribe to ALL users broadcast for now
    // Backend endpoint /app/presence.subscribe-contacts not implemented yet
    // TODO: Implement contact-based presence on backend for scalability
    print('[ChatWebSocketService] ✅ ENABLED temporarily - will optimize after backend ready');
    _subscribeToAllUsersPresence();  // ✅ ENABLED temporarily - will optimize after backend ready
    
    // Subscribe to read receipts
    print('[ChatWebSocketService] 🔔 Subscribing to read receipts for user=$_currentUserId...');
    _subscribeToReadReceipts();
    _subscribeToExplicitReadReceiptsDestination();

    // Subscribe to send acknowledgements so outgoing messages can be confirmed
    // (✓) or marked failed (❌) instead of silently assumed delivered.
    _subscribeToMessageAcks();

    // Security events (Phase 3's local_storage.revoked, Phase 5's
    // session.revoked) — best-effort real-time nudges from auth-service.
    _subscribeToSecurityEvents();

    _processOfflineQueue();

    // Phase 4: catch up on anything that arrived while disconnected. Fires on
    // every connect (initial AND reconnect), not just app cold-start - a
    // reconnect after a network blip needs the same catch-up as a fresh
    // launch. Only writes local data on a device that currently owns local
    // storage (Phase 3) - re-checked every reconnect rather than cached once,
    // so a device that loses ownership mid-session stops here too.
    if (!kIsWeb && _chatStore != null) {
      MobileStorageGate.silentCheck().then((isOwner) {
        if (isOwner == true) {
          _chatSyncService.syncAll(_chatStore!, _currentUserId).catchError((e) {
            print('[ChatWebSocketService] ⚠️ Chat sync failed: $e');
          });
        }
      });
    }

    _notifyPresenceUpdate(true);
    
    // ✅ Request initial presence status (who is already online)
    // CRITICAL: Reduce delay to 500ms for faster UI updates - users should see online status immediately
    Future.delayed(const Duration(milliseconds: 500), () {
      print('[ChatWebSocketService] ⏰ Initial presence request starting (after 500ms)...');
      print('[ChatWebSocketService]    └─ Active subscriptions: ${_activeSubscriptions.toList()}');
      _requestInitialPresence();
    });
  }

  void _onDisconnect(StompFrame frame) {
    print('[ChatWebSocketService] 🔴 DISCONNECTED');
    print('[ChatWebSocketService] ❌ Active subscriptions being cleared: ${_activeSubscriptions.toList()}');
    _isConnected = false;
    _isConnecting = false;
    _activeSubscriptions.clear();
    _stopPresenceHeartbeat();
    _notifyConnectionListeners(false);
    
    // Auto-reconnect after 5 seconds if we have credentials
    if (_currentToken != null && _currentUserId > 0) {
      print('[ChatWebSocketService] 🔄 Scheduling reconnection in 5s...');
      Future.delayed(const Duration(seconds: 5), () {
        if (!_isConnected && !_isConnecting) {
          print('[ChatWebSocketService] 🔄 Attempting reconnection for userId=$_currentUserId...');
          connect(_currentToken!, _currentUserId).catchError((e) {
            print('[ChatWebSocketService] ❌ Reconnection failed: $e');
          });
        }
      });
    }
  }

  void _onStompError(StompFrame frame) {
    print('[ChatWebSocketService] ❌ STOMP ERROR RECEIVED');
    print('[ChatWebSocketService] Headers: ${frame.headers}');
    print('[ChatWebSocketService] Body: ${frame.body}');
    _isConnected = false;

    // Phase 5: WebSocketSecurityInterceptor rejects every frame from a
    // revoked session (single-active-web-session takeover, remote device
    // logout) with a "Session revoked" STOMP ERROR — connection-scoped, so
    // unlike the best-effort /queue/security push, receiving THIS error
    // unambiguously means it's OUR OWN session, not another device's.
    final signal = ('${frame.headers['message'] ?? ''} ${frame.body ?? ''}').toLowerCase();
    if (signal.contains('session revoked')) {
      print('[ChatWebSocketService] 🔒 Session revoked by server — forcing logout');
      _handleForcedLogout();
    }
  }

  /// Ends the local session the same way a manual logout does (stop
  /// reconnect attempts, clear local chat data, sign out server-side,
  /// return to the login screen) but triggered from the WebSocket layer
  /// itself rather than a user tapping a button. Uses the app's global
  /// navigator key to reach Riverpod/app state from this singleton service,
  /// which otherwise has no BuildContext of its own.
  Future<void> _handleForcedLogout() async {
    await clear(); // stops the auto-reconnect loop before it can retry with the now-dead token
    try {
      await ApiService.logout();
    } catch (e) {
      print('[ChatWebSocketService] ⚠️ Logout cleanup failed (session was already revoked server-side): $e');
    }

    final context = rootNavigatorKey.currentContext;
    if (context == null) return;
    ProviderScope.containerOf(context, listen: false)
        .read(appStateProvider.notifier)
        .logout();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('You were logged out because your account was signed in on another device.'),
      duration: Duration(seconds: 6),
    ));
  }

  void _onWebSocketError(dynamic error) {
    print('[ChatWebSocketService] ❌ WEBSOCKET ERROR');
    print('[ChatWebSocketService] Error: $error');
    print('[ChatWebSocketService] Error type: ${error.runtimeType}');
    print('[ChatWebSocketService] ❌ Stack: ${StackTrace.current}');
    _isConnected = false;
    
    // Try to reconnect after a short delay
    print('[ChatWebSocketService] 🔄 Scheduling reconnection in 2 seconds...');
    Future.delayed(const Duration(seconds: 2), () {
      if (!_isConnected && !_isConnecting && _currentToken != null && _currentUserId > 0) {
        print('[ChatWebSocketService] 🔄 Attempting automatic reconnection...');
        connect(_currentToken!, _currentUserId).catchError((e) {
          print('[ChatWebSocketService] ❌ Auto-reconnection failed: $e');
        });
      }
    });
  }

  /// Subscribe to personal message queue: /user/queue/messages
  void _subscribeToMessageQueue() {
    final topic = '/user/queue/messages';
    if (_activeSubscriptions.contains(topic)) {
      print('[ChatWebSocketService] ⚠️ Already subscribed to $topic (skipping re-subscription)');
      return;
    }

    print('[ChatWebSocketService] 📨 SUBSCRIBING to $topic');
    print('[ChatWebSocketService] 🔍 DEBUG INFO:');
    print('[ChatWebSocketService]    ├─ _currentUserId: $_currentUserId');
    print('[ChatWebSocketService]    ├─ _isConnected: $_isConnected');
    print('[ChatWebSocketService]    ├─ _stompClient.isActive: ${_stompClient.isActive}');
    print('[ChatWebSocketService]    ├─ _stompClient: ${_stompClient.runtimeType}');
    print('[ChatWebSocketService]    └─ Topic: $topic');
    
    try {
      // === CRITICAL FIX: Use a unique subscription ID ===
      // Spring STOMP routes messages by subscription ID, not by destination
      final subscriptionId = 'sub-messages-$_currentUserId-${DateTime.now().millisecondsSinceEpoch}';
      print('[ChatWebSocketService] 🔑 Using subscription ID: $subscriptionId');
      
      // === CRITICAL FIX: Wrap callback with try-catch to catch any errors ===
      void wrappedCallback(StompFrame frame) {
        print('[ChatWebSocketService] 🚨🚨🚨 WRAPPED CALLBACK TRIGGERED 🚨🚨🚨');
        try {
          _handleMessageQueueFrame(frame);
        } catch (e, st) {
          print('[ChatWebSocketService] ❌ CALLBACK ERROR: $e');
          print('[ChatWebSocketService] ❌ CALLBACK STACK: $st');
        }
      }
      
      // Store the unsubscribe function to prevent garbage collection
      final unsubscribeFn = _stompClient.subscribe(
        destination: topic,
        callback: wrappedCallback,
        headers: {'id': subscriptionId, 'ack': 'auto'},
      );
      
      // Store handler to prevent GC
      _subscriptionHandlers[topic] = unsubscribeFn;
      // Also store the callback to prevent GC
      _subscriptionHandlers['${topic}_callback'] = wrappedCallback;
      _activeSubscriptions.add(topic);
      
      print('[ChatWebSocketService] ✅ SUBSCRIPTION REGISTERED for $topic');
      print('[ChatWebSocketService] ✅ Subscription ID: $subscriptionId');
      print('[ChatWebSocketService] ✅ Subscription handler stored: ${unsubscribeFn != null}');
      print('[ChatWebSocketService] ✅ Active subscriptions: ${_activeSubscriptions.toList()}');
      print('[ChatWebSocketService] ✅ Total subscriptions: ${_activeSubscriptions.length}');
    } catch (e) {
      print('[ChatWebSocketService] ❌ ERROR SUBSCRIBING: $e');
      print('[ChatWebSocketService] ❌ Stack: ${StackTrace.current}');
      rethrow;
    }
  }
  
  /// === CRITICAL FIX: Backup subscription to explicit user destination ===
  /// Some STOMP implementations require subscribing to the explicit path
  void _subscribeToExplicitUserDestination() {
    // Subscribe to /user/{userId}/queue/messages as a backup
    final topic = '/user/$_currentUserId/queue/messages';
    if (_activeSubscriptions.contains(topic)) {
      print('[ChatWebSocketService] ⚠️ Already subscribed to explicit destination $topic');
      return;
    }
    
    try {
      final subscriptionId = 'sub-explicit-$_currentUserId-${DateTime.now().millisecondsSinceEpoch}';
      print('[ChatWebSocketService] 📨 SUBSCRIBING to EXPLICIT USER DESTINATION: $topic');
      print('[ChatWebSocketService] 🔑 Subscription ID: $subscriptionId');
      
      final unsubscribeFn = _stompClient.subscribe(
        destination: topic,
        callback: (StompFrame frame) {
          print('[ChatWebSocketService] 🚨 EXPLICIT USER DESTINATION CALLBACK FIRED! 🚨');
          _handleMessageQueueFrame(frame);
        },
        headers: {'id': subscriptionId, 'ack': 'auto'},
      );
      
      _subscriptionHandlers[topic] = unsubscribeFn;
      _activeSubscriptions.add(topic);
      print('[ChatWebSocketService] ✅ Explicit user destination subscription registered');
    } catch (e) {
      print('[ChatWebSocketService] ❌ Error subscribing to explicit destination: $e');
    }
  }

  /// === CRITICAL FIX: Explicit subscription for typing destination ===
  /// Backend sends to /user/{userId}/queue/typing but we also need explicit subscription
  void _subscribeToExplicitTypingDestination() {
    final topic = '/user/$_currentUserId/queue/typing';
    if (_activeSubscriptions.contains(topic)) {
      print('[ChatWebSocketService] ⚠️ Already subscribed to explicit typing destination $topic');
      return;
    }
    
    try {
      final subscriptionId = 'sub-explicit-typing-$_currentUserId-${DateTime.now().millisecondsSinceEpoch}';
      print('[ChatWebSocketService] ⌨️ SUBSCRIBING to EXPLICIT TYPING DESTINATION: $topic');
      print('[ChatWebSocketService] 🔑 Subscription ID: $subscriptionId');
      
      final unsubscribeFn = _stompClient.subscribe(
        destination: topic,
        callback: (StompFrame frame) {
          print('[ChatWebSocketService] 🚨 EXPLICIT TYPING DESTINATION CALLBACK FIRED! 🚨');
          _onTypingIndicator(frame);
        },
        headers: {'id': subscriptionId, 'ack': 'auto'},
      );
      
      _subscriptionHandlers[topic] = unsubscribeFn;
      _activeSubscriptions.add(topic);
      print('[ChatWebSocketService] ✅ Explicit typing destination subscription registered');
    } catch (e) {
      print('[ChatWebSocketService] ❌ Error subscribing to explicit typing destination: $e');
    }
  }
  
  /// Handle incoming frame from /user/queue/messages
  /// === CRITICAL FIX: Deduplicate at frame level to prevent multiple callbacks ===
  void _handleMessageQueueFrame(StompFrame frame) {
    print('\n\n[ChatWebSocketService] 🔔🔔🔔🔔🔔🔔🔔🔔 MESSAGE QUEUE CALLBACK FIRED 🔔🔔🔔🔔🔔🔔🔔🔔');
    print('[ChatWebSocketService] 📨 Frame received on /user/queue/messages');
    print('[ChatWebSocketService] Frame command: ${frame.command}');
    print('[ChatWebSocketService] Frame headers: ${frame.headers}');
    print('[ChatWebSocketService] Frame body length: ${frame.body?.length ?? 0}');
    
    if (frame.body != null && frame.body!.isNotEmpty) {
      final preview = frame.body!.length > 200 
          ? '${frame.body!.substring(0, 200)}...' 
          : frame.body!;
      print('[ChatWebSocketService] Frame body: $preview');
    }
    
    try {
      if (frame.body == null || frame.body!.isEmpty) {
        print('[ChatWebSocketService] ⚠️ Empty frame body received');
        return;
      }
      
      // === FRAME-LEVEL DEDUPLICATION: Check message-id header ===
      // This prevents duplicate processing when multiple subscriptions deliver the same frame
      final messageId = frame.headers['message-id'] as String?;
      final subscription = frame.headers['subscription'] as String?;
      
      if (messageId != null && subscription != null) {
        final frameDedupeKey = '${subscription}_${messageId}';
        
        if (_recentlyProcessedMessages.contains(frameDedupeKey)) {
          print('[ChatWebSocketService] ⚠️⚠️⚠️ DUPLICATE FRAME DETECTED (multiple subscriptions) ⚠️⚠️⚠️');
          print('[ChatWebSocketService]    ├─ message-id: $messageId');
          print('[ChatWebSocketService]    ├─ subscription: $subscription');
          print('[ChatWebSocketService]    └─ dedupeKey: $frameDedupeKey (SKIPPING - already processed)');
          return;
        }
        
        // Mark this frame as processed
        _recentlyProcessedMessages.add(frameDedupeKey);
        print('[ChatWebSocketService] ✅ Frame added to processed set: $frameDedupeKey');
      }
      
      _onMessageReceived(frame);
      print('[ChatWebSocketService] ✅ Frame processed successfully');
    } catch (e, st) {
      print('[ChatWebSocketService] ❌ ERROR processing frame: $e');
      print('[ChatWebSocketService] ❌ Stack: $st');
      print('[ChatWebSocketService] ❌ Raw body: ${frame.body}');
    }
    print('[ChatWebSocketService] 🔔🔔🔔🔔🔔🔔🔔🔔 END CALLBACK 🔔🔔🔔🔔🔔🔔🔔🔔\n\n');
  }

  /// Subscribe to typing indicators: /user/queue/typing
  void _subscribeToTypingIndicators() {
    final topic = '/user/queue/typing';
    if (_activeSubscriptions.contains(topic)) {
      print('[ChatWebSocketService] ⚠️ Already subscribed to $topic');
      return;
    }

    try {
      print('[ChatWebSocketService] 📝 SUBSCRIBING to typing indicators at $topic...');
      print('[ChatWebSocketService]    ├─ Current User ID: $_currentUserId');
      print('[ChatWebSocketService]    ├─ STOMP Connected: $_isConnected');
      print('[ChatWebSocketService]    └─ Subscription will receive messages from backend convertAndSendToUser()');
      
      // Create callback wrapper with additional logging
      void typingCallback(StompFrame frame) {
        print('[ChatWebSocketService] 🚨🚨🚨 TYPING CALLBACK FIRED 🚨🚨🚨');
        print('[ChatWebSocketService]    ├─ Frame destination: ${frame.headers?['destination']}');
        print('[ChatWebSocketService]    ├─ Frame subscription: ${frame.headers?['subscription']}');
        print('[ChatWebSocketService]    └─ Frame message-id: ${frame.headers?['message-id']}');
        _onTypingIndicator(frame);
      }
      
      // Store the unsubscribe function to prevent garbage collection
      final unsubscribeFn = _stompClient.subscribe(
        destination: topic,
        callback: typingCallback,
        headers: {'id': 'sub-typing-${_currentUserId}', 'ack': 'auto'},
      );
      
      // Store handler to prevent GC
      _subscriptionHandlers[topic] = unsubscribeFn;
      _activeSubscriptions.add(topic);
      
      // CRITICAL: Also subscribe to EXPLICIT user destination for typing
      _subscribeToExplicitTypingDestination();
      
      print('[ChatWebSocketService] ✅ Subscribed to $topic');
      print('[ChatWebSocketService]    ├─ Subscription ID: sub-typing-${_currentUserId}');
      print('[ChatWebSocketService]    ├─ Handler stored: ${unsubscribeFn != null}');
      print('[ChatWebSocketService]    ├─ STOMP subscribe() returned: ${unsubscribeFn != null ? 'Function' : 'null'}');
      print('[ChatWebSocketService]    └─ Active subscriptions: ${_activeSubscriptions.length}');
    } catch (e) {
      print('[ChatWebSocketService] ❌ ERROR SUBSCRIBING to typing: $e');
      print('[ChatWebSocketService]    └─ Stack trace: ${StackTrace.current}');
    }
  }

  /// Subscribe to notifications queue: /user/queue/notifications
  /// Receives: follow, like, comment, mention notifications, etc
  void _subscribeToNotifications() {
    final topic = '/user/queue/notifications';
    if (_activeSubscriptions.contains(topic)) {
      print('[ChatWebSocketService] ⚠️ Already subscribed to $topic');
      return;
    }

    try {
      print('[ChatWebSocketService] 🔔 SUBSCRIBING to notifications at $topic...');
      
      // Store the unsubscribe function to prevent garbage collection
      final unsubscribeFn = _stompClient.subscribe(
        destination: topic,
        callback: _onNotificationReceived,
        headers: {'id': 'sub-notifications-${_currentUserId}', 'ack': 'auto'},
      );
      
      // Store handler to prevent GC
      _subscriptionHandlers[topic] = unsubscribeFn;
      _activeSubscriptions.add(topic);
      
      print('[ChatWebSocketService] ✅ Subscribed to $topic');
      print('[ChatWebSocketService]    └─ Handler stored: ${unsubscribeFn != null}');
    } catch (e) {
      print('[ChatWebSocketService] ❌ ERROR SUBSCRIBING to notifications: $e');
    }
  }

  /// Best-effort real-time security notices pushed via auth-service's relay
  /// (see ChatsServiceRelayClient / /internal/relay/to-user server-side).
  /// These are account-wide broadcasts, not scoped to one device/session, so
  /// only notices that are safe to act on unconditionally — regardless of
  /// which of the account's devices they were really about — are handled
  /// here. `session.revoked` is deliberately NOT one of these (see
  /// _onStompError's "Session revoked" ERROR-frame handling instead, which
  /// is connection-scoped and therefore unambiguous).
  void _subscribeToSecurityEvents() {
    final topic = '/user/queue/security';
    if (_activeSubscriptions.contains(topic)) {
      print('[ChatWebSocketService] ⚠️ Already subscribed to $topic');
      return;
    }
    try {
      print('[ChatWebSocketService] 🔔 SUBSCRIBING to security events at $topic...');
      final unsubscribeFn = _stompClient.subscribe(
        destination: topic,
        callback: _onSecurityEvent,
        headers: {'id': 'sub-security-${_currentUserId}', 'ack': 'auto'},
      );
      _subscriptionHandlers[topic] = unsubscribeFn;
      _activeSubscriptions.add(topic);
      print('[ChatWebSocketService] ✅ Subscribed to $topic');
    } catch (e) {
      print('[ChatWebSocketService] ❌ ERROR SUBSCRIBING to security events: $e');
    }
  }

  void _onSecurityEvent(StompFrame frame) {
    try {
      final data = jsonDecode(frame.body ?? '{}') as Map<String, dynamic>;
      final type = data['type'] as String?;
      print('[ChatWebSocketService] 🔒 Security event received: $type');
      if (type == 'local_storage.revoked' && !kIsWeb) {
        _handleLocalStorageRevoked(data);
      } else if (type == 'session.revoked' && kIsWeb) {
        _handleSessionRevokedBroadcast(data);
      }
    } catch (e) {
      print('[ChatWebSocketService] ⚠️ Error processing security event: $e');
    }
  }

  /// These relay pushes are account-wide (every connected device gets them),
  /// not scoped to one device/session — so before reacting, compare the
  /// payload's numeric backend device id against our own (persisted at
  /// login from AuthResponse.deviceId, see ApiService.getBackendDeviceId).
  /// Without this a device could act on a notice that was really about a
  /// DIFFERENT device on the same account.
  Future<void> _handleLocalStorageRevoked(Map<String, dynamic> data) async {
    final myDeviceId = await ApiService.getBackendDeviceId();
    final revokedDeviceId = data['revokedDeviceId'];
    // Can't disambiguate (pre-Phase-5 session with no stored device id) —
    // fall back to the always-safe unconditional re-check rather than
    // silently doing nothing.
    final pertainsToMe = myDeviceId == null || revokedDeviceId == null || myDeviceId == revokedDeviceId;
    if (pertainsToMe) {
      // MobileStorageGate.silentCheck() is itself idempotent/self-correcting
      // against the server's actual state, so this is safe even when it
      // turns out to be a false positive.
      await MobileStorageGate.silentCheck();
    } else {
      print('[ChatWebSocketService] 🔒 local_storage.revoked was about a different device (id=$revokedDeviceId, mine=$myDeviceId) — ignoring');
    }
  }

  /// Single-active-web-session takeover notice (Phase 5). Unlike
  /// local_storage.revoked, acting on this incorrectly means logging out a
  /// device that's still perfectly valid — so unlike the method above, an
  /// unresolvable comparison (no stored device id) does nothing here rather
  /// than guessing; the connection-scoped STOMP "Session revoked" ERROR
  /// frame (see _onStompError) is the reliable fallback either way.
  Future<void> _handleSessionRevokedBroadcast(Map<String, dynamic> data) async {
    final myDeviceId = await ApiService.getBackendDeviceId();
    final newDeviceId = data['newDeviceId'];
    if (myDeviceId == null || newDeviceId == null) {
      print('[ChatWebSocketService] 🔒 session.revoked received but cannot self-identify — deferring to STOMP error handling');
      return;
    }
    if (newDeviceId == myDeviceId) {
      print('[ChatWebSocketService] 🔒 session.revoked is about OUR OWN new login — ignoring');
      return;
    }
    print('[ChatWebSocketService] 🔒 This web session was replaced by device $newDeviceId — forcing logout');
    await _handleForcedLogout();
  }

  /// Subscribe to incoming call signals: /topic/calls.{userId}
  /// Receives: CALL_INVITE, CALL_ACCEPT, CALL_REJECT, CALL_END
  void _subscribeToIncomingCalls() {
    final topic = '/topic/calls.$_currentUserId';
    if (_activeSubscriptions.contains(topic)) {
      print('[ChatWebSocketService] ⚠️ Already subscribed to $topic');
      return;
    }

    try {
      print('[ChatWebSocketService] 📞 SUBSCRIBING to incoming calls at $topic...');
      
      // Store the unsubscribe function to prevent garbage collection
      final unsubscribeFn = _stompClient.subscribe(
        destination: topic,
        callback: (frame) {
          print('[ChatWebSocketService] 📞📞📞 INCOMING CALL RECEIVED on $topic 📞📞📞');
          print('[ChatWebSocketService] Frame body: ${frame.body}');
          try {
            _onIncomingCallSignal(frame);
          } catch (e) {
            print('[ChatWebSocketService] ❌ ERROR processing incoming call: $e');
          }
        },
        headers: {'id': 'sub-calls-${_currentUserId}', 'ack': 'auto'},
      );
      
      // Store handler to prevent GC
      _subscriptionHandlers[topic] = unsubscribeFn;
      _activeSubscriptions.add(topic);
      
      print('[ChatWebSocketService] ✅ Subscribed to $topic - Incoming calls active');
      print('[ChatWebSocketService]    └─ Handler stored: ${unsubscribeFn != null}');
    } catch (e) {
      print('[ChatWebSocketService] ❌ ERROR SUBSCRIBING to incoming calls: $e');
    }
  }

  /// Handle incoming call signals (CALL_INVITE, CALL_ACCEPT, CALL_REJECT, CALL_END)
  void _onIncomingCallSignal(StompFrame frame) {
    try {
      final data = jsonDecode(frame.body ?? '{}') as Map<String, dynamic>;
      print('[ChatWebSocketService] 📞 _onIncomingCallSignal CALLED');
      print('[ChatWebSocketService] 📞 Call signal data: $data');

      // The backend sends: {type: "CALL_INVITE", payload: {...}}
      // or legacy format: {payload: {...}, type: "CALL_INVITE"}
      final signalType = (data['type'] ?? data['signalType']) as String?;
      final payload = (data['payload'] is Map<String, dynamic>)
          ? data['payload'] as Map<String, dynamic>
          : data;

      print('[ChatWebSocketService] 📞 signalType=$signalType payload=$payload');

      // Emit as notification to subscribers
      final notification = {
        'type': signalType ?? 'UNKNOWN',
        'payload': payload,
      };
      
      print('[ChatWebSocketService] 📞 Emitting as notification: $notification');
      _notificationController.add(notification);

      // Also notify legacy listeners
      for (final listener in _notificationListeners) {
        try {
          listener(notification);
        } catch (e) {
          print('[ChatWebSocketService] ❌ Error in listener: $e');
        }
      }
    } catch (e) {
      print('[ChatWebSocketService] ❌ ERROR in _onIncomingCallSignal: $e');
      print('[ChatWebSocketService] ❌ Stack: ${StackTrace.current}');
    }
  }

  /// Handle incoming MESSAGE_RECEIVED from server
  void _onMessageReceived(StompFrame frame) {
    try {
      print('\n\n[ChatWebSocketService] 📨 _onMessageReceived CALLED');
      print('[ChatWebSocketService] Frame body length: ${frame.body?.length ?? 0}');
      
      final data = jsonDecode(frame.body ?? '{}') as Map<String, dynamic>;
      
      // === MESSAGE DEDUPLICATION ===
      // Create a unique key for this message to detect duplicates
      final messageId = data['id'] as int?;
      final clientMessageId = data['clientMessageId'] as String?;
      final frameType = data['type'] as String?;
      
      String dedupeKey;
      if (frameType == 'read_receipt') {
        // For read receipts, use timestamp + fromUserId as key
        final fromUserId = data['fromUserId'] ?? data['readerUserId'];
        final timestamp = data['timestamp'] ?? DateTime.now().toIso8601String();
        dedupeKey = 'read_${fromUserId}_$timestamp';
      } else if (messageId != null && messageId > 0) {
        dedupeKey = 'msg_$messageId';
      } else if (clientMessageId != null && clientMessageId.isNotEmpty) {
        dedupeKey = 'client_$clientMessageId';
      } else {
        // Fallback: use hash of the frame body
        dedupeKey = 'hash_${frame.body.hashCode}';
      }
      
      // Check if we've already processed this message
      if (_recentlyProcessedMessages.contains(dedupeKey)) {
        print('[ChatWebSocketService] ⚠️ DUPLICATE MESSAGE DETECTED - skipping');
        print('[ChatWebSocketService]    └─ dedupeKey: $dedupeKey');
        return;
      }
      
      // Add to processed set
      _recentlyProcessedMessages.add(dedupeKey);
      
      // Cleanup old entries if too many
      if (_recentlyProcessedMessages.length > _maxRecentMessagesTracked) {
        final toRemove = _recentlyProcessedMessages.take(
          _recentlyProcessedMessages.length - _maxRecentMessagesTracked ~/ 2
        ).toList();
        _recentlyProcessedMessages.removeAll(toRemove);
      }
      // === END DEDUPLICATION ===
      
      print('[ChatWebSocketService] ===== MESSAGE_RECEIVED (from server) =====');
      print('[ChatWebSocketService] Data keys: ${data.keys.join(", ")}');
      print('[ChatWebSocketService] Full data: $data');

      // FRAME TYPE DETECTION: Check what type of frame this is
      
      // Handle read receipts (different JSON structure)
      if (frameType == 'read_receipt') {
        print('[ChatWebSocketService] 📖 FRAME TYPE: READ_RECEIPT detected');
        _handleReadReceipt(data);
        return;
      }

      // Handle typing indicators (different JSON structure)
      if (frameType == 'typing' || (data.containsKey('isTyping') && !data.containsKey('senderId'))) {
        print('[ChatWebSocketService] ⌨️ FRAME TYPE: TYPING_INDICATOR detected');
        _handleTypingIndicatorFrame(data);
        return;
      }

      // Otherwise, parse as regular message
      print('[ChatWebSocketService] 💬 FRAME TYPE: REGULAR_MESSAGE detected');
      
      // Parse message from server response
      final message = Message.fromJson(data);
      final receiverId = (data['receiverId'] as int?) ?? (data['recipientId'] as int?) ?? 0;
      final senderId = data['senderId'] as int? ?? 0;

      print('[ChatWebSocketService] From: $senderId');
      print('[ChatWebSocketService] To: $receiverId');  // ← Changed from 'recipientId'
      print('[ChatWebSocketService] Server ID: $messageId');
      print('[ChatWebSocketService] Client ID: $clientMessageId');
      print('[ChatWebSocketService] Current User ID: $_currentUserId');
      print('[ChatWebSocketService] ChatStore available: ${_chatStore != null}');

      // Determine otherUserId (conversation key)
      final otherUserId = (senderId == _currentUserId) ? receiverId : senderId;
      
      if (otherUserId <= 0) {
        print('[ChatWebSocketService] ❌ Invalid otherUserId in message');
        return;
      }

      // If this message is from the current user, it's a confirmation of our send
      if (senderId == _currentUserId) {
        print('\n\n🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴');
        print('[SENDER] [ChatWebSocketService] ===== CONFIRMATION RECEIVED =====');
        print('[SENDER] [ChatWebSocketService] ✅ Our message confirmed by server!');
        print('[SENDER] [ChatWebSocketService]    ├─ clientId: $clientMessageId');
        print('[SENDER] [ChatWebSocketService]    ├─ serverId: $messageId');
        print('[SENDER] [ChatWebSocketService]    ├─ to: $receiverId');
        print('[SENDER] [ChatWebSocketService]    ├─ status: sent (✓)');
        print('[SENDER] [ChatWebSocketService]    └─ (UI will update from ⏱ to ✓)');
        print('[SENDER] [ChatWebSocketService] ===== END CONFIRMATION =====');
        print('🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴\n');
        
        // Update message state tracking
        if (clientMessageId != null && clientMessageId.isNotEmpty) {
          _messageStates[clientMessageId] = MessageState.delivered;
        }
        
        // Let ChatStore handle reconciliation - it will find optimistic message and update
        _chatStore?.addIncomingMessage(message, _currentUserId);
        // Emit to SQLite persistence stream (write-behind cache)
        _messageController.add(message);
        return;
      }

      // Otherwise, incoming message from other user
      _chatStore?.addIncomingMessage(message, _currentUserId);
      // Emit to SQLite persistence stream (write-behind cache)
      _messageController.add(message);
      print('\n\n🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢');
      print('[RECEIVER] [ChatWebSocketService] ===== MESSAGE RECEIVED FROM OTHER USER =====');
      print('[RECEIVER] [ChatWebSocketService] ✅ Added incoming message from user=$senderId');
      print('[RECEIVER] [ChatWebSocketService]    ├─ clientId: $clientMessageId');
      print('[RECEIVER] [ChatWebSocketService]    ├─ serverId: $messageId');
      print('[RECEIVER] [ChatWebSocketService]    └─ from other user (will appear in UI)');
      print('[RECEIVER] [ChatWebSocketService] ===== END MESSAGE RECEIVED =====');
      print('🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢\n');
    } catch (e) {
      print('[ChatWebSocketService] ❌ Error processing MESSAGE_RECEIVED: $e');
      _errorController.add('Failed to receive message: ${e.toString()}');
    }
  }

  /// Handle typing indicator
  void _onTypingIndicator(StompFrame frame) {
    try {
      print('[ChatWebSocketService] 🔔 TYPING FRAME RECEIVED - processing...');
      print('[ChatWebSocketService]    ├─ Frame command: ${frame.command}');
      print('[ChatWebSocketService]    ├─ Frame headers: ${frame.headers}');
      print('[ChatWebSocketService]    ├─ Frame body length: ${frame.body?.length}');
      print('[ChatWebSocketService]    └─ Frame body (first 100): ${frame.body?.substring(0, min(100, frame.body?.length ?? 0))}');
      
      if (frame.body == null || frame.body!.isEmpty) {
        print('[ChatWebSocketService] ⚠️ Empty frame body, skipping');
        return;
      }
      
      final data = jsonDecode(frame.body!) as Map<String, dynamic>;
      print('[ChatWebSocketService]    ├─ Parsed data keys: ${data.keys}');
      print('[ChatWebSocketService]    ├─ Full parsed data: $data');
      
      // Backend sends 'fromUserId', not 'userId'
      final userId = (data['fromUserId'] as num?)?.toInt() ?? (data['userId'] as int?);
      final isTyping = data['isTyping'] as bool? ?? false;

      print('[ChatWebSocketService]    ├─ Extracted userId: $userId');
      print('[ChatWebSocketService]    ├─ Extracted isTyping: $isTyping');
      print('[ChatWebSocketService]    └─ ChatStore available: ${_chatStore != null}');

      if (userId != null && userId > 0) {
        _chatStore?.setTyping(userId, isTyping);
        print('[ChatWebSocketService] ⌨️✅ Typing indicator PROCESSED: user=$userId isTyping=$isTyping');
      } else {
        print('[ChatWebSocketService] ⚠️ Invalid typing indicator - userId=$userId, data=$data');
      }
    } catch (e, stackTrace) {
      print('[ChatWebSocketService] ❌ Error processing typing indicator: $e');
      print('[ChatWebSocketService]    ├─ Frame body: ${frame.body}');
      print('[ChatWebSocketService]    └─ Stack trace: $stackTrace');
    }
  }

  /// Handle incoming notifications: follow, like, comment, mention, etc
  void _onNotificationReceived(StompFrame frame) {
    try {
      final data = jsonDecode(frame.body ?? '{}') as Map<String, dynamic>;
      print('[ChatWebSocketService] NOTIFICATION_RECEIVED: type=${data["type"]}, actor=${data["actorId"]}');
      
      // Handle read receipts (NEW)
      if (data['type'] == 'read_receipt') {
        _handleReadReceipt(data);
        return;  // Don't broadcast read receipts to other listeners
      }
      
      // Broadcast to all notification listeners
      for (var listener in _notificationListeners) {
        listener(data);
      }
      
      // Also emit to the stream for other services (CallSignalingService, etc)
      _notificationController.add(data);
    } catch (e) {
      print('[ChatWebSocketService] Error parsing notification: $e');
    }
  }
  
  /// Handle read receipt notifications (NEW METHOD)
  /// 
  /// Read receipt flow:
  /// 1. User A sends message to User B
  /// 2. User B reads it, frontend sends read receipt with {messageIds, otherUserId: A}
  /// 3. Backend broadcasts to User A: {type: read_receipt, messageIds, fromUserId: B}
  /// 4. User A's frontend receives this and marks messages as READ (double tick)
  void _handleReadReceipt(Map<String, dynamic> data) {
    try {
      print('[CHECKPOINT-030] _handleReadReceipt ENTRY POINT');
      print('\n[ChatWebSocketService] 📖📖📖 READ_RECEIPT PROCESSING STARTED 📖📖📖');
      print('[ChatWebSocketService] 📖 Raw data received: $data');
      print('[CHECKPOINT-031] Data keys: ${data.keys.toList()}');
      
      final messageIds = data['messageIds'] as List?;
      // Backend sends 'readerId', but also check 'fromUserId' for backwards compatibility
      final fromUserId = data['readerId'] ?? data['fromUserId'];
      
      print('[CHECKPOINT-032] Extracted messageIds: $messageIds');
      print('[CHECKPOINT-033] Extracted fromUserId (from readerId or fromUserId): $fromUserId');
      print('[ChatWebSocketService] 📖 Extracted values:');
      print('[ChatWebSocketService]    ├─ messageIds raw: $messageIds (type: ${messageIds.runtimeType})');
      print('[ChatWebSocketService]    ├─ fromUserId raw: $fromUserId (type: ${fromUserId.runtimeType})');
      
      // Parse fromUserId
      int? parsedFromUserId;
      print('[CHECKPOINT-034] Parsing fromUserId...');
      if (fromUserId is int) {
        print('[CHECKPOINT-035] fromUserId is int');
        parsedFromUserId = fromUserId;
      } else if (fromUserId is double) {
        print('[CHECKPOINT-036] fromUserId is double');
        parsedFromUserId = fromUserId.toInt();
      } else if (fromUserId is String) {
        print('[CHECKPOINT-037] fromUserId is String');
        parsedFromUserId = int.tryParse(fromUserId);
      } else if (fromUserId is num) {
        print('[CHECKPOINT-038] fromUserId is num');
        parsedFromUserId = (fromUserId as num).toInt();
      }
      print('[CHECKPOINT-039] Parsed fromUserId: $parsedFromUserId');
      
      if (messageIds == null || messageIds.isEmpty) {
        print('[CHECKPOINT-040] messageIds is null or empty - RETURNING');
        print('[ChatWebSocketService] ⚠️ No message IDs in read receipt');
        return;
      }
      print('[CHECKPOINT-041] messageIds is valid');
      
      if (parsedFromUserId == null) {
        print('[CHECKPOINT-042] parsedFromUserId is null - RETURNING');
        print('[ChatWebSocketService] ⚠️ Could not parse fromUserId: $fromUserId');
        return;
      }
      print('[CHECKPOINT-043] parsedFromUserId is valid');
      
      if (_chatStore == null) {
        print('[CHECKPOINT-044] _chatStore is null - RETURNING');
        print('[ChatWebSocketService] ⚠️ ChatStore is null - cannot process');
        return;
      }
      print('[CHECKPOINT-045] _chatStore is initialized');
      
      print('[ChatWebSocketService] 📖 Validated values:');
      print('[ChatWebSocketService]    ├─ fromUserId (reader): $parsedFromUserId');
      print('[ChatWebSocketService]    ├─ currentUserId (sender): $_currentUserId');
      print('[ChatWebSocketService]    ├─ messageIds count: ${messageIds.length}');
      print('[ChatWebSocketService]    └─ messageIds: $messageIds');
      
      // Convert messageIds to List<int>
      print('[CHECKPOINT-046] Converting messageIds to List<int>');
      final ids = messageIds.map((e) {
        if (e is int) return e;
        if (e is double) return e.toInt();
        if (e is String) return int.tryParse(e) ?? 0;
        return (e as num).toInt();
      }).toList();
      print('[CHECKPOINT-047] Converted IDs: $ids');
      
      print('[ChatWebSocketService] 📖 Converted message IDs: $ids');
      
      // The fromUserId is the person who READ the messages
      // We need to update messages in OUR conversation with that person
      // These messages are the ones WE SENT (senderId = currentUserId)
      print('[CHECKPOINT-048] About to call markMessagesAsReadByRecipient');
      print('[ChatWebSocketService] 📖 Calling markMessagesAsReadByRecipient with:');
      print('[ChatWebSocketService]    ├─ otherUserId: $parsedFromUserId');
      print('[ChatWebSocketService]    ├─ messageIds: $ids');
      print('[ChatWebSocketService]    └─ Will mark our sent messages as READ');
      
      print('[CHECKPOINT-049] CALLING: markMessagesAsReadByRecipient');
      _chatStore!.markMessagesAsReadByRecipient(parsedFromUserId, ids);
      print('[CHECKPOINT-050] markMessagesAsReadByRecipient COMPLETED');
      
      // Emit to SQLite persistence stream (write-behind cache)
      print('[CHECKPOINT-051] Creating ReadReceipt object');
      final readReceipt = ReadReceipt(
        fromUserId: parsedFromUserId,
        messageIds: ids,
      );
      print('[CHECKPOINT-052] Adding readReceipt to controller');
      _readReceiptController.add(readReceipt);
      print('[CHECKPOINT-053] ReadReceipt added to stream');
      
      print('[ChatWebSocketService] ✅ Read receipt processed successfully');
      print('[ChatWebSocketService] ✅ Messages should show double ticks (✓✓) in UI');
      print('[ChatWebSocketService] 📖📖📖 READ_RECEIPT PROCESSING COMPLETE 📖📖📖\n');
      print('[CHECKPOINT-054] _handleReadReceipt EXIT POINT - SUCCESS');
    } catch (e, st) {
      print('[CHECKPOINT-099] EXCEPTION in _handleReadReceipt: $e');
      print('[ChatWebSocketService] ❌ EXCEPTION processing read receipt: $e');
      print('[ChatWebSocketService] ❌ Stack: $st');
    }
  }

  /// Handle typing indicator frame (when received via /user/queue/messages)
  void _handleTypingIndicatorFrame(Map<String, dynamic> data) {
    try {
      print('[ChatWebSocketService] ⌨️ TYPING_INDICATOR received via frame');
      
      final userId = (data['fromUserId'] as num?)?.toInt() ?? (data['userId'] as int?);
      final isTyping = data['isTyping'] as bool? ?? false;
      
      if (userId != null && userId > 0 && _chatStore != null) {
        _chatStore!.setTyping(userId, isTyping);
        print('[ChatWebSocketService] ✅ Typing status updated: user=$userId isTyping=$isTyping');
      }
    } catch (e) {
      print('[ChatWebSocketService] ❌ Error processing typing indicator frame: $e');
    }
  }
  
  /// Add a listener for real-time notifications
  void addNotificationListener(OnNotificationReceived listener) {
    _notificationListeners.add(listener);
    print('[ChatWebSocketService] Notification listener added');
  }
  
  /// Remove a notification listener
  void removeNotificationListener(OnNotificationReceived listener) {
    _notificationListeners.remove(listener);
    print('[ChatWebSocketService] Notification listener removed');
  }
  
  /// Subscribe to notifications (alias for addNotificationListener for compatibility)
  void subscribeToNotifications(OnNotificationReceived listener) {
    addNotificationListener(listener);
  }
  
  /// Unsubscribe from notifications (alias for removeNotificationListener for compatibility)
  void unsubscribeFromNotifications(OnNotificationReceived listener) {
    removeNotificationListener(listener);
  }
  
  /// Send call signal via WebSocket
  void sendCallSignal(String signalType, Map<String, dynamic> payload) {
    if (!_isConnected || _currentUserId <= 0) {
      print('[ChatWebSocketService] Cannot send call signal: not connected');
      return;
    }
    
    try {
      _stompClient.send(
        destination: '/app/call.signal',
        body: jsonEncode({
          'signalType': signalType,
          'payload': payload,
        }),
        headers: {'content-type': 'application/json'},
      );
      print('[ChatWebSocketService] Call signal sent: $signalType');
    } catch (e) {
      print('[ChatWebSocketService] Error sending call signal: $e');
    }
  }
  
  /// Send message (alias for sendChatMessage for compatibility)
  Future<String> sendMessage(
    int recipientId,
    String content, {
    String? mediaUrl,
  }) async {
    return sendChatMessage(recipientId, content, mediaUrl: mediaUrl);
  }
  
  /// Send typing start indicator
  void sendTypingStart(int recipientId) {
    if (!_isConnected || _currentUserId <= 0) {
      return;
    }
    
    try {
      if (recipientId > 0) {
        sendTypingIndicator(recipientId, true);
      }
    } catch (e) {
      print('[ChatWebSocketService] Error sending typing start: $e');
    }
  }
  
  /// Send typing stop indicator
  Future<void> sendTypingStop(int recipientId) async {
    if (!_isConnected || _currentUserId <= 0) {
      return;
    }
    
    try {
      if (recipientId > 0) {
        sendTypingIndicator(recipientId, false);
      }
    } catch (e) {
      print('[ChatWebSocketService] Error sending typing stop: $e');
    }
  }
  
  /// Add initial messages to conversation (for loading history)
  void addInitialMessages(int userId, List<Message> messages) {
    if (messages.isEmpty) {
      return;
    }
    
    for (final message in messages) {
      _chatStore?.addIncomingMessage(message, _currentUserId);
    }
    print('[ChatWebSocketService] Added ${messages.length} initial messages for user=$userId');
  }

  /// Send chat message with optimistic update
  /// 
  /// Flow:
  /// 1. Generate unique clientMessageId
  /// 2. Create optimistic message + add to ChatStore immediately (UI updates)
  /// 3. Track message state as "sending"
  /// 4. Send MESSAGE_SEND via WebSocket
  /// 5. On success, message transitions to "sent"
  /// 6. When server broadcasts MESSAGE_RECEIVED, transitions to "delivered"
  /// 7. If offline, message queued and auto-retried on reconnect
  String sendChatMessage(int recipientId, String content, {String? mediaUrl, bool skipOptimistic = false, String? clientMessageId}) {
    print('\n[SENDER] [ChatWebSocketService] ===== SEND_CHAT_MESSAGE =====');
    print('[SENDER] [ChatWebSocketService] 🔍 DEBUG: recipientId=$recipientId, _currentUserId=$_currentUserId, skipOptimistic=$skipOptimistic, providedClientId=$clientMessageId');
    
    if (_currentUserId <= 0) {
      print('[SENDER] [ChatWebSocketService] ❌ ERROR: _currentUserId not set ($_currentUserId)');
      print('[SENDER] [ChatWebSocketService] This means connect(token, userId) was never called or failed!');
      throw Exception('Current user not set. Please reconnect.');
    }
    
    if (recipientId == _currentUserId) {
      print('[SENDER] [ChatWebSocketService] ❌ ERROR: recipientId is SAME as _currentUserId!');
      print('[SENDER] [ChatWebSocketService] You\'re trying to send a message to yourself!');
      print('[SENDER] [ChatWebSocketService] This means widget.conversation.userId is wrong!');
      throw Exception('Cannot send message to yourself! recipientId=$recipientId, sender=$_currentUserId');
    }
    
    print('[SENDER] [ChatWebSocketService] ✅ Sender ID: $_currentUserId');

    if (_chatStore == null) {
      print('[SENDER] [ChatWebSocketService] ⚠️ WARNING: ChatStore is null');
      print('[SENDER] [ChatWebSocketService] This means setChatStore() was never called!');
      print('[SENDER] [ChatWebSocketService] Message will queue but won\'t appear in UI until ChatStore is set');
      // Don't throw - allow message to queue for sending
    } else {
      print('[SENDER] [ChatWebSocketService] ✅ ChatStore: initialized');
    }

    // Generate or use provided clientMessageId
    final actualClientMessageId = clientMessageId ?? _generateClientMessageId();
    print('[SENDER] [ChatWebSocketService] ✅ Using clientMessageId: $actualClientMessageId (provided=$clientMessageId)');
    
    // Create optimistic message (id=0 indicates not yet confirmed)
    final optimisticMessage = Message(
      id: 0,
      clientMessageId: actualClientMessageId,
      senderId: _currentUserId,
      senderName: '',
      senderProfilePic: null,
      recipientId: recipientId,
      content: content,
      mediaUrl: mediaUrl,
      createdAt: DateTime.now().toUtc(),
      isRead: false,
      status: MessageStatus.sending,
    );

    // Add optimistic message to store (UI updates immediately) - UNLESS this is a retry
    if (!skipOptimistic && _chatStore != null) {
      _chatStore!.addIncomingMessage(optimisticMessage, _currentUserId);
      print('[SENDER] [ChatWebSocketService] ✅ Optimistic message added to ChatStore');
      print('[SENDER] [ChatWebSocketService]    ├─ clientId: $actualClientMessageId');
      print('[SENDER] [ChatWebSocketService]    ├─ from: $_currentUserId');
      print('[SENDER] [ChatWebSocketService]    ├─ to: $recipientId');
      print('[SENDER] [ChatWebSocketService]    └─ status: sending (⏱)');
    } else if (skipOptimistic) {
      print('[SENDER] [ChatWebSocketService] ℹ️  Skipping optimistic message (retry)');
    } else {
      print('[SENDER] [ChatWebSocketService] ⚠️ ChatStore null - message won\'t show in UI yet');
    }

    // Track message state
    _messageStates[actualClientMessageId] = MessageState.sending;

    // Queue or send immediately
    final messageData = <String, dynamic>{
      'clientMessageId': actualClientMessageId,
      'recipientId': recipientId,
      'content': content,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      if (mediaUrl != null) 'mediaUrl': mediaUrl,
    };

    if (_isConnected) {
      // Connected: send immediately
      try {
        _sendMessageViaWebSocket(messageData);
        print('[SENDER] [ChatWebSocketService] ✅ SENT to WebSocket: /app/chat.send');

        // The message stays in `sending` (⏱) until the server acknowledges it on
        // /user/queue/message-ack. If no ack arrives within the timeout we mark it
        // FAILED rather than pretending it was delivered — a silent drop must stay
        // visible to the user so they can retry.
        _startAckTimeout(actualClientMessageId, recipientId);
      } catch (e) {
        // Send threw synchronously - mark failed but KEEP the message in the store
        // so the user can see it and retry it.
        _messageStates[actualClientMessageId] = MessageState.failed;
        _cancelAckTimeout(actualClientMessageId);
        if (_chatStore != null) {
          _chatStore!.updateMessageStatus(recipientId, actualClientMessageId, MessageStatus.failed);
        }
        print('[SENDER] [ChatWebSocketService] ❌ SEND FAILED: $e');
        throw e; // Re-throw so UI can surface it
      }
    } else {
      // Offline: queue for later (with size limit)
      if (_offlineQueue.length < _maxOfflineQueueSize) {
        // Store with destination and body for offline queue processing
        final queuedMessage = {
          'destination': '/app/chat.send',
          'body': jsonEncode({
            'clientMessageId': actualClientMessageId,
            'recipientId': recipientId,
            'content': content,
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            if (mediaUrl != null) 'mediaUrl': mediaUrl,
          }),
          'messageData': messageData,  // Keep original for fallback
        };
        _offlineQueue.add(queuedMessage);
        print('[SENDER] [ChatWebSocketService] ⚠️  WebSocket NOT connected!');
        print('[SENDER] [ChatWebSocketService]    └─ Message queued (${_offlineQueue.length}/$_maxOfflineQueueSize)');
      } else {
        // Queue is full - the message is genuinely dropped, so surface it as FAILED
        // instead of leaving it on the pending (⏱) icon forever.
        _messageStates[actualClientMessageId] = MessageState.failed;
        if (_chatStore != null) {
          _chatStore!.updateMessageStatus(recipientId, actualClientMessageId, MessageStatus.failed);
        }
        print('[SENDER] [ChatWebSocketService] ❌ Offline queue full! Message marked FAILED.');
        throw Exception('Offline queue full. Please wait for connection.');
      }
    }
    print('[SENDER] [ChatWebSocketService] ===== END SEND_CHAT_MESSAGE =====\n');

    return actualClientMessageId;
  }

  /// Retry a message that previously failed to send.
  ///
  /// Reuses the original [clientMessageId] and skips the optimistic insert so the
  /// existing bubble is reused rather than duplicated. Puts the message back into
  /// the pending (⏱) state and restarts the acknowledgement watchdog.
  void retryFailedMessage({
    required int recipientId,
    required String clientMessageId,
    required String content,
    String? mediaUrl,
  }) {
    print('[RETRY] 🔁 Retrying message $clientMessageId → $recipientId');

    _messageStates[clientMessageId] = MessageState.sending;
    _chatStore?.updateMessageStatus(recipientId, clientMessageId, MessageStatus.sending);

    try {
      sendChatMessage(
        recipientId,
        content,
        mediaUrl: mediaUrl,
        skipOptimistic: true,
        clientMessageId: clientMessageId,
      );
    } catch (e) {
      print('[RETRY] ❌ Retry failed immediately: $e');
      _messageStates[clientMessageId] = MessageState.failed;
      _chatStore?.updateMessageStatus(recipientId, clientMessageId, MessageStatus.failed);
    }
  }

  /// Start the server-acknowledgement watchdog for an outgoing message.
  /// If no ack arrives before [_ackTimeout], the message is marked FAILED.
  void _startAckTimeout(String clientMessageId, int recipientId) {
    _cancelAckTimeout(clientMessageId);
    _ackTimers[clientMessageId] = Timer(_ackTimeout, () {
      _ackTimers.remove(clientMessageId);

      // Only fail it if it is still awaiting acknowledgement.
      if (_messageStates[clientMessageId] != MessageState.sending) return;

      print('[SENDER] [ChatWebSocketService] ❌ NO ACK after ${_ackTimeout.inSeconds}s');
      print('[SENDER] [ChatWebSocketService]    └─ Marking message FAILED: $clientMessageId');
      _messageStates[clientMessageId] = MessageState.failed;
      _chatStore?.updateMessageStatus(recipientId, clientMessageId, MessageStatus.failed);
      _emitError('Message not sent. Tap to retry.');
    });
  }

  void _cancelAckTimeout(String clientMessageId) {
    _ackTimers.remove(clientMessageId)?.cancel();
  }

  /// Handle a server acknowledgement frame on /user/queue/message-ack.
  /// Success -> message becomes `sent` (✓). Failure -> `failed` (❌) + error surfaced.
  void _onMessageAck(StompFrame frame) {
    try {
      if (frame.body == null || frame.body!.isEmpty) return;
      final data = jsonDecode(frame.body!) as Map<String, dynamic>;

      final clientMessageId = (data['clientMessageId'] ?? data['messageId'])?.toString();
      if (clientMessageId == null) {
        print('[ACK] ⚠️ Ack frame without clientMessageId: ${frame.body}');
        return;
      }

      final bool ok = data['success'] == true;
      final int recipientId = (data['receiverId'] as int?) ?? (data['recipientId'] as int?) ?? 0;

      _cancelAckTimeout(clientMessageId);

      if (ok) {
        _messageStates[clientMessageId] = MessageState.sent;
        _chatStore?.updateMessageStatus(recipientId, clientMessageId, MessageStatus.sent);
        print('[ACK] ✅ Server acknowledged $clientMessageId → sent (✓)');
      } else {
        final error = data['error']?.toString() ?? 'Message could not be sent';
        _messageStates[clientMessageId] = MessageState.failed;
        _chatStore?.updateMessageStatus(recipientId, clientMessageId, MessageStatus.failed);
        print('[ACK] ❌ Server rejected $clientMessageId: $error');
        _emitError(error);
      }
    } catch (e) {
      print('[ACK] ❌ Error parsing ack frame: $e');
    }
  }

  void _emitError(String message) {
    if (!_errorController.isClosed) {
      _errorController.add(message);
    }
  }

  /// Send message via WebSocket
  void _sendMessageViaWebSocket(Map<String, dynamic> messageData) {
    try {
      if (!_isConnected) {
        print('[ChatWebSocketService] ❌ Cannot send: not connected');
        return;
      }

      final clientMessageId = messageData['clientMessageId'] as String?;
      final recipientId = messageData['recipientId'] as int?;
      
      print('\n[ChatWebSocketService] 📤 SENDING MESSAGE VIA WEBSOCKET');
      print('[ChatWebSocketService]    ├─ clientMessageId: $clientMessageId');
      print('[ChatWebSocketService]    ├─ recipientId: $recipientId');
      print('[ChatWebSocketService]    ├─ destination: /app/chat.send');
      print('[ChatWebSocketService]    └─ body size: ${jsonEncode(messageData).length} bytes');

      _stompClient.send(
        destination: '/app/chat.send',
        body: jsonEncode(messageData),
        headers: {'content-type': 'application/json'},
      );

      print('[ChatWebSocketService] ✅ MESSAGE SENT to broker');
      print('[ChatWebSocketService] ⏳ WAITING FOR CONFIRMATION on /user/queue/messages...\n');
    } catch (e) {
      print('[ChatWebSocketService] ❌ Error sending message: $e');
      rethrow;
    }
  }

  /// Send typing indicator
  void sendTypingIndicator(int recipientId, bool isTyping) {
    if (!_isConnected || _currentUserId <= 0) {
      return;
    }

    try {
      _stompClient.send(
        destination: '/app/chat.typing',
        body: jsonEncode({
          'receiverId': recipientId,
          'isTyping': isTyping,
        }),
        headers: {'content-type': 'application/json'},
      );
      print('[ChatWebSocketService] Typing indicator sent: isTyping=$isTyping');
    } catch (e) {
      print('[ChatWebSocketService] Error sending typing indicator: $e');
    }
  }
  
  /// Send read receipt for messages
  void sendReadReceipt(int otherUserId, List<int> messageIds) {
    if (!_isConnected) {
      print('[ChatWebSocketService] ❌ Cannot send read receipt: not connected');
      return;
    }
    
    if (_currentUserId <= 0) {
      print('[ChatWebSocketService] ❌ Cannot send read receipt: currentUserId invalid ($_currentUserId)');
      return;
    }
    
    if (messageIds.isEmpty) {
      print('[ChatWebSocketService] ⚠️ No messageIds to send in read receipt');
      return;
    }

    try {
      print('[ChatWebSocketService] 📤 SENDING READ RECEIPT');
      print('[ChatWebSocketService]    ├─ destination: /app/chat.read');
      print('[ChatWebSocketService]    ├─ from (readerId): $_currentUserId');
      print('[ChatWebSocketService]    ├─ to (otherUserId): $otherUserId');
      print('[ChatWebSocketService]    ├─ messageIds: $messageIds');
      print('[ChatWebSocketService]    └─ count: ${messageIds.length}');
      
      _stompClient.send(
        destination: '/app/chat.read',
        body: jsonEncode({
          'readerId': _currentUserId,    // CRITICAL: Add readerId field
          'messageIds': messageIds,
          'otherUserId': otherUserId,
        }),
        headers: {'content-type': 'application/json'},
      );
      print('[ChatWebSocketService] ✅ Read receipt sent to /app/chat.read: ${messageIds.length} messages');
      print('[ChatWebSocketService] ⏳ Waiting for broadcast on /user/$otherUserId/queue/read-receipts...');
    } catch (e) {
      print('[ChatWebSocketService] ❌ ERROR sending read receipt: $e');
    }
  }

  /// Send presence update (online/offline status) to server (NEW - PHASE 3)
  void sendPresenceUpdate(bool isOnline) {
    if (!_isConnected || _currentUserId <= 0) {
      print('[ChatWebSocketService] Cannot send presence: connected=$_isConnected userId=$_currentUserId');
      return;
    }

    try {
      _stompClient.send(
        destination: '/app/presence.update',
        body: jsonEncode({
          'userId': _currentUserId,
          'isOnline': isOnline,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        }),
        headers: {'content-type': 'application/json'},
      );
      final status = isOnline ? 'ONLINE' : 'OFFLINE';
      print('[ChatWebSocketService] 📍 Presence updated: $status');
    } catch (e) {
      print('[ChatWebSocketService] Error sending presence update: $e');
    }
  }

  /// G1: subscribe to a group conversation topic (/topic/conversation.{id}).
  ///
  /// Returns an unsubscribe function, or null if not connected. The caller
  /// (group chat screen) owns the subscription lifecycle; dedup against
  /// optimistic sends is done by the caller via clientMessageId/server id.
  void Function()? subscribeToConversationTopic(
      int conversationId, void Function(Map<String, dynamic> frame) onMessage) {
    final topic = '/topic/conversation.$conversationId';
    if (!_isConnected) {
      print('[ChatWebSocketService] ❌ Cannot subscribe to $topic: not connected');
      return null;
    }
    try {
      final unsubscribeFn = _stompClient.subscribe(
        destination: topic,
        callback: (frame) {
          try {
            if (frame.body == null || frame.body!.isEmpty) return;
            onMessage(jsonDecode(frame.body!) as Map<String, dynamic>);
          } catch (e) {
            print('[ChatWebSocketService] ❌ Error handling $topic frame: $e');
          }
        },
      );
      print('[ChatWebSocketService] ✅ Subscribed to $topic');
      return () {
        try {
          unsubscribeFn();
          print('[ChatWebSocketService] Unsubscribed from $topic');
        } catch (_) {}
      };
    } catch (e) {
      print('[ChatWebSocketService] ❌ Error subscribing to $topic: $e');
      return null;
    }
  }

  /// Begin sending a periodic "still online" heartbeat. Idempotent.
  void _startPresenceHeartbeat() {
    _presenceHeartbeatTimer?.cancel();
    _presenceHeartbeatTimer = Timer.periodic(_presenceHeartbeatInterval, (_) {
      if (_isConnected && _currentUserId > 0) {
        sendPresenceUpdate(true);
      }
    });
    print('[ChatWebSocketService] 💓 Presence heartbeat started (${_presenceHeartbeatInterval.inSeconds}s)');
  }

  void _stopPresenceHeartbeat() {
    _presenceHeartbeatTimer?.cancel();
    _presenceHeartbeatTimer = null;
  }

  /// ✅ PUBLIC: Request initial presence - get list of currently online users
  /// Call this after login to populate initial online status for all contacts
  void requestInitialPresence() {
    print('[ChatWebSocketService] 📡 PUBLIC requestInitialPresence called - requesting who is online...');
    _requestInitialPresence();
  }

  /// ✅ NEW: Subscribe to presence updates (Phase 2)
  void _subscribeToPresenceUpdates() {
    final topic = '/user/queue/presence';
    if (_activeSubscriptions.contains(topic)) {
      print('[ChatWebSocketService] ⚠️ Already subscribed to $topic');
      return;
    }

    print('[ChatWebSocketService] 👤 SUBSCRIBING to presence updates at $topic...');
    print('[ChatWebSocketService]    └─ Timestamp: ${DateTime.now().toIso8601String()}');
    
    try {
      // Store the unsubscribe function to prevent garbage collection
      final unsubscribeFn = _stompClient.subscribe(
        destination: topic,
        callback: (frame) {
          print('[ChatWebSocketService] 👤👤👤 PRESENCE UPDATE RECEIVED on /user/queue/presence 👤👤👤');
          print('[ChatWebSocketService]    └─ Raw body: ${frame.body}');
          print('[ChatWebSocketService]    └─ Timestamp: ${DateTime.now().toIso8601String()}');
          try {
            _onPresenceUpdate(frame);
          } catch (e) {
            print('[ChatWebSocketService] ❌ ERROR processing presence: $e');
          }
        },
        headers: {'id': 'sub-presence-${_currentUserId}', 'ack': 'auto'},
      );
      
      // Store handler to prevent GC
      _subscriptionHandlers[topic] = unsubscribeFn;
      _activeSubscriptions.add(topic);
      
      print('[ChatWebSocketService] ✅ Subscribed to $topic - Presence updates active');
      print('[ChatWebSocketService]    ├─ Handler stored: ${unsubscribeFn != null}');
      print('[ChatWebSocketService]    └─ Timestamp: ${DateTime.now().toIso8601String()}');
      
      // ✅ CRITICAL FIX: Also subscribe to explicit user destination as backup
      // stomp_dart_client sometimes doesn't route /user/queue/* correctly
      _subscribeToExplicitPresenceDestination();
    } catch (e) {
      print('[ChatWebSocketService] ❌ ERROR SUBSCRIBING to presence: $e');
    }
  }
  
  /// ✅ CRITICAL: Subscribe to explicit presence destination as backup
  /// stomp_dart_client has issues with /user/queue/* routing
  void _subscribeToExplicitPresenceDestination() {
    final explicitTopic = '/user/$_currentUserId/queue/presence';
    if (_activeSubscriptions.contains(explicitTopic)) {
      print('[ChatWebSocketService] ⚠️ Already subscribed to $explicitTopic');
      return;
    }
    
    print('[ChatWebSocketService] 👤 SUBSCRIBING to EXPLICIT PRESENCE DESTINATION: $explicitTopic');
    
    try {
      final unsubscribeFn = _stompClient.subscribe(
        destination: explicitTopic,
        callback: (frame) {
          print('[ChatWebSocketService] 👤👤👤 EXPLICIT PRESENCE UPDATE RECEIVED on $explicitTopic 👤👤👤');
          print('[ChatWebSocketService]    └─ Raw body: ${frame.body}');
          try {
            _onPresenceUpdate(frame);
          } catch (e) {
            print('[ChatWebSocketService] ❌ ERROR processing explicit presence: $e');
          }
        },
        headers: {'id': 'sub-explicit-presence-$_currentUserId-${DateTime.now().millisecondsSinceEpoch}', 'ack': 'auto'},
      );
      
      _subscriptionHandlers[explicitTopic] = unsubscribeFn;
      _activeSubscriptions.add(explicitTopic);
      print('[ChatWebSocketService] ✅ Explicit presence destination subscription registered');
    } catch (e) {
      print('[ChatWebSocketService] ❌ ERROR subscribing to explicit presence: $e');
    }
  }

  /// ✅ NEW: Handle presence updates (Phase 2)
  void _onPresenceUpdate(StompFrame frame) {
    try {
      final data = jsonDecode(frame.body ?? '{}') as Map<String, dynamic>;
      print('[ChatWebSocketService] 👤 Presence update: $data');
      
      // Parse userId - handle int, double, or string
      int? userId;
      final rawUserId = data['userId'];
      if (rawUserId is int) {
        userId = rawUserId;
      } else if (rawUserId is double) {
        userId = rawUserId.toInt();
      } else if (rawUserId is String) {
        userId = int.tryParse(rawUserId);
      }
      
      // Handle BOTH formats from backend:
      // 1. {type: "USER_CONNECTED", userId: X} or {type: "USER_DISCONNECTED", userId: X}
      // 2. {type: "presence_update", userId: X, isOnline: true/false}
      bool? isOnline;
      if (data.containsKey('type')) {
        final type = data['type'] as String?;
        if (type == 'USER_CONNECTED') {
          isOnline = true;
        } else if (type == 'USER_DISCONNECTED') {
          isOnline = false;
        } else if (type == 'presence_update' && data.containsKey('isOnline')) {
          isOnline = data['isOnline'] as bool?;
        }
      } else if (data.containsKey('isOnline')) {
        isOnline = data['isOnline'] as bool?;
      }
      
      if (userId != null && isOnline != null) {
        print('[ChatWebSocketService] 👤 Calling _chatStore?.setUserOnline($userId, $isOnline)');
        print('[ChatWebSocketService]    └─ _chatStore is null? ${_chatStore == null}');
        _chatStore?.setUserOnline(userId, isOnline);
        print('[ChatWebSocketService] 👤 User $userId now ${isOnline ? "🟢 ONLINE" : "⚫ OFFLINE"}');
      } else {
        print('[ChatWebSocketService] ⚠️ Could not parse presence: userId=$userId isOnline=$isOnline');
      }
    } catch (e) {
      print('[ChatWebSocketService] ❌ ERROR in _onPresenceUpdate: $e');
    }
  }

  /// ✅ NEW: Subscribe to read receipts (double ticks ✓✓)
  /// Subscribe to server acknowledgements for outgoing messages.
  /// Without this the client has no way to know whether a send actually
  /// succeeded, which is what allowed silent drops to render as delivered.
  void _subscribeToMessageAcks() {
    for (final topic in [
      '/user/queue/message-ack',
      '/user/$_currentUserId/queue/message-ack',
    ]) {
      if (_activeSubscriptions.contains(topic)) {
        print('[ChatWebSocketService] ⚠️ Already subscribed to $topic');
        continue;
      }

      if (!_isConnected) {
        print('[ChatWebSocketService] ❌ Cannot subscribe to $topic: not connected');
        continue;
      }

      try {
        print('[ChatWebSocketService] 📬 SUBSCRIBING to message acks at $topic...');
        final unsubscribeFn = _stompClient.subscribe(
          destination: topic,
          callback: _onMessageAck,
        );
        _activeSubscriptions.add(topic);
        _subscriptionHandlers[topic] = unsubscribeFn;
        print('[ChatWebSocketService] ✅ Subscribed to $topic');
      } catch (e) {
        print('[ChatWebSocketService] ❌ Error subscribing to $topic: $e');
      }
    }
  }

  void _subscribeToReadReceipts() {
    final topic = '/user/queue/read-receipts';
    if (_activeSubscriptions.contains(topic)) {
      print('[ChatWebSocketService] ⚠️ Already subscribed to $topic');
      return;
    }

    print('[ChatWebSocketService] 📖 SUBSCRIBING to read receipts at $topic...');
    print('[ChatWebSocketService]    ├─ userId: $_currentUserId');
    print('[ChatWebSocketService]    ├─ client connected: $_isConnected');
    print('[ChatWebSocketService]    ├─ client ready: ${_stompClient != null}');
    print('[ChatWebSocketService]    └─ Attempting to subscribe NOW...');
    
    if (!_isConnected || _stompClient == null) {
      print('[ChatWebSocketService] ❌ CANNOT SUBSCRIBE: Client not connected or null!');
      print('[ChatWebSocketService]    ├─ _isConnected: $_isConnected');
      print('[ChatWebSocketService]    └─ _stompClient: ${_stompClient != null}');
      return;
    }
    
    try {
      // Store the unsubscribe function to prevent garbage collection
      print('[ChatWebSocketService] ➡️ Calling _stompClient.subscribe() for $topic');
      final unsubscribeFn = _stompClient.subscribe(
        destination: topic,
        callback: (frame) {
          print('[CHECKPOINT-020] subscription.callback INVOKED - READ RECEIPT FRAME RECEIVED!');
          print('\n[ChatWebSocketService] 🚨🚨🚨 READ RECEIPT CALLBACK FIRED 🚨🚨🚨');
          print('[ChatWebSocketService]    ├─ Frame command: ${frame.command}');
          print('[ChatWebSocketService]    ├─ Frame destination: ${frame.headers['destination']}');
          print('[ChatWebSocketService]    ├─ Frame body length: ${frame.body?.length ?? 0}');
          print('[ChatWebSocketService]    └─ Frame headers: ${frame.headers}');
          print('[ChatWebSocketService] 📖📖📖 READ_RECEIPT_RECEIVED 📖📖📖');
          try {
            print('[CHECKPOINT-021] Decoding frame body');
            final data = jsonDecode(frame.body ?? '{}') as Map<String, dynamic>;
            print('[CHECKPOINT-022] JSON decode SUCCEEDED: $data');
            print('[ChatWebSocketService] ✅ Decoded read receipt data: $data');
            print('[CHECKPOINT-023] Calling _handleReadReceipt() from subscription callback');
            _handleReadReceipt(data);
            print('[CHECKPOINT-024] _handleReadReceipt returned successfully');
          } catch (e, st) {
            print('[CHECKPOINT-025] EXCEPTION in subscription callback: $e');
            print('[ChatWebSocketService] ❌ ERROR processing read receipt: $e');
            print('[ChatWebSocketService] ❌ Stack: $st');
          }
        },
        headers: {'id': 'sub-read-receipts-${_currentUserId}', 'ack': 'auto'},
      );
      print('[ChatWebSocketService] ✅ Subscribe() returned: ${unsubscribeFn != null}');
      
      // Store handler to prevent GC
      _subscriptionHandlers[topic] = unsubscribeFn;
      _activeSubscriptions.add(topic);
      
      print('[ChatWebSocketService] ✅ Subscribed to $topic - Read receipts active');
      print('[ChatWebSocketService]    ├─ Handler stored: ${unsubscribeFn != null}');
      print('[ChatWebSocketService]    ├─ Added to _activeSubscriptions: ${_activeSubscriptions.contains(topic)}');
      print('[ChatWebSocketService]    └─ Waiting for read receipts on: /user/$_currentUserId/queue/read-receipts');
    } catch (e) {
      print('[ChatWebSocketService] ❌ ERROR SUBSCRIBING to read receipts: $e');
      print('[ChatWebSocketService]    └─ Stack trace: ${e}');
    }
  }

  /// === CRITICAL FIX: Explicit subscription for read receipts destination ===
  /// Backend sends to /user/{userId}/queue/read-receipts - need explicit subscription
  void _subscribeToExplicitReadReceiptsDestination() {
    final topic = '/user/$_currentUserId/queue/read-receipts';
    if (_activeSubscriptions.contains(topic)) {
      print('[ChatWebSocketService] ⚠️ Already subscribed to explicit read receipts destination $topic');
      return;
    }
    
    try {
      final subscriptionId = 'sub-explicit-read-receipts-$_currentUserId-${DateTime.now().millisecondsSinceEpoch}';
      print('[ChatWebSocketService] 📖 SUBSCRIBING to EXPLICIT READ RECEIPTS DESTINATION: $topic');
      print('[ChatWebSocketService] 🔑 Subscription ID: $subscriptionId');
      
      final unsubscribeFn = _stompClient.subscribe(
        destination: topic,
        callback: (StompFrame frame) {
          print('[ChatWebSocketService] 🚨 EXPLICIT READ RECEIPTS DESTINATION CALLBACK FIRED! 🚨');
          print('[ChatWebSocketService] 📖 READ RECEIPT FRAME RECEIVED');
          print('[ChatWebSocketService]    ├─ Frame command: ${frame.command}');
          print('[ChatWebSocketService]    ├─ Frame destination: ${frame.headers['destination']}');
          print('[ChatWebSocketService]    ├─ Frame body length: ${frame.body?.length ?? 0}');
          
          try {
            final data = jsonDecode(frame.body ?? '{}') as Map<String, dynamic>;
            print('[ChatWebSocketService] ✅ Decoded read receipt: $data');
            _handleReadReceipt(data);
            print('[ChatWebSocketService] ✅ Read receipt processed successfully');
          } catch (e, st) {
            print('[ChatWebSocketService] ❌ ERROR processing read receipt: $e');
            print('[ChatWebSocketService] ❌ Stack: $st');
          }
        },
        headers: {'id': subscriptionId, 'ack': 'auto'},
      );
      
      _subscriptionHandlers[topic] = unsubscribeFn;
      _activeSubscriptions.add(topic);
      print('[ChatWebSocketService] ✅ Explicit read receipts destination subscription registered');
    } catch (e) {
      print('[ChatWebSocketService] ❌ Error subscribing to explicit read receipts destination: $e');
    }
  }

  /// ✅ PRODUCTION: Subscribe to presence of CHAT CONTACTS ONLY (not all users)
  /// This is scalable: instead of 10,000 broadcasts, only get updates for ~500 chat contacts
  /// Reduces server load, bandwidth, and AWS costs significantly
  Future<void> subscribeToContactsPresence(List<int> contactUserIds) async {
    if (contactUserIds.isEmpty) {
      print('[ChatWebSocketService] ℹ️ No contacts to track presence for');
      return;
    }

    if (!_isConnected) {
      print('[ChatWebSocketService] ❌ Cannot subscribe to contacts presence - not connected');
      return;
    }

    print('[ChatWebSocketService] 👥 Subscribing to presence of ${contactUserIds.length} chat contacts...');
    
    try {
      // Send backend a list of contact IDs to track
      _stompClient.send(
        destination: '/app/presence.subscribe-contacts',
        body: jsonEncode({
          'userId': _currentUserId,
          'contactIds': contactUserIds,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        }),
        headers: {'content-type': 'application/json'},
      );
      
      print('[ChatWebSocketService] ✅ Sent contact presence subscription request');
      print('[ChatWebSocketService]    └─ Tracking ${contactUserIds.length} contacts');
    } catch (e) {
      print('[ChatWebSocketService] ❌ Error subscribing to contacts presence: $e');
    }
  }

  /// ⚠️ OLD (EXPENSIVE): Subscribe to ALL USERS' presence broadcasts
  /// DO NOT USE IN PRODUCTION - causes socket floods and high AWS costs
  /// Kept for reference only
  void _subscribeToAllUsersPresence() {
    final topic = '/topic/presence';
    if (_activeSubscriptions.contains(topic)) {
      print('[ChatWebSocketService] ⚠️ Already subscribed to $topic');
      return;

    }

    print('[ChatWebSocketService] 👥 SUBSCRIBING to all users presence broadcasts at $topic...');
    
    try {
      final unsubscribeFn = _stompClient.subscribe(
        destination: topic,
        callback: (frame) {
          try {
            _onPresenceUpdate(frame);  // Reuse same handler
          } catch (e) {
            print('[ChatWebSocketService] ❌ ERROR processing broadcast presence: $e');
          }
        },
        headers: {'id': 'sub-broadcast-presence-${_currentUserId}', 'ack': 'auto'},
      );
      
      _subscriptionHandlers[topic] = unsubscribeFn;
      _activeSubscriptions.add(topic);
      
      print('[ChatWebSocketService] ✅ Subscribed to $topic - All users presence updates active');
    } catch (e) {
      print('[ChatWebSocketService] ❌ ERROR SUBSCRIBING to broadcast presence: $e');
    }
  }
  
  /// ✅ NEW: Subscribe to user-specific presence queue (for initial status from backend)
  void _subscribeToUserPresenceQueue() {
    final topic = '/user/queue/presence';
    if (_activeSubscriptions.contains(topic)) {
      print('[ChatWebSocketService] ⚠️ Already subscribed to $topic');
      return;
    }

    print('[ChatWebSocketService] 👤 SUBSCRIBING to user presence queue at $topic...');
    
    try {
      final unsubscribeFn = _stompClient.subscribe(
        destination: topic,
        callback: (frame) {
          print('[ChatWebSocketService] 📥 USER PRESENCE QUEUE: ${frame.body}');
          try {
            _onPresenceUpdate(frame);  // Reuse same handler
          } catch (e) {
            print('[ChatWebSocketService] ❌ ERROR processing user presence: $e');
          }
        },
        headers: {'id': 'sub-user-presence-${_currentUserId}', 'ack': 'auto'},
      );
      
      _subscriptionHandlers[topic] = unsubscribeFn;
      _activeSubscriptions.add(topic);
      
      print('[ChatWebSocketService] ✅ Subscribed to $topic - User presence queue active');
    } catch (e) {
      print('[ChatWebSocketService] ❌ ERROR SUBSCRIBING to user presence queue: $e');
    }
  }
  
  /// ✅ NEW: Request initial presence status from server
  void _requestInitialPresence() {
    print('[ChatWebSocketService] 🔍 _requestInitialPresence called - connected=$_isConnected userId=$_currentUserId');
    print('[ChatWebSocketService]    └─ /user/queue/presence subscription active? ${_activeSubscriptions.contains('/user/queue/presence')}');
    
    if (!_isConnected || _currentUserId <= 0) {
      print('[ChatWebSocketService] ❌ Cannot request initial presence: connected=$_isConnected userId=$_currentUserId');
      return;
    }
    
    // CRITICAL: Verify the presence subscription is active before requesting
    if (!_activeSubscriptions.contains('/user/queue/presence')) {
      print('[ChatWebSocketService] ⚠️⚠️⚠️ WARNING: /user/queue/presence NOT in activeSubscriptions!');
      print('[ChatWebSocketService]    └─ Active subs: $_activeSubscriptions');
      // Try subscribing again and retry after a delay
      _subscribeToPresenceUpdates();
      Future.delayed(const Duration(milliseconds: 500), () {
        print('[ChatWebSocketService] 🔄 Retrying initial presence after re-subscription...');
        _requestInitialPresence();
      });
      return;
    }

    try {
      print('[ChatWebSocketService] 📥📥📥 Requesting initial presence for user=$_currentUserId...');
      _stompClient.send(
        destination: '/app/presence.getInitial',
        body: jsonEncode({
          'userId': _currentUserId,
        }),
        headers: {'content-type': 'application/json'},
      );
      print('[ChatWebSocketService] ✅✅✅ Initial presence request SENT to /app/presence.getInitial');
    } catch (e) {
      print('[ChatWebSocketService] ❌ Error requesting initial presence: $e');
    }
  }

  /// ✅ NEW: Notify presence to server (Phase 2)
  void _notifyPresenceUpdate(bool isOnline) {
    if (!_isConnected || _currentUserId <= 0) {
      print('[ChatWebSocketService] Cannot send presence: connected=$_isConnected userId=$_currentUserId');
      return;
    }

    try {
      _stompClient.send(
        destination: '/app/presence.update',
        body: jsonEncode({
          'userId': _currentUserId,
          'isOnline': isOnline,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        }),
        headers: {'content-type': 'application/json'},
      );
      final status = isOnline ? '🟢 ONLINE' : '⚫ OFFLINE';
      print('[ChatWebSocketService] 👤 Presence notified: $status');
    } catch (e) {
      print('[ChatWebSocketService] Error notifying presence: $e');
    }
  }

  /// ✅ NEW: Process offline queue on reconnect (Phase 1)
  void _processOfflineQueue() {
    if (_offlineQueue.isEmpty) {
      print('[ChatWebSocketService] ✅ No offline messages to process');
      return;
    }

    print('[ChatWebSocketService] 📤 Processing ${_offlineQueue.length} offline messages...');
    
    final queue = List.from(_offlineQueue);  // Copy to avoid modification
    _offlineQueue.clear();

    for (final msgData in queue) {
      try {
        // Safely extract destination and body with null checks
        final destination = msgData['destination'];
        final body = msgData['body'];
        
        // Validate data before sending
        if (destination == null || body == null) {
          print('[ChatWebSocketService] ⚠️ Invalid queued message format: destination=$destination, body=$body');
          print('[ChatWebSocketService]    └─ Message data: $msgData');
          continue;  // Skip this message
        }
        
        print('[ChatWebSocketService] 📤 Sending queued message to $destination');
        
        _stompClient.send(
          destination: destination.toString(),
          body: body.toString(),
          headers: {'content-type': 'application/json'},
        );
        
        print('[ChatWebSocketService] ✅ Queued message sent: $destination');
      } catch (e) {
        print('[ChatWebSocketService] ❌ Failed to send queued message: $e');
        print('[ChatWebSocketService]    └─ Message data: $msgData');
        // Re-queue on failure
        _offlineQueue.add(msgData);
      }
    }

    if (_offlineQueue.isNotEmpty) {
      print('[ChatWebSocketService] ⚠️ ${_offlineQueue.length} messages still queued');
    } else {
      print('[ChatWebSocketService] ✅ All offline messages processed');
    }
  }

  /// Retry all queued messages (called when reconnected)
  void _sendQueuedMessages() {
    if (_offlineQueue.isEmpty) {
      return;
    }

    print('[ChatWebSocketService] Sending ${_offlineQueue.length} queued messages');
    final queue = List.of(_offlineQueue);
    _offlineQueue.clear();

    for (final messageData in queue) {
      try {
        _sendMessageViaWebSocket(messageData);
      } catch (e) {
        // Re-queue on failure
        _offlineQueue.add(messageData);
        print('[ChatWebSocketService] Failed to send queued message, re-queued: $e');
      }
    }
  }

  /// Generate unique clientMessageId
  String _generateClientMessageId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = (timestamp * 1000 + DateTime.now().microsecond) % 999999;
    return '${_currentUserId}_${timestamp}_$random';
  }

  /// Notify connection listeners
  void _notifyConnectionListeners(bool isConnected) {
    for (final listener in _connectionListeners) {
      try {
        listener(isConnected);
      } catch (e) {
        print('[ChatWebSocketService] Error in connection listener: $e');
      }
    }
  }

  /// Disconnect WebSocket
  Future<void> disconnect() async {
    print('[ChatWebSocketService] 🔴 DISCONNECTING...');
    _stopPresenceHeartbeat();

    // Clear subscription handlers first
    for (final handler in _subscriptionHandlers.values) {
      try {
        if (handler != null) {
          handler();  // Call unsubscribe function
        }
      } catch (e) {
        print('[ChatWebSocketService] Error unsubscribing: $e');
      }
    }
    _subscriptionHandlers.clear();
    
    if (_stompClient != null) {
      _stompClient.deactivate();
    }
    _isConnected = false;
    _isConnecting = false;
    _activeSubscriptions.clear();
    _messageStates.clear();
    _offlineQueue.clear();
    print('[ChatWebSocketService] ✅ Disconnected and cleaned up');
  }

  /// Force reconnection - useful when subscriptions seem dead
  Future<void> forceReconnect() async {
    print('[ChatWebSocketService] 🔄 FORCE RECONNECT REQUESTED');
    
    if (_currentToken == null || _currentUserId <= 0) {
      print('[ChatWebSocketService] ❌ Cannot reconnect - no credentials');
      return;
    }
    
    final token = _currentToken!;
    final userId = _currentUserId;
    
    // Disconnect first
    await disconnect();
    
    // Wait a moment
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Reconnect
    print('[ChatWebSocketService] 🔄 Reconnecting with userId=$userId...');
    await connect(token, userId);
  }

  /// Clear all state (for logout)
  Future<void> clear() async {
    _currentUserId = 0;
    _currentToken = null;
    _messageStates.clear();
    _offlineQueue.clear();
    await disconnect();
  }

  /// Verify and re-subscribe if subscriptions are lost
  Future<void> verifySubscriptions() async {
    print('[ChatWebSocketService] 🔍 VERIFYING SUBSCRIPTIONS...');
    print('[ChatWebSocketService]    ├─ isConnected: $_isConnected');
    print('[ChatWebSocketService]    ├─ currentUserId: $_currentUserId');
    print('[ChatWebSocketService]    ├─ stompClient.isActive: ${_stompClient.isActive}');
    print('[ChatWebSocketService]    ├─ Active subscriptions: ${_activeSubscriptions.toList()}');
    print('[ChatWebSocketService]    ├─ Subscription handlers: ${_subscriptionHandlers.keys.toList()}');
    print('[ChatWebSocketService]    └─ Subscription count: ${_activeSubscriptions.length}');
    
    if (!_isConnected) {
      print('[ChatWebSocketService] ⚠️ NOT CONNECTED - Cannot verify subscriptions');
      return;
    }
    
    // Verify STOMP client is actually active
    if (!_stompClient.isActive) {
      print('[ChatWebSocketService] ❌ STOMP CLIENT NOT ACTIVE - forcing reconnect');
      await forceReconnect();
      return;
    }

    // Check if all required subscriptions are present
    // NOTE: /topic/calls uses userId in path, not /user/queue pattern
    final requiredSubscriptions = [
      '/user/queue/messages',
      '/user/queue/typing',
      '/user/queue/notifications',
      '/user/queue/read-receipts',  // ✅ CRITICAL: Read receipt subscription for double ticks
      '/topic/calls.$_currentUserId',  // FIXED: Use the actual topic format
      '/user/queue/presence',  // Personal presence updates (own status)
      '/topic/presence',        // ✅ NEW: Broadcast presence updates (all users)
    ];

    final List<String> missingSubscriptions = [];
    
    for (final subscription in requiredSubscriptions) {
      if (!_activeSubscriptions.contains(subscription)) {
        print('[ChatWebSocketService] ⚠️ MISSING SUBSCRIPTION: $subscription');
        missingSubscriptions.add(subscription);
      }
    }
    
    // Only subscribe to ACTUALLY missing subscriptions, don't clear everything
    if (missingSubscriptions.isNotEmpty) {
      print('[ChatWebSocketService] 🔄 Subscribing to ${missingSubscriptions.length} missing subscriptions...');
      
      for (final subscription in missingSubscriptions) {
        if (subscription == '/user/queue/messages') {
          _subscribeToMessageQueue();
        } else if (subscription == '/user/queue/typing') {
          _subscribeToTypingIndicators();
        } else if (subscription == '/user/queue/notifications') {
          _subscribeToNotifications();
        } else if (subscription == '/user/queue/read-receipts') {
          _subscribeToReadReceipts();  // ✅ CRITICAL: Re-subscribe to read receipts if missing
          _subscribeToMessageAcks();   // ✅ Re-subscribe to send acks if missing
        } else if (subscription == '/topic/calls.$_currentUserId') {
          _subscribeToIncomingCalls();
        } else if (subscription == '/user/queue/presence') {
          _subscribeToPresenceUpdates();
        } else if (subscription == '/topic/presence') {
          _subscribeToAllUsersPresence();  // ✅ NEW: Re-subscribe to broadcast presence if missing
        }
      }
    } else {
      print('[ChatWebSocketService] ✅ All subscriptions are active');
    }
    
    print('[ChatWebSocketService] ✅ Subscription verification complete');
    print('[ChatWebSocketService]    └─ Active subscriptions now: ${_activeSubscriptions.toList()}');
  }

  /// Health check endpoint
  String getStatus() {
    return '''
[ChatWebSocketService Status]
  Connected: $_isConnected
  Current User: $_currentUserId
  Message States: ${_messageStates.length}
  Queued Messages: ${_offlineQueue.length}
  Active Subscriptions: ${_activeSubscriptions.length}
  Connection Listeners: ${_connectionListeners.length}
''';
  }
}
