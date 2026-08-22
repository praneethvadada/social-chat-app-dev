import 'dart:async';
import 'package:flutter/material.dart';
import '../database/local_chat_repository.dart';
import '../database/database_helper.dart';
import '../models/message.dart';
import 'chat_websocket_service.dart';
import 'connectivity_service.dart';

/// MessageQueueService - Manages pending messages and auto-retry on reconnect
/// 
/// Features:
/// - Queues messages when offline or connection unstable
/// - Auto-retries pending messages when connection stabilizes
/// - Updates message status: PENDING → SENT → READ
/// - Shows clock icon ⏱ for pending, ✓ for sent, ✓✓ for read
class MessageQueueService {
  static final MessageQueueService _instance = MessageQueueService._internal();
  
  factory MessageQueueService() {
    return _instance;
  }
  
  MessageQueueService._internal();
  
  final LocalChatRepository _localRepo = LocalChatRepository();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  
  // Pending messages cache: clientMessageId -> (receiverId, content)
  final Map<String, (int, String)> _pendingMessages = {};
  
  // Track if we're currently retrying
  bool _isRetrying = false;
  
  /// Initialize queue monitoring
  /// Should be called once in main.dart
  Future<void> initialize(
    ChatWebSocketService webSocketService,
    ConnectivityService connectivityService,
  ) async {
    print('[MessageQueue] 🔧 Initializing message queue service...');
    
    // Load pending messages from SQLite on startup
    await _loadPendingMessages();
    print('[MessageQueue] Loaded ${_pendingMessages.length} pending messages from SQLite');
    
    // Listen for connectivity changes
    connectivityService.addListener((isOnline) {
      print('[MessageQueue] 🔔 Connectivity listener triggered: ${isOnline ? "🟢 ONLINE" : "🔴 OFFLINE"}');
      print('[MessageQueue] Pending messages in queue: ${_pendingMessages.length}');
      
      if (isOnline && _pendingMessages.isNotEmpty) {
        print('[MessageQueue] 🔄 Connection restored! Waiting for WebSocket to connect...');
        
        // Wait for WebSocket to actually connect (not just network available)
        Future.delayed(const Duration(milliseconds: 100), () async {
          int attempts = 0;
          const maxAttempts = 30; // 30 * 1 second = 30 seconds max wait
          
          while (!webSocketService.isConnected && attempts < maxAttempts) {
            await Future.delayed(const Duration(seconds: 1));
            attempts++;
            print('[MessageQueue] ⏳ Waiting for WebSocket... Attempt $attempts/$maxAttempts (connected: ${webSocketService.isConnected})');
          }
          
          if (webSocketService.isConnected) {
            print('[MessageQueue] ✅ WebSocket connected! Retrying ${_pendingMessages.length} pending messages...');
            _retryPendingMessages(webSocketService);
          } else {
            print('[MessageQueue] ❌ WebSocket failed to connect after $maxAttempts seconds');
          }
        });
      } else if (isOnline && _pendingMessages.isEmpty) {
        print('[MessageQueue] ✅ Back online but no pending messages to retry');
      }
    });
    
    // Listen for successful message sends
    webSocketService.messageStream.listen((message) {
      if (message.clientMessageId != null) {
        // Message was sent successfully, update status
        _updateMessageStatus(message.clientMessageId!, 'SENT');
      }
    });
    
    // Listen for read receipts
    webSocketService.readReceiptStream.listen((receipt) {
      // receipt is a ReadReceipt object with messageIds list
      for (final messageId in receipt.messageIds) {
        _updateMessageStatus(messageId.toString(), 'READ');
      }
    });
    
    print('[MessageQueue] ✅ Message queue service initialized');
  }
  
  /// Add a message to the queue (called when sending offline or immediately after reconnect)
  Future<void> queueMessage({
    required String clientMessageId,
    required int chatId,
    required int senderId,
    required int receiverId,
    required String content,
    required DateTime createdAt,
  }) async {
    print('[MessageQueue] ➕ Queueing message: clientId=$clientMessageId');
    
    _pendingMessages[clientMessageId] = (receiverId, content);
    
    // Save to SQLite with PENDING status
    final message = SQLiteMessage(
      clientMessageId: clientMessageId,
      chatId: chatId,
      senderId: senderId,
      receiverId: receiverId,
      content: content,
      createdAt: createdAt.millisecondsSinceEpoch,
      status: 'PENDING',
    );
    
    await _localRepo.insertMessage(message);
    print('[MessageQueue] ✅ Message queued and saved to SQLite: $clientMessageId');
  }
  
  /// Retry all pending messages
  Future<void> _retryPendingMessages(ChatWebSocketService webSocketService) async {
    if (_isRetrying || _pendingMessages.isEmpty) return;
    
    // CRITICAL: Only retry if WebSocket is actually connected
    if (!webSocketService.isConnected) {
      print('[MessageQueue] ⚠️ Cannot retry: WebSocket not connected yet (${webSocketService.isConnected})');
      return;
    }
    
    _isRetrying = true;
    print('[MessageQueue] 🔄 Starting retry of ${_pendingMessages.length} pending messages... (WebSocket connected: ${webSocketService.isConnected})');
    
    try {
      final entriesToRemove = <String>[];
      
      for (final entry in _pendingMessages.entries) {
        final originalClientMessageId = entry.key;
        final (receiverId, content) = entry.value;
        
        print('[MessageQueue] 🔄 Retrying: $originalClientMessageId → user $receiverId');
        
        try {
          // CRITICAL: Only send if WebSocket is still connected
          if (!webSocketService.isConnected) {
            print('[MessageQueue] ⚠️ WebSocket disconnected mid-retry, stopping');
            break;
          }
          
          // Send the message via WebSocket with skipOptimistic=true and original clientMessageId
          // (message already exists in chat with ⏱ icon from when it was first sent offline)
          final newClientMessageId = webSocketService.sendChatMessage(
            receiverId,
            content,
            skipOptimistic: true,  // Don't add duplicate, just send
            clientMessageId: originalClientMessageId,  // Use original ID for reconciliation
          );
          print('[MessageQueue] ✅ Message sent with ID: $newClientMessageId');
          
          // Remove from pending queue since it's been sent
          entriesToRemove.add(originalClientMessageId);
          
          // Wait a bit before next send to avoid overloading
          await Future.delayed(const Duration(milliseconds: 500));
        } catch (e) {
          print('[MessageQueue] ❌ Failed to retry: $originalClientMessageId - $e');
          // Keep in queue for next retry attempt
        }
      }
      
      // Remove successfully sent messages from queue
      for (final clientId in entriesToRemove) {
        _pendingMessages.remove(clientId);
        print('[MessageQueue] Removed from queue: $clientId');
      }
      
      print('[MessageQueue] ✅ Retry complete. Remaining pending: ${_pendingMessages.length}');
    } finally {
      _isRetrying = false;
    }
  }
  
  /// Update message status and remove from pending queue if sent
  Future<void> _updateMessageStatus(String clientMessageId, String newStatus) async {
    print('[MessageQueue] 📝 Updating status: $clientMessageId → $newStatus');
    
    await _localRepo.updateMessageStatus(clientMessageId, newStatus);
    
    // Remove from pending queue if it was sent or read
    if (newStatus == 'SENT' || newStatus == 'READ') {
      _pendingMessages.remove(clientMessageId);
      print('[MessageQueue] ✅ Message confirmed: $clientMessageId');
    }
  }
  
  /// Load pending messages from SQLite on app startup
  Future<void> _loadPendingMessages() async {
    try {
      final db = await _dbHelper.database;
      
      final maps = await db.query(
        'messages',
        where: 'status = ?',
        whereArgs: ['PENDING'],
      );
      
      for (final map in maps) {
        final clientMessageId = map['client_message_id'] as String?;
        final receiverId = map['receiver_id'] as int;
        final content = map['content'] as String;
        
        if (clientMessageId != null) {
          _pendingMessages[clientMessageId] = (receiverId, content);
        }
      }
      
      print('[MessageQueue] Loaded ${_pendingMessages.length} pending messages from SQLite');
    } catch (e) {
      print('[MessageQueue] Error loading pending messages: $e');
    }
  }
  
  /// Get pending messages (for debugging/UI)
  Map<String, (int, String)> getPendingMessages() => Map.unmodifiable(_pendingMessages);
  
  /// Check if a specific message is pending
  bool isMessagePending(String clientMessageId) => _pendingMessages.containsKey(clientMessageId);
  
  /// Dispose and cleanup
  void dispose() {
    print('[MessageQueue] Disposing message queue service...');
  }
}
