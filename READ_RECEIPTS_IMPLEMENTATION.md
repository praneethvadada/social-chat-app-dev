# Read Receipts & Activity Status Implementation Summary

## Overview
Implemented WhatsApp-style read receipts and activity status privacy settings for the chat feature, with full support for user privacy controls.

## Frontend Changes (Flutter/Dart)

### 1. **Message Model Updates** ([message.dart](social-media-mobile/lib/src/models/message.dart))
- Already had `isRead` field to track message read status

### 2. **User Profile Model** ([user_profile.dart](social-media-mobile/lib/src/models/user_profile.dart))
- Added `showReadReceipts` field (default: true) - controls whether read receipts are visible to others
- Added `showActivityStatus` field (default: true) - controls whether online/offline status is visible to others
- Updated `fromJson()` factory to parse these fields from backend

### 3. **API Service** ([api_service.dart](social-media-mobile/lib/src/services/api_service.dart))
- Added `markMessageAsRead(messageId)` method - calls PUT /messages/{messageId}/read endpoint
- Updated `updateMyProfile()` to accept `showReadReceipts` and `showActivityStatus` parameters

### 4. **Chat Screen** ([chat_screen.dart](social-media-mobile/lib/src/screens/chats/chat_screen.dart))
- **State Variables Added**:
  - `_targetShowActivityStatus` - whether other user shares their online status
  - `_targetShowReadReceipts` - whether other user shares read receipts
  
- **Auto-mark Messages as Read**:
  - When a received message appears on screen, it's automatically marked as read via API
  - Only marks messages that aren't already read

- **Read Receipt Icons**:
  - Single tick (✓) - message sent but not read
  - Double tick (✓✓) - message read by recipient
  - If target user has `showReadReceipts` disabled, always shows single tick

- **Activity Status Display**:
  - Shows "Online" or "Offline" in chat header if user has `showActivityStatus` enabled
  - Shows "Active now" if user has disabled activity status
  - Respects user's privacy setting

- **Message Mark-as-Read Method**:
  - `_markMessageAsRead(Message)` - calls API and updates local state

### 5. **Privacy Settings Screen** ([privacy_settings_screen.dart](social-media-mobile/lib/src/screens/settings/privacy_settings_screen.dart))
- **Load Settings**: Fetches `showReadReceipts` and `showActivityStatus` from backend on init
- **Save to Backend**: Both settings are now saved to backend (not just local storage)
- **Updated Callbacks**:
  - `_onActivityStatusChanged()` - saves to backend with snackbar feedback
  - `_onReadReceiptsChanged()` - saves to backend with snackbar feedback

## Backend Changes (Java/Spring Boot)

### 1. **UserProfile Entity** ([UserProfile.java](backend/social-service/src/main/java/com/socialmedia/social/entity/UserProfile.java))
```java
@Column(name = "show_read_receipts", nullable = false)
private Boolean showReadReceipts = true;

@Column(name = "show_activity_status", nullable = false)
private Boolean showActivityStatus = true;
```
- Default values: both true (features enabled by default)

### 2. **UserProfileResponse DTO** ([UserProfileResponse.java](backend/social-service/src/main/java/com/socialmedia/social/dto/UserProfileResponse.java))
- Added `showReadReceipts` field
- Added `showActivityStatus` field

### 3. **UserProfileRequest DTO** ([UserProfileRequest.java](backend/social-service/src/main/java/com/socialmedia/social/dto/UserProfileRequest.java))
- Added `showReadReceipts` field for updates
- Added `showActivityStatus` field for updates

### 4. **UserProfileService** ([UserProfileService.java](backend/social-service/src/main/java/com/socialmedia/social/service/UserProfileService.java))
- Updated `mapToResponse()` to map new fields to response DTOs
- Updated `updateProfile()` to handle new fields in update requests

### 5. **Database Migration** ([migrate_read_receipts.sql](backend/migrate_read_receipts.sql))
```sql
ALTER TABLE users ADD COLUMN show_read_receipts BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE users ADD COLUMN show_activity_status BOOLEAN NOT NULL DEFAULT true;
CREATE INDEX idx_show_read_receipts ON users(show_read_receipts);
CREATE INDEX idx_show_activity_status ON users(show_activity_status);
```

### 6. **MessageController** (Existing)
- Already has endpoints:
  - `PUT /messages/{messageId}/read` - mark single message as read
  - `PUT /messages/conversation/{otherUserId}/read` - mark all messages in conversation as read

## Feature Behavior

### Read Receipts
1. **Sending**: When user sends message, it shows with single tick (✓)
2. **Recipient Views**: When recipient opens chat and message appears on screen, it's automatically marked as read
3. **Sender Sees Update**: Sender sees double tick (✓✓) when message is read
4. **Privacy Respected**: If sender's `showReadReceipts` is disabled, recipient never sees double tick, only single tick

### Activity Status
1. **Default**: All new users have activity status visible by default
2. **Display**: Chat header shows "Online" or "Offline" if enabled, shows "Active now" if disabled
3. **WebSocket**: Uses existing WebSocket connection to track online/offline status in real-time
4. **Privacy**: User can disable from Settings > Privacy > Show Activity Status

## User Privacy Control Flow

```
Settings Screen
    ↓
User toggles "Show Read Receipts" or "Show Activity Status"
    ↓
Frontend calls API: PUT /profiles/me with updated fields
    ↓
Backend updates UserProfile record
    ↓
When other users view this user's chat:
    - Fetch user profile (includes showReadReceipts, showActivityStatus)
    - Respect these settings when displaying read receipts and online status
```

## Testing Checklist
- [ ] Send message → recipient opens chat → verify auto-marked as read
- [ ] Verify single tick shows initially, changes to double tick when read
- [ ] Disable read receipts → verify sender only sees single tick even when recipient reads
- [ ] Verify "Active now" shows when activity status is disabled
- [ ] Verify "Online/Offline" shows when activity status is enabled
- [ ] Run migration script to add new columns
- [ ] Test settings persistence across app restarts

## Files Modified
- `social-media-mobile/lib/src/models/user_profile.dart`
- `social-media-mobile/lib/src/services/api_service.dart`
- `social-media-mobile/lib/src/screens/chats/chat_screen.dart`
- `social-media-mobile/lib/src/screens/settings/privacy_settings_screen.dart`
- `backend/social-service/src/main/java/com/socialmedia/social/entity/UserProfile.java`
- `backend/social-service/src/main/java/com/socialmedia/social/dto/UserProfileResponse.java`
- `backend/social-service/src/main/java/com/socialmedia/social/dto/UserProfileRequest.java`
- `backend/social-service/src/main/java/com/socialmedia/social/service/UserProfileService.java`
- `backend/migrate_read_receipts.sql` (new)
