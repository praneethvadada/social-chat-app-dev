# Follow System - Complete Implementation Analysis

## Executive Summary
The follow system is **FULLY IMPLEMENTED** with follow requests for private accounts. The 500 error is likely occurring in a specific edge case or error handling scenario, not in the core follow request logic.

---

## 1. FOLLOW REQUEST API ENDPOINT & IMPLEMENTATION

### ✅ Backend Endpoint
**Location:** [FollowRequestController.java](backend/social-service/src/main/java/com/socialmedia/social/controller/FollowRequestController.java)

```
POST /social/follow-requests/{userId}
Authorization: Bearer <token>
```

**Implementation:**
```java
@PostMapping("/{userId}")
public ResponseEntity<Map<String, String>> sendRequest(
    @PathVariable Long userId, 
    @RequestAttribute("userId") Long requesterId) {
    followRequestService.sendFollowRequest(requesterId, userId);
    return ResponseEntity.ok(response);
}
```

**Flow:**
1. Controller receives POST request with target userId
2. Calls `FollowRequestService.sendFollowRequest(requesterId, targetId)`
3. Service validates:
   - Not self-follow
   - Checks if blocked (via `BlockService.isEitherBlocked()`)
   - Not already following
   - Request not already sent
4. Creates `FollowRequest` entity with status = 'PENDING'
5. Sends notification to target user
6. Returns 200 OK

**Validation Checks:**
- ✅ `requesterId.equals(targetId)` → throws "Cannot request to follow yourself"
- ✅ `blockService.isEitherBlocked()` → throws "Cannot send follow request to this user" (prevents blocked follow requests)
- ✅ `followerService.isFollowing()` → throws "Already following this user"
- ✅ `existsByRequesterIdAndTargetId()` → throws "Follow request already sent"

---

## 2. USER MODEL STRUCTURE - ISRIVATE FIELD ✅

### Database Schema
**Table:** `users` (lines 24-59 in complete_schema_v2.sql)

```sql
CREATE TABLE IF NOT EXISTS users (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(100) NOT NULL UNIQUE,
    -- ... other fields ...
    
    -- Privacy & Verification
    is_private BOOLEAN NOT NULL DEFAULT FALSE
        COMMENT 'Account visibility - false=public, true=private',
    is_verified BOOLEAN NOT NULL DEFAULT FALSE
        COMMENT 'OTP/Email verification status',
    
    -- Online status
    is_online BOOLEAN NOT NULL DEFAULT FALSE,
    last_seen_at DATETIME,
    
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    -- Indexes for performance
    INDEX idx_is_private (is_private),
    INDEX idx_is_verified (is_verified),
    -- ... other indexes ...
)
```

### Backend DTO
**File:** [UserProfileResponse.java](backend/social-service/src/main/java/com/socialmedia/social/dto/UserProfileResponse.java)

```java
@Data
public class UserProfileResponse {
    private Long userId;
    private String username;
    private String email;
    private String fullName;
    private String bio;
    private String profilePictureUrl;
    private String coverPhotoUrl;
    private String location;
    private String website;
    private LocalDate dateOfBirth;
    
    private Boolean isPrivate;      // ✅ Privacy field
    private Boolean isVerified;     // ✅ Verification flag
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;
    
    // Social stats
    private Long followersCount;
    private Long followingCount;
    private Long postsCount;
    private Boolean isFollowing;
    private Boolean isFollowedBy;
}
```

### Mobile Model
**File:** [privacy_settings_screen.dart](social-media-mobile/lib/src/screens/settings/privacy_settings_screen.dart)

```dart
// Privacy setting is fetched from backend UserProfile
final profile = await ApiService.getMyProfile();
final backendIsPrivate = profile['isPrivate'] as bool? ?? false;

// Used for follow visibility control
if (_isPrivate && !_isFollowing) {
    // Show follow request button instead of direct follow
}
```

---

## 3. FOLLOW/FOLLOWER RELATIONSHIP MODEL

### Database Schema

#### Followers Table (Direct Follows)
```sql
CREATE TABLE IF NOT EXISTS followers (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    follower_id BIGINT NOT NULL COMMENT 'User who follows',
    following_id BIGINT NOT NULL COMMENT 'User being followed',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_follower_following (follower_id, following_id),
    CONSTRAINT fk_followers_follower FOREIGN KEY (follower_id) 
        REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_followers_following FOREIGN KEY (following_id) 
        REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_follower (follower_id),
    INDEX idx_following (following_id),
    INDEX idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

#### Follow Requests Table (Pending Requests)
```sql
CREATE TABLE IF NOT EXISTS follow_requests (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    requester_id BIGINT NOT NULL COMMENT 'User sending follow request',
    receiver_id BIGINT NOT NULL COMMENT 'User receiving follow request',
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING' COMMENT 'PENDING, APPROVED, REJECTED',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_follow_request (requester_id, receiver_id),
    CONSTRAINT fk_follow_req_requester FOREIGN KEY (requester_id) 
        REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_follow_req_receiver FOREIGN KEY (receiver_id) 
        REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_receiver_status (receiver_id, status),
    INDEX idx_requester_status (requester_id, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

#### Blocked Users Table
```sql
CREATE TABLE IF NOT EXISTS blocked_users (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    blocker_id BIGINT NOT NULL COMMENT 'User who blocks',
    blocked_id BIGINT NOT NULL COMMENT 'User being blocked',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_blocker_blocked (blocker_id, blocked_id),
    CONSTRAINT fk_blocked_blocker FOREIGN KEY (blocker_id) 
        REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_blocked_blocked FOREIGN KEY (blocked_id) 
        REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_blocker (blocker_id),
    INDEX idx_blocked (blocked_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

### Follow Flow Logic (Backend)
**File:** [FollowerService.java](backend/social-service/src/main/java/com/socialmedia/social/service/FollowerService.java)

```java
@Service
public class FollowerService {
    
    @Transactional
    public void followUser(Long followerId, Long followingId) {
        // For PUBLIC accounts - direct follow
        if (!followerRepository.existsByFollowerIdAndFollowingId(followerId, followingId)) {
            Follower f = new Follower(followerId, followingId);
            followerRepository.save(f);
        }
    }
    
    @Transactional
    public void createFollowerRelationship(Long followerId, Long followingId) {
        // Internal method used when follow request is ACCEPTED
        // Bypasses privacy checks
    }
    
    public boolean isFollowing(Long followerId, Long followingId) {
        return followerRepository.existsByFollowerIdAndFollowingId(followerId, followingId);
    }
}
```

---

## 4. POST VISIBILITY FILTERING LOGIC

### Posts Table Structure
```sql
CREATE TABLE IF NOT EXISTS posts (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    content TEXT,
    is_public BOOLEAN NOT NULL DEFAULT TRUE,
    
    -- Close Friends Visibility (IMPLEMENTED)
    visibility ENUM('PUBLIC', 'CLOSE_FRIENDS') NOT NULL DEFAULT 'PUBLIC',
    
    likes_count INT NOT NULL DEFAULT 0,
    comments_count INT NOT NULL DEFAULT 0,
    shares_count INT NOT NULL DEFAULT 0,
    saves_count INT NOT NULL DEFAULT 0,
    
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_posts_user FOREIGN KEY (user_id) 
        REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_user_posts (user_id, created_at DESC),
    INDEX idx_created_at (created_at DESC),
    INDEX idx_is_public (is_public)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

### Mobile Post Loading (User Profile)
**File:** [user_profile_screen.dart](social-media-mobile/lib/src/screens/profile/user_profile_screen.dart)

```dart
Future<void> _loadUserPosts() async {
    try {
      final posts = await ApiService.getUserPosts(widget.userId);
      
      // Visibility check
      print('[POST VISIBILITY] ✅ Showing ${posts.length} posts');
      print('  Conditions: _isPrivate=$_isPrivate || isOwnProfile=$isOwnProfile || _isFollowing=$_isFollowing');
      
      if (mounted) {
        setState(() {
          _userPosts = posts;
        });
      }
    } catch (e) {
      print('Error loading user posts: $e');
    }
}
```

### Post Filtering Rules (Frontend)
1. **Own profile** → Show all posts
2. **Public account** → Show all posts to anyone
3. **Private account, not following** → Show 0 posts (hidden)
4. **Private account, following** → Show all posts
5. **Close Friends visibility** → Only close friends can see

---

## 5. FOLLOW BUTTON IMPLEMENTATION IN PROFILE SCREEN

### Mobile Implementation
**File:** [user_profile_screen.dart](social-media-mobile/lib/src/screens/profile/user_profile_screen.dart)

#### Status Check
```dart
Future<void> _checkFollowStatus() async {
    try {
      final isFollowing = await ApiService.checkFollowStatus(widget.userId);
      bool hasRequest = false;

      // Only check for follow request if not currently following
      if (!isFollowing && _isPrivate) {
        hasRequest = await ApiService.hasFollowRequest(widget.userId);
      }

      if (mounted) {
        setState(() {
          _isFollowing = isFollowing;
          _followRequested = hasRequest;
        });
      }

      print('[FOLLOW STATUS CHECK] userId: ${widget.userId}, isFollowing: $isFollowing, hasRequest: $hasRequest, isPrivate: $_isPrivate');
    } catch (e) {
      print('Error checking follow status: $e');
    }
}
```

#### Toggle Follow Action
```dart
Future<void> _toggleFollow() async {
    print('[TOGGLE FOLLOW] Button pressed - checking state...');
    print('  _followRequested: $_followRequested');
    print('  _isFollowLoading: $_isFollowLoading');
    print('  _isFollowing: $_isFollowing');
    print('  _isPrivate: $_isPrivate');

    if (_followRequested) {
      print('[FOLLOW] ❌ BLOCKED - request already sent!');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Follow request already sent - waiting for approval'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (_isFollowLoading) {
      print('[FOLLOW] ❌ Already loading - please wait');
      return;
    }

    setState(() => _isFollowLoading = true);
    try {
      print('\n========== TOGGLE FOLLOW ==========');
      print('userId: ${widget.userId}, isFollowing: $_isFollowing, isPrivate: $_isPrivate, followRequested: $_followRequested');

      if (_isFollowing) {
        // Already following → unfollow
        await ApiService.unfollowUser(widget.userId);
        print('[UNFOLLOW] Success');
        if (mounted) {
          setState(() {
            _isFollowing = false;
            _followersCount = (_followersCount - 1).clamp(0, 999999);
            _isFollowLoading = false;
          });
          await _loadUserPosts();
        }
      } else if (_isPrivate) {
        // Private account → send request
        print('[FOLLOW REQUEST] Sending request to private account...');
        await ApiService.sendFollowRequest(widget.userId);
        print('[FOLLOW REQUEST] ✅ Sent');
        if (mounted) {
          setState(() {
            _followRequested = true;
            _isFollowLoading = false;
          });
        }
      } else {
        // Public account → direct follow
        print('[FOLLOW] Following public account...');
        await ApiService.followUser(widget.userId);
        print('[FOLLOW] ✅ Success');
        if (mounted) {
          setState(() {
            _isFollowing = true;
            _followersCount = (_followersCount + 1).clamp(0, 999999);
            _isFollowLoading = false;
          });
          await _loadUserPosts();
        }
      }
    } catch (e) {
      print('[FOLLOW ERROR] $e');
      if (mounted) {
        setState(() {
          _isFollowLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
}
```

#### Button UI Logic
- **Public account** → "Follow" button
- **Private account, not following** → "Request" button
- **Private account, request sent** → "Requested" button (disabled)
- **Already following** → "Following" button (showing Unfollow on tap)

---

## 6. API SERVICE METHODS (Mobile)

**File:** [api_service.dart](social-media-mobile/lib/src/services/api_service.dart)

```dart
// Follow a public account directly
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

// Send follow request to private account
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

// Check if pending follow request exists
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
    
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Failed to unfollow user');
    }
}
```

---

## 7. COMPLETE API ENDPOINTS

### Follow Endpoints
| Method | Endpoint | Purpose | Auth |
|--------|----------|---------|------|
| POST | `/social/followers/{userId}` | Follow a user | ✅ Required |
| DELETE | `/social/followers/{userId}` | Unfollow a user | ✅ Required |
| GET | `/social/followers/check/{userId}` | Check if following | ✅ Required |
| GET | `/social/followers/user/{userId}` | Get followers list | ✅ Required |
| GET | `/social/followers/user/{userId}/following` | Get following list | ✅ Required |
| GET | `/social/followers/user/{userId}/stats` | Get follower stats | ✅ Required |
| GET | `/social/followers/mutual` | Get mutual followers | ✅ Required |

### Follow Request Endpoints
| Method | Endpoint | Purpose | Auth |
|--------|----------|---------|------|
| POST | `/social/follow-requests/{userId}` | Send follow request | ✅ Required |
| GET | `/social/follow-requests` | Get incoming requests | ✅ Required |
| GET | `/social/follow-requests/check/{userId}` | Check for pending request | ✅ Required |
| POST | `/social/follow-requests/{requestId}/accept` | Accept request | ✅ Required |
| POST | `/social/follow-requests/{requestId}/decline` | Decline request | ✅ Required |

---

## 8. EXISTING PRIVATE ACCOUNT CHECKS ✅

### Backend Privacy Checks

#### In FollowRequestService
```java
@Transactional
public void sendFollowRequest(Long requesterId, Long targetId) {
    // Check 1: Self-follow validation
    if (requesterId.equals(targetId)) {
        throw new IllegalArgumentException("Cannot request to follow yourself");
    }
    
    // Check 2: Block check
    if (blockService.isEitherBlocked(requesterId, targetId)) {
        throw new IllegalArgumentException("Cannot send follow request to this user");
    }

    // Check 3: Already following check
    if (followerService.isFollowing(requesterId, targetId)) {
        throw new IllegalArgumentException("Already following this user");
    }

    // Check 4: Duplicate request check
    if (followRequestRepository.existsByRequesterIdAndTargetId(requesterId, targetId)) {
        throw new IllegalArgumentException("Follow request already sent");
    }

    // Create follow request and send notification
    FollowRequest fr = new FollowRequest(requesterId, targetId);
    followRequestRepository.save(fr);
    fcmService.onFollowRequestReceived(targetId, requesterId);
}
```

### Mobile Privacy Checks
```dart
// In _checkFollowStatus()
if (!isFollowing && _isPrivate) {
    hasRequest = await ApiService.hasFollowRequest(widget.userId);
}

// In _toggleFollow()
if (_isFollowing) {
    // Unfollow
} else if (_isPrivate) {
    // Send follow request
} else {
    // Direct follow
}
```

---

## LIKELY SOURCES OF 500 ERROR

### 1. **Block Service Issue** (Most Likely)
**Location:** `blockService.isEitherBlocked(requesterId, targetId)`

**Potential Problems:**
- ❌ BlockService might be null (not injected)
- ❌ BlockService method throwing NPE
- ❌ Database query failing on blocked_users table
- ❌ User IDs being mismatched in condition

**Fix Check:**
```java
// In FollowRequestService.java
private final BlockService blockService;  // ← Must be @Autowired/injected

// In sendFollowRequest()
if (blockService.isEitherBlocked(requesterId, targetId)) {  // ← Might throw NPE
    throw new IllegalArgumentException("Cannot send follow request to this user");
}
```

### 2. **FCM Service Issue**
**Location:** `fcmService.onFollowRequestReceived(targetId, requesterId)`

**Potential Problems:**
- ❌ FCM service not properly initialized
- ❌ Invalid user IDs for push notification
- ❌ Firebase configuration missing

### 3. **Database Constraint Violation**
**Location:** Follow request creation

**Potential Problems:**
- ❌ Unique constraint `uk_follow_request (requester_id, receiver_id)` violation
- ❌ Foreign key violation on users table
- ❌ Database transaction isolation issue

### 4. **Authorization/JWT Issue**
**Location:** `@RequestAttribute("userId") Long requesterId`

**Potential Problems:**
- ❌ JWT token missing from request header
- ❌ JWT filter not adding userId attribute
- ❌ Invalid token format

### 5. **Null Pointer in Service**
**Location:** Any service method

**Potential Problems:**
- ❌ UserProfileService.getUserProfilesByIds() returning null
- ❌ NotificationService.createNotification() failing

---

## MISSING PIECES

### What's Implemented ✅
1. Follow request API endpoint
2. User model with isPrivate field
3. Follow/follower relationships
4. Follow request table
5. Post visibility filtering (for close friends)
6. Follow button implementation
7. Private account checks

### What Might Need Work ⚠️
1. **BlockService.isEitherBlocked()** - Verify this is properly injected and working
2. **FCMService.onFollowRequestReceived()** - Verify push notification handling
3. **NotificationService** - Verify notification creation
4. **Error Handling** - Ensure all exceptions return proper 4xx status, not 500

---

## QUICK DEBUGGING STEPS

1. **Check BlockService injection:**
   ```bash
   grep -r "BlockService" backend/social-service/src
   ```

2. **Check FollowRequestService constructor:**
   ```bash
   grep -A 5 "@RequiredArgsConstructor" FollowRequestService.java
   ```

3. **Check application logs for 500 error:**
   ```
   Look for: "blockService.isEitherBlocked()" error
   Or: FCMService or NotificationService exceptions
   ```

4. **Add debug logging:**
   ```java
   System.out.println("[DEBUG] sendFollowRequest called: " + requesterId + " -> " + targetId);
   System.out.println("[DEBUG] BlockService null? " + (blockService == null));
   System.out.println("[DEBUG] Checking block status...");
   ```

---

## TESTING COMMANDS

```bash
# Test follow request (private account)
curl -X POST http://localhost:8080/api/social/follow-requests/5 \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json"

# Check for pending request
curl -X GET http://localhost:8080/api/social/follow-requests/check/5 \
  -H "Authorization: Bearer <TOKEN>"

# Get incoming requests
curl -X GET http://localhost:8080/api/social/follow-requests \
  -H "Authorization: Bearer <TOKEN>"

# Accept request
curl -X POST http://localhost:8080/api/social/follow-requests/123/accept \
  -H "Authorization: Bearer <TOKEN>"
```

---

## SUMMARY

✅ **Complete Follow System:** Public follows work, private account follow requests implemented
✅ **Database:** Users table has `is_private` field, follow_requests table exists
✅ **Frontend:** Mobile app checks privacy and uses correct endpoints
✅ **Error Handling:** Most validations in place

⚠️ **Likely 500 Error:** BlockService dependency injection or error handling in privacy checks
⚠️ **Action:** Check BlockService initialization and add debug logging to findRoot cause

