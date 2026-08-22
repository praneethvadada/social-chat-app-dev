# Close Friends Feature - Quick Reference

## 🚀 Quick Start

### Database Migration
```bash
mysql -h <HOST> -u <USER> -p auth_db < backend/migrate_close_friends_feature.sql
```

### Verify Migration
```sql
SELECT * FROM schema_version WHERE version = '2.1.0';
SELECT COUNT(*) FROM close_friends;
SHOW COLUMNS FROM posts LIKE 'visibility';
```

---

## 📝 Code Examples

### Backend - Create Post with Visibility
```java
// PostService.java - Already implemented
PostRequest request = new PostRequest();
request.setContent("Hello close friends!");
request.setVisibility(PostVisibility.CLOSE_FRIENDS);
postService.createPost(request, userId);
```

### Frontend - Create Post with Visibility
```dart
// Create Post Screen - Already implemented
PostVisibility _selectedVisibility = PostVisibility.CLOSE_FRIENDS;

await ref.read(postProvider.notifier).addPost(
  content: "Hello close friends!",
  imageUrls: uploadedUrls,
  visibility: _selectedVisibility.name, // "CLOSE_FRIENDS"
);
```

---

## 🎨 UI Components

### Visibility Dropdown
```dart
DropdownButton<PostVisibility>(
  value: _selectedVisibility,
  items: [
    DropdownMenuItem(
      value: PostVisibility.PUBLIC,
      child: Row(children: [
        Icon(Icons.public, size: 18),
        SizedBox(width: 8),
        Text('Public'),
      ]),
    ),
    DropdownMenuItem(
      value: PostVisibility.CLOSE_FRIENDS,
      child: Row(children: [
        Icon(Icons.star, size: 18, color: Colors.green),
        SizedBox(width: 8),
        Text('Close Friends', style: TextStyle(color: Colors.green)),
      ]),
    ),
  ],
  onChanged: (value) {
    setState(() => _selectedVisibility = value!);
  },
)
```

### Close Friends Badge
```dart
if (post.visibility == PostVisibility.CLOSE_FRIENDS)
  Container(
    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.green.shade100,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: Colors.green),
    ),
    child: Row(children: [
      Icon(Icons.star, size: 11, color: Colors.green.shade700),
      SizedBox(width: 3),
      Text('Close Friends', 
        style: TextStyle(fontSize: 10, color: Colors.green.shade700)),
    ]),
  )
```

---

## 🔍 Testing Commands

### Test Close Friends List
```bash
# Add to close friends
curl -X POST http://localhost:8080/api/social/close-friends/add/{userId} \
  -H "Authorization: Bearer <token>"

# Get close friends
curl http://localhost:8080/api/social/close-friends \
  -H "Authorization: Bearer <token>"
```

### Test Post Creation
```bash
# Create close friends post
curl -X POST http://localhost:8080/api/social/posts \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "Test close friends post",
    "imageUrls": [],
    "visibility": "CLOSE_FRIENDS"
  }'
```

### Test Feed Filtering
```bash
# Get feed (should filter by visibility)
curl http://localhost:8080/api/social/posts/feed \
  -H "Authorization: Bearer <token>"
```

---

## 🐛 Troubleshooting

### Issue: Posts not filtering
**Solution**: Check if CloseFriendService is injected in PostService
```java
private final CloseFriendService closeFriendService; // Must be present
```

### Issue: Visibility dropdown not showing
**Solution**: Import PostVisibility enum in create_post_screen.dart
```dart
import '../../models/post.dart'; // Includes PostVisibility enum
```

### Issue: Badge not showing
**Solution**: Check visibility parsing in Post.fromJson()
```dart
final visibilityStr = json['visibility']?.toString() ?? 'PUBLIC';
final visibility = visibilityStr == 'CLOSE_FRIENDS' 
    ? PostVisibility.CLOSE_FRIENDS 
    : PostVisibility.PUBLIC;
```

---

## 📊 Database Schema

### posts table
```sql
visibility ENUM('PUBLIC', 'CLOSE_FRIENDS') NOT NULL DEFAULT 'PUBLIC'
```

### close_friends table
```sql
CREATE TABLE close_friends (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  user_id BIGINT NOT NULL,
  close_friend_user_id BIGINT NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uk_close_friends_pair (user_id, close_friend_user_id)
);
```

---

## 🎯 Key Files

### Backend
- `Post.java` - PostVisibility enum + visibility field
- `PostService.java` - Visibility filtering logic
- `PostRequest.java` - visibility field
- `PostResponse.java` - visibility field

### Frontend
- `post.dart` - PostVisibility enum + parsing
- `create_post_screen.dart` - Dropdown selector
- `post_card.dart` - Close Friends badge
- `api_service.dart` - API calls with visibility
- `post_service.dart` - State management

### Database
- `COMPLETE_SCHEMA_AWS_PRODUCTION.sql` - Full schema
- `migrate_close_friends_feature.sql` - Migration script

---

## ✅ Verification Checklist

- [ ] Database migration completed
- [ ] visibility column exists in posts table
- [ ] close_friends table exists
- [ ] Backend compiles without errors
- [ ] Frontend builds without errors
- [ ] Can create PUBLIC posts
- [ ] Can create CLOSE_FRIENDS posts
- [ ] Badge shows on CLOSE_FRIENDS posts
- [ ] Badge doesn't show on PUBLIC posts
- [ ] Non-close friends can't see CLOSE_FRIENDS posts
- [ ] Close friends can see CLOSE_FRIENDS posts
- [ ] Can edit post visibility

---

**For full details, see**: `CLOSE_FRIENDS_IMPLEMENTATION_SUMMARY.md`
