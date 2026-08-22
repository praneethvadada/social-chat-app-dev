# Chat System - Exact Code Changes Needed

## CHANGE 1: Backend - Add Status Field to MessageResponse

**File:** `backend/social-service/src/main/java/com/socialmedia/social/dto/MessageResponse.java`

**REPLACE:**
```java
package com.socialmedia.social.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class MessageResponse {
    private Long id;
    private Long senderId;
    private String senderName;
    private String senderProfilePictureUrl;
    private Long receiverId;
    private String content;
    private String mediaUrl;
    private Boolean isRead;
    private LocalDateTime readAt;
    private LocalDateTime createdAt;
    private String clientMessageId;  // ← Echo back client's optimistic ID for reconciliation
}
```

**WITH:**
```java
package com.socialmedia.social.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class MessageResponse {
    private Long id;
    private Long senderId;
    private String senderName;
    private String senderProfilePictureUrl;
    private Long receiverId;
    private String content;
    private String mediaUrl;
    private Boolean isRead;
    private LocalDateTime readAt;
    private LocalDateTime createdAt;
    private String clientMessageId;  // ← Echo back client's optimistic ID for reconciliation
    private String status;  // ← NEW: "sending", "sent", or "read"
}
```

---

## CHANGE 2: Backend - Set Status in MessageService.mapToResponse()

**File:** `backend/social-service/src/main/java/com/socialmedia/social/service/MessageService.java`

**Find the mapToResponse() method around line 306, and REPLACE:**
```java
private MessageResponse mapToResponse(Message message) {
    MessageResponse response = new MessageResponse();
    response.setId(message.getId());
    response.setSenderId(message.getSenderId());
    response.setReceiverId(message.getReceiverId());
    response.setContent(message.getContent());
    response.setMediaUrl(message.getMediaUrl());
    response.setIsRead(message.getIsRead());
    response.setReadAt(message.getReadAt());
    response.setCreatedAt(message.getCreatedAt());
    response.setClientMessageId(message.getClientMessageId());  // ← Echo back client ID for reconciliation
    
    // Fetch sender details
    try {
        UserProfile sender = userProfileRepository.findByUserId(message.getSenderId()).orElse(null);
        if (sender != null) {
            response.setSenderName(sender.getUsername());
            
            // Construct full S3 URL for sender profile picture
            String senderProfilePic = sender.getProfilePictureUrl();
            if (senderProfilePic != null && !senderProfilePic.isEmpty()) {
                if (!senderProfilePic.startsWith("http://") && !senderProfilePic.startsWith("https://")) {
                    senderProfilePic = String.format("https://%s.s3.%s.amazonaws.com/%s", 
                        bucketName, region, senderProfilePic);
                }
            }
            response.setSenderProfilePictureUrl(senderProfilePic);
        } else {
            response.setSenderName("Unknown");
            response.setSenderProfilePictureUrl(null);
        }
    } catch (Exception e) {
        System.out.println("[MessageService] Error fetching sender details: " + e.getMessage());
        response.setSenderName("Unknown");
        response.setSenderProfilePictureUrl(null);
    }
    
    return response;
}
```

**WITH:**
```java
private MessageResponse mapToResponse(Message message) {
    MessageResponse response = new MessageResponse();
    response.setId(message.getId());
    response.setSenderId(message.getSenderId());
    response.setReceiverId(message.getReceiverId());
    response.setContent(message.getContent());
    response.setMediaUrl(message.getMediaUrl());
    response.setIsRead(message.getIsRead());
    response.setReadAt(message.getReadAt());
    response.setCreatedAt(message.getCreatedAt());
    response.setClientMessageId(message.getClientMessageId());  // ← Echo back client ID for reconciliation
    
    // ✅ NEW: Set status based on message state
    if (message.getIsRead()) {
        response.setStatus("read");
    } else if (message.getId() != null && message.getId() > 0) {
        response.setStatus("sent");
    } else {
        response.setStatus("sending");
    }
    
    // Fetch sender details
    try {
        UserProfile sender = userProfileRepository.findByUserId(message.getSenderId()).orElse(null);
        if (sender != null) {
            response.setSenderName(sender.getUsername());
            
            // Construct full S3 URL for sender profile picture
            String senderProfilePic = sender.getProfilePictureUrl();
            if (senderProfilePic != null && !senderProfilePic.isEmpty()) {
                if (!senderProfilePic.startsWith("http://") && !senderProfilePic.startsWith("https://")) {
                    senderProfilePic = String.format("https://%s.s3.%s.amazonaws.com/%s", 
                        bucketName, region, senderProfilePic);
                }
            }
            response.setSenderProfilePictureUrl(senderProfilePic);
        } else {
            response.setSenderName("Unknown");
            response.setSenderProfilePictureUrl(null);
        }
    } catch (Exception e) {
        System.out.println("[MessageService] Error fetching sender details: " + e.getMessage());
        response.setSenderName("Unknown");
        response.setSenderProfilePictureUrl(null);
    }
    
    return response;
}
```

---

## CHANGE 3: Backend - Fix Typing Indicator Queue

**File:** `backend/social-service/src/main/java/com/socialmedia/social/controller/MessageController.java`

**Find line ~171, and REPLACE:**
```java
                // Forward typing event to the recipient's notifications queue
                try {
                    messagingTemplate.convertAndSendToUser(request.getReceiverId().toString(), "/queue/notifications", payload);
```

**WITH:**
```java
                // Forward typing event to the recipient's typing queue
                try {
                    messagingTemplate.convertAndSendToUser(request.getReceiverId().toString(), "/queue/typing", payload);
```

---

## CHANGE 4: Frontend - Parse Status from Backend

**File:** `social-media-mobile/lib/src/models/message.dart`

**Find the fromJson factory method around line 63, and REPLACE:**
```dart
  factory Message.fromJson(Map<String, dynamic> json) {
    // Debug logging
    print('[MESSAGE] 📨 Parsing message JSON: id=${json['id']}, clientMessageId=${json['clientMessageId']}, senderId=${json['senderId']}');

    // Determine message status
    MessageStatus status = MessageStatus.sent;
    
    // If client message ID is present and server ID is 0, it's still sending (optimistic)
    final serverId = json['id'] as int? ?? 0;
    final clientId = (json['messageId'] ?? json['clientMessageId'])?.toString();
    
    if (serverId == 0 && clientId != null) {
      status = MessageStatus.sending;
      print('[MESSAGE] 📤 Status: SENDING (optimistic)');
    } else if (json['isRead'] == true) {
      status = MessageStatus.read;
      print('[MESSAGE] 📖 Status: READ');
    } else {
      status = MessageStatus.sent;
      print('[MESSAGE] ✅ Status: SENT');
    }

    return Message(
```

**WITH:**
```dart
  factory Message.fromJson(Map<String, dynamic> json) {
    // Debug logging
    print('[MESSAGE] 📨 Parsing message JSON: id=${json['id']}, clientMessageId=${json['clientMessageId']}, senderId=${json['senderId']}');

    // Determine message status
    MessageStatus status = MessageStatus.sent;
    
    // ✅ FIRST, try to use explicit status from backend
    final statusStr = json['status'] as String?;
    if (statusStr != null) {
      switch (statusStr.toLowerCase()) {
        case 'sending':
          status = MessageStatus.sending;
          print('[MESSAGE] 📤 Status: SENDING (from backend)');
          break;
        case 'read':
          status = MessageStatus.read;
          print('[MESSAGE] 📖 Status: READ (from backend)');
          break;
        case 'sent':
        default:
          status = MessageStatus.sent;
          print('[MESSAGE] ✅ Status: SENT (from backend)');
      }
    } else {
      // Fallback: infer from other fields if status not provided
      final serverId = json['id'] as int? ?? 0;
      final clientId = (json['messageId'] ?? json['clientMessageId'])?.toString();
      
      if (serverId == 0 && clientId != null) {
        status = MessageStatus.sending;
        print('[MESSAGE] 📤 Status: SENDING (inferred - optimistic)');
      } else if (json['isRead'] == true) {
        status = MessageStatus.read;
        print('[MESSAGE] 📖 Status: READ (inferred from isRead)');
      } else {
        status = MessageStatus.sent;
        print('[MESSAGE] ✅ Status: SENT (inferred from serverId)');
      }
    }

    return Message(
```

---

## CHANGE 5: Frontend - Fix Timestamp Fallback

**File:** `social-media-mobile/lib/src/models/message.dart`

**Find line ~89, and REPLACE:**
```dart
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now().toUtc(),
```

**WITH:**
```dart
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime(1970, 1, 1).toUtc(),  // Fallback to epoch instead of "now" - messages with missing timestamps appear at bottom
```

---

## CHANGE 6: Frontend - Add Read Receipt Handler

**File:** `social-media-mobile/lib/src/services/chat_websocket_service.dart`

**Find the _onNotificationReceived method around line 348, and REPLACE:**
```dart
  /// Handle incoming notifications: follow, like, comment, mention, etc
  void _onNotificationReceived(StompFrame frame) {
    try {
      final data = jsonDecode(frame.body ?? '{}') as Map<String, dynamic>;
      print('[ChatWebSocketService] NOTIFICATION_RECEIVED: type=${data["type"]}, actor=${data["actorId"]}');
      
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
```

**WITH:**
```dart
  /// Handle incoming notifications: follow, like, comment, mention, read receipts, etc
  void _onNotificationReceived(StompFrame frame) {
    try {
      final data = jsonDecode(frame.body ?? '{}') as Map<String, dynamic>;
      final notificationType = data["type"] as String? ?? '';
      
      print('[ChatWebSocketService] NOTIFICATION_RECEIVED: type=$notificationType');
      
      // ✅ NEW: Handle read receipts
      if (notificationType == 'read_receipt' || notificationType == 'read_receipts') {
        print('[ChatWebSocketService] 📖 Read receipt received');
        _handleReadReceipt(data);
        return; // Don't broadcast read receipts, handle internally
      }
      
      // Broadcast other notifications to listeners
      for (var listener in _notificationListeners) {
        listener(data);
      }
      
      // Also emit to the stream for other services (CallSignalingService, etc)
      _notificationController.add(data);
    } catch (e) {
      print('[ChatWebSocketService] Error parsing notification: $e');
    }
  }

  /// ✅ NEW: Handle read receipt notifications from server
  void _handleReadReceipt(Map<String, dynamic> notification) {
    try {
      final messageIds = (notification['messageIds'] as List?)
          ?.map((id) => (id as num?)?.toInt() ?? 0)
          .where((id) => id > 0)
          .toList() ?? [];
      
      final fromUserId = (notification['fromUserId'] as num?)?.toInt();
      
      print('[ChatWebSocketService] 📖 Processing read receipt from user=$fromUserId for ${messageIds.length} messages');
      
      if (fromUserId != null && fromUserId > 0 && messageIds.isNotEmpty && _chatStore != null) {
        // Mark messages as read in ChatStore
        _chatStore!.markMessagesRead(
          fromUserId,
          messageIds: messageIds,
          currentUserId: _currentUserId,
        );
        print('[ChatWebSocketService] ✅ Read receipt processed - messages marked as read');
      }
    } catch (e) {
      print('[ChatWebSocketService] ❌ Error handling read receipt: $e');
    }
  }
```

---

## CHANGE 7: Frontend - Send All Message IDs When Marking as Read

**File:** `social-media-mobile/lib/src/state/chat_store.dart`

**Find markMessagesRead() method around line 295-313, and REPLACE:**
```dart
    if (changed) {
      _messagesByUser[otherUserId] = newList..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      print('[CHATSTORE] markMessagesRead applied for otherUserId=$otherUserId marked=$markedCount');
      
      // Send read receipt to server via WebSocket
      try {
        final wsService = ChatWebSocketService();
        if (wsService.isConnected && idsSet.isNotEmpty) {
          wsService.sendReadReceipt(otherUserId, idsSet.toList());
        }
      } catch (e) {
        print('[CHATSTORE] Failed to send read receipt: $e');
      }
      
      notifyListeners();
    }
```

**WITH:**
```dart
    if (changed) {
      _messagesByUser[otherUserId] = newList..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      print('[CHATSTORE] markMessagesRead applied for otherUserId=$otherUserId marked=$markedCount');
      
      // ✅ NEW: Collect ALL message IDs that were marked (whether explicit or all unread)
      List<int> allMarkedIds = newList
          .where((m) => m.readAt != null && m.recipientId == effCurrentUserId)
          .map((m) => m.id)
          .where((id) => id > 0)
          .toList();
      
      print('[CHATSTORE] Marked ${allMarkedIds.length} messages as read, sending to backend');
      
      // Send read receipt to server via WebSocket
      try {
        final wsService = ChatWebSocketService();
        if (wsService.isConnected && allMarkedIds.isNotEmpty) {
          wsService.sendReadReceipt(otherUserId, allMarkedIds);
        }
      } catch (e) {
        print('[CHATSTORE] Failed to send read receipt: $e');
      }
      
      notifyListeners();
    }
```

---

## Summary of Changes

| # | File | Type | Lines | Change |
|---|------|------|-------|--------|
| 1 | MessageResponse.java | ADD | - | Add `status` field |
| 2 | MessageService.java | MODIFY | ~306-340 | Set status in mapToResponse() |
| 3 | MessageController.java | MODIFY | ~171 | Change queue from notifications → typing |
| 4 | message.dart | MODIFY | ~63-92 | Parse status field; use fallback to epoch |
| 5 | chat_websocket_service.dart | MODIFY | ~348-365 | Add _handleReadReceipt() method |
| 6 | chat_store.dart | MODIFY | ~295-313 | Collect and send all marked message IDs |

