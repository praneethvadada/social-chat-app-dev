# Follow Request System - Quick Reference

## 📁 Key File Paths

### Frontend - Flutter
```
Mobile UI Screens:
├── social-media-mobile/lib/src/screens/
│   ├── profile/user_profile_screen.dart           (Follow button & state)
│   ├── followers_list_screen.dart                 (Followers/Following lists)
│   ├── requests/requests_screen.dart              (Incoming follow requests)
│   └── notifications/notifications_screen.dart    (Notification display)
│
├── Components:
│   └── components/notification_card.dart          (Notification card UI)
│
├── Models:
│   └── models/notification_item.dart              (Notification structure)
│
└── Services:
    └── services/api_service.dart                  (HTTP API calls)
```

### Backend - Java Spring Boot
```
Social Service:
├── controller/
│   ├── FollowRequestController.java               (Follow request endpoints)
│   └── FollowerController.java                    (Follow/unfollow endpoints)
│
├── service/
│   ├── FollowRequestService.java                  (Request handling logic)
│   ├── FollowerService.java                       (Follow/unfollow logic)
│   └── FCMService.java                            (Push notifications)
│
├── entity/
│   └── FollowRequest.java                         (Database entity)
│
├── dto/
│   ├── FollowRequestResponse.java                 (API response DTO)
│   ├── FollowerResponse.java                      (Follower list DTO)
│   └── RequesterInfo.java                         (Nested requester info)
│
└── repository/
    ├── FollowRequestRepository.java               (Database queries)
    └── FollowerRepository.java                    (Database queries)
```

---

## 🔘 FOLLOW BUTTON STATE MANAGEMENT

### Button States
```
┌─────────────────────┬──────────────┬──────────┬──────────────┐
│ Condition           │ Button Text  │ Disabled │ Action       │
├─────────────────────┼──────────────┼──────────┼──────────────┤
│ Public, unfollowed  │ Follow       │ No       │ Direct follow│
│ Public, following   │ Following    │ No       │ Unfollow     │
│ Private, no request │ Request      │ No       │ Send request │
│ Private, requested  │ Requested    │ YES      │ (disabled)   │
│ Private, following  │ Following    │ No       │ Unfollow     │
│ Loading action      │ (spinner)    │ YES      │ Wait...      │
└─────────────────────┴──────────────┴──────────┴──────────────┘
```

### State Variables in UserProfileScreen
```dart
_isFollowing = false;      // Is following this user
_followRequested = false;  // Request sent (private accounts)
_isFollowLoading = false;  // Action in progress
_isPrivate = false;        // Is target account private
```

### State Check Flow
```dart
1. Load profile → get isPrivate
2. Call checkFollowStatus(userId) → get isFollowing
3. If !isFollowing && isPrivate:
   Call hasFollowRequest(userId) → get followRequested
4. Determine button state based on combination
```

---

## 📱 NOTIFICATION TYPES

### Follow-Related Notifications
```
Type: follow_request_received
├── Icon: Icons.person_add
├── Message: "{name} sent you a follow request"
└── Display: NotificationCard

Type: follow_request_accepted  
├── Icon: Icons.check_circle
├── Message: "{name} accepted your follow request"
└── Display: NotificationCard

Type: follow
├── Icon: Icons.person_add
├── Message: "{name} started following you"
└── Display: NotificationCard
```

### Map Backend → Frontend
```
Backend Type            → Frontend NotificationType
─────────────────────────────────────────────────────
'follow_request_received' → follow_request_received
'follow_request_accepted' → follow_request_accepted
'follow'                  → follow
```

---

## 🔗 API ENDPOINTS CHEAT SHEET

### Follow Requests
```
POST   /social/follow-requests/{userId}
       Send follow request to private account
       
GET    /social/follow-requests
       Get incoming requests for current user
       
GET    /social/follow-requests/check/{userId}
       Check if have pending request to user
       
POST   /social/follow-requests/{requestId}/accept
       Accept a follow request
       
POST   /social/follow-requests/{requestId}/decline
       Decline a follow request
```

### Direct Follows
```
POST   /social/followers/{userId}
       Follow a public account (direct follow)
       
DELETE /social/followers/{userId}
       Unfollow a user
       
GET    /social/followers/check/{userId}
       Check if currently following user
       
GET    /social/followers/user/{userId}
       Get followers list
       
GET    /social/following/user/{userId}
       Get following list
```

---

## 📊 DATA STRUCTURES

### FollowRequestResponse (Backend → Frontend)
```json
{
  "id": 456,
  "requester": {
    "userId": 789,
    "username": "john_doe",
    "fullName": "John Doe",
    "profilePictureUrl": "https://...",
    "mutualCount": 5
  },
  "createdAt": "2024-01-15T10:30:00"
}
```

### NotificationItem (Mobile)
```dart
NotificationItem(
  id: "n123",
  type: NotificationType.follow_request_received,
  actorName: "John Doe",
  actorId: 789,
  message: "sent you a follow request",
  time: DateTime.now(),
  highlighted: false
)
```

---

## 🔄 API SERVICE Methods (Frontend)

```dart
// Send follow request (private account)
sendFollowRequest(int userId)

// Follow publicly (public account)
followUser(int userId)

// Unfollow
unfollowUser(int userId)

// Check current following status
checkFollowStatus(int userId) → bool

// Check if have pending request
hasFollowRequest(int userId) → bool

// Get incoming requests
getFollowRequests() → List<Map>

// Accept/Decline request
respondFollowRequest(int requestId, bool accept)

// Get followers/following lists
getFollowers(int userId) → List<Map>
getFollowing(int userId) → List<Map>
```

---

## ⚙️ SERVICE METHODS (Backend)

### FollowRequestService
```java
sendFollowRequest(Long requesterId, Long targetId)
  └─ Validates & creates PENDING request
  
getIncomingRequests(Long targetId, Pageable) → Page<FollowRequestResponse>
  └─ Gets requests for current user
  
acceptRequest(Long requestId, Long targetId)
  └─ Creates follower relationship & sends notification
  
declineRequest(Long requestId, Long targetId)
  └─ Deletes request
  
hasPendingRequest(Long requesterId, Long targetId) → boolean
  └─ Checks if request exists and is PENDING
```

### FollowerService
```java
followUser(Long followerId, Long followingId)
  └─ Direct follow (checks target is public)
  
createFollowerRelationship(Long followerId, Long followingId)
  └─ Internal method (used by acceptRequest)
  
unfollowUser(Long followerId, Long followingId)
  └─ Remove following relationship
  
isFollowing(Long followerId, Long followingId) → boolean
  └─ Check if following
  
getFollowers(Long userId, Pageable) → Page<FollowerResponse>
  └─ Get followers list
  
getFollowing(Long userId, Pageable) → Page<FollowerResponse>
  └─ Get following list
```

---

## 🎯 IMPORTANT RULES

### Button Behavior
- Button is **DISABLED** only when:
  - Request has been sent and is pending (waiting for approval)
  - OR action is in progress (loading)
- Button is **ENABLED** for unfollow even if loading (can cancel follow)

### Posts Visibility
```
Private Account = true:
  ├─ Own profile? Show posts
  ├─ Not following? Hide posts (show lock message)
  │   Even if request was sent, don't show posts until approved
  └─ Following? Show posts

Private Account = false (Public):
  └─ Show posts to everyone
```

### Follow vs Request
```
Public Account Flow:
  Click "Follow" → Direct follow (POST /followers/{userId})
                → Instant
                → Button shows "Following"

Private Account Flow:
  Click "Request" → Send follow request (POST /follow-requests/{userId})
                 → Button shows "Requested" (disabled)
                 → Wait for approval
                 → Receiver accepts → Creates actual follow
                 → Button shows "Following"
```

### Duplicate Prevention
```
FollowRequestService.sendFollowRequest():
  ✓ Check not already following
  ✓ Check request not already sent
  ✓ Check not blocked
  ✓ Check not self-follow
  
FollowerService.followUser():
  ✓ Check target is PUBLIC (not private)
  ✓ Check not already following
  ✓ Check not blocked
  ✓ Check not self-follow
```

---

## 🔔 NOTIFICATION FLOW

### Request Sent → Receiver Notification
```
1. User clicks "Request"
   → Frontend: POST /follow-requests/{userId}
   → Backend: sendFollowRequest()
   → Creates FollowRequest (PENDING)
   → Sends notification to receiver
   
2. Receiver gets notification
   Type: follow_request_received
   Can view in Notifications screen
   Can view full list in Requests screen
```

### Request Accepted → Sender Notification
```
1. Receiver clicks "Accept" in RequestsScreen
   → Frontend: POST /follow-requests/{requestId}/accept
   → Backend: acceptRequest()
   → Creates Follower relationship
   → Deletes request
   → Sends notification to requester
   
2. Requester gets notification
   Type: follow_request_accepted
   Their follow request was accepted
   They can now see posts
   Button should show "Following"
```

---

## 🐛 COMMON ISSUES & FIXES

### Issue: Button shows "Follow" after sending request
**Fix:** FollowersListScreen checks backend with `hasFollowRequest()` before showing states
- Local tracking: `_requestedIds` set
- Backend check: `ApiService.hasFollowRequest(userId)`

### Issue: Posts visible on private account without following
**Fix:** Visibility check in `_loadUserPosts()`
```dart
if (_isPrivate && !isOwnProfile && !_isFollowing) {
  return; // Don't load posts
}
```

### Issue: Can send multiple follow requests
**Fix:** Service validates:
```java
if (followRequestRepository.existsByRequesterIdAndReceiverId(...)) {
  throw new IllegalArgumentException("Request already sent");
}
```

### Issue: Can follow private account directly
**Fix:** Controller checks:
```java
if (targetProfile.getIsPrivate()) {
  throw new IllegalArgumentException(
    "Cannot follow private accounts directly. Send request instead."
  );
}
```

