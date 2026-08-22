# Block Users Feature - Complete Guide

## 🎯 Overview

User safety feature allowing users to block others to prevent unwanted interactions. When you block someone:
- They cannot follow you
- You cannot follow them
- Their posts don't appear in your feed
- They don't appear in search results
- All follow relationships are automatically removed

## 📊 Database Schema

### Blocked Users Table
```sql
CREATE TABLE blocked_users (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    blocker_id BIGINT NOT NULL,
    blocked_id BIGINT NOT NULL,
    reason VARCHAR(200),
    created_at TIMESTAMP NOT NULL,
    
    UNIQUE KEY unique_block (blocker_id, blocked_id),
    INDEX idx_blocker_id (blocker_id),
    INDEX idx_blocked_id (blocked_id)
);
```

## 🔌 API Endpoints

### Base URL
```
http://localhost:8080/api/social/blocks
```

---

### 1. Block a User

**Endpoint:** `POST /blocks/{userId}`

**Request:**
```bash
curl -X POST http://localhost:8080/api/social/blocks/5 \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "reason": "Spam or harassment"
  }'
```

**Response:** `200 OK`
```json
{
  "id": 1,
  "blockedUserId": 5,
  "reason": "Spam or harassment",
  "blockedAt": "2025-12-02T10:30:00"
}
```

---

### 2. Unblock a User

**Endpoint:** `DELETE /blocks/{userId}`

**Request:**
```bash
curl -X DELETE http://localhost:8080/api/social/blocks/5 \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

**Response:** `200 OK`
```json
{
  "message": "User unblocked successfully"
}
```

---

### 3. Check if User is Blocked

**Endpoint:** `GET /blocks/check/{userId}`

**Request:**
```bash
curl -X GET http://localhost:8080/api/social/blocks/check/5 \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

**Response:** `200 OK`
```json
{
  "isBlocked": true
}
```

---

### 4. Check if Either User Blocked the Other

**Endpoint:** `GET /blocks/check-either/{userId}`

**Request:**
```bash
curl -X GET http://localhost:8080/api/social/blocks/check-either/5 \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

**Response:** `200 OK`
```json
{
  "isBlocked": true
}
```

---

### 5. Get Blocked Users List

**Endpoint:** `GET /blocks/my-list?page=0&size=20`

**Request:**
```bash
curl -X GET "http://localhost:8080/api/social/blocks/my-list?page=0&size=20" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

**Response:** `200 OK`
```json
{
  "content": [
    {
      "id": 1,
      "blockedUserId": 5,
      "reason": "Spam",
      "blockedAt": "2025-12-02T10:30:00"
    }
  ],
  "totalElements": 1,
  "totalPages": 1
}
```

---

### 6. Count Blocked Users

**Endpoint:** `GET /blocks/count`

**Request:**
```bash
curl -X GET http://localhost:8080/api/social/blocks/count \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

**Response:** `200 OK`
```json
{
  "count": 3
}
```

---

## 🔒 Block Effects

### Automatic Actions When Blocking:
1. **Removes Follow Relationships** - Both directions are removed
2. **Prevents Future Follows** - Cannot follow each other
3. **Hides from Feed** - Blocked users' posts don't show in your feed
4. **Filters from Search** - Blocked users don't appear in search results
5. **Excludes from Suggestions** - Won't be suggested to follow

### Integration Points:

**FollowerService:**
- `followUser()` - Prevents following if blocked
- Automatically removes follows when blocking

**PostService:**
- `getFeed()` - Filters blocked users from feed

**UserProfileService:**
- `searchUsers()` - Excludes blocked users from results
- `getSuggestedUsers()` - Excludes blocked users

---

## 📈 Usage Examples

### Complete Block Flow

#### 1. Block a User
```bash
POST /blocks/5
Body: { "reason": "Harassment" }
```

#### 2. Verify Block Status
```bash
GET /blocks/check/5
Response: { "isBlocked": true }
```

#### 3. Try to Follow (Will Fail)
```bash
POST /followers/5
Response: 400 - "Cannot follow this user due to block"
```

#### 4. Check Feed (User 5's posts hidden)
```bash
GET /posts/feed
# User 5's posts won't appear
```

#### 5. Search Users (User 5 not in results)
```bash
GET /profiles/search?query=john
# User 5 won't appear if their name matches
```

#### 6. Unblock User
```bash
DELETE /blocks/5
Response: { "message": "User unblocked successfully" }
```

---

## 🎨 Frontend Integration

### React Example

```javascript
// Block a user
const blockUser = async (userId, reason) => {
  const response = await fetch(`/api/social/blocks/${userId}`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ reason })
  });
  
  if (response.ok) {
    alert('User blocked successfully');
  }
};

// Unblock a user
const unblockUser = async (userId) => {
  const response = await fetch(`/api/social/blocks/${userId}`, {
    method: 'DELETE',
    headers: {
      'Authorization': `Bearer ${token}`
    }
  });
  
  if (response.ok) {
    alert('User unblocked successfully');
  }
};

// Check if user is blocked
const checkBlockStatus = async (userId) => {
  const response = await fetch(`/api/social/blocks/check/${userId}`, {
    headers: {
      'Authorization': `Bearer ${token}`
    }
  });
  
  const data = await response.json();
  return data.isBlocked;
};

// Get blocked users list
const getBlockedUsers = async () => {
  const response = await fetch('/api/social/blocks/my-list', {
    headers: {
      'Authorization': `Bearer ${token}`
    }
  });
  
  const data = await response.json();
  return data.content;
};
```

---

## 🎯 Best Practices

### When to Use Block:
- Harassment or abusive behavior
- Spam accounts
- Unwanted contact
- Privacy concerns

### Block Reasons (Optional):
- "Spam"
- "Harassment"
- "Inappropriate content"
- "Impersonation"
- "Other"

### User Experience:
- Show block option on user profiles
- Confirm before blocking
- Allow viewing and managing blocked list
- Provide unblock option
- Don't notify blocked users

---

## ✅ Testing Checklist

- [ ] Block user successfully
- [ ] Cannot follow blocked user
- [ ] Cannot be followed by blocked user
- [ ] Blocked user's posts hidden from feed
- [ ] Blocked user hidden from search
- [ ] Blocked user hidden from suggestions
- [ ] Unblock user successfully
- [ ] Can follow after unblocking
- [ ] View blocked users list
- [ ] Count blocked users
- [ ] Block with reason
- [ ] Block without reason

---

## 🎉 Summary

**Block Users Feature - Fully Implemented!**

✅ **6 REST API endpoints** for block management  
✅ **Automatic follow removal** when blocking  
✅ **Feed filtering** - blocked users' posts hidden  
✅ **Search filtering** - blocked users excluded  
✅ **Follow prevention** - cannot follow blocked users  
✅ **Suggestions filtering** - blocked users excluded  
✅ **Optional block reasons** for tracking  
✅ **Full Swagger documentation**  

**Next Steps:**
- Consider adding report functionality
- Add block analytics for admins
- Implement notification when someone blocks you (optional)
- Add batch block/unblock operations

**Test in Swagger:** http://localhost:8082/swagger-ui.html
