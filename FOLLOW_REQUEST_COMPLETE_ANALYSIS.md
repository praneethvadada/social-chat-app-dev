# Follow Request System - Complete Component Analysis

## 📋 Overview
This document provides a complete breakdown of the follow request flow across frontend and backend, including UI implementation, button state management, notification handling, and all API endpoints.

---

## 1️⃣ FOLLOWERS/FOLLOW-REQUESTS SCREEN UI

### Mobile Screens

#### RequestsScreen (Follow Requests Tab)
**File:** [social-media-mobile/lib/src/screens/requests/requests_screen.dart](social-media-mobile/lib/src/screens/requests/requests_screen.dart)

**Purpose:** Displays incoming follow requests for the currently logged-in user

**Key Components:**
- Loads follow requests from backend: `ApiService.getFollowRequests()`
- Displays list of users who sent follow requests
- Shows user avatar, name, username, and mutual connection count
- Accept/Decline buttons for each request

**Current Implementation:**
```dart
class RequestsScreen extends ConsumerStatefulWidget {
  // Loads incoming requests
  Future<void> _loadRequests() async {
    final data = await ApiService.getFollowRequests();
    // data is List<Map<String, dynamic>> with requester info
  }
  
  // Accept/Decline handler
  Future<void> _respond(int requestId, bool accept, int index) async {
    await ApiService.respondFollowRequest(requestId, accept);
    // Shows confirmation and removes from list
  }
}
```

**Data Structure for Each Request:**
```json
{
  "id": <request_id>,
  "requester": {
    "userId": <user_id>,
    "username": "username",
    "fullName": "Full Name",
    "profilePictureUrl": "url_or_null",
    "mutualCount": <count>
  },
  "createdAt": "2024-01-15T10:30:00"
}
```

#### FollowersListScreen (Followers/Following Tabs)
**File:** [social-media-mobile/lib/src/screens/followers_list_screen.dart](social-media-mobile/lib/src/screens/followers_list_screen.dart)

**Purpose:** Shows followers or following lists with ability to follow/unfollow from list view

**Key Features:**
- Displays follower/following lists with paginated data
- Shows follow button for each person (for non-own users)
- Prevents duplicate follow requests via `hasFollowRequest()` check
- Tracks locally requested users in `_requestedIds` set

**Button State Logic in List:**
```dart
// Button states for private accounts
final isFollowing = /* from API */;
final isPrivate = /* from user profile */;
final isRequested = /* from backend check or local tracking */;

// Display logic
if (isFollowing) {
  buttonText = 'Unfollow';
} else if (isPrivate) {
  buttonText = isRequested ? 'Requested' : 'Request';
} else {
  buttonText = 'Follow';
}

// Disabled only when: private account AND already requested
disabled = isPrivate && isRequested;
```

---

## 2️⃣ PROFILE SCREEN WITH FOLLOW BUTTON

### User Profile Screen
**File:** [social-media-mobile/lib/src/screens/profile/user_profile_screen.dart](social-media-mobile/lib/src/screens/profile/user_profile_screen.dart)

**Purpose:** Displays user's profile with follow/unfollow button and posts

### Button State Management

#### State Variables:
```dart
bool _isFollowing = false;      // Is user currently following this profile
bool _followRequested = false;  // Is follow request pending (for private accounts)
bool _isFollowLoading = false;  // Show loading spinner while action in progress
bool _isPrivate = false;        // Is the profile private
int _followersCount = 0;        // Number of followers
```

#### Follow Status Check:
```dart
Future<void> _checkFollowStatus() async {
  // 1. Check if currently following
  final isFollowing = await ApiService.checkFollowStatus(widget.userId);
  
  // 2. For private accounts, also check for pending request
  bool hasRequest = false;
  if (!isFollowing && _isPrivate) {
    hasRequest = await ApiService.hasFollowRequest(widget.userId);
  }
  
  setState(() {
    _isFollowing = isFollowing;
    _followRequested = hasRequest;
  });
}
```

#### Button State Values:

| State | Button Text | Button Disabled | Conditions |
|-------|-------------|-----------------|------------|
| **Public Account - Not Following** | "Follow" | false | `!_isFollowing && !_isPrivate` |
| **Public Account - Following** | "Following" | false | `_isFollowing && !_isPrivate` |
| **Private Account - Not Requested** | "Request" | false | `!_isFollowing && _isPrivate && !_followRequested` |
| **Private Account - Request Sent** | "Requested" | **true** | `!_isFollowing && _isPrivate && _followRequested` |
| **Private Account - Following (After Acceptance)** | "Following" | false | `_isFollowing && _isPrivate` |
| **Loading** | (spinner) | **true** | `_isFollowLoading` |

#### Toggle Follow Action:
```dart
Future<void> _toggleFollow() async {
  // Safety checks
  if (_followRequested) {
    // Already sent request - show snackbar and return
    return;
  }
  if (_isFollowLoading) {
    // Already loading - return
    return;
  }
  
  setState(() => _isFollowLoading = true);
  
  try {
    if (_isFollowing) {
      // UNFOLLOW
      await ApiService.unfollowUser(widget.userId);
      setState(() {
        _isFollowing = false;
        _followersCount = (_followersCount - 1).clamp(0, 999999);
        _isFollowLoading = false;
      });
      await _loadUserPosts(); // Reload posts - hide if private
    } else if (_isPrivate) {
      // SEND FOLLOW REQUEST (private account)
      await ApiService.sendFollowRequest(widget.userId);
      setState(() {
        _followRequested = true;
        _isFollowLoading = false;
      });
      // Don't load posts - wait for approval
    } else {
      // DIRECT FOLLOW (public account)
      await ApiService.followUser(widget.userId);
      setState(() {
        _isFollowing = true;
        _followersCount = (_followersCount + 1).clamp(0, 999999);
        _isFollowLoading = false;
      });
      await _loadUserPosts(); // Load posts now visible
    }
  } catch (e) {
    setState(() => _isFollowLoading = false);
    // Show error snackbar
  }
}
```

#### Button UI Styling:
```dart
ElevatedButton(
  onPressed:
      (_followRequested || _isFollowLoading)
          ? null  // Disabled when requested or loading
          : _toggleFollow,
  style: ElevatedButton.styleFrom(
    backgroundColor: _followRequested
        ? Colors.grey[400]  // Grey when requested
        : (_isFollowing
            ? Colors.grey[300]  // Light grey when following
            : primary),         // Primary color for Follow/Request
    foregroundColor: _followRequested
        ? Colors.grey[700]  // Dark grey text when requested
        : null,
    disabledBackgroundColor: Colors.grey[400],
  ),
  child: _isFollowLoading
      ? const SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : Text(
          _isFollowing
              ? 'Following'
              : (_followRequested
                  ? 'Requested'
                  : 'Follow'),
          style: TextStyle(
            color: _followRequested ? Colors.grey[700] : (
              _isFollowing ? Colors.black : Colors.white
            ),
            fontWeight: FontWeight.w700,
          ),
        ),
)
```

#### Post Visibility Logic:
```dart
Future<void> _loadUserPosts() async {
  final isOwnProfile = _currentUserId == widget.userId;
  
  // Posts are ONLY visible if:
  // 1. User is following, OR
  // 2. It's their own profile
  if (_isPrivate && !isOwnProfile && !_isFollowing) {
    // Private, not own profile, not following
    // Show locked message - DON'T show posts even if request was sent
    return;
  }
  
  // Load and show posts
  final posts = await ApiService.getUserPosts(widget.userId);
}
```

---

## 3️⃣ NOTIFICATION CARD IMPLEMENTATION

### Notification Model
**File:** [social-media-mobile/lib/src/models/notification_item.dart](social-media-mobile/lib/src/models/notification_item.dart)

**Notification Types Enum:**
```dart
enum NotificationType { 
  like,
  mention,
  follow,
  comment,
  reply,
  follow_request_received,    // ← Follow request received
  follow_request_accepted     // ← Follow request was accepted
}
```

**Notification Item Structure:**
```dart
class NotificationItem {
  final String id;                      // Unique notification ID
  final NotificationType type;          // Type of notification
  final String actorName;               // Name of user who triggered it
  final int? actorId;                   // ID of actor
  final int? postId;                    // Related post (if any)
  final String message;                 // Notification message
  final DateTime time;                  // When it occurred
  final bool highlighted;               // Whether newly received
}
```

### Notification Card Component
**File:** [social-media-mobile/lib/src/components/notification_card.dart](social-media-mobile/lib/src/components/notification_card.dart)

**Visual Rendering:**
```dart
class NotificationCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Icon based on type
    final icon = _iconForType(item.type);
    
    // Layout: Avatar (icon) + Name + Message + Time
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(...)],
      ),
      child: Row(
        children: [
          // Icon container
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.green.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.actorName} ${item.message}',
                  style: TextStyle(fontWeight: FontWeight.w700, ...)
                ),
                const SizedBox(height: 6),
                TimeAgoWidget(timestamp: item.time),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  IconData _iconForType(NotificationType t) {
    switch (t) {
      case NotificationType.follow_request_received:
        return Icons.person_add;  // ← Person icon
      case NotificationType.follow_request_accepted:
        return Icons.check_circle;  // ← Checkmark icon
      // ... other types
    }
  }
}
```

**Notification Type Icons:**
| Type | Icon | Message |
|------|------|---------|
| `follow_request_received` | `Icons.person_add` | "sent you a follow request" |
| `follow_request_accepted` | `Icons.check_circle` | "accepted your follow request" |
| `follow` | `Icons.person_add` | "started following you" |

### Notifications Screen Mapping
**File:** [social-media-mobile/lib/src/screens/notifications/notifications_screen.dart](social-media-mobile/lib/src/screens/notifications/notifications_screen.dart)

**Backend type → Frontend NotificationType mapping:**
```dart
// In _buildNotificationItem(), backend message type is converted:
'follow_request_received' → NotificationType.follow_request_received
'follow_request_accepted' → NotificationType.follow_request_accepted

// These are then filtered/displayed separately:
// Line 128-129: Special handling for follow request notifications
if (i.type == NotificationType.follow_request_received ||
    i.type == NotificationType.follow_request_accepted) {
  // May be displayed in separate section or with special styling
}
```

---

## 4️⃣ FOLLOWREQUESTRESPONSE DTO & MODEL

### FollowRequestResponse DTO
**File:** [backend/social-service/src/main/java/com/socialmedia/social/dto/FollowRequestResponse.java](backend/social-service/src/main/java/com/socialmedia/social/dto/FollowRequestResponse.java)

**Structure:**
```java
public class FollowRequestResponse {
    private Long id;                          // Request ID
    private RequesterInfo requester;          // Info about user sending request
    private LocalDateTime createdAt;          // When request was sent
    
    // Getters/Setters
}
```

**RequesterInfo Nested Object:**
```java
class RequesterInfo {
    private Long userId;                      // Requester's user ID
    private String username;                  // Requester's username
    private String fullName;                  // Requester's full name
    private String profilePictureUrl;         // Avatar URL
    private Integer mutualCount;              // Number of mutual followers
}
```

### FollowRequest Entity
**File:** [backend/social-service/src/main/java/com/socialmedia/social/entity/FollowRequest.java](backend/social-service/src/main/java/com/socialmedia/social/entity/FollowRequest.java)

**Database Structure:**
```java
@Entity
@Table(name = "follow_requests",
    uniqueConstraints = @UniqueConstraint(columnNames = {"requester_id", "receiver_id"}),
    indexes = {
        @Index(name = "idx_requester_id", columnList = "requester_id"),
        @Index(name = "idx_receiver_id", columnList = "receiver_id")
    }
)
public class FollowRequest {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "requester_id", nullable = false)
    private Long requesterId;                 // User sending the request

    @Column(name = "receiver_id", nullable = false)
    private Long receiverId;                  // User receiving the request

    @Column(name = "status", nullable = false, length = 20)
    private String status = "PENDING";        // PENDING, APPROVED, REJECTED

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;
}
```

---

## 5️⃣ API ENDPOINTS & IMPLEMENTATION

### Backend Controller
**File:** [backend/social-service/src/main/java/com/socialmedia/social/controller/FollowRequestController.java](backend/social-service/src/main/java/com/socialmedia/social/controller/FollowRequestController.java)

**Base Path:** `/social/follow-requests`

#### Endpoint 1: Send Follow Request
```
POST /social/follow-requests/{userId}
Authorization: Bearer <JWT_TOKEN>

Response (200):
{
  "message": "Follow request sent",
  "targetUserId": "123"
}

Error (400):
{
  "error": "Invalid target user ID" | "Already following" | "User not found"
}
```

#### Endpoint 2: Get Incoming Requests
```
GET /social/follow-requests?page=0&size=20
Authorization: Bearer <JWT_TOKEN>

Response (200):
{
  "content": [
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
  ],
  "pageable": {
    "pageNumber": 0,
    "pageSize": 20,
    "totalElements": 15,
    "totalPages": 1
  }
}
```

#### Endpoint 3: Check Pending Request
```
GET /social/follow-requests/check/{userId}
Authorization: Bearer <JWT_TOKEN>

Response (200):
{
  "hasPendingRequest": true,
  "targetUserId": 123,
  "requesterId": 456
}
```

**Purpose:** Used to determine if current user has already sent a follow request to target user (for button state)

#### Endpoint 4: Accept Follow Request
```
POST /social/follow-requests/{requestId}/accept
Authorization: Bearer <JWT_TOKEN>

Response (200):
{
  "message": "Follow request accepted",
  "requestId": "456"
}
```

**Server Action:**
1. Validates request belongs to authenticated user
2. Calls `FollowRequestService.acceptRequest(requestId, targetId)`
3. Creates follower relationship
4. Deletes the request
5. Sends notification to requester

#### Endpoint 5: Decline Follow Request
```
POST /social/follow-requests/{requestId}/decline
Authorization: Bearer <JWT_TOKEN>

Response (200):
{
  "message": "Follow request declined",
  "requestId": "456"
}
```

### Regular Follow Endpoints

**File:** [backend/social-service/src/main/java/com/socialmedia/social/controller/FollowerController.java](backend/social-service/src/main/java/com/socialmedia/social/controller/FollowerController.java)

**Base Path:** `/social/followers`

#### Endpoint 1: Follow User (Direct - Public Accounts Only)
```
POST /social/followers/{userId}
Authorization: Bearer <JWT_TOKEN>

Response (200):
{
  "message": "Successfully followed user",
  "followingUserId": "123"
}

Error (400):
{
  "error": "Cannot follow yourself" | "Already following this user" | 
           "Cannot follow a private account directly. Please send a follow request instead."
}
```

**Server Logic:**
1. Checks if target account is private
2. If private: rejects with error message
3. If public: creates follower relationship and sends notification

#### Endpoint 2: Unfollow User
```
DELETE /social/followers/{userId}
Authorization: Bearer <JWT_TOKEN>

Response (200):
{
  "message": "Successfully unfollowed user",
  "unfollowedUserId": "123"
}
```

#### Endpoint 3: Check Following Status
```
GET /social/followers/check/{userId}
Authorization: Bearer <JWT_TOKEN>

Response (200):
{
  "isFollowing": true
}
```

#### Endpoint 4: Get User's Followers
```
GET /social/followers/user/{userId}?page=0&size=20
Authorization: Bearer <JWT_TOKEN>

Response (200):
Page<FollowerResponse> with paginated follower list
```

#### Endpoint 5: Get User's Following
```
GET /social/following/user/{userId}?page=0&size=20
Authorization: Bearer <JWT_TOKEN>

Response (200):
Page<FollowerResponse> with paginated following list
```

---

## 6️⃣ SERVICE LAYER LOGIC

### FollowRequestService
**File:** [backend/social-service/src/main/java/com/socialmedia/social/service/FollowRequestService.java](backend/social-service/src/main/java/com/socialmedia/social/service/FollowRequestService.java)

**Key Methods:**

#### sendFollowRequest()
```java
@Transactional
public void sendFollowRequest(Long requesterId, Long targetId) {
    // 1. Validate input
    if (requesterId.equals(targetId)) {
        throw new IllegalArgumentException("Cannot follow yourself");
    }
    
    // 2. Check if blocked
    if (blockService.isEitherBlocked(requesterId, targetId)) {
        throw new IllegalArgumentException("Cannot send follow request to blocked user");
    }
    
    // 3. Check if user already exists
    if (followerRepository.existsByFollowerIdAndFollowingId(requesterId, targetId)) {
        throw new IllegalArgumentException("Already following this user");
    }
    
    // 4. Check if request already sent
    if (followRequestRepository.existsByRequesterIdAndReceiverId(requesterId, targetId)) {
        throw new IllegalArgumentException("Follow request already sent");
    }
    
    // 5. Create and save request
    FollowRequest request = new FollowRequest(requesterId, targetId);
    request.setStatus("PENDING");
    followRequestRepository.save(request);
    
    // 6. Send notification
    notificationService.createNotification(
        targetId, "follow_request_received", requesterId, targetId, 
        "sent you a follow request"
    );
}
```

#### getIncomingRequests()
```java
@Transactional(readOnly = true)
public Page<FollowRequestResponse> getIncomingRequests(Long targetId, Pageable pageable) {
    // Get requests where this user is the receiver
    Page<FollowRequest> page = 
        followRequestRepository.findByReceiverIdOrderByCreatedAtDesc(targetId, pageable);
    
    // Build response with requester profile info
    return page.map(fr -> {
        FollowRequestResponse r = new FollowRequestResponse();
        r.setId(fr.getId());
        r.setCreatedAt(fr.getCreatedAt());
        
        // Get requester's profile info
        UserProfile profile = userProfileService.getUserProfileById(fr.getRequesterId());
        RequesterInfo info = new RequesterInfo();
        info.setUserId(fr.getRequesterId());
        info.setUsername(profile.getUsername());
        info.setFullName(profile.getFullName());
        info.setProfilePictureUrl(profile.getProfilePictureUrl());
        info.setMutualCount(calculateMutuals(targetId, fr.getRequesterId()));
        
        r.setRequester(info);
        return r;
    });
}
```

#### acceptRequest()
```java
@Transactional
public void acceptRequest(Long requestId, Long targetId) {
    // 1. Find request
    FollowRequest request = followRequestRepository.findById(requestId)
        .orElseThrow(() -> new IllegalArgumentException("Request not found"));
    
    // 2. Verify ownership (request is to current user)
    if (!request.getReceiverId().equals(targetId)) {
        throw new IllegalArgumentException("Not authorized");
    }
    
    // 3. Create follower relationship
    followerService.createFollowerRelationship(
        request.getRequesterId(), 
        request.getReceiverId()
    );
    
    // 4. Update request status
    request.setStatus("APPROVED");
    followRequestRepository.save(request);
    
    // 5. Send notification to requester
    notificationService.createNotification(
        request.getRequesterId(), 
        "follow_request_accepted", 
        targetId, 
        request.getRequesterId(),
        "accepted your follow request"
    );
}
```

#### hasPendingRequest()
```java
@Transactional(readOnly = true)
public boolean hasPendingRequest(Long requesterId, Long targetId) {
    return followRequestRepository.existsByRequesterIdAndReceiverIdAndStatus(
        requesterId, targetId, "PENDING"
    );
}
```

### FollowerService
**File:** [backend/social-service/src/main/java/com/socialmedia/social/service/FollowerService.java](backend/social-service/src/main/java/com/socialmedia/social/service/FollowerService.java)

#### followUser() - Direct Follow (Public Accounts)
```java
@Transactional
public void followUser(Long followerId, Long followingId) {
    // 1. Validate not self-follow
    if (followerId.equals(followingId)) {
        throw new IllegalArgumentException("Cannot follow yourself");
    }
    
    // 2. Check block status
    if (blockService.isEitherBlocked(followerId, followingId)) {
        throw new IllegalArgumentException("Cannot follow this user due to block");
    }
    
    // 3. Check not already following
    if (followerRepository.existsByFollowerIdAndFollowingId(followerId, followingId)) {
        throw new IllegalArgumentException("Already following this user");
    }
    
    // 4. Check if target is private
    UserProfile targetProfile = userProfileService.getUserProfileById(followingId);
    if (Boolean.TRUE.equals(targetProfile.getIsPrivate())) {
        throw new IllegalArgumentException(
            "Cannot follow a private account directly. Please send a follow request instead."
        );
    }
    
    // 5. Create relationship
    createFollowerRelationship(followerId, followingId);
}
```

#### createFollowerRelationship() - Used by Accept Request
```java
@Transactional
public void createFollowerRelationship(Long followerId, Long followingId) {
    // Internal method - no privacy check needed (called by acceptRequest)
    
    // 1. Save relationship
    Follower follower = new Follower(followerId, followingId);
    followerRepository.save(follower);
    
    // 2. Send notification
    notificationService.createNotification(
        followingId, "follow", followerId, followingId,
        "started following you"
    );
}
```

---

## 7️⃣ FRONTEND API SERVICE METHODS

**File:** [social-media-mobile/lib/src/services/api_service.dart](social-media-mobile/lib/src/services/api_service.dart)

### Follow-Related Methods:

```dart
// Public account direct follow
static Future<void> followUser(int userId) async {
  final token = await getToken();
  final response = await http.post(
    Uri.parse('$baseUrl/social/followers/$userId'),
    headers: {'Authorization': 'Bearer $token'},
  );
  
  if (response.statusCode != 200 && response.statusCode != 201) {
    throw Exception('Failed to follow user');
  }
}

// Send follow request (private account)
static Future<void> sendFollowRequest(int userId) async {
  final token = await getToken();
  final response = await http.post(
    Uri.parse('$baseUrl/social/follow-requests/$userId'),
    headers: {'Authorization': 'Bearer $token'},
  );
  
  if (response.statusCode != 200 && response.statusCode != 201) {
    throw Exception('Failed to send follow request');
  }
}

// Check if user has pending request to target user
static Future<bool> hasFollowRequest(int userId) async {
  final token = await getToken();
  final response = await http.get(
    Uri.parse('$baseUrl/social/follow-requests/check/$userId'),
    headers: {'Authorization': 'Bearer $token'},
  );
  
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    return data['hasPendingRequest'] == true;
  }
  return false;
}

// Check if currently following a user
static Future<bool> checkFollowStatus(int userId) async {
  final token = await getToken();
  final response = await http.get(
    Uri.parse('$baseUrl/social/followers/check/$userId'),
    headers: {'Authorization': 'Bearer $token'},
  );
  
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    return data['isFollowing'] == true;
  }
  return false;
}

// Unfollow a user
static Future<void> unfollowUser(int userId) async {
  final token = await getToken();
  final response = await http.delete(
    Uri.parse('$baseUrl/social/followers/$userId'),
    headers: {'Authorization': 'Bearer $token'},
  );
  
  if (response.statusCode != 200) {
    throw Exception('Failed to unfollow user');
  }
}

// Get incoming follow requests
static Future<List<Map<String, dynamic>>> getFollowRequests() async {
  final token = await getToken();
  final response = await http.get(
    Uri.parse('$baseUrl/social/follow-requests'),
    headers: {'Authorization': 'Bearer $token'},
  );
  
  if (response.statusCode == 200) {
    final json = jsonDecode(response.body) as Map;
    final content = json['content'] as List? ?? [];
    return content.cast<Map<String, dynamic>>();
  }
  throw Exception('Failed to load follow requests');
}

// Accept or decline a follow request
static Future<void> respondFollowRequest(int requestId, bool accept) async {
  final token = await getToken();
  final endpoint = accept ? 'accept' : 'decline';
  
  final response = await http.post(
    Uri.parse('$baseUrl/social/follow-requests/$requestId/$endpoint'),
    headers: {'Authorization': 'Bearer $token'},
  );
  
  if (response.statusCode != 200) {
    throw Exception(accept ? 'Failed to accept request' : 'Failed to decline request');
  }
}

// Get followers list
static Future<List<Map<String, dynamic>>> getFollowers(int userId,
    {int page = 0, int size = 20}) async {
  final token = await getToken();
  final response = await http.get(
    Uri.parse(
        '$baseUrl/social/followers/user/$userId?page=$page&size=$size'),
    headers: {'Authorization': 'Bearer $token'},
  );
  
  if (response.statusCode == 200) {
    final json = jsonDecode(response.body) as Map;
    final content = json['content'] as List? ?? [];
    return content.cast<Map<String, dynamic>>();
  }
  throw Exception('Failed to load followers');
}

// Get following list
static Future<List<Map<String, dynamic>>> getFollowing(int userId,
    {int page = 0, int size = 20}) async {
  final token = await getToken();
  final response = await http.get(
    Uri.parse(
        '$baseUrl/social/following/user/$userId?page=$page&size=$size'),
    headers: {'Authorization': 'Bearer $token'},
  );
  
  if (response.statusCode == 200) {
    final json = jsonDecode(response.body) as Map;
    final content = json['content'] as List? ?? [];
    return content.cast<Map<String, dynamic>>();
  }
  throw Exception('Failed to load following');
}
```

---

## 8️⃣ COMPLETE FOLLOW REQUEST FLOW DIAGRAM

```
┌─────────────────────────────────────────────────────────────────┐
│                    USER VIEWS PROFILE                            │
│         (user_profile_screen.dart)                              │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ├─→ API: checkFollowStatus(userId)
                         │   └─→ GET /social/followers/check/{userId}
                         │       └─→ _isFollowing = bool
                         │
                         ├─→ If private && !following:
                         │   API: hasFollowRequest(userId)
                         │   └─→ GET /social/follow-requests/check/{userId}
                         │       └─→ _followRequested = bool
                         │
                         └─→ Load profile info (_isPrivate)
                             └─→ Determine button state

┌─────────────────────────────────────────────────────────────────┐
│                  USER CLICKS FOLLOW BUTTON                       │
└────────────────────────┬────────────────────────────────────────┘
                         │
          ┌──────────────┼──────────────┐
          │              │              │
          ▼              ▼              ▼
    PUBLIC ACCOUNT  PRIVATE ACCOUNT  ALREADY FOLLOWING
    (NOT FOLLOWING) (NOT FOLLOWING)  
          │              │              │
          │              │              ▼
          │              │          UNFOLLOW
          │              │          └─→ DELETE /social/followers/{userId}
          │              │              └─→ Remove _isFollowing
          │              │
          │              ▼
          │         SEND REQUEST
          │         └─→ POST /social/follow-requests/{userId}
          │             ├─→ Backend validates:
          │             │   - Not self-follow
          │             │   - Not blocked
          │             │   - Request doesn't exist
          │             │   - Saves FollowRequest (PENDING)
          │             │   - Sends notification
          │             └─→ Set _followRequested = true
          │
          ▼
     DIRECT FOLLOW
     └─→ POST /social/followers/{userId}
         ├─→ Backend validates:
         │   - Not self-follow
         │   - Not blocked
         │   - Not already following
         │   - Target is PUBLIC
         │   - Creates Follower relationship
         │   - Sends notification
         └─→ Set _isFollowing = true

┌─────────────────────────────────────────────────────────────────┐
│                FOLLOW REQUEST RECEIVED                           │
│         (notifications, requests screen)                         │
└────────────────────────┬────────────────────────────────────────┘
                         │
                    NOTIFICATION
                    ├─→ Type: follow_request_received
                    ├─→ Icon: Icons.person_add
                    ├─→ Message: "{name} sent you a follow request"
                    │
                    └─→ RequestsScreen
                        ├─→ GET /social/follow-requests
                        └─→ Shows list with Accept/Decline buttons

┌─────────────────────────────────────────────────────────────────┐
│              USER ACCEPTS FOLLOW REQUEST                         │
└────────────────────────┬────────────────────────────────────────┘
                         │
                    ACCEPT
                    └─→ POST /social/follow-requests/{requestId}/accept
                        ├─→ Backend:
                        │   - Validates request ownership
                        │   - Creates Follower relationship
                        │   - Updates request status = APPROVED
                        │   - Sends notification to requester
                        │
                        └─→ Removes from RequestsScreen list
                            └─→ Notification sent:
                                - Type: follow_request_accepted
                                - Icon: Icons.check_circle
                                - Message: "{name} accepted your follow request"

┌─────────────────────────────────────────────────────────────────┐
│              USER DECLINES FOLLOW REQUEST                        │
└────────────────────────┬────────────────────────────────────────┘
                         │
                    DECLINE
                    └─→ POST /social/follow-requests/{requestId}/decline
                        ├─→ Backend:
                        │   - Validates request ownership
                        │   - Deletes request
                        │
                        └─→ Removes from RequestsScreen list
```

---

## 📊 SUMMARY TABLE

| Component | Location | Purpose |
|-----------|----------|---------|
| **UI Screens** |
| RequestsScreen | [requests_screen.dart](social-media-mobile/lib/src/screens/requests/requests_screen.dart) | Shows incoming follow requests |
| FollowersListScreen | [followers_list_screen.dart](social-media-mobile/lib/src/screens/followers_list_screen.dart) | Displays followers/following lists |
| UserProfileScreen | [user_profile_screen.dart](social-media-mobile/lib/src/screens/profile/user_profile_screen.dart) | Profile with follow button & posts |
| **Models** |
| NotificationItem | [notification_item.dart](social-media-mobile/lib/src/models/notification_item.dart) | Defines notification structure |
| FollowRequestResponse | [FollowRequestResponse.java](backend/social-service/src/main/java/com/socialmedia/social/dto/FollowRequestResponse.java) | Backend DTO for requests |
| FollowRequest | [FollowRequest.java](backend/social-service/src/main/java/com/socialmedia/social/entity/FollowRequest.java) | Database entity |
| **Components** |
| NotificationCard | [notification_card.dart](social-media-mobile/lib/src/components/notification_card.dart) | Renders notification UI |
| **Services** |
| FollowRequestService | [FollowRequestService.java](backend/social-service/src/main/java/com/socialmedia/social/service/FollowRequestService.java) | Handles requests logic |
| FollowerService | [FollowerService.java](backend/social-service/src/main/java/com/socialmedia/social/service/FollowerService.java) | Handles follows logic |
| ApiService | [api_service.dart](social-media-mobile/lib/src/services/api_service.dart) | Frontend HTTP calls |
| **Controllers** |
| FollowRequestController | [FollowRequestController.java](backend/social-service/src/main/java/com/socialmedia/social/controller/FollowRequestController.java) | REST endpoints for requests |
| FollowerController | [FollowerController.java](backend/social-service/src/main/java/com/socialmedia/social/controller/FollowerController.java) | REST endpoints for follows |

---

## 🎯 KEY BEHAVIOR RULES

### Follow Button States:
1. **"Follow"** (enabled) → Public account, not following
2. **"Following"** (enabled) → Publicly following (allows unfollow)
3. **"Request"** (enabled) → Private account, no request sent yet
4. **"Requested"** (disabled) → Private account, request already sent waiting for approval

### Posts Visibility:
- **Always visible:** Own profile's posts
- **Visible if:** Not your profile AND public account OR following
- **Hidden if:** Not your profile AND private account AND not following (even if request was sent)

### Notifications:
- **follow_request_received**: When someone sends you a follow request
- **follow_request_accepted**: When your follow request is accepted
- **follow**: When someone directly follows you (public account)

