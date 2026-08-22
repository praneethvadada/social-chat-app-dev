# Database Schema Documentation

## Quick Start

### Fresh Installation
```bash
# Create database and tables
mysql -u root -p < backend/schema.sql

# Restart services
cd backend
restart-services.bat
```

### Migrate Existing Data
```bash
# Backup first
mysqldump -u root -p auth_db > backup_auth.sql
mysqldump -u root -p social_db > backup_social.sql

# Run migration
mysql -u root -p < backend/migrate.sql

# Restart services
cd backend
restart-services.bat
```

## Database Structure

### Single Database: `auth_db`

**Users & Auth:**
- `users` - Main user table (username, email, password, full_name, bio, profile_picture)
- `user_roles` - User roles (USER, ADMIN, MODERATOR)
- `password_reset_token` - Password reset tokens
- `user_profile_extensions` - Social-specific fields (cover_photo, location, website, etc.)

**Content:**
- `posts` - User posts
- `post_images` - Post media (images/videos)

**Interactions:**
- `likes` - Post likes
- `comments` - Post comments (supports threading)
- `shares` - Post shares
- `saves` - Saved posts (bookmarks)

**Social Graph:**
- `followers` - Follow relationships
- `blocked_users` - Blocked users

**Messaging:**
- `messages` - Direct messages

## Foreign Keys

All tables have proper foreign key constraints:
```
posts.user_id → users.id
likes.user_id → users.id
likes.post_id → posts.id
comments.user_id → users.id
comments.post_id → posts.id
followers.follower_id → users.id
followers.following_id → users.id
... etc
```

## Indexes

Optimized indexes for common queries:
- User lookups: `users(username)`, `users(email)`
- Post feeds: `posts(user_id, created_at DESC)`
- Likes: `likes(post_id)`, `likes(user_id, created_at DESC)`
- Comments: `comments(post_id, created_at)`
- Social graph: `followers(follower_id)`, `followers(following_id)`

## Triggers

Auto-update counters:
- `posts.likes_count` updated when likes added/removed
- `posts.comments_count` updated when comments added/removed
- `posts.shares_count` updated when shares added/removed
- `posts.saves_count` updated when saves added/removed

## Views

Pre-built views for common queries:
- `v_user_profiles` - Complete user profile with stats
- `v_post_feed` - Posts with author information

## Key Features

✅ **Single Source of Truth**: User data in one place  
✅ **Data Integrity**: Foreign key constraints  
✅ **Performance**: Proper indexes on all lookup columns  
✅ **Automation**: Triggers for counter updates  
✅ **Scalability**: Normalized schema, InnoDB engine  
✅ **UTF-8 Support**: Full Unicode support for international users  

## Schema Diagram

```
users (id, username, email, password, full_name, bio, profile_picture)
  ├─→ user_roles (user_id, role)
  ├─→ password_reset_token (user_id, token)
  ├─→ user_profile_extensions (user_id, cover_photo, location, website)
  ├─→ posts (user_id, content, likes_count, comments_count)
  │    ├─→ post_images (post_id, image_url)
  │    ├─→ likes (user_id, post_id)
  │    ├─→ comments (user_id, post_id, parent_comment_id)
  │    ├─→ shares (user_id, post_id)
  │    └─→ saves (user_id, post_id)
  ├─→ followers (follower_id, following_id)
  ├─→ blocked_users (blocker_id, blocked_id)
  └─→ messages (sender_id, receiver_id, content)
```

## Configuration

Both services use the same database:

**auth-service** (`application.properties`):
```properties
spring.datasource.url=jdbc:mysql://localhost:3306/auth_db
```

**social-service** (`application.properties`):
```properties
spring.datasource.url=jdbc:mysql://localhost:3306/auth_db
```

## Files

- `schema.sql` - Complete database schema with tables, indexes, triggers, views
- `migrate.sql` - Migration script to move data from social_db to auth_db
- `SCHEMA_VERIFICATION.md` - Detailed schema documentation
- `MIGRATION_GUIDE.md` - Step-by-step migration instructions

## Troubleshooting

**Issue: Tables not created**
```bash
mysql -u root -p
USE auth_db;
SHOW TABLES;
```

**Issue: Foreign key errors**
```sql
SET FOREIGN_KEY_CHECKS = 0;
-- Run your queries
SET FOREIGN_KEY_CHECKS = 1;
```

**Issue: Data not migrating**
```bash
# Check if social_db exists
mysql -u root -p -e "SHOW DATABASES;"

# Check table counts
mysql -u root -p social_db -e "SELECT COUNT(*) FROM posts;"
mysql -u root -p auth_db -e "SELECT COUNT(*) FROM posts;"
```
