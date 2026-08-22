# User Profiles & Search System - Complete Guide

## 🎯 Overview

Complete user profile management and search functionality allowing users to:
- View and edit their profiles
- Search for other users
- Get user suggestions
- View verified users
- Search by location

## 📊 Database Schema

### User Profiles Table
```sql
CREATE TABLE user_profiles (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    user_id BIGINT NOT NULL UNIQUE,
    username VARCHAR(50) NOT NULL UNIQUE,
    full_name VARCHAR(100),
    email VARCHAR(255) NOT NULL UNIQUE,
    bio VARCHAR(500),
    profile_picture_url VARCHAR(500),
    cover_photo_url VARCHAR(500),
    location VARCHAR(100),
    website VARCHAR(200),
    date_of_birth DATE,
    is_private BOOLEAN NOT NULL DEFAULT FALSE,
    is_verified BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP,
    
    INDEX idx_user_id (user_id),
    INDEX idx_username (username)
);
```

**Note:** Table will be auto-created by Hibernate when you start the application.

## 🔌 API Endpoints

### Base URL
```
http://localhost:8080/api/social/profiles
```

All endpoints require **JWT authentication** via `Authorization: Bearer <token>` header.

---

### 1. Get My Profile

**Endpoint:** `GET /profiles/me`

**Description:** Get the authenticated user's profile with statistics.

**Request:**
```bash
curl -X GET http://localhost:8080/api/social/profiles/me \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

**Response:** `200 OK`
```json
{
  "userId": 1,
  "username": "johndoe",
  "fullName": "John Doe",
  "email": "john@example.com",
  "bio": "Software developer and coffee enthusiast ☕",
  "profilePictureUrl": "/files/profile-123.jpg",
  "coverPhotoUrl": "/files/cover-123.jpg",
  "location": "San Francisco, CA",
  "website": "https://johndoe.com",
  "dateOfBirth": "1990-05-15",
  "isPrivate": false,
  "isVerified": false,
  "createdAt": "2025-11-15T10:30:00",
  "updatedAt": "2025-12-01T14:20:00",
  "followersCount": 245,
  "followingCount": 180,
  "postsCount": 52,
  "isFollowing": false,
  "isFollowedBy": false
}
```

---

### 2. Update My Profile

**Endpoint:** `PUT /profiles/me`

**Description:** Update your profile information.

**Request:**
```bash
curl -X PUT http://localhost:8080/api/social/profiles/me \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "fullName": "John Doe Jr.",
    "bio": "Senior Software Engineer | Tech Enthusiast",
    "location": "New York, NY",
    "website": "https://johndoe.dev",
    "isPrivate": false
  }'
```

**Response:** `200 OK`
```json
{
  "userId": 1,
  "username": "johndoe",
  "fullName": "John Doe Jr.",
  "bio": "Senior Software Engineer | Tech Enthusiast",
  ...
}
```

---

### 3. Get User Profile by ID

**Endpoint:** `GET /profiles/user/{userId}`

**Description:** View another user's profile with relationship status.

**Request:**
```bash
curl -X GET http://localhost:8080/api/social/profiles/user/5 \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

**Response:** `200 OK`
```json
{
  "userId": 5,
  "username": "janedoe",
  "fullName": "Jane Doe",
  "bio": "UX Designer",
  "profilePictureUrl": "/files/profile-456.jpg",
  "followersCount": 520,
  "followingCount": 300,
  "postsCount": 89,
  "isFollowing": true,
  "isFollowedBy": false,
  "isPrivate": false,
  "isVerified": true
}
```

---

### 4. Get User Profile by Username

**Endpoint:** `GET /profiles/username/{username}`

**Description:** View a user's profile using their username.

**Request:**
```bash
curl -X GET http://localhost:8080/api/social/profiles/username/janedoe \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

**Response:** Same as endpoint #3

---

### 5. Search Users

**Endpoint:** `GET /profiles/search?query={query}&page=0&size=20`

**Description:** Search for users by username or full name.

**Request:**
```bash
curl -X GET "http://localhost:8080/api/social/profiles/search?query=john&page=0&size=20" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

**Response:** `200 OK`
```json
{
  "content": [
    {
      "userId": 1,
      "username": "johndoe",
      "fullName": "John Doe",
      "bio": "Software developer",
      "profilePictureUrl": "/files/profile-123.jpg",
      "isPrivate": false,
      "isVerified": false,
      "isFollowing": false,
      "followersCount": 245,
      "followingCount": 180
    },
    {
      "userId": 12,
      "username": "johnny_appleseed",
      "fullName": "John Smith",
      "bio": "Entrepreneur",
      "profilePictureUrl": "/files/profile-789.jpg",
      "isPrivate": false,
      "isVerified": true,
      "isFollowing": true,
      "followersCount": 1200,
      "followingCount": 450
    }
  ],
  "pageable": {
    "pageNumber": 0,
    "pageSize": 20
  },
  "totalElements": 2,
  "totalPages": 1
}
```

---

### 6. Search Public Users Only

**Endpoint:** `GET /profiles/search/public?query={query}&page=0&size=20`

**Description:** Search only users with public profiles.

**Request:**
```bash
curl -X GET "http://localhost:8080/api/social/profiles/search/public?query=jane" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

**Response:** Same format as endpoint #5

---

### 7. Get Suggested Users

**Endpoint:** `GET /profiles/suggested?page=0&size=20`

**Description:** Get users you might want to follow (users you don't currently follow).

**Request:**
```bash
curl -X GET "http://localhost:8080/api/social/profiles/suggested?page=0&size=20" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

**Response:** `200 OK`
```json
{
  "content": [
    {
      "userId": 15,
      "username": "alex_tech",
      "fullName": "Alex Johnson",
      "bio": "Full-stack developer",
      "profilePictureUrl": "/files/profile-990.jpg",
      "isPrivate": false,
      "isVerified": false,
      "isFollowing": false,
      "followersCount": 340,
      "followingCount": 220
    }
  ],
  "totalElements": 15
}
```

---

### 8. Get Verified Users

**Endpoint:** `GET /profiles/verified?page=0&size=20`

**Description:** Get a list of verified users on the platform.

**Request:**
```bash
curl -X GET "http://localhost:8080/api/social/profiles/verified" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

**Response:** List of verified users (same format as search)

---

### 9. Search Users by Location

**Endpoint:** `GET /profiles/location?location={location}&page=0&size=20`

**Description:** Find users in a specific location.

**Request:**
```bash
curl -X GET "http://localhost:8080/api/social/profiles/location?location=New%20York" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

**Response:** List of users in that location

---

### 10. Get User Profiles in Bulk

**Endpoint:** `POST /profiles/bulk`

**Description:** Get multiple user profiles by IDs (useful for follower/following lists).

**Request:**
```bash
curl -X POST http://localhost:8080/api/social/profiles/bulk \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '[1, 2, 5, 8, 12]'
```

**Response:** `200 OK`
```json
[
  {
    "userId": 1,
    "username": "johndoe",
    "fullName": "John Doe",
    ...
  },
  {
    "userId": 2,
    "username": "janedoe",
    ...
  }
]
```

---

## 💡 Usage Examples

### Complete User Flow

#### 1. Get Your Profile
```bash
TOKEN="your_jwt_token"

curl -X GET http://localhost:8080/api/social/profiles/me \
  -H "Authorization: Bearer $TOKEN"
```

#### 2. Update Your Profile
```bash
curl -X PUT http://localhost:8080/api/social/profiles/me \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "fullName": "John Doe",
    "bio": "Passionate developer 💻",
    "location": "San Francisco, CA",
    "website": "https://johndoe.dev",
    "profilePictureUrl": "/files/my-photo.jpg"
  }'
```

#### 3. Search for Users
```bash
curl -X GET "http://localhost:8080/api/social/profiles/search?query=jane" \
  -H "Authorization: Bearer $TOKEN"
```

#### 4. View Someone's Profile
```bash
curl -X GET http://localhost:8080/api/social/profiles/user/5 \
  -H "Authorization: Bearer $TOKEN"
```

#### 5. Follow the User (using Followers API)
```bash
curl -X POST http://localhost:8080/api/social/followers/5 \
  -H "Authorization: Bearer $TOKEN"
```

#### 6. Get Suggested Users to Follow
```bash
curl -X GET "http://localhost:8080/api/social/profiles/suggested?size=10" \
  -H "Authorization: Bearer $TOKEN"
```

---

## 🎨 Frontend Integration

### React Example

```javascript
// Get my profile
const getMyProfile = async () => {
  const response = await fetch('/api/social/profiles/me', {
    headers: {
      'Authorization': `Bearer ${localStorage.getItem('token')}`
    }
  });
  
  const profile = await response.json();
  console.log(profile);
};

// Update profile
const updateProfile = async (profileData) => {
  const response = await fetch('/api/social/profiles/me', {
    method: 'PUT',
    headers: {
      'Authorization': `Bearer ${localStorage.getItem('token')}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(profileData)
  });
  
  return await response.json();
};

// Search users
const searchUsers = async (query) => {
  const response = await fetch(
    `/api/social/profiles/search?query=${encodeURIComponent(query)}`,
    {
      headers: {
        'Authorization': `Bearer ${localStorage.getItem('token')}`
      }
    }
  );
  
  const results = await response.json();
  return results.content;
};

// Get suggested users
const getSuggestedUsers = async () => {
  const response = await fetch('/api/social/profiles/suggested?size=10', {
    headers: {
      'Authorization': `Bearer ${localStorage.getItem('token')}`
    }
  });
  
  const results = await response.json();
  return results.content;
};
```

### JavaScript (Vanilla)

```javascript
// Search users as you type
document.getElementById('searchInput').addEventListener('input', async (e) => {
  const query = e.target.value;
  
  if (query.length < 2) return;
  
  const response = await fetch(
    `/api/social/profiles/search?query=${query}&size=5`,
    {
      headers: {
        'Authorization': `Bearer ${token}`
      }
    }
  );
  
  const data = await response.json();
  displaySearchResults(data.content);
});

function displaySearchResults(users) {
  const resultsDiv = document.getElementById('searchResults');
  resultsDiv.innerHTML = users.map(user => `
    <div class="user-result">
      <img src="${user.profilePictureUrl}" alt="${user.username}">
      <div>
        <h4>${user.fullName} ${user.isVerified ? '✓' : ''}</h4>
        <p>@${user.username}</p>
        <p>${user.bio}</p>
        <span>${user.followersCount} followers</span>
        ${!user.isFollowing ? 
          `<button onclick="followUser(${user.userId})">Follow</button>` :
          `<button onclick="unfollowUser(${user.userId})">Following</button>`
        }
      </div>
    </div>
  `).join('');
}
```

---

## 🔍 Profile Fields

### Required Fields (set during registration)
- `userId` - Links to auth-service user
- `username` - Unique username
- `email` - User's email

### Optional Fields (editable)
- `fullName` - Display name
- `bio` - Profile description (max 500 chars)
- `profilePictureUrl` - Profile picture path
- `coverPhotoUrl` - Cover photo path
- `location` - User's location
- `website` - Personal website
- `dateOfBirth` - Birthday
- `isPrivate` - Private account flag

### System Fields (read-only)
- `isVerified` - Verified badge
- `createdAt` - Account creation date
- `updatedAt` - Last profile update

### Computed Statistics
- `followersCount` - Number of followers
- `followingCount` - Number following
- `postsCount` - Total posts
- `isFollowing` - Follow relationship
- `isFollowedBy` - Mutual follow status

---

## 🚀 Search Features

### 1. Basic Search
Search by username or full name (case-insensitive, partial match)

### 2. Public Search
Returns only users with `isPrivate = false`

### 3. Suggested Users
Shows users you don't follow yet (excludes yourself and current follows)

### 4. Verified Users
Filter for verified accounts only

### 5. Location Search
Find users in specific locations

### 6. Bulk Lookup
Get multiple profiles at once (useful for follower lists)

---

## 📈 Profile Statistics

Each profile includes real-time statistics:
- **Followers Count** - Number of people following this user
- **Following Count** - Number of users this person follows  
- **Posts Count** - Total posts created
- **Relationship Status** - Your follow relationship with this user

---

## 🔒 Privacy Features

### Private Profiles
Users can set `isPrivate = true` to:
- Hide from public search results
- Restrict profile visibility
- Control who can see their posts

### Verified Badges
Accounts marked `isVerified = true` display a verification badge.

---

## 🎯 Integration Points

### With Followers System
- Profile stats include follower/following counts
- `isFollowing` and `isFollowedBy` show relationship
- Suggested users exclude current follows

### With Posts System
- Profile shows total posts count
- Can navigate from profile to user's posts via `/posts/user/{userId}`

### With Auth Service
- Profiles are created when users register
- `userId` links to auth-service User table
- Username and email synchronized

---

## 🧪 Testing Workflow

### 1. View Your Profile
```bash
GET /profiles/me
```

### 2. Update Profile
```bash
PUT /profiles/me
Body: { "bio": "New bio", "location": "NYC" }
```

### 3. Search for Users
```bash
GET /profiles/search?query=john
```

### 4. View Someone's Profile
```bash
GET /profiles/user/5
```

### 5. Get Suggestions
```bash
GET /profiles/suggested
```

### 6. Follow a User
```bash
POST /followers/5
```

### 7. Check Updated Profile
```bash
GET /profiles/user/5
# isFollowing should now be true
```

---

## 🎉 Summary

**User Profiles & Search System - Fully Implemented!**

✅ **10 REST API endpoints** for complete profile management  
✅ **Profile CRUD** (view, edit)  
✅ **Advanced search** (username, name, location)  
✅ **User suggestions** algorithm  
✅ **Verified users** filtering  
✅ **Bulk profile lookup** for efficiency  
✅ **Real-time statistics** (followers, following, posts)  
✅ **Relationship status** tracking  
✅ **Privacy controls** (private accounts)  
✅ **Swagger documentation** for all endpoints  
✅ **Database indexes** for fast queries  

**Next Steps:**
- Profiles are auto-created when users register in auth-service
- Consider adding profile picture upload endpoint
- Implement username change with validation
- Add profile view/visitor tracking
- Create "People You May Know" algorithm based on mutual connections

**Test in Swagger:** http://localhost:8082/swagger-ui.html
