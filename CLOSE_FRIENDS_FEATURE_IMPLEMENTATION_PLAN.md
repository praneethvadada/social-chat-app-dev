# Close Friends Feature - Complete Implementation Plan

## 📋 Feature Overview

Allow users to create a "Close Friends" list and share posts exclusively with this group. When creating a post, users can choose:
- **Public**: Visible to all followers/public users
- **Close Friends**: Visible only to users in the close friends list

## 🔍 Current Implementation Status

### ✅ Already Implemented
1. **Database Table**: `close_friends` table exists
2. **Backend Entity**: `CloseFriend.java` entity created
3. **Backend Repository**: `CloseFriendRepository.java` with all necessary queries
4. **Backend Service**: `CloseFriendService.java` with CRUD operations
5. **Backend Controller**: `CloseFriendController.java` for API endpoints
6. **Frontend Settings**: Close Friends management UI in `privacy_settings_screen.dart`

### ❌ Missing Implementations
1. **Database Schema**: Need to add `visibility` enum column to `posts` table
2. **Backend Post Entity**: Need to add `visibility` field to `Post.java`
3. **Backend Post Service**: Need to implement visibility filtering logic
4. **Backend DTOs**: Need to update `PostRequest` and `PostResponse` with visibility
5. **Frontend Create Post**: Need to add visibility selector (Public/Close Friends)
6. **Frontend Post Feed**: Need to handle visibility filtering

---

## 🗄️ Database Changes

### 1. Update `posts` table in schema

**Current Structure:**
```sql
CREATE TABLE posts (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    content TEXT,
    is_public BOOLEAN NOT NULL DEFAULT TRUE,
    ...
)
```

**New Structure:**
```sql
CREATE TABLE posts (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    content TEXT,
    is_public BOOLEAN NOT NULL DEFAULT TRUE,
    visibility ENUM('PUBLIC', 'CLOSE_FRIENDS') NOT NULL DEFAULT 'PUBLIC',  -- NEW
    ...
)
```

### 2. Migration Script

```sql
-- Add visibility column to posts table
ALTER TABLE posts 
ADD COLUMN visibility ENUM('PUBLIC', 'CLOSE_FRIENDS') NOT NULL DEFAULT 'PUBLIC' 
AFTER is_public;

-- Update existing posts based on is_public flag
UPDATE posts 
SET visibility = CASE 
    WHEN is_public = TRUE THEN 'PUBLIC'
    ELSE 'CLOSE_FRIENDS'  -- Treat private posts as close friends
END;

-- Add index for visibility filtering
CREATE INDEX idx_visibility ON posts(visibility);
CREATE INDEX idx_user_visibility ON posts(user_id, visibility);
```

**Note**: We'll keep `is_public` for backward compatibility, but `visibility` will be the source of truth.

---

## 🔧 Backend Implementation Changes

### 1. Update `Post.java` Entity

**File**: `backend/social-service/src/main/java/com/socialmedia/social/entity/Post.java`

**Add**:
```java
public enum PostVisibility {
    PUBLIC,
    CLOSE_FRIENDS
}

// Add this field to Post class
@Enumerated(EnumType.STRING)
@Column(nullable = false, length = 20)
private PostVisibility visibility = PostVisibility.PUBLIC;
```

### 2. Update `PostRequest.java` DTO

**File**: `backend/social-service/src/main/java/com/socialmedia/social/dto/PostRequest.java`

**Add**:
```java
import com.socialmedia.social.entity.Post.PostVisibility;

@Data
public class PostRequest {
    @Size(max = 5000)
    private String content;
    
    private List<String> imageUrls = new ArrayList<>();
    
    private Boolean isPublic = true;
    
    // NEW: Visibility field
    private PostVisibility visibility = PostVisibility.PUBLIC;
    
    @AssertTrue(message = "Post must have either content or images")
    private boolean isValid() {
        boolean hasContent = content != null && !content.trim().isEmpty();
        boolean hasImages = imageUrls != null && !imageUrls.isEmpty();
        return hasContent || hasImages;
    }
}
```

### 3. Update `PostResponse.java` DTO

**File**: `backend/social-service/src/main/java/com/socialmedia/social/dto/PostResponse.java`

**Add**:
```java
import com.socialmedia.social.entity.Post.PostVisibility;

// Add this field
private PostVisibility visibility;
```

### 4. Update `PostService.java`

**File**: `backend/social-service/src/main/java/com/socialmedia/social/service/PostService.java`

**Changes Required**:

#### A. Inject CloseFriendService
```java
private final CloseFriendService closeFriendService;
```

#### B. Update `createPost()` method
```java
@Transactional
public PostResponse createPost(PostRequest request, Long userId) {
    Post post = new Post();
    post.setUserId(userId);
    post.setContent(request.getContent() != null ? request.getContent().trim() : "");
    post.setImageUrls(request.getImageUrls() != null ? request.getImageUrls() : new ArrayList<>());
    
    // NEW: Handle visibility
    PostVisibility visibility = request.getVisibility() != null 
        ? request.getVisibility() 
        : PostVisibility.PUBLIC;
    post.setVisibility(visibility);
    
    // Update isPublic based on visibility
    post.setIsPublic(visibility == PostVisibility.PUBLIC);
    
    Post savedPost = postRepository.saveAndFlush(post);
    return mapToResponse(savedPost, userId);
}
```

#### C. Update `updatePost()` method
```java
@Transactional
public PostResponse updatePost(Long postId, PostRequest request, Long userId) {
    Post post = postRepository.findById(postId)
            .orElseThrow(() -> new RuntimeException("Post not found"));
    
    if (!post.getUserId().equals(userId)) {
        throw new RuntimeException("Unauthorized to update this post");
    }
    
    post.setContent(request.getContent() != null ? request.getContent().trim() : "");
    post.setImageUrls(request.getImageUrls() != null ? request.getImageUrls() : new ArrayList<>());
    
    // NEW: Update visibility
    if (request.getVisibility() != null) {
        post.setVisibility(request.getVisibility());
        post.setIsPublic(request.getVisibility() == PostVisibility.PUBLIC);
    }
    
    Post updatedPost = postRepository.save(post);
    return mapToResponse(updatedPost, userId);
}
```

#### D. Update `getFeed()` method - **CRITICAL CHANGE**
```java
@Transactional(readOnly = true)
public Page<PostResponse> getFeed(Long userId, Pageable pageable) {
    List<Long> followingIds = followerService.getFollowingIds(userId);
    followingIds.add(userId);
    
    // Block filtering
    List<Long> blockedUserIds = blockService.getBlockedUserIds(userId);
    List<Long> blockerUserIds = blockService.getBlockerUserIds(userId);
    followingIds = followingIds.stream()
        .filter(id -> !blockedUserIds.contains(id) && !blockerUserIds.contains(id))
        .collect(Collectors.toList());
    
    if (followingIds.isEmpty()) {
        return Page.empty(pageable);
    }
    
    // NEW: Get close friends list
    List<Long> closeFriendIds = closeFriendService.getCloseFriendIds(userId);
    
    // Fetch posts
    Page<Post> posts = postRepository.findByUserIdIn(followingIds, pageable);
    
    // NEW: Filter posts based on visibility
    Page<Post> filteredPosts = posts.map(post -> {
        // If post is public, show it
        if (post.getVisibility() == PostVisibility.PUBLIC) {
            return post;
        }
        
        // If post is close friends only
        if (post.getVisibility() == PostVisibility.CLOSE_FRIENDS) {
            // Show if:
            // 1. Current user is the author
            // 2. Current user is in the author's close friends list
            if (post.getUserId().equals(userId)) {
                return post;  // Own post
            }
            
            // Check if current user is in author's close friends
            boolean isInCloseFriends = closeFriendService.isCloseFriend(post.getUserId(), userId);
            if (isInCloseFriends) {
                return post;
            }
        }
        
        return null;  // Filter out
    });
    
    // Remove null entries
    List<Post> visiblePosts = filteredPosts.getContent().stream()
        .filter(post -> post != null)
        .collect(Collectors.toList());
    
    return new PageImpl<>(
        visiblePosts.stream().map(p -> mapToResponse(p, userId)).collect(Collectors.toList()),
        pageable,
        visiblePosts.size()
    );
}
```

#### E. Update `getUserPosts()` method
```java
@Transactional(readOnly = true)
public Page<PostResponse> getUserPosts(Long targetUserId, Long currentUserId, Pageable pageable) {
    // Existing privacy check
    UserProfile targetProfile = userProfileRepository.findByUserId(targetUserId).orElse(null);
    boolean isPrivate = false;
    if (targetProfile != null && targetProfile.getIsPrivate() != null) {
        isPrivate = targetProfile.getIsPrivate();
    }

    if (isPrivate && !targetUserId.equals(currentUserId)) {
        boolean isFollowing = followerService.isFollowing(currentUserId, targetUserId);
        if (!isFollowing) {
            return Page.empty(pageable);
        }
    }

    Page<Post> posts = postRepository.findByUserIdOrderByCreatedAtDesc(targetUserId, pageable);
    
    // NEW: Filter by visibility
    List<Long> closeFriendIds = closeFriendService.getCloseFriendIds(targetUserId);
    boolean isInCloseFriends = closeFriendIds.contains(currentUserId);
    
    // Filter posts
    List<Post> visiblePosts = posts.getContent().stream()
        .filter(post -> {
            // Show own posts
            if (post.getUserId().equals(currentUserId)) {
                return true;
            }
            
            // Show public posts
            if (post.getVisibility() == PostVisibility.PUBLIC) {
                return true;
            }
            
            // Show close friends posts only if viewer is in close friends
            if (post.getVisibility() == PostVisibility.CLOSE_FRIENDS && isInCloseFriends) {
                return true;
            }
            
            return false;
        })
        .collect(Collectors.toList());
    
    return new PageImpl<>(
        visiblePosts.stream().map(p -> mapToResponse(p, currentUserId)).collect(Collectors.toList()),
        pageable,
        visiblePosts.size()
    );
}
```

#### F. Update `mapToResponse()` method
```java
private PostResponse mapToResponse(Post post, Long userId) {
    PostResponse response = new PostResponse();
    response.setId(post.getId());
    response.setUserId(post.getUserId());
    response.setContent(post.getContent());
    
    // ... existing code for image URLs, likes, etc.
    
    // NEW: Add visibility
    response.setVisibility(post.getVisibility());
    
    return response;
}
```

### 5. Add Repository Methods (if needed)

**File**: `backend/social-service/src/main/java/com/socialmedia/social/repository/PostRepository.java`

Add if not exists:
```java
Page<Post> findByUserIdAndVisibility(Long userId, PostVisibility visibility, Pageable pageable);
```

---

## 📱 Frontend Implementation Changes

### 1. Update Post Model

**File**: `social-media-mobile/lib/src/models/post.dart`

**Add**:
```dart
enum PostVisibility {
  PUBLIC,
  CLOSE_FRIENDS,
}

class Post {
  final int id;
  final int userId;
  final String authorName;
  final String? profilePicUrl;
  final DateTime timestamp;
  final String content;
  final List<String> imageUrls;
  final int likes;
  final int comments;
  final int shares;
  final int saves;
  final bool isLiked;
  final bool isSaved;
  final PostVisibility visibility;  // NEW
  
  const Post({
    required this.id,
    required this.userId,
    required this.authorName,
    this.profilePicUrl,
    required this.timestamp,
    required this.content,
    this.imageUrls = const [],
    this.likes = 0,
    this.comments = 0,
    this.shares = 0,
    this.saves = 0,
    this.isLiked = false,
    this.isSaved = false,
    this.visibility = PostVisibility.PUBLIC,  // NEW
  });
  
  factory Post.fromJson(Map<String, dynamic> json) {
    // ... existing code
    
    // NEW: Parse visibility
    final visibilityStr = json['visibility']?.toString() ?? 'PUBLIC';
    final visibility = visibilityStr == 'CLOSE_FRIENDS' 
        ? PostVisibility.CLOSE_FRIENDS 
        : PostVisibility.PUBLIC;
    
    return Post(
      // ... existing fields
      visibility: visibility,  // NEW
    );
  }
}
```

### 2. Update API Service

**File**: `social-media-mobile/lib/src/services/api_service.dart`

**Update `createPost()` method**:
```dart
static Future<Post> createPost(
  String content, 
  List<String> imageUrls, 
  {String visibility = 'PUBLIC'}  // Already exists
) async {
  // ... existing code
  
  final body = {
    'content': content,
    'imageUrls': imageUrls,
    'visibility': visibility,  // NEW: Send visibility enum
  };
  
  // ... rest of code
}
```

**Add `updatePost()` method**:
```dart
static Future<Post> updatePost(
  int postId,
  String content, 
  List<String> imageUrls, 
  {String visibility = 'PUBLIC'}
) async {
  final token = await TokenStorage.getAccessToken();
  
  final response = await http.put(
    Uri.parse('$baseUrl/posts/$postId'),
    headers: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'content': content,
      'imageUrls': imageUrls,
      'visibility': visibility,
    }),
  );
  
  if (response.statusCode == 200) {
    return Post.fromJson(jsonDecode(response.body));
  } else {
    throw Exception('Failed to update post: ${response.statusCode}');
  }
}
```

### 3. Update Create Post Screen

**File**: `social-media-mobile/lib/src/screens/create_post/create_post_screen.dart`

**Add State Variables**:
```dart
class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  // ... existing state
  
  // NEW: Visibility state
  String _selectedVisibility = 'PUBLIC';  // 'PUBLIC' or 'CLOSE_FRIENDS'
}
```

**Add Visibility Selector Widget**:
```dart
Widget _buildVisibilitySelector() {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(color: Colors.grey.shade300),
      ),
    ),
    child: Row(
      children: [
        const Icon(Icons.public, size: 20, color: Colors.grey),
        const SizedBox(width: 12),
        const Text(
          'Visibility:',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedVisibility,
              isExpanded: true,
              items: const [
                DropdownMenuItem(
                  value: 'PUBLIC',
                  child: Row(
                    children: [
                      Icon(Icons.public, size: 18),
                      SizedBox(width: 8),
                      Text('Public'),
                    ],
                  ),
                ),
                DropdownMenuItem(
                  value: 'CLOSE_FRIENDS',
                  child: Row(
                    children: [
                      Icon(Icons.star, size: 18, color: Colors.green),
                      SizedBox(width: 8),
                      Text(
                        'Close Friends',
                        style: TextStyle(color: Colors.green),
                      ),
                    ],
                  ),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedVisibility = value;
                  });
                }
              },
            ),
          ),
        ),
      ],
    ),
  );
}
```

**Update `_post()` method**:
```dart
Future<void> _post() async {
  // ... existing validation
  
  // Create/update post with visibility
  if (widget.editingPostId != null) {
    await PostService.updatePost(
      widget.editingPostId!,
      content,
      finalUrls,
      visibility: _selectedVisibility,  // NEW
    );
  } else {
    await PostService.createPost(
      content,
      uploadedUrls,
      visibility: _selectedVisibility,  // NEW
    );
  }
  
  // ... rest of code
}
```

**Update Build Method** (insert visibility selector):
```dart
@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: Text(widget.editingPostId != null ? 'Edit Post' : 'Create Post'),
      actions: [
        IconButton(
          icon: const Icon(Icons.send),
          onPressed: _uploading ? null : _post,
        ),
      ],
    ),
    body: Column(
      children: [
        // User profile header
        _buildUserHeader(),
        
        // NEW: Visibility selector
        _buildVisibilitySelector(),
        
        // Content text field
        Expanded(
          child: TextField(
            controller: _controller,
            // ... existing config
          ),
        ),
        
        // Media preview
        if (_selected.isNotEmpty) MediaPreviewCarousel(...),
        
        // ... rest of UI
      ],
    ),
  );
}
```

### 4. Update Post Service

**File**: `social-media-mobile/lib/src/services/post_service.dart`

**Update Methods**:
```dart
static Future<void> createPost(
  String content,
  List<String> imageUrls, {
  String visibility = 'PUBLIC',  // Already exists
}) async {
  final post = await ApiService.createPost(
    content, 
    imageUrls, 
    visibility: visibility,
  );
  // ... existing code
}

static Future<void> updatePost(
  int postId,
  String content,
  List<String> imageUrls, {
  String visibility = 'PUBLIC',  // NEW
}) async {
  final post = await ApiService.updatePost(
    postId,
    content, 
    imageUrls, 
    visibility: visibility,
  );
  // ... existing code
}
```

### 5. Visual Indicator for Close Friends Posts

**File**: `social-media-mobile/lib/src/components/post_card.dart` (or wherever posts are displayed)

**Add Close Friends Badge**:
```dart
Widget build(BuildContext context) {
  return Card(
    child: Column(
      children: [
        // Post header
        ListTile(
          leading: CircleAvatar(...),
          title: Row(
            children: [
              Text(post.authorName),
              const SizedBox(width: 8),
              // NEW: Close friends indicator
              if (post.visibility == PostVisibility.CLOSE_FRIENDS)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.star, size: 12, color: Colors.green),
                      SizedBox(width: 4),
                      Text(
                        'Close Friends',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          subtitle: Text(post.timeAgo),
        ),
        
        // ... rest of post UI
      ],
    ),
  );
}
```

---

## 🎯 Implementation Summary

### Database Changes
1. ✅ `close_friends` table (already exists)
2. ❌ Add `visibility` column to `posts` table
3. ❌ Add index on `visibility` column

### Backend Changes
1. ✅ `CloseFriend` entity (already exists)
2. ✅ `CloseFriendRepository` (already exists)
3. ✅ `CloseFriendService` (already exists)
4. ✅ `CloseFriendController` (already exists)
5. ❌ Add `PostVisibility` enum to `Post` entity
6. ❌ Add `visibility` field to `Post` entity
7. ❌ Update `PostRequest` DTO with `visibility`
8. ❌ Update `PostResponse` DTO with `visibility`
9. ❌ Update `PostService.createPost()` to handle visibility
10. ❌ Update `PostService.updatePost()` to handle visibility
11. ❌ Update `PostService.getFeed()` to filter by visibility
12. ❌ Update `PostService.getUserPosts()` to filter by visibility
13. ❌ Update `PostService.mapToResponse()` to include visibility

### Frontend Changes
1. ✅ Close Friends management UI (already exists in settings)
2. ❌ Add `PostVisibility` enum to Post model
3. ❌ Update `Post.fromJson()` to parse visibility
4. ❌ Add visibility selector to Create Post screen
5. ❌ Update Create Post UI with dropdown
6. ❌ Update `ApiService.createPost()` to send visibility
7. ❌ Add `ApiService.updatePost()` method
8. ❌ Update `PostService` methods with visibility
9. ❌ Add Close Friends badge to post cards

---

## 🔒 Security & Privacy Considerations

1. **Authorization**: Only post author can change visibility
2. **Filtering**: Backend MUST enforce visibility filtering (don't trust frontend)
3. **Close Friends List**: Only the user can see/modify their own close friends list
4. **Feed Optimization**: Use database indexes for efficient visibility filtering
5. **Privacy**: Close friends posts never appear in public/explore feeds

---

## 🧪 Testing Checklist

### Backend Tests
- [ ] Create post with PUBLIC visibility
- [ ] Create post with CLOSE_FRIENDS visibility
- [ ] Update post visibility from PUBLIC to CLOSE_FRIENDS
- [ ] Update post visibility from CLOSE_FRIENDS to PUBLIC
- [ ] Feed shows PUBLIC posts to all followers
- [ ] Feed shows CLOSE_FRIENDS posts only to close friends
- [ ] Feed hides CLOSE_FRIENDS posts from non-close friends
- [ ] User profile shows correct posts based on visibility
- [ ] Close friends can view CLOSE_FRIENDS posts on profile
- [ ] Non-close friends cannot view CLOSE_FRIENDS posts on profile

### Frontend Tests
- [ ] Visibility selector appears in Create Post screen
- [ ] Can select PUBLIC visibility
- [ ] Can select CLOSE_FRIENDS visibility
- [ ] Post is created with correct visibility
- [ ] Close Friends badge appears on CLOSE_FRIENDS posts
- [ ] Close Friends badge does NOT appear on PUBLIC posts
- [ ] Feed filters posts correctly
- [ ] Profile filters posts correctly
- [ ] Editing post preserves visibility
- [ ] Can change visibility when editing post

---

## 📊 Database Impact

### Storage Impact
- New column: `visibility` enum (1-2 bytes per row)
- New index: `idx_visibility` (minimal overhead)
- Existing data: Will be migrated to 'PUBLIC'

### Performance Impact
- **Positive**: Indexed visibility column enables faster filtering
- **Minimal**: Enum storage is very efficient
- **Query Impact**: Minimal - visibility check is simple equality comparison

### Migration Impact
- **Zero Downtime**: Column addition with default value is non-blocking
- **Backward Compatible**: Keep `is_public` for legacy support
- **Safe Rollback**: Can rollback by removing column

---

## 🚀 Rollout Strategy

### Phase 1: Database Migration
1. Add `visibility` column with default 'PUBLIC'
2. Migrate existing `is_public` values
3. Add indexes

### Phase 2: Backend Deployment
1. Deploy backend with visibility support
2. Keep backward compatibility with `is_public`
3. Monitor logs for any issues

### Phase 3: Frontend Deployment
1. Deploy frontend with visibility selector
2. Enable feature for all users
3. Monitor user adoption

### Phase 4: Cleanup (Optional - Future)
1. Deprecate `is_public` field
2. Remove `is_public` after 3 months
3. Use only `visibility` field

---

## ✅ Files to Modify

### Backend Files (7 files)
1. ✅ `COMPLETE_SCHEMA_AWS_PRODUCTION.sql` - Add migration
2. ❌ `Post.java` - Add visibility enum and field
3. ❌ `PostRequest.java` - Add visibility field
4. ❌ `PostResponse.java` - Add visibility field
5. ❌ `PostService.java` - Update all methods with visibility logic
6. ✅ `CloseFriendService.java` - Already exists
7. ✅ `CloseFriendRepository.java` - Already exists

### Frontend Files (4 files)
1. ❌ `post.dart` - Add visibility enum and field
2. ❌ `create_post_screen.dart` - Add visibility selector
3. ❌ `api_service.dart` - Update createPost, add updatePost
4. ❌ `post_service.dart` - Update methods
5. ❌ `post_card.dart` (or similar) - Add close friends badge

### Total Files to Modify: **11 files**

---

## 💡 Additional Features (Future Enhancements)

1. **Close Friends Stories**: Separate story visibility for close friends
2. **Analytics**: Show user how many posts they've shared with close friends
3. **Bulk Visibility Change**: Change visibility of multiple posts at once
4. **Notification**: Notify when someone adds you to close friends
5. **Quick Toggle**: Quick switch between PUBLIC/CLOSE_FRIENDS during creation

---

**Ready for Implementation? Reply "ok" to proceed! ✨**
