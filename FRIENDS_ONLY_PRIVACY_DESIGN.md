# Friends-Only Post Privacy System - Design & Implementation

## Overview
Users can choose post visibility: **Public** (everyone) or **Close Friends** (only close friends). Feed algorithm filters posts based on user relationships.

---

## 1. DATA MODEL CHANGES

### Backend - Post Entity
```java
@Entity
@Table(name = "posts")
public class Post {
  // ... existing fields ...
  
  @Enumerated(EnumType.STRING)
  @Column(name = "visibility", nullable = false)
  private PostVisibility visibility = PostVisibility.PUBLIC;  // DEFAULT: PUBLIC
  
  @ManyToMany(fetch = FetchType.LAZY)
  @JoinTable(
    name = "post_visible_to_close_friends",
    joinColumns = @JoinColumn(name = "post_id"),
    inverseJoinColumns = @JoinColumn(name = "friend_id")
  )
  private Set<User> visibleToCloseFriends = new HashSet<>();
}

public enum PostVisibility {
  PUBLIC,
  CLOSE_FRIENDS
}
```

### Frontend - Post Model (Dart)
```dart
enum PostVisibility { public, closeFriends }

class Post {
  final int id;
  final int userId;
  final String authorName;
  final String? profilePicUrl;
  final DateTime timestamp;
  final String content;
  final List<String> imageUrls;
  final List<SelectedMedia> media;
  final int likes;
  final int comments;
  final int shares;
  final int saves;
  final bool isLiked;
  final bool isSaved;
  final List<UserProfile> sampleLikers;
  final PostVisibility visibility;  // NEW: PUBLIC or CLOSE_FRIENDS
  
  const Post({
    required this.id,
    required this.userId,
    required this.authorName,
    this.profilePicUrl,
    required this.timestamp,
    required this.content,
    this.imageUrls = const [],
    this.media = const [],
    this.likes = 0,
    this.comments = 0,
    this.shares = 0,
    this.saves = 0,
    this.isLiked = false,
    this.isSaved = false,
    this.sampleLikers = const [],
    this.visibility = PostVisibility.public,  // DEFAULT
  });
  
  factory Post.fromJson(Map<String, dynamic> json) {
    // ... existing code ...
    
    // Parse visibility field
    final visibilityStr = json['visibility']?.toString()?.toUpperCase() ?? 'PUBLIC';
    PostVisibility visibility = PostVisibility.public;
    if (visibilityStr == 'CLOSE_FRIENDS') {
      visibility = PostVisibility.closeFriends;
    }
    
    return Post(
      // ... existing fields ...
      visibility: visibility,
    );
  }
}
```

---

## 2. FEED ALGORITHM (Backend)

### Get Feed Endpoint
```
GET /social/posts/feed
Query Parameters:
  - page: int (default: 0)
  - size: int (default: 10)

Response: Page<PostDTO>
```

### Feed Filtering Logic (SQL)
```sql
SELECT p.* FROM posts p
WHERE 
  -- Own posts (always visible to user)
  p.user_id = :currentUserId
  
  OR
  
  -- Public posts
  (p.visibility = 'PUBLIC')
  
  OR
  
  -- Close-friends posts where current user is a close friend
  (p.visibility = 'CLOSE_FRIENDS' 
   AND EXISTS (
     SELECT 1 FROM user_close_friends ucf
     WHERE ucf.user_id = p.user_id 
     AND ucf.close_friend_user_id = :currentUserId
   ))

ORDER BY p.created_at DESC
LIMIT :size OFFSET :offset
```

### Backend Service Implementation
```java
@Service
public class PostService {
  
  @Transactional(readOnly = true)
  public Page<PostDTO> getFeed(int page, int size, Long currentUserId) {
    // This query handles all visibility rules
    return postRepository.findFeedForUser(currentUserId, PageRequest.of(page, size));
  }
  
  @Transactional
  public PostDTO createPost(CreatePostRequest request, Long userId) {
    Post post = new Post();
    post.setContent(request.getContent());
    post.setImageUrls(request.getImageUrls());
    
    // Set visibility based on request (default: PUBLIC)
    PostVisibility visibility = PostVisibility.valueOf(
      request.getVisibility() != null ? request.getVisibility() : "PUBLIC"
    );
    post.setVisibility(visibility);
    
    // If close-friends, populate the visible-to list
    if (visibility == PostVisibility.CLOSE_FRIENDS) {
      User author = userRepository.findById(userId).orElseThrow();
      Set<User> closeFriends = author.getCloseFriends();
      post.setVisibleToCloseFriends(closeFriends);
    }
    
    return postRepository.save(post);
  }
}
```

### Repository Query
```java
@Repository
public interface PostRepository extends JpaRepository<Post, Long> {
  
  @Query("""
    SELECT p FROM Post p
    WHERE p.userId = :currentUserId
       OR p.visibility = 'PUBLIC'
       OR (p.visibility = 'CLOSE_FRIENDS' 
           AND :currentUserId IN (
             SELECT ucf.closeFriendUserId 
             FROM UserCloseFriend ucf 
             WHERE ucf.userId = p.userId
           ))
    ORDER BY p.createdAt DESC
  """)
  Page<Post> findFeedForUser(
    @Param("currentUserId") Long currentUserId,
    Pageable pageable
  );
}
```

---

## 3. API ENDPOINT CHANGES

### Create Post Request (Updated)
```
POST /social/posts
Content-Type: application/json

{
  "content": "Hello world!",
  "imageUrls": ["url1", "url2"],
  "visibility": "CLOSE_FRIENDS"  // NEW: "PUBLIC" | "CLOSE_FRIENDS"
}
```

### Get Feed Endpoint (New)
```
GET /social/posts/feed?page=0&size=10

Response:
{
  "content": [
    {
      "id": 1,
      "userId": 123,
      "authorName": "John Doe",
      "content": "Hello friends!",
      "visibility": "CLOSE_FRIENDS",
      "timestamp": "2024-01-09T12:30:45Z",
      ...
    }
  ],
  "page": 0,
  "size": 10,
  "totalPages": 5,
  "totalElements": 50
}
```

---

## 4. FRONTEND IMPLEMENTATION

### Step 1: Update Post Model
- Add `visibility: PostVisibility` field
- Update `Post.fromJson()` to parse visibility

### Step 2: Update Create Post Screen
- Add toggle/radio button for privacy selection
- Pass visibility to API call

### Step 3: Update API Service
- Modify `createPost()` to accept visibility parameter
- Change from `getPosts()` to `getFeed()` endpoint

### Step 4: Feed Filtering (Automatic)
- No changes needed! Backend handles all filtering
- Frontend just displays what backend returns

---

## 5. UI COMPONENTS

### Privacy Toggle in Create Post Screen
```dart
// In create_post_screen.dart
class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  PostVisibility _selectedVisibility = PostVisibility.public;
  
  Widget _buildPrivacySelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Icon(
            _selectedVisibility == PostVisibility.public
                ? Icons.public
                : Icons.people,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Privacy',
                  style: theme.textTheme.labelSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  _selectedVisibility == PostVisibility.public
                      ? 'Public - Anyone can see'
                      : 'Close Friends - Only close friends can see',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _showPrivacyOptions,
            child: Icon(Icons.arrow_drop_down, color: theme.primaryColor),
          ),
        ],
      ),
    );
  }
  
  void _showPrivacyOptions() {
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.public),
              title: const Text('Public'),
              subtitle: const Text('Anyone can see this post'),
              trailing: _selectedVisibility == PostVisibility.public
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                setState(() => _selectedVisibility = PostVisibility.public);
                Navigator.pop(c);
              },
            ),
            ListTile(
              leading: const Icon(Icons.people),
              title: const Text('Close Friends'),
              subtitle: const Text('Only close friends can see'),
              trailing: _selectedVisibility == PostVisibility.closeFriends
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                setState(() => _selectedVisibility = PostVisibility.closeFriends);
                Navigator.pop(c);
              },
            ),
          ],
        ),
      ),
    );
  }
}
```

### Privacy Badge on Post Card
```dart
// In post_card.dart
class _PostCardState extends ConsumerState<PostCard> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Column(
      children: [
        // Header with privacy indicator
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Profile pic & name
              CircleAvatar(
                backgroundImage: post.profilePicUrl != null
                    ? NetworkImage(post.profilePicUrl!)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(post.authorName, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        Text('${TimeAgoWidget(timestamp: post.timestamp)}', style: theme.textTheme.bodySmall),
                        if (post.visibility == PostVisibility.closeFriends) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.people, size: 12, color: theme.hintColor),
                          const SizedBox(width: 4),
                          Text('Close Friends', style: theme.textTheme.bodySmall?.copyWith(fontSize: 10)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // More options
              IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
            ],
          ),
        ),
        // Content, images, actions...
      ],
    );
  }
}
```

---

## 6. IMPLEMENTATION STEPS

### Backend (Java/Spring Boot):
1. Add `visibility` field to Post entity
2. Add `PostVisibility` enum
3. Create `@Query` in PostRepository with feed filtering logic
4. Update `PostController.createPost()` to accept visibility parameter
5. Add new `getFeed()` endpoint
6. Update `PostService.createPost()` to set close-friends list if needed
7. Update PostDTO to include visibility

### Frontend (Flutter):
1. Add `PostVisibility` enum to post.dart
2. Update `Post` class with visibility field
3. Update `Post.fromJson()` to parse visibility
4. Add privacy selector UI to create_post_screen.dart
5. Update `ApiService.createPost()` method signature
6. Update `api_service.dart` to call new `/feed` endpoint instead of `/posts`
7. Add privacy badge to post_card.dart

---

## 7. BACKWARD COMPATIBILITY

- Default visibility: **PUBLIC** (existing posts)
- Existing posts without visibility field → treat as PUBLIC
- No changes to post URLs, IDs, or feed structure
- Graceful migration: all existing posts remain public

---

## 8. PRIVACY CONSIDERATIONS

✅ **What's shown in feed:**
- Public posts from anyone
- Close-friends posts only to actual close friends
- Own posts to yourself always

❌ **What's NOT shown:**
- Close-friends posts to non-friends (they don't appear)
- Private posts to unauthorized users (complete filtering)

✅ **Security:**
- Server-side validation (not client-side)
- Close-friend list checked on backend
- No privacy bypass possible

---

## 9. FUTURE ENHANCEMENTS

- [ ] Edit post visibility after creation
- [ ] "Save to Drafts" - close-friends posts only
- [ ] "Scheduled Posts" - visibility scheduled changes
- [ ] "Story" feature - close-friends by default
- [ ] Direct messaging - close-friends notification badge

---

## 10. TESTING CHECKLIST

**Backend:**
- [ ] Create public post → visible to all
- [ ] Create close-friends post → visible to close friends only
- [ ] Create close-friends post → not visible to non-friends
- [ ] Feed returns correct posts based on relationships
- [ ] Page cursor works with filtered results

**Frontend:**
- [ ] Privacy toggle shows in create post
- [ ] Public option selected by default
- [ ] Privacy badge shows on close-friends posts
- [ ] Feed filters correctly when viewing
- [ ] Profile posts show correct visibility

