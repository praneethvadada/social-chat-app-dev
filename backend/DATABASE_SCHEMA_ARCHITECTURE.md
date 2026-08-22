# Database Schema Architecture

## Overview
The social media platform uses a shared MySQL database (`auth_db`) with 21 tables, designed for optimal performance, data integrity, and scalability. The schema supports comprehensive social media features including authentication, content sharing, real-time messaging, and video calling.

## Database Configuration
- **Engine:** InnoDB
- **Charset:** utf8mb4
- **Collation:** utf8mb4_unicode_ci
- **Timezone:** UTC (enforced application-wide)

## Schema Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        AUTH_DB SCHEMA                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │   USERS         │  │   OTP           │  │   PASSWORD      │ │
│  │   (Auth)        │  │   VERIFICATIONS │  │   RESET TOKEN   │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
│                                                                 │
│  ┌─────────────────┐  ┌─────────────────┐                       │
│  │   USER ROLES    │  │   USER PROFILE  │                       │
│  │   (Auth)        │  │   EXTENSIONS    │                       │
│  └─────────────────┘  └─────────────────┘                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │   POSTS         │  │   POST IMAGES   │  │   LIKES         │ │
│  │   (Social)      │  │   (Social)      │  │   (Social)      │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
│                                                                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │   COMMENTS      │  │   SHARES        │  │   SAVES         │ │
│  │   (Social)      │  │   (Social)      │  │   (Social)      │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │   FOLLOWERS     │  │   FOLLOW        │  │   BLOCKED       │ │
│  │   (Social)      │  │   REQUESTS      │  │   USERS         │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
│                                                                 │
│  ┌─────────────────┐                                           │
│  │   CLOSE FRIENDS │                                           │
│  │   (Social)      │                                           │
│  └─────────────────┘                                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │   MESSAGES      │  │   CHAT          │  │   NOTIFICATIONS │ │
│  │   (Social)      │  │   DELETIONS     │  │   (Social)      │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
│                                                                 │
│  ┌─────────────────┐  ┌─────────────────┐                       │
│  │   CALL LOGS     │  │   SCHEMA        │                       │
│  │   (Social)      │  │   VERSION       │                       │
│  └─────────────────┘  └─────────────────┘                       │
└─────────────────────────────────────────────────────────────────┘
```

## Core Tables Detail

### 1. Users & Authentication Tables

#### users
**Purpose:** Main user entity with authentication and profile data
**Key Fields:**
- `id` (BIGINT, PK, AUTO_INCREMENT)
- `username` (VARCHAR(50), UNIQUE)
- `email` (VARCHAR(100), UNIQUE)
- `password` (VARCHAR(255), BCrypt hashed)
- `full_name` (VARCHAR(100))
- `bio` (VARCHAR(500))
- `profile_picture` (VARCHAR(255))
- `enabled` (BOOLEAN, DEFAULT TRUE)
- `account_non_locked` (BOOLEAN, DEFAULT TRUE)
- `failed_login_attempts` (INT, DEFAULT 0)
- `last_login` (DATETIME)
- `is_private` (BOOLEAN, DEFAULT FALSE) - Account visibility
- `is_verified` (BOOLEAN, DEFAULT FALSE) - OTP verification status
- `is_online` (BOOLEAN, DEFAULT FALSE) - Real-time status
- `last_seen_at` (DATETIME) - Last activity timestamp
- `created_at`, `updated_at` (DATETIME)

**Indexes:**
- `idx_username`, `idx_email`
- `idx_created_at`, `idx_is_online`, `idx_is_private`, `idx_is_verified`, `idx_last_seen_at`

#### user_roles
**Purpose:** User role assignments (many-to-many)
**Key Fields:**
- `user_id` (BIGINT, FK → users.id)
- `role` (VARCHAR(50)) - USER, ADMIN, MODERATOR
**Constraints:** PRIMARY KEY (user_id, role)

#### otp_verifications
**Purpose:** Email verification for signup
**Key Fields:**
- `id` (BIGINT, PK, AUTO_INCREMENT)
- `email` (VARCHAR(255), UNIQUE)
- `otp` (VARCHAR(4)) - 4-digit code
- `created_at` (DATETIME)
- `expires_at` (DATETIME) - 10 minutes validity
- `is_used` (BOOLEAN, DEFAULT FALSE)
- `attempts` (INT, DEFAULT 0) - Resend counter

#### password_reset_token
**Purpose:** Password reset functionality
**Key Fields:**
- `id` (BIGINT, PK, AUTO_INCREMENT)
- `user_id` (BIGINT, FK → users.id)
- `token` (VARCHAR(255), UNIQUE)
- `expiry_date` (DATETIME)

#### user_profile_extensions
**Purpose:** Extended social profile information
**Key Fields:**
- `id` (BIGINT, PK, AUTO_INCREMENT)
- `user_id` (BIGINT, FK → users.id, UNIQUE)
- `cover_photo_url` (VARCHAR(500))
- `location` (VARCHAR(100))
- `website` (VARCHAR(200))
- `date_of_birth` (DATE)
- `is_private` (BOOLEAN, DEFAULT FALSE)
- `is_verified` (BOOLEAN, DEFAULT FALSE)
- `show_read_receipts` (BOOLEAN, DEFAULT TRUE)
- `show_activity_status` (BOOLEAN, DEFAULT TRUE)

### 2. Content & Social Features Tables

#### posts
**Purpose:** User posts with visibility controls
**Key Fields:**
- `id` (BIGINT, PK, AUTO_INCREMENT)
- `user_id` (BIGINT, FK → users.id)
- `content` (TEXT)
- `is_public` (BOOLEAN, DEFAULT TRUE)
- `visibility` (ENUM: PUBLIC, CLOSE_FRIENDS)
- `likes_count`, `comments_count`, `shares_count`, `saves_count` (INT, DEFAULT 0)
- `created_at`, `updated_at` (DATETIME, UTC)

**Indexes:**
- `idx_user_posts` (user_id, created_at DESC)
- `idx_created_at`, `idx_is_public`
- `idx_visibility`, `idx_user_visibility` (user_id, visibility)

#### post_images
**Purpose:** Media attachments for posts
**Key Fields:**
- `id` (BIGINT, PK, AUTO_INCREMENT)
- `post_id` (BIGINT, FK → posts.id)
- `image_url` (VARCHAR(500)) - S3 key only
- `display_order` (INT, DEFAULT 0)

### 3. Interactions Tables

#### likes
**Purpose:** Post likes (prevent duplicates)
**Key Fields:**
- `id` (BIGINT, PK, AUTO_INCREMENT)
- `user_id` (BIGINT, FK → users.id)
- `target_type` (ENUM: POST, COMMENT)
- `target_id` (BIGINT)
- `created_at` (DATETIME)
**Constraints:** UNIQUE (user_id, target_type, target_id)

#### comments
**Purpose:** Post comments with threading support
**Key Fields:**
- `id` (BIGINT, PK, AUTO_INCREMENT)
- `post_id` (BIGINT, FK → posts.id)
- `user_id` (BIGINT, FK → users.id)
- `parent_comment_id` (BIGINT, FK → comments.id) - For nested comments
- `content` (TEXT)
- `created_at`, `updated_at` (DATETIME)

#### shares & saves
**Purpose:** Content sharing and bookmarking
**Similar Structure:**
- `id`, `user_id`, `post_id`, `created_at`
- UNIQUE constraints prevent duplicates
- Separate counters updated via triggers

### 4. Social Graph Tables

#### followers
**Purpose:** Follow relationships
**Key Fields:**
- `id` (BIGINT, PK, AUTO_INCREMENT)
- `follower_id` (BIGINT, FK → users.id)
- `following_id` (BIGINT, FK → users.id)
- `created_at` (DATETIME)
**Constraints:** UNIQUE (follower_id, following_id)

#### follow_requests
**Purpose:** Follow request system for private accounts
**Key Fields:**
- `id` (BIGINT, PK, AUTO_INCREMENT)
- `requester_id`, `receiver_id` (BIGINT, FK → users.id)
- `status` (VARCHAR(20): PENDING, APPROVED, REJECTED)
- `created_at`, `updated_at` (DATETIME)

#### blocked_users
**Purpose:** User blocking functionality
**Key Fields:**
- `id` (BIGINT, PK, AUTO_INCREMENT)
- `blocker_id`, `blocked_id` (BIGINT, FK → users.id)
- `created_at` (DATETIME)
**Constraints:** UNIQUE (blocker_id, blocked_id)

#### close_friends
**Purpose:** Close friends relationships for exclusive content
**Key Fields:**
- `id` (BIGINT, PK, AUTO_INCREMENT)
- `user_id` (BIGINT, FK → users.id)
- `close_friend_user_id` (BIGINT, FK → users.id)
- `created_at` (DATETIME)
**Constraints:** UNIQUE (user_id, close_friend_user_id)

### 5. Messaging Tables

#### messages
**Purpose:** Direct messages with media support
**Key Fields:**
- `id` (BIGINT, PK, AUTO_INCREMENT)
- `sender_id`, `receiver_id` (BIGINT, FK → users.id)
- `content` (TEXT)
- `media_url` (VARCHAR(500)) - S3 key only
- `client_message_id` (VARCHAR(255), UNIQUE) - Optimistic updates
- `is_read` (BOOLEAN, DEFAULT FALSE)
- `read_at` (DATETIME)
- `created_at` (DATETIME, UTC)

**Indexes:**
- `idx_sender_receiver` (sender_id, receiver_id)
- `idx_receiver_read` (receiver_id, is_read)

#### chat_deletions
**Purpose:** WhatsApp-like independent conversation deletion
**Key Fields:**
- `id` (BIGINT, PK, AUTO_INCREMENT)
- `user_id` (BIGINT, FK → users.id)
- `other_user_id` (BIGINT, FK → users.id)
- `deleted_at` (DATETIME)
**Constraints:** UNIQUE (user_id, other_user_id)

### 6. Notifications & Calls Tables

#### notifications
**Purpose:** Activity notifications
**Key Fields:**
- `id` (BIGINT, PK, AUTO_INCREMENT)
- `user_id` (BIGINT, FK → users.id)
- `type` (VARCHAR(50)) - LIKE, COMMENT, FOLLOW, MESSAGE, etc.
- `actor_id` (BIGINT, FK → users.id) - Who triggered notification
- `target_id` (BIGINT) - Post/comment ID
- `content` (TEXT)
- `is_read` (BOOLEAN, DEFAULT FALSE)
- `created_at` (DATETIME)

#### call_logs
**Purpose:** Video call history with soft deletes
**Key Fields:**
- `id` (BIGINT, PK, AUTO_INCREMENT)
- `initiator_id`, `receiver_id` (BIGINT, FK → users.id)
- `call_type` (VARCHAR(10): AUDIO, VIDEO)
- `status` (VARCHAR(20): INITIATED, ACCEPTED, DECLINED, ENDED)
- `duration_seconds` (INT, DEFAULT 0)
- `deleted_for_initiator`, `deleted_for_receiver` (BOOLEAN, DEFAULT FALSE)
- `created_at`, `updated_at` (DATETIME)

### 7. System Tables

#### schema_version
**Purpose:** Database versioning and migration tracking
**Key Fields:**
- `version` (VARCHAR(20), PK)
- `applied_at` (DATETIME, DEFAULT CURRENT_TIMESTAMP)
- `description` (TEXT)

## Database Design Patterns

### 1. Denormalized Counters
- `likes_count`, `comments_count`, `shares_count`, `saves_count` on posts
- Updated via database triggers for performance
- Prevents expensive COUNT(*) queries

### 2. Soft Deletes
- `deleted_for_initiator/receiver` in call_logs
- `chat_deletions` table for independent message deletion
- Maintains data integrity while respecting user privacy

### 3. Composite Primary Keys
- `user_roles`: (user_id, role)
- `followers`: (follower_id, following_id)
- `blocked_users`: (blocker_id, blocked_id)
- `close_friends`: (user_id, close_friend_user_id)

### 4. Audit Fields
- `created_at`, `updated_at` on all entities
- Automatic timestamps via Hibernate annotations
- UTC timezone enforcement

### 5. Optimistic Locking Prevention
- Unique constraints on relationships
- Application-level duplicate prevention
- Database-level integrity constraints

## Performance Optimizations

### Indexes
- **User lookups:** username, email, created_at, online status
- **Social graph:** follower/following relationships
- **Content:** user posts, visibility filters, creation time
- **Messaging:** conversation queries, unread message counts
- **Composite indexes** for complex queries

### Query Optimization
- **Pagination:** LIMIT/OFFSET for large result sets
- **Selective fields:** Only fetch required columns
- **Join optimization:** Proper indexing on foreign keys
- **Caching:** Redis for frequently accessed data

### Data Types
- **BIGINT** for IDs (future-proofing)
- **VARCHAR** with appropriate lengths
- **TEXT** for unlimited content
- **DATETIME** with UTC timezone
- **BOOLEAN** for flags
- **ENUM** for controlled vocabularies

## Data Integrity & Constraints

### Foreign Key Constraints
- **CASCADE DELETE** for dependent data
- **SET NULL** for optional references
- **RESTRICT** for critical relationships

### Unique Constraints
- **User identifiers:** username, email
- **Relationships:** Prevent duplicate follows/blocks/friendships
- **OTP emails:** One active OTP per email
- **Client message IDs:** Prevent duplicate sends

### Check Constraints
- **ENUM values** for controlled fields
- **Positive integers** for counts
- **Date validations** for logical time ordering

## Backup & Recovery

### Automated Backups
- **RDS automated backups** (configurable retention)
- **Point-in-time recovery** capability
- **Cross-region replication** for disaster recovery

### Data Export
- **Schema-only dumps** for structure
- **Data migration scripts** for content
- **Anonymized exports** for testing

## Migration Strategy

### Version Control
- **schema_version** table tracks applied migrations
- **Idempotent scripts** (safe to run multiple times)
- **Rollback procedures** for failed deployments

### Zero-Downtime Deployments
- **Backward compatibility** during transitions
- **Feature flags** for gradual rollouts
- **Database connection pooling** for stability

This database schema provides a solid foundation for a scalable social media platform, with careful consideration for performance, data integrity, and future extensibility.