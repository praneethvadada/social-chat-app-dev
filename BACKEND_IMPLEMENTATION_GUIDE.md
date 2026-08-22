# Backend Implementation Guide - Friends-Only Post Privacy

## Quick Start: 5 Backend Changes Required

### 1. Add PostVisibility Enum
**File:** `PostVisibility.java`
```java
public enum PostVisibility {
  PUBLIC,
  CLOSE_FRIENDS
}
```

---

### 2. Update Post Entity
**File:** `Post.java`

```java
@Entity
@Table(name = "posts")
public class Post {
  // ... existing fields ...
  
  @Enumerated(EnumType.STRING)
  @Column(name = "visibility", nullable = false)
  private PostVisibility visibility = PostVisibility.PUBLIC;
  
  @ManyToMany(fetch = FetchType.LAZY)
  @JoinTable(
    name = "post_visible_to_close_friends",
    joinColumns = @JoinColumn(name = "post_id"),
    inverseJoinColumns = @JoinColumn(name = "friend_id")
  )
  private Set<User> visibleToCloseFriends = new HashSet<>();
  
  // Getters & Setters
  public PostVisibility getVisibility() {
    return visibility;
  }
  
  public void setVisibility(PostVisibility visibility) {
    this.visibility = visibility;
  }
  
  public Set<User> getVisibleToCloseFriends() {
    return visibleToCloseFriends;
  }
  
  public void setVisibleToCloseFriends(Set<User> visibleToCloseFriends) {
    this.visibleToCloseFriends = visibleToCloseFriends;
  }
}
```

---

### 3. Update PostRepository
**File:** `PostRepository.java`

Add feed filtering query:
```java
@Repository
public interface PostRepository extends JpaRepository<Post, Long> {
  
  // NEW: Get feed for user with visibility filtering
  @Query("""
    SELECT p FROM Post p
    WHERE p.userId = :currentUserId
       OR p.visibility = 'PUBLIC'
       OR (p.visibility = 'CLOSE_FRIENDS' 
           AND :currentUserId IN (
             SELECT uf.closeFriendUserId 
             FROM UserCloseFriend uf 
             WHERE uf.userId = p.userId
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

### 4. Update PostService
**File:** `PostService.java`

```java
@Service
public class PostService {
  
  @Autowired
  private PostRepository postRepository;
  
  @Autowired
  private UserRepository userRepository;
  
  // NEW: Get feed for current user
  @Transactional(readOnly = true)
  public Page<PostDTO> getFeedForUser(Long currentUserId, int page, int size) {
    Pageable pageable = PageRequest.of(page, size, Sort.by("createdAt").descending());
    Page<Post> posts = postRepository.findFeedForUser(currentUserId, pageable);
    return posts.map(this::mapToResponse);
  }
  
  // EXISTING: Create post - ADD visibility handling
  @Transactional
  public PostDTO createPost(CreatePostRequest request, Long userId) {
    Post post = new Post();
    post.setUserId(userId);
    post.setContent(request.getContent());
    post.setImageUrls(request.getImageUrls());
    post.setCreatedAt(LocalDateTime.now(ZoneId.of("UTC")));
    
    // NEW: Handle visibility
    PostVisibility visibility = PostVisibility.PUBLIC;
    if (request.getVisibility() != null) {
      try {
        visibility = PostVisibility.valueOf(request.getVisibility().toUpperCase());
      } catch (IllegalArgumentException e) {
        visibility = PostVisibility.PUBLIC; // Default
      }
    }
    post.setVisibility(visibility);
    
    // NEW: If close-friends, populate the visible-to list
    if (visibility == PostVisibility.CLOSE_FRIENDS) {
      User author = userRepository.findById(userId)
        .orElseThrow(() -> new RuntimeException("User not found"));
      
      // Get close friends list (assuming there's a getCloseFriends() method)
      Set<User> closeFriends = author.getCloseFriends();
      post.setVisibleToCloseFriends(closeFriends);
      
      System.out.println("[PostService] 🔒 Created CLOSE_FRIENDS post for user " + userId + 
                        " visible to " + closeFriends.size() + " close friends");
    } else {
      System.out.println("[PostService] 🌐 Created PUBLIC post for user " + userId);
    }
    
    Post savedPost = postRepository.save(post);
    return mapToResponse(savedPost);
  }
  
  // Helper: Map to DTO with visibility
  private PostDTO mapToResponse(Post post) {
    PostDTO dto = new PostDTO();
    dto.setId(post.getId());
    dto.setUserId(post.getUserId());
    dto.setContent(post.getContent());
    dto.setImageUrls(post.getImageUrls());
    dto.setVisibility(post.getVisibility().name()); // NEW: Include visibility
    dto.setCreatedAt(post.getCreatedAt());
    // ... map other fields ...
    return dto;
  }
}
```

---

### 5. Update PostController
**File:** `PostController.java`

```java
@RestController
@RequestMapping("/api/social")
public class PostController {
  
  @Autowired
  private PostService postService;
  
  // NEW: Get feed for current user
  @GetMapping("/posts/feed")
  public ResponseEntity<?> getFeed(
      @RequestParam(defaultValue = "0") int page,
      @RequestParam(defaultValue = "10") int size,
      @AuthenticationPrincipal UserDetails userDetails) {
    try {
      Long userId = getUserIdFromDetails(userDetails);
      Page<PostDTO> feed = postService.getFeedForUser(userId, page, size);
      return ResponseEntity.ok(feed);
    } catch (Exception e) {
      return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
    }
  }
  
  // EXISTING: Create post - should already accept visibility
  @PostMapping("/posts")
  public ResponseEntity<?> createPost(
      @RequestBody CreatePostRequest request,
      @AuthenticationPrincipal UserDetails userDetails) {
    try {
      Long userId = getUserIdFromDetails(userDetails);
      PostDTO post = postService.createPost(request, userId);
      return ResponseEntity.ok(post);
    } catch (Exception e) {
      return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
    }
  }
  
  // Helper method
  private Long getUserIdFromDetails(UserDetails userDetails) {
    // Parse from token or session
    // return userId;
  }
}
```

---

### 6. Update CreatePostRequest DTO
**File:** `CreatePostRequest.java`

```java
public class CreatePostRequest {
  private String content;
  private List<String> imageUrls;
  private boolean isPublic;
  private String visibility;  // NEW: "PUBLIC" or "CLOSE_FRIENDS"
  
  public String getVisibility() {
    return visibility;
  }
  
  public void setVisibility(String visibility) {
    this.visibility = visibility;
  }
  
  // ... other getters/setters ...
}
```

---

## Database Migration (Liquibase or Flyway)

If using Liquibase:
```xml
<changeSet id="add-post-visibility" author="dev">
  <addColumn tableName="posts">
    <column name="visibility" type="VARCHAR(50)" defaultValue="PUBLIC">
      <constraints nullable="false"/>
    </column>
  </addColumn>
  
  <createTable tableName="post_visible_to_close_friends">
    <column name="post_id" type="BIGINT">
      <constraints foreignKeyName="fk_post_visibility_post" 
                  referencedTableName="posts" 
                  referencedColumnName="id"/>
    </column>
    <column name="friend_id" type="BIGINT">
      <constraints foreignKeyName="fk_post_visibility_friend" 
                  referencedTableName="users" 
                  referencedColumnName="id"/>
    </column>
    <addPrimaryKey columnNames="post_id,friend_id"/>
  </createTable>
</changeSet>
```

Or raw SQL:
```sql
-- Add visibility column
ALTER TABLE posts ADD COLUMN visibility VARCHAR(50) NOT NULL DEFAULT 'PUBLIC';

-- Create junction table for close-friends visibility
CREATE TABLE post_visible_to_close_friends (
  post_id BIGINT NOT NULL,
  friend_id BIGINT NOT NULL,
  PRIMARY KEY (post_id, friend_id),
  FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE,
  FOREIGN KEY (friend_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Create index for performance
CREATE INDEX idx_post_visibility ON posts(visibility);
CREATE INDEX idx_post_close_friends ON post_visible_to_close_friends(friend_id);
```

---

## Testing Scenarios

### Test 1: Create Public Post
```bash
POST /api/social/posts
{
  "content": "Hello world!",
  "imageUrls": [],
  "visibility": "PUBLIC"
}

# Expected: Post visible to everyone in feed
```

### Test 2: Create Close-Friends Post
```bash
POST /api/social/posts
{
  "content": "Only for close friends!",
  "imageUrls": [],
  "visibility": "CLOSE_FRIENDS"
}

# Expected: Post visible only to user's close friends
```

### Test 3: View Feed as Close Friend
```bash
GET /api/social/posts/feed?page=0&size=10
(As User B who is close friend of Post Author)

# Expected: 
# - User B sees all public posts
# - User B sees post by Author (because User B is their close friend)
```

### Test 4: View Feed as Non-Friend
```bash
GET /api/social/posts/feed?page=0&size=10
(As User C who is NOT close friend of Post Author)

# Expected:
# - User C sees all public posts
# - User C does NOT see Author's close-friends posts
```

### Test 5: View Own Feed
```bash
GET /api/social/posts/feed?page=0&size=10
(As the Post Author)

# Expected:
# - Author sees all their own posts (public AND close-friends)
# - Author sees all public posts from others
# - Author sees close-friends posts from their close friends
```

---

## Validation Rules

- ✅ Visibility can only be: PUBLIC or CLOSE_FRIENDS
- ✅ Default is PUBLIC (if not specified)
- ✅ Only author can see their close-friends posts if not a close friend
- ✅ Close-friends validation happens server-side
- ✅ No client-side bypass possible

---

## Performance Considerations

1. **Index on visibility**: Makes filtering fast
2. **Cache feed**: Consider caching for 30-60 seconds
3. **Pagination**: Always paginate (default 10 per page)
4. **Lazy loading**: visibleToCloseFriends uses FetchType.LAZY

---

## Logging for Debugging

Add these logs to PostService:
```java
System.out.println("[PostService] 🔒 Created CLOSE_FRIENDS post");
System.out.println("[PostService] 🌐 Created PUBLIC post");
System.out.println("[PostService] 👥 Post visible to " + closeFriends.size() + " friends");
System.out.println("[PostService] 📋 Feed query returned " + posts.size() + " posts for user " + userId);
```

---

## After Backend Implementation

1. Test with Postman/Insomnia
2. Verify database entries
3. Check filtering logic
4. Test edge cases (no close friends, etc.)
5. Run full end-to-end test

Then frontend will automatically:
- ✅ Show privacy toggle
- ✅ Accept visibility input
- ✅ Display posts filtered by backend
- ✅ Show privacy badges

