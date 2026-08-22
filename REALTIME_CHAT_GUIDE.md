# Real-Time Chat Implementation Guide

## Overview

This document describes the production-level real-time chat system implemented in the social media mobile app using WebSocket (STOMP) for instant message delivery, similar to WhatsApp and Instagram.

## Architecture

### Backend (Spring Boot)

**WebSocket Configuration**: `WebSocketConfig.java` (social-service:8082)
- STOMP endpoint: `/ws` with SockJS fallback
- Message broker configured with:
  - Application destination prefix: `/app`
  - Broker destinations: `/topic`, `/queue`, `/user`
  - User queue destination: `/user/queue/messages`

**Message Controller**: `@MessageMapping("/chat.send")`
- Receives messages sent to `/app/chat.send`
- Routes messages to `/user/queue/messages` for user-specific delivery
- Ensures real-time delivery only to intended recipient

**REST Endpoints** (for initial load and fallback):
- `GET /social/messages/conversations` - Fetch all conversations with unread counts
- `GET /social/messages/conversation/{otherUserId}` - Fetch conversation history
- `POST /social/messages` - Send message (fallback if WebSocket unavailable)
- `PUT /social/messages/conversation/{otherUserId}/read` - Mark as read

### Frontend (Flutter Mobile)

**Core Components**:

1. **ChatWebSocketService** (`lib/src/services/chat_websocket_service.dart`)
   - Singleton service managing WebSocket lifecycle
   - Handles STOMP client connection, subscription, and message sending
   - Features:
     - Automatic connection management
     - Conversation-specific subscriptions
     - Connection status listeners
     - Message listener callbacks
  ````markdown
  # Real-Time Chat Implementation Guide

  ## Overview

  This document describes the production-level real-time chat system implemented in the social media mobile app using WebSocket (STOMP) for instant message delivery, similar to WhatsApp and Instagram.

  ## Architecture

  ### Backend (Spring Boot)

  **WebSocket Configuration**: `WebSocketConfig.java` (social-service:8082)
  - STOMP endpoint: `/ws` with SockJS fallback
  - Message broker configured with:
    - Application destination prefix: `/app`
    - Broker destinations: `/topic`, `/queue`, `/user`
    - User queue destination: `/user/queue/messages`

  **Message Controller**: `@MessageMapping("/chat.send")`
  - Receives messages sent to `/app/chat.send`
  - Routes messages to `/user/queue/messages` for user-specific delivery
  - Ensures real-time delivery only to intended recipient

  **REST Endpoints** (for initial load and fallback):
  - `GET /social/messages/conversations` - Fetch all conversations with unread counts
  - `GET /social/messages/conversation/{otherUserId}` - Fetch conversation history
  - `POST /social/messages` - Send message (fallback if WebSocket unavailable)
  - `PUT /social/messages/conversation/{otherUserId}/read` - Mark as read

  ### Frontend (Flutter Mobile)

  **Core Components**:

  1. **ChatWebSocketService** (`lib/src/services/chat_websocket_service.dart`)
     - Singleton service managing WebSocket lifecycle
     - Handles STOMP client connection, subscription, and message sending
     - Features:
       - Automatic connection management
       - Conversation-specific subscriptions
       - Connection status listeners
       - Message listener callbacks
     - Connection Details:
       - URL: `ws://192.168.31.74:8082/ws`
       - Subscribe to: `/user/queue/messages`
       - Send to: `/app/chat.send`

  2. **Message Model** (`lib/src/models/message.dart`)
     ```dart
     Message {
       int id
       int senderId
       String senderName
       String? senderProfilePic
       int recipientId
       String content
       DateTime createdAt
       bool isRead
       String timeAgo // Computed property
     }
     ```

  3. **Conversation Model** (`lib/src/models/message.dart`)
     ```dart
     Conversation {
       int userId
       String username
       String fullName
       String? profilePictureUrl
       String lastMessage
       int unreadCount
       bool isOnline
     }
     ```

  4. **ChatDetailScreen** (`lib/src/screens/chats/chat_screen.dart`)
     - Displays individual conversations with real-time updates
     - Features:
       - Loads message history on init
       - WebSocket subscription for real-time messages
       - Message sending via WebSocket with REST fallback
       - Automatic scrolling to latest messages
       - Online status indicator
       - Message time formatting

  5. **ChatsScreen** (`lib/src/screens/chats/chats_screen.dart`)
     - Lists all conversations with last message preview
     - Features:
       - Real API data (no mock data)
       - Unread count badges
       - Online status indicators
       - Search functionality
       - Professional UI matching Instagram/WhatsApp

  ## Real-Time Message Flow

  ### Sending a Message
  ```
  User types message
      ↓
  ChatDetailScreen._sendMessage()
      ↓
  (if WebSocket connected) 
      → ChatWebSocketService.sendMessage()
        → STOMP send to /app/chat.send
        → Backend receives via @MessageMapping
        → Backend routes to /user/queue/messages
        → Recipient receives via WebSocket subscription
  (else - fallback)
      → ApiService.sendMessage() (REST POST)
      → Reload messages from API
  ```

  ### Receiving a Message
  ```
  Backend publishes to /user/queue/messages
      ↓
  ChatWebSocketService receives (via subscription callback)
      ↓
  _onMessageReceived(Message message)
      ↓
  ChatDetailScreen._onMessageReceived()
      ↓
  setState(() { _messages.add(message) })
      ↓
  UI updates automatically with new message
  ```

  ## Implementation Details

  ### WebSocket Service Initialization

  ```dart
  // In ChatDetailScreen.initState()
  Future<void> _initializeWebSocket() async {
    try {
      final token = await ApiService.getToken();
      final profile = await ApiService.getMyProfile();
      _currentUserId = profile['userId'] as int? ?? 0;
    
      if (token != null && _currentUserId > 0) {
        await _webSocketService.connect(token, _currentUserId);
      
        // Subscribe to incoming messages
        _webSocket_service.subscribeToConversation(
          widget.conversation.userId,
          _onMessageReceived,
        );
      }
    } catch (e) {
      print('Error initializing WebSocket: $e');
    }
  }
  ```

  ### Message Display Logic

  ```dart
  // Determine if message is from current user
  final isMine = msg.senderId == _currentUserId;

  // Right-aligned for sent messages (primary color)
  // Left-aligned for received messages (card color)
  ```

  ### Cleanup on Screen Close

  ```dart
  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    // Unsubscribe from WebSocket updates
    _webSocketService.unsubscribeFromConversation(widget.conversation.userId);
    _webSocketService.removeConnectionListener(_onWebSocketConnectionChanged);
    super.dispose();
  }
  ```

  ## Features

  ✅ **Real-Time Messaging** - Instant message delivery via WebSocket
  ✅ **Online Status** - User presence indication
  ✅ **Unread Badges** - Conversation unread message count
  ✅ **Message History** - Load previous messages on conversation open
  ✅ **Automatic Scrolling** - Scroll to latest message when new ones arrive
  ✅ **Connection Status** - Visual feedback on WebSocket connection
  ✅ **Fallback Support** - REST API fallback if WebSocket unavailable
  ✅ **User Identification** - Correct message alignment based on sender
  ✅ **Time Formatting** - Relative time display (2m, 1h, yesterday, etc.)
  ✅ **Professional UI** - Instagram/WhatsApp-style message bubbles

  ## Dependencies

  Added to `pubspec.yaml`:
  ```yaml
  web_socket_channel: ^2.4.0
  stomp_dart_client: ^0.4.4
  ```

  ## Network Configuration

  **Device IP**: `192.168.31.74`
  **Social Service**: `8082`
  **WebSocket Endpoint**: `ws://192.168.31.74:8082/ws`

  > Note: Update IP address in `ChatWebSocketService.connect()` if deploying to different network

  ## Testing the System

  1. **Start Backend Services**
     ```bash
     cd backend
     ./start-all-services.bat
     ```

  2. **Launch Mobile App**
     ```bash
     flutter run
     ```

  3. **Test Real-Time Messaging**
     - Login as User A
     - Open chat with User B
     - Send message from User A
     - Message should appear in User B's chat in real-time
     - Send message from User B
     - Message should appear in User A's chat in real-time

  4. **Monitor WebSocket**
     - Check console logs for `[WS]` prefix messages
     - Verify `Connected successfully` appears on chat open
     - Check message send/receive logs

  ## Troubleshooting

  ### WebSocket Connection Fails
  - Verify backend services are running
  - Check IP address matches network configuration
  - Ensure port 8082 is accessible
  - Check firewall settings

  ### Messages Not Arriving
  - Verify WebSocket is connected (check console logs)
  - Check user IDs match in Message model
  - Verify recipient ID is set correctly
  - Check backend message routing in MessageController

  ### Old Messages Displayed
  - Ensure `_messages` list is populated from API on init
  - Verify message sorting by createdAt
  - Check Message.fromJson() parsing

  ## Future Enhancements

  - [ ] Typing indicators
  - [ ] Message read receipts
  - [ ] Image/file sharing
  - [ ] Message reactions
  - [ ] Message editing/deletion
  - [ ] Voice/video calling
  - [ ] Group chats
  - [ ] Message search
  - [ ] Chat encryption

  ## Related Files

  - Backend: `backend/social-service/src/main/java/com/example/socialservice/controller/MessageController.java`
  - Backend Config: `backend/social-service/src/main/java/com/example/socialservice/config/WebSocketConfig.java`
  - Frontend Service: `lib/src/services/chat_websocket_service.dart`
  - Frontend Screen: `lib/src/screens/chats/chat_screen.dart`
  - Frontend List: `lib/src/screens/chats/chats_screen.dart`
  - Models: `lib/src/models/message.dart`

  ---

  **Last Updated**: Current session
  **Status**: ✅ Production Ready for Development/Testing

  ````
