# New Chat Feature Implementation

## Overview
Added the ability to start a new chat with available users. Users can now search for other users and initiate conversations.

## Changes Made

### 1. Backend - API Service Updates
**File:** `backend/social-service/src/main/java/com/socialmedia/social/dto/ConversationResponse.java`
- Created new DTO to represent conversations with user info and last message details
- Fields: userId, username, fullName, profilePictureUrl, isVerified, lastMessageContent, lastMessageMediaUrl, lastMessageTime, unreadCount, isLastMessageFromMe

**File:** `backend/social-service/src/main/java/com/socialmedia/social/repository/MessageRepository.java`
- Added `findLastMessageBetween()` method to get the last message between two users
- Added `countUnreadMessagesBetween()` method to count unread messages from a specific user

**File:** `backend/social-service/src/main/java/com/socialmedia/social/service/MessageService.java`
- Added `getConversations()` method that fetches all conversations with:
  - User profile information
  - Last message content and time
  - Unread message count
  - Sorted by most recent message first

**File:** `backend/social-service/src/main/java/com/socialmedia/social/controller/MessageController.java`
- Added `GET /messages/conversations` endpoint to fetch conversation list
- Returns list of ConversationResponse objects

### 2. Frontend - Flutter App Updates

#### API Service
**File:** `social-media-mobile/lib/src/services/api_service.dart`
- Added `searchUsers()` method to search for users by keyword
  - Parameters: query string, page number, page size
  - Returns list of user objects (userId, username, fullName, profilePictureUrl, isVerified)

- Added `startNewChat()` method to initiate a new conversation
  - Sends the first message to create a conversation
  - Returns the message response

#### Chat Screen
**File:** `social-media-mobile/lib/src/screens/chats/chat_screen.dart`
- Updated `ChatDetailScreen` constructor to accept `isNewChat` parameter
- Modified `initState()` to handle new chats:
  - For new chats, starts with empty message list
  - For existing conversations, loads message history
  - Skips marking as read for new chats until first message is sent

#### Chats List Screen
**File:** `social-media-mobile/lib/src/screens/chats/chats_screen.dart`
- Added `FloatingActionButton` to open new chat screen
  - Button icon: message icon in primary color
  - Taps navigate to `NewChatScreen`
  - Refreshes conversation list when returning

#### New Chat Screen
**File:** `social-media-mobile/lib/src/screens/chats/new_chat_screen.dart`
- New stateful widget for searching and selecting users
- Features:
  - Search bar with debounced search (500ms delay)
  - User list display with:
    - Avatar (profile picture or initials)
    - Full name and username
    - Verification badge (if verified)
  - Filters out current user from results
  - Tap on user starts a new chat conversation
  - Automatic navigation to chat detail screen
  - Pop back to chats screen after starting chat

## Conversation Model Updates
**File:** `social-media-mobile/lib/src/models/message.dart`
- `Conversation` class already supports all required fields
- No changes needed - fully compatible with new API

## How to Use

1. **Open Chats Screen** - Navigate to the Chats tab in the app
2. **Click Floating Action Button** - Tap the message button in the bottom-right corner
3. **Search for Users** - Type a username or name to search
4. **Select User** - Tap on a user from the search results
5. **Start Chat** - New chat conversation opens and you can send your first message

## API Endpoints

### Get Conversations (Existing)
```
GET /api/social/messages/conversations
Headers: Authorization: Bearer {token}
Response: List<ConversationResponse>
```

### Search Users (New)
```
GET /api/social/profiles/search?keyword={query}&page={page}&size={size}
Headers: Authorization: Bearer {token}
Response: List of user objects
```

### Send Message / Start Chat (Updated)
```
POST /api/social/messages
Headers: Authorization: Bearer {token}, Content-Type: application/json
Body: { "recipientId": int, "content": string }
Response: MessageResponse
```

## Testing

1. Start the app and navigate to Chats tab
2. Tap the floating action button (message icon)
3. Search for available users
4. Tap on a user to start chatting
5. The chat screen opens with empty message history
6. Type and send a message to initiate the conversation
7. Return to Chats screen - the new conversation appears in the list

## Technical Details

- **Debounced Search:** User search is debounced by 500ms to reduce API calls
- **Real-time Updates:** WebSocket connection established when chat is opened
- **User Filtering:** Current user is automatically excluded from search results
- **Profile Pictures:** Supports full URLs and relative paths with proper URL construction
- **Verification Badge:** Shows checkmark for verified users
- **Unread Count:** Displays badge for unread messages in conversation list

## Error Handling

- Network errors show snackbar notifications
- Invalid searches return empty results
- Failed message sends show error messages
- Graceful fallback to user initials if no profile picture available

## Future Enhancements

1. Recent contacts/favorites
2. Blocked users list
3. Group chats
4. Chat search history
5. Quick reply templates
6. Rich message formatting
