# Close Friends Backend Implementation Guide

## Current Status
✅ **Frontend**: Implemented in `privacy_settings_screen.dart`
❌ **Backend**: Not yet implemented
⚠️ **Storage**: Currently using local SharedPreferences (not persistent across devices)

## What's Needed in Backend

### 1. Database Schema
Create a new table `close_friends`:

```sql
CREATE TABLE close_friends (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    close_friend_user_id BIGINT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (close_friend_user_id) REFERENCES users(id) ON DELETE CASCADE,
    UNIQUE KEY unique_close_friend (user_id, close_friend_user_id)
);
```

### 2. Backend Entity (Java)
File: `backend/social-service/src/main/java/com/socialmedia/social/entity/CloseFriend.java`

```java
@Entity
@Table(name = "close_friends")
@Data
@NoArgsConstructor
@AllArgsConstructor
public class CloseFriend {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    
    @Column(name = "user_id", nullable = false)
    private Long userId;
    
    @Column(name = "close_friend_user_id", nullable = false)
    private Long closeFriendUserId;
    
    @Column(name = "created_at")
    private LocalDateTime createdAt;
    
    @PrePersist
    protected void onCreate() {
        createdAt = LocalDateTime.now();
    }
}
```

### 3. Repository
File: `backend/social-service/src/main/java/com/socialmedia/social/repository/CloseFriendRepository.java`

```java
public interface CloseFriendRepository extends JpaRepository<CloseFriend, Long> {
    List<CloseFriend> findByUserId(Long userId);
    
    boolean existsByUserIdAndCloseFriendUserId(Long userId, Long closeFriendUserId);
    
    void deleteByUserIdAndCloseFriendUserId(Long userId, Long closeFriendUserId);
    
    @Query("SELECT cf.closeFriendUserId FROM CloseFriend cf WHERE cf.userId = :userId")
    List<Long> findCloseFriendIdsByUserId(@Param("userId") Long userId);
}
```

### 4. Service
File: `backend/social-service/src/main/java/com/socialmedia/social/service/CloseFriendService.java`

```java
@Service
@RequiredArgsConstructor
public class CloseFriendService {
    private final CloseFriendRepository closeFriendRepository;
    private final UserProfileRepository userProfileRepository;
    
    public List<UserProfile> getCloseFriends(Long userId) {
        List<Long> closeFriendIds = closeFriendRepository.findCloseFriendIdsByUserId(userId);
        return userProfileRepository.findAllById(closeFriendIds);
    }
    
    public void addCloseFriend(Long userId, Long friendUserId) {
        if (closeFriendRepository.existsByUserIdAndCloseFriendUserId(userId, friendUserId)) {
            throw new RuntimeException("User is already in close friends");
        }
        CloseFriend closeFriend = new CloseFriend();
        closeFriend.setUserId(userId);
        closeFriend.setCloseFriendUserId(friendUserId);
        closeFriendRepository.save(closeFriend);
    }
    
    public void removeCloseFriend(Long userId, Long friendUserId) {
        closeFriendRepository.deleteByUserIdAndCloseFriendUserId(userId, friendUserId);
    }
    
    public boolean isCloseFriend(Long userId, Long potentialFriendId) {
        return closeFriendRepository.existsByUserIdAndCloseFriendUserId(userId, potentialFriendId);
    }
}
```

### 5. Controller
File: `backend/social-service/src/main/java/com/socialmedia/social/controller/CloseFriendController.java`

```java
@RestController
@RequestMapping("/close-friends")
@RequiredArgsConstructor
public class CloseFriendController {
    private final CloseFriendService closeFriendService;
    
    @GetMapping
    public ResponseEntity<List<UserProfile>> getCloseFriends(
            @RequestAttribute("userId") Long userId
    ) {
        return ResponseEntity.ok(closeFriendService.getCloseFriends(userId));
    }
    
    @PostMapping("/{friendUserId}")
    public ResponseEntity<Void> addCloseFriend(
            @RequestAttribute("userId") Long userId,
            @PathVariable Long friendUserId
    ) {
        closeFriendService.addCloseFriend(userId, friendUserId);
        return ResponseEntity.ok().build();
    }
    
    @DeleteMapping("/{friendUserId}")
    public ResponseEntity<Void> removeCloseFriend(
            @RequestAttribute("userId") Long userId,
            @PathVariable Long friendUserId
    ) {
        closeFriendService.removeCloseFriend(userId, friendUserId);
        return ResponseEntity.ok().build();
    }
}
```

### 6. Frontend API Service Update
File: `social-media-mobile/lib/src/services/api_service.dart`

Add these methods:

```dart
// Get close friends list
static Future<List<Map<String, dynamic>>> getCloseFriends() async {
  final token = await getToken();
  if (token == null) throw Exception('Not authenticated');

  final response = await http.get(
    Uri.parse('$baseUrl/social/close-friends'),
    headers: {'Authorization': 'Bearer $token'},
  );

  if (response.statusCode == 200) {
    final List<dynamic> data = json.decode(response.body);
    return data.cast<Map<String, dynamic>>();
  }
  throw Exception('Failed to load close friends');
}

// Add close friend
static Future<void> addCloseFriend(int friendUserId) async {
  final token = await getToken();
  if (token == null) throw Exception('Not authenticated');

  final response = await http.post(
    Uri.parse('$baseUrl/social/close-friends/$friendUserId'),
    headers: {'Authorization': 'Bearer $token'},
  );

  if (response.statusCode != 200) {
    throw Exception('Failed to add close friend');
  }
}

// Remove close friend
static Future<void> removeCloseFriend(int friendUserId) async {
  final token = await getToken();
  if (token == null) throw Exception('Not authenticated');

  final response = await http.delete(
    Uri.parse('$baseUrl/social/close-friends/$friendUserId'),
    headers: {'Authorization': 'Bearer $token'},
  );

  if (response.statusCode != 200) {
    throw Exception('Failed to remove close friend');
  }
}
```

### 7. Update Frontend Privacy Settings
File: `social-media-mobile/lib/src/screens/settings/privacy_settings_screen.dart`

Replace the current local storage implementation with API calls to the backend.

## Benefits After Implementation
- ✅ Close friends list synced across all devices
- ✅ Can show "Close Friends Only" posts (future feature)
- ✅ Better privacy control
- ✅ Server-side validation
- ✅ Can use in story features (like Instagram)
