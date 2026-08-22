# Complete Flow Trace: Login → Profile Display

## Current Implementation Status

### Backend Services (Running)
- **Auth Service** (port 8081): Handles registration, login, token refresh
- **Social Service** (port 8082): Manages user profiles and social features  
- **API Gateway** (port 8080): Routes requests to appropriate services

### Key Changes Made

#### 1. AuthResponse DTO (auth-service)
✅ Added fullName field to include user's full name in auth responses
- Constructor updated to accept fullName parameter
- Getters/setters added for fullName field

#### 2. AuthService.java (auth-service)
✅ Updated three response methods to include fullName:
- `register()`: Returns fullName from savedUser.getFullName()
- `login()`: Returns fullName from user.getFullName()
- `refreshToken()`: Returns fullName from existing auth response

#### 3. API Gateway Configuration
✅ Fixed social-service routing from port 8081 → 8082

#### 4. Mobile App - api_service.dart
✅ Added local data storage for user info:
- Constants: `_usernameKey`, `_emailKey`, `_fullNameKey`
- Methods: `getUsername()`, `getEmail()`, `getFullName()`
- `login()` extracts and stores username, email, fullName from response
- `register()` extracts and stores username, email, fullName from response
- `clearSession()` removes all user data on logout
- Added debug logging to trace data flow

#### 5. ProfileScreen (mobile app)
✅ Simplified to:
- Call `getMyProfile()` API on init
- Display fetched data (fullName, username, bio, counts)
- Removed auto-create logic

---

## Expected Flow (End-to-End)

### Step 1: Registration
```
Mobile App (SignUp)
  ↓
POST /api/auth/register 
  email: "test@gmail.com"
  password: "password123"
  username: "testuser"
  fullName: "Test User"
  ↓
Auth Service (port 8081)
  ↓ 
Return AuthResponse {
  accessToken: "jwt...",
  refreshToken: "jwt...",
  userId: 13,
  username: "testuser",
  email: "test@gmail.com",
  fullName: "Test User"  ← THIS IS CRITICAL
}
  ↓
Mobile App Stores in SharedPreferences:
  - accessToken
  - userId
  - username: "testuser"
  - email: "test@gmail.com"
  - fullName: "Test User"  ← THIS MUST BE STORED
```

### Step 2: Login
```
Mobile App (LoginScreen) 
  ↓
POST /api/auth/login
  email: "test@gmail.com"
  password: "password123"
  ↓
Auth Service (port 8081)
  ↓
Return AuthResponse {
  accessToken: "jwt...",
  userId: 13,
  username: "testuser",
  email: "test@gmail.com",
  fullName: "Test User"  ← MUST INCLUDE THIS
}
  ↓
Mobile App:
  1. Extract fullName from response
  2. Store in SharedPreferences with key 'fullName'
  3. Save token, userId, username, email, fullName
  4. Navigate to /home
```

### Step 3: ProfileScreen Display
```
Mobile App (HomeScreen → ProfileScreen tab)
  ↓
initState → _loadProfile()
  ↓
Call GET /api/social/profiles/me
  Header: Authorization: Bearer {accessToken}
  ↓
API Gateway (8080)
  ↓ (StripPrefix /api/social)
  ↓
Social Service (8082)
  ↓
GET /profiles/me
  ↓
Return UserProfile {
  id: 13,
  userId: 13,
  username: "testuser",
  fullName: "Test User",  ← MUST RETURN THIS
  bio: "My bio",
  profilePictureUrl: "...",
  postsCount: 0,
  followersCount: 0,
  followingCount: 0
}
  ↓
Mobile App ProfileScreen:
  1. Receive profile data
  2. Extract fullName, username, bio, counts
  3. setState() to display data
  4. Show: "Test User" (fullName, not "User 13")
```

---

## Verification Points

### 1. Database Check
```sql
SELECT id, username, email, fullName FROM users WHERE username = 'testuser';
SELECT id, userId, username, fullName FROM user_profiles WHERE userId = 13;
```

### 2. API Response Validation
Check that auth response includes:
- ✅ accessToken
- ✅ userId
- ✅ username
- ✅ email
- **✅ fullName** (THIS IS THE KEY FIELD)

### 3. Mobile App Storage
After login, SharedPreferences should contain:
- `accessToken`: "jwt..."
- `userId`: 13
- `username`: "testuser"
- `email`: "test@gmail.com"
- **`fullName`: "Test User"** (THIS MUST BE STORED)

### 4. Profile Display
ProfileScreen should show:
- **fullName: "Test User"** (from API response)
- NOT "User 13" (placeholder)
- NOT static data

---

## Debug Logging Added

### api_service.dart
```dart
// login() method now prints:
[DEBUG] Login: Calling /auth/login with email=$email
[DEBUG] Login Response Status: 200
[DEBUG] Login Response Body: {...}
[DEBUG] Extracted from response: userId=13, username=testuser, email=..., fullName=Test User
[DEBUG] Storing session data in SharedPreferences
[DEBUG] Session stored successfully

// getMyProfile() method now prints:
[DEBUG] getMyProfile: Calling /social/profiles/me with token=$token
[DEBUG] getMyProfile Response Status: 200
[DEBUG] getMyProfile Response Body: {...}
[DEBUG] Profile data received: {...}
```

### profile_screen.dart
```dart
[DEBUG] _loadProfile: Fetching profile from backend
[DEBUG] _loadProfile: Received profile: {...}
[DEBUG] _loadProfile: Set state - fullName=Test User, username=testuser
```

---

## What Should Happen Next

1. **Register a test user** via mobile app
   - Should see: `[DEBUG] Extracted from response: ... fullName=Test User`
   
2. **Navigate to Profile screen**
   - Should see: `[DEBUG] _loadProfile: Set state - fullName=Test User`
   
3. **Profile should display**
   - fullName: "Test User" (NOT "User 13")
   - username: "testuser" (NOT static data)

---

## Services Status
- ✅ Auth Service (8081) - Running
- ✅ Social Service (8082) - Running
- ✅ API Gateway (8080) - Started

**Note**: Check debug console in mobile app to verify logs match this trace
