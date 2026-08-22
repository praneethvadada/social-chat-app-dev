# Followers System - Complete Implementation Guide

## 🎯 Overview

The Followers System enables users to follow/unfollow each other, view follower/following lists, check relationship status, and get personalized feed from followed users.

## 📊 Database Schema

### Followers Table
```sql
CREATE TABLE followers (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    follower_id BIGINT NOT NULL,      -- User who is following
    following_id BIGINT NOT NULL,     -- User being followed
    created_at TIMESTAMP NOT NULL,
    
    UNIQUE KEY uk_follower_following (follower_id, following_id),
    INDEX idx_follower_id (follower_id),
    INDEX idx_following_id (following_id)
);
```

**Note:** The table will be auto-created by Hibernate when you start the application.

## 🔌 API Endpoints

### Base URL
```
http://localhost:8080/api/social/followers
```

All endpoints require **JWT authentication** via `Authorization: Bearer <token>` header.

---

### 1. Follow a User

**Endpoint:** `POST /followers/{userId}`

**Description:** Create a follow relationship with another user.

**Request:**
```bash
curl -X POST http://localhost:8080/api/social/followers/5 \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

**Response:** `200 OK`
```json
{
  "message": "Successfully followed user",
  "followingUserId": "5"
}
```

**Errors:**
- `400 Bad Request` - Cannot follow yourself or already following
- `401 Unauthorized` - Invalid/missing JWT token

---

### 2. Unfollow a User

**Endpoint:** `DELETE /followers/{userId}`

**Description:** Remove a follow relationship.

**Request:**
```bash
curl -X DELETE http://localhost:8080/api/social/followers/5 \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

**Response:** `200 OK`
```json
{
  "message": "Successfully unfollowed user",
  "unfollowedUserId": "5"
}
```

**Errors:**
- `400 Bad Request` - Not following this user
- `401 Unauthorized` - Invalid/missing JWT token

---

### 3. Check Follow Status

**Endpoint:** `GET /followers/check/{userId}`

**Description:** Check if you are following a specific user.

**Request:**
```bash
curl -X GET http://localhost:8080/api/social/followers/check/5 \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

**Response:** `200 OK`
```json
{
  "isFollowing": true
}
```

---

### 4. Get User's Followers

**Endpoint:** `GET /followers/user/{userId}?page=0&size=20`

**Description:** Get a paginated list of users who follow the specified user.

**Request:**
```bash
curl -X GET "http://localhost:8080/api/social/followers/user/5?page=0&size=20" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

**Response:** `200 OK`
```json
{
  "content": [
    {
      "id": 123,
      "userId": 3,
      "followedAt": "2025-12-01T10:30:00"
    },
    {
      "id": 124,
      "userId": 7,
      "followedAt": "2025-12-01T11:45:00"
    }
  ],
  "pageable": {
    "pageNumber": 0,
    "pageSize": 20,
    "sort": {
      "sorted": true,
      "unsorted": false,
      "empty": false
    }
  },
  "totalPages": 3,
  "totalElements": 52,
  "last": false,
  "first": true,
  "size": 20,
  "number": 0
}
```

**Fields:**
- `id` - Follow relationship ID
- `userId` - ID of the follower (person who follows)
- `followedAt` - When the follow relationship was created

---

### 5. Get Users Following

**Endpoint:** `GET /followers/user/{userId}/following?page=0&size=20`

**Description:** Get a paginated list of users that the specified user is following.

**Request:**
```bash
curl -X GET "http://localhost:8080/api/social/followers/user/5/following?page=0&size=20" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

**Response:** `200 OK`
```json
{
  "content": [
    {
      "id": 125,
      "userId": 8,
      "followedAt": "2025-11-28T14:20:00"
    },
    {
      "id": 126,
      "userId": 12,
      "followedAt": "2025-11-29T09:15:00"
    }
  ],
  "totalElements": 38,
  "totalPages": 2
}
```

**Fields:**
- `id` - Follow relationship ID
- `userId` - ID of the user being followed
- `followedAt` - When started following

---

### 6. Get Follower Statistics

**Endpoint:** `GET /followers/user/{userId}/stats`

**Description:** Get comprehensive statistics about a user's followers and relationship status.

**Request:**
```bash
curl -X GET http://localhost:8080/api/social/followers/user/5/stats \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

**Response:** `200 OK`
```json
{
  "userId": 5,
  "followersCount": 152,
  "followingCount": 89,
  "isFollowing": true,
  "isFollowedBy": false,
  "isMutual": false
}
```

**Fields:**
- `userId` - Target user ID
- `followersCount` - Number of followers this user has
- `followingCount` - Number of users this user follows
- `isFollowing` - Does the requesting user follow this user?
- `isFollowedBy` - Does this user follow the requesting user back?
- `isMutual` - Do they follow each other? (friends)

---

### 7. Get Mutual Followers

**Endpoint:** `GET /followers/mutual?page=0&size=20`

**Description:** Get users who follow each other with you (mutual friends).

**Request:**
```bash
curl -X GET "http://localhost:8080/api/social/followers/mutual?page=0&size=20" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

**Response:** `200 OK`
```json
{
  "content": [
    {
      "id": 130,
      "userId": 15,
      "followedAt": "2025-11-25T16:30:00"
    }
  ],
  "totalElements": 23
}
```

---

## 🔄 Personalized Feed Integration

The feed now shows posts **only from users you follow** (plus your own posts).

**Endpoint:** `GET /posts/feed?page=0&size=20`

**Request:**
```bash
curl -X GET "http://localhost:8080/api/social/posts/feed?page=0&size=20" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

**Response:** `200 OK`
```json
{
  "content": [
    {
      "id": 45,
      "userId": 8,
      "content": "Post from someone I follow",
      "imageUrls": [],
      "likesCount": 12,
      "commentsCount": 3,
      "createdAt": "2025-12-02T10:00:00"
    }
  ]
}
```

**Behavior:**
- Shows posts from users you follow
- Includes your own posts
- Returns empty if you don't follow anyone
- Sorted by creation date (newest first)

---

## 💡 Usage Examples

### Complete User Flow

#### 1. Register & Login
```bash
# Register
curl -X POST http://localhost:8080/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "alice",
    "email": "alice@example.com",
    "password": "password123",
    "fullName": "Alice Smith"
  }'

# Save the accessToken
TOKEN="eyJhbGciOiJIUzI1NiJ9..."
```

#### 2. Follow Users
```bash
# Follow user ID 2
curl -X POST http://localhost:8080/api/social/followers/2 \
  -H "Authorization: Bearer $TOKEN"

# Follow user ID 3
curl -X POST http://localhost:8080/api/social/followers/3 \
  -H "Authorization: Bearer $TOKEN"

# Follow user ID 5
curl -X POST http://localhost:8080/api/social/followers/5 \
  -H "Authorization: Bearer $TOKEN"
```

#### 3. Check Your Following List
```bash
curl -X GET "http://localhost:8080/api/social/followers/user/1/following" \
  -H "Authorization: Bearer $TOKEN"
```

#### 4. View Personalized Feed
```bash
# See posts from users 2, 3, and 5 only
curl -X GET "http://localhost:8080/api/social/posts/feed?page=0&size=20" \
  -H "Authorization: Bearer $TOKEN"
```

#### 5. Check Who Follows You Back
```bash
curl -X GET http://localhost:8080/api/social/followers/user/1/stats \
  -H "Authorization: Bearer $TOKEN"
```

#### 6. View Mutual Friends
```bash
curl -X GET "http://localhost:8080/api/social/followers/mutual?page=0&size=20" \
  -H "Authorization: Bearer $TOKEN"
```

#### 7. Unfollow Someone
```bash
curl -X DELETE http://localhost:8080/api/social/followers/3 \
  -H "Authorization: Bearer $TOKEN"
```

---

## 🧪 Testing with Swagger UI

1. **Start the application**
2. **Open Swagger UI:** http://localhost:8082/swagger-ui.html
3. **Register a user** via Auth Service
4. **Click "Authorize"** and paste your JWT token
5. **Test endpoints** under the "Followers" section

---

## 🎨 Frontend Integration Examples

### React Example

```javascript
// Follow a user
const followUser = async (userId) => {
  const response = await fetch(`/api/social/followers/${userId}`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${localStorage.getItem('token')}`
    }
  });
  
  if (response.ok) {
    alert('Followed successfully!');
  }
};

// Get follower stats
const getStats = async (userId) => {
  const response = await fetch(`/api/social/followers/user/${userId}/stats`, {
    headers: {
      'Authorization': `Bearer ${localStorage.getItem('token')}`
    }
  });
  
  const stats = await response.json();
  console.log(`Followers: ${stats.followersCount}`);
  console.log(`Following: ${stats.followingCount}`);
  console.log(`Mutual: ${stats.isMutual}`);
};

// Get personalized feed
const getFeed = async () => {
  const response = await fetch('/api/social/posts/feed?page=0&size=20', {
    headers: {
      'Authorization': `Bearer ${localStorage.getItem('token')}`
    }
  });
  
  const feed = await response.json();
  return feed.content;
};
```

### JavaScript (Vanilla)

```javascript
// Follow button click handler
document.getElementById('followBtn').addEventListener('click', async () => {
  const userId = document.getElementById('profileUserId').value;
  
  const response = await fetch(`/api/social/followers/${userId}`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`
    }
  });
  
  if (response.ok) {
    document.getElementById('followBtn').textContent = 'Following';
    document.getElementById('followBtn').disabled = true;
  }
});
```

---

## 🔍 Business Logic

### Follow Rules
1. ✅ Users can follow any other user
2. ❌ Users **cannot** follow themselves
3. ❌ Users **cannot** follow the same user twice
4. ✅ Follow relationships are **one-way** (not mutual by default)
5. ✅ User A can follow User B without User B following back

### Feed Algorithm
1. Query all users that current user follows
2. Add current user's own ID to the list
3. Fetch posts from all these users
4. Sort by creation date (newest first)
5. Return paginated results

### Unfollow Rules
1. ✅ Can unfollow any user you're currently following
2. ❌ Cannot unfollow if not following
3. ✅ Unfollowing is instant (no confirmation)

---

## 🚀 Performance Optimizations

### Database Indexes
```sql
-- Automatically created by JPA
CREATE INDEX idx_follower_id ON followers(follower_id);
CREATE INDEX idx_following_id ON followers(following_id);
CREATE UNIQUE INDEX uk_follower_following ON followers(follower_id, following_id);
```

### Query Optimization
- Uses `@Query` annotations for efficient queries
- Paginated results to avoid loading too much data
- Indexed columns for fast lookups
- `EXISTS` checks instead of `COUNT` for better performance

---

## 📈 Analytics Queries

### Get Top Followed Users
```java
// Add to FollowerRepository
@Query("SELECT f.followingId, COUNT(f) as cnt FROM Follower f " +
       "GROUP BY f.followingId ORDER BY cnt DESC")
List<Object[]> findTopFollowedUsers(Pageable pageable);
```

### Get Most Active Followers
```java
// Add to FollowerRepository
@Query("SELECT f.followerId, COUNT(f) as cnt FROM Follower f " +
       "GROUP BY f.followerId ORDER BY cnt DESC")
List<Object[]> findMostActiveFollowers(Pageable pageable);
```

---

## 🐛 Troubleshooting

### Issue: "Already following this user"
**Solution:** Check if you're already following by calling `/followers/check/{userId}` first.

### Issue: Empty feed after following users
**Solution:** Make sure the users you follow have created public posts.

### Issue: Cannot follow user
**Possible causes:**
1. Trying to follow yourself
2. Already following this user
3. Invalid JWT token
4. User ID doesn't exist

---

## 📝 Database Migration (If Needed)

If the `followers` table doesn't auto-create:

```sql
CREATE TABLE followers (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    follower_id BIGINT NOT NULL,
    following_id BIGINT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_follower_following (follower_id, following_id),
    KEY idx_follower_id (follower_id),
    KEY idx_following_id (following_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

---

## ✅ Testing Checklist

- [ ] Can follow a user
- [ ] Cannot follow yourself
- [ ] Cannot follow same user twice
- [ ] Can unfollow a user
- [ ] Get followers list returns correct users
- [ ] Get following list returns correct users
- [ ] Follower counts are accurate
- [ ] isFollowing status is correct
- [ ] Feed shows only followed users' posts
- [ ] Feed includes own posts
- [ ] Mutual followers query works
- [ ] Pagination works for all endpoints
- [ ] JWT authentication required for all endpoints

---

## 🎉 Summary

The Followers System is now **fully implemented** with:

✅ **7 REST API endpoints** for comprehensive follower management  
✅ **Personalized feed** showing posts from followed users  
✅ **Follower statistics** with mutual follow detection  
✅ **Paginated results** for scalability  
✅ **Database indexes** for performance  
✅ **Swagger documentation** for easy testing  
✅ **JWT authentication** for security  

**Next Steps:**
- Implement user profile endpoints to display follower/following counts
- Add notifications when someone follows you
- Implement suggested users to follow
- Add follow recommendations based on mutual connections
