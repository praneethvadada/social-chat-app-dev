# Database Schema Verification Report

## Database Overview

The project uses **2 separate MySQL databases**:
- **`auth_db`** - Authentication service (port 8081)
- **`social_db`** - Social features service (port 8082)

Schema generation: `spring.jpa.hibernate.ddl-auto=update` (auto-generated from JPA entities)

---

## 🔴 **CRITICAL ISSUE FOUND: Data Split Problem**

### **Current Configuration:**
- **auth-service** → `auth_db` database
- **social-service** → `social_db` database  

### **Problem:**
User data exists in **TWO PLACES**:
1. **`auth_db.users`** table - managed by auth-service (registration, login)
2. **`social_db.user_profile`** table - managed by social-service (profile display, posts)

This causes **data synchronization issues**:
- Username/fullName updated in auth_db → NOT reflected in user_profile table
- Profile shows "User 11" placeholders because user_profile is out of sync

---

## Database: **auth_db**

### Table: `users`
**Entity:** `com.socialmedia.auth.entity.User`

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | BIGINT | PRIMARY KEY, AUTO_INCREMENT | ✅ |
| username | VARCHAR(50) | NOT NULL, UNIQUE | ✅ |
| email | VARCHAR(100) | NOT NULL, UNIQUE | ✅ |
| password | VARCHAR(255) | NOT NULL | ✅ Hashed |
| full_name | VARCHAR(100) | NULL | ✅ |
| bio | VARCHAR(500) | NULL | ✅ |
| profile_picture | VARCHAR(255) | NULL | ✅ |
| enabled | BOOLEAN | NOT NULL, DEFAULT TRUE | ✅ |
| account_non_locked | BOOLEAN | NOT NULL, DEFAULT TRUE | ✅ |
| failed_login_attempts | INT | NOT NULL, DEFAULT 0 | ✅ |
| last_login | DATETIME | NULL | ✅ |
| created_at | DATETIME | NOT NULL | ✅ Auto-set |
| updated_at | DATETIME | NOT NULL | ✅ Auto-set |

### Table: `user_roles`
**Relation:** User roles (ElementCollection)

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| user_id | BIGINT | FOREIGN KEY → users(id) | ✅ |
| role | VARCHAR(255) | NOT NULL | ✅ (USER, ADMIN) |

### Table: `password_reset_token`
**Entity:** `com.socialmedia.auth.entity.PasswordResetToken`

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | BIGINT | PRIMARY KEY, AUTO_INCREMENT | ✅ |
| user_id | BIGINT | NOT NULL | ✅ |
| token | VARCHAR(255) | NOT NULL | ✅ |
| expiry_date | DATETIME | NOT NULL | ✅ |

---

## Database: **social_db**

### Table: `user_profile`
**Entity:** `com.socialmedia.social.entity.UserProfile`

⚠️ **DUPLICATE USER DATA** - This table replicates user info from `auth_db.users`

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | BIGINT | PRIMARY KEY, AUTO_INCREMENT | ✅ |
| user_id | BIGINT | NOT NULL, UNIQUE | ⚠️ References auth_db.users(id) |
| username | VARCHAR(50) | NOT NULL, UNIQUE | ⚠️ DUPLICATE from auth_db |
| full_name | VARCHAR(100) | NULL | ⚠️ DUPLICATE from auth_db |
| email | VARCHAR(255) | NOT NULL, UNIQUE | ⚠️ DUPLICATE from auth_db |
| bio | VARCHAR(500) | NULL | ⚠️ DUPLICATE from auth_db |
| profile_picture_url | VARCHAR(500) | NULL | ⚠️ DUPLICATE from auth_db |
| cover_photo_url | VARCHAR(500) | NULL | ✅ Social-only field |
| location | VARCHAR(100) | NULL | ✅ Social-only field |
| website | VARCHAR(200) | NULL | ✅ Social-only field |
| date_of_birth | DATE | NULL | ✅ Social-only field |
| is_private | BOOLEAN | DEFAULT FALSE | ✅ Social-only field |
| is_verified | BOOLEAN | DEFAULT FALSE | ✅ Social-only field |
| created_at | DATETIME | NOT NULL | ✅ Auto-set |
| updated_at | DATETIME | NULL | ✅ Auto-set |

### Table: `posts`
**Entity:** `com.socialmedia.social.entity.Post`

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | BIGINT | PRIMARY KEY, AUTO_INCREMENT | ✅ |
| user_id | BIGINT | NOT NULL | ✅ References user_profile(user_id) |
| content | TEXT | NULL | ✅ |
| is_public | BOOLEAN | NOT NULL, DEFAULT TRUE | ✅ |
| likes_count | INT | NOT NULL, DEFAULT 0 | ✅ |
| comments_count | INT | NOT NULL, DEFAULT 0 | ✅ |
| shares_count | INT | NOT NULL, DEFAULT 0 | ✅ |
| saves_count | INT | NOT NULL, DEFAULT 0 | ✅ |
| created_at | DATETIME | NOT NULL | ✅ Auto-set |
| updated_at | DATETIME | NOT NULL | ✅ Auto-set |

### Table: `post_images`
**Relation:** Post media URLs (ElementCollection)

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| post_id | BIGINT | FOREIGN KEY → posts(id) | ✅ |
| image_url | VARCHAR(255) | NOT NULL | ✅ Stores images/videos |

### Table: `likes`
**Entity:** `com.socialmedia.social.entity.Like`

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | BIGINT | PRIMARY KEY, AUTO_INCREMENT | ✅ |
| user_id | BIGINT | NOT NULL | ✅ |
| post_id | BIGINT | NOT NULL | ✅ |
| created_at | DATETIME | NOT NULL | ✅ |

### Table: `comments`
**Entity:** `com.socialmedia.social.entity.Comment`

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | BIGINT | PRIMARY KEY, AUTO_INCREMENT | ✅ |
| post_id | BIGINT | NOT NULL | ✅ |
| user_id | BIGINT | NOT NULL | ✅ |
| content | TEXT | NOT NULL | ✅ |
| parent_comment_id | BIGINT | NULL | ✅ For nested comments |
| created_at | DATETIME | NOT NULL | ✅ |
| updated_at | DATETIME | NOT NULL | ✅ |

### Table: `followers`
**Entity:** `com.socialmedia.social.entity.Follower`

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | BIGINT | PRIMARY KEY, AUTO_INCREMENT | ✅ |
| follower_id | BIGINT | NOT NULL | ✅ User who follows |
| following_id | BIGINT | NOT NULL | ✅ User being followed |
| created_at | DATETIME | NOT NULL | ✅ |

### Table: `blocked_users`
**Entity:** `com.socialmedia.social.entity.BlockedUser`

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | BIGINT | PRIMARY KEY, AUTO_INCREMENT | ✅ |
| blocker_id | BIGINT | NOT NULL | ✅ User who blocks |
| blocked_id | BIGINT | NOT NULL | ✅ User being blocked |
| created_at | DATETIME | NOT NULL | ✅ |

### Table: `shares`
**Entity:** `com.socialmedia.social.entity.Share`

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | BIGINT | PRIMARY KEY, AUTO_INCREMENT | ✅ |
| user_id | BIGINT | NOT NULL | ✅ |
| post_id | BIGINT | NOT NULL | ✅ |
| created_at | DATETIME | NOT NULL | ✅ |

### Table: `saves`
**Entity:** `com.socialmedia.social.entity.Save`

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | BIGINT | PRIMARY KEY, AUTO_INCREMENT | ✅ |
| user_id | BIGINT | NOT NULL | ✅ |
| post_id | BIGINT | NOT NULL | ✅ |
| created_at | DATETIME | NOT NULL | ✅ |

### Table: `messages`
**Entity:** `com.socialmedia.social.entity.Message`

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | BIGINT | PRIMARY KEY, AUTO_INCREMENT | ✅ |
| sender_id | BIGINT | NOT NULL | ✅ |
| receiver_id | BIGINT | NOT NULL | ✅ |
| content | TEXT | NOT NULL | ✅ |
| is_read | BOOLEAN | DEFAULT FALSE | ✅ |
| created_at | DATETIME | NOT NULL | ✅ |
| updated_at | DATETIME | NOT NULL | ✅ |

---

## 🔴 **Issues Found**

### 1. **Data Duplication**
User information stored in TWO tables:
- `auth_db.users` (source of truth for auth)
- `social_db.user_profile` (copy for social features)

**Problem:** Changes in one don't sync to the other automatically.

### 2. **Synchronization Gaps**
When a user updates their profile:
- ❌ Username changed in auth_db → NOT updated in user_profile
- ❌ Full name changed in auth_db → NOT updated in user_profile
- ❌ Profile picture changed in auth_db → NOT updated in user_profile

### 3. **Placeholder Data**
When `user_profile` doesn't exist, the service creates:
```java
username: "user_11"
fullName: "User 11"
email: "user_11@social.com"
```
This is shown in the app instead of real user data from `auth_db.users`.

---

## ✅ **Recommended Solutions**

### Option A: **Single Database (RECOMMENDED)**
Merge both databases into one:
1. Move `posts`, `likes`, `comments`, etc. to `auth_db`
2. Remove `user_profile` table completely
3. Use `auth_db.users` as the single source of truth
4. Update social-service to point to `auth_db`

**Pros:** No data duplication, no sync issues  
**Cons:** Requires migration

### Option B: **Cross-Database Foreign Keys**
Keep separate databases but add sync mechanism:
1. Add event listener in auth-service
2. When user updates profile → call social-service API to update user_profile
3. Implement consistency checks

**Pros:** Services remain independent  
**Cons:** Complex, potential for sync failures

### Option C: **Remove Duplicate Fields**
Keep user_profile but remove duplicated fields:
- Remove: username, fullName, email, bio, profile_picture_url from user_profile
- Keep only: cover_photo_url, location, website, date_of_birth, is_private, is_verified
- Always fetch user data from auth-service API

**Pros:** Minimal changes  
**Cons:** Extra API calls, potential performance impact

---

## Current Status

**What's working:**
- ✅ Posts stored in `social_db.posts`
- ✅ Likes, comments, followers all in `social_db`
- ✅ User authentication in `auth_db.users`
- ✅ All timestamps auto-generated

**What's broken:**
- ❌ User profile shows placeholder names ("User 11")
- ❌ Profile updates in auth_db don't reflect in social features
- ❌ Data inconsistency between databases

**Next Steps:**
Choose a solution (A, B, or C) and implement it to fix the data synchronization issue.
