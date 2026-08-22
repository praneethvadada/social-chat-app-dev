# Database Migration Guide: social_db → auth_db

## Overview
This migration consolidates the `social_db` and `auth_db` databases into a single `auth_db` database with proper foreign key relationships.

## Changes Made

### 1. Schema Changes
- ✅ Created `schema.sql` with complete production-level schema
- ✅ Added proper foreign key constraints
- ✅ Added indexes for performance
- ✅ Created database triggers for counter updates
- ✅ Added views for common queries
- ✅ Removed duplicate `user_profile` table

### 2. Configuration Changes
- ✅ Updated `social-service/application.properties` to use `auth_db`
- ✅ Updated `UserProfile` entity to map to `users` table
- ✅ Changed `userId` to map to `id` (primary key)

### 3. Code Changes
- ✅ Modified `UserProfileRepository` to use `id` instead of `user_id`
- ✅ Added getter/setter methods to sync `userId` with `id`
- ✅ Marked social-specific fields as `@Transient` (not in users table)

## Migration Steps

### Option A: Fresh Install (Recommended for Development)

1. **Backup existing data** (if you have important posts/users):
   ```sql
   mysqldump -u root -p auth_db > auth_db_backup.sql
   mysqldump -u root -p social_db > social_db_backup.sql
   ```

2. **Drop old databases**:
   ```sql
   DROP DATABASE IF EXISTS auth_db;
   DROP DATABASE IF EXISTS social_db;
   ```

3. **Run the new schema**:
   ```bash
   mysql -u root -p < backend/schema.sql
   ```

4. **Restart all services**:
   ```bash
   cd backend
   restart-services.bat
   ```

5. **Test the application**:
   - Register a new user
   - Create posts
   - Verify profile shows correct username/fullName

### Option B: Migrate Existing Data (Production)

1. **Backup databases**:
   ```sql
   mysqldump -u root -p auth_db > auth_db_backup_$(date +%Y%m%d).sql
   mysqldump -u root -p social_db > social_db_backup_$(date +%Y%m%d).sql
   ```

2. **Create migration script** (`migrate.sql`):
   ```sql
   USE auth_db;
   
   -- Migrate posts from social_db to auth_db
   INSERT INTO auth_db.posts (id, user_id, content, is_public, likes_count, comments_count, shares_count, saves_count, created_at, updated_at)
   SELECT id, user_id, content, is_public, likes_count, comments_count, shares_count, saves_count, created_at, updated_at
   FROM social_db.posts;
   
   -- Migrate post_images
   INSERT INTO auth_db.post_images (post_id, image_url, display_order)
   SELECT post_id, image_url, 0
   FROM social_db.post_images;
   
   -- Migrate likes
   INSERT INTO auth_db.likes (id, user_id, post_id, created_at)
   SELECT id, user_id, post_id, created_at
   FROM social_db.likes;
   
   -- Migrate comments
   INSERT INTO auth_db.comments (id, post_id, user_id, parent_comment_id, content, created_at, updated_at)
   SELECT id, post_id, user_id, parent_comment_id, content, created_at, updated_at
   FROM social_db.comments;
   
   -- Migrate followers
   INSERT INTO auth_db.followers (id, follower_id, following_id, created_at)
   SELECT id, follower_id, following_id, created_at
   FROM social_db.followers;
   
   -- Migrate blocked_users
   INSERT INTO auth_db.blocked_users (id, blocker_id, blocked_id, created_at)
   SELECT id, blocker_id, blocked_id, created_at
   FROM social_db.blocked_users;
   
   -- Migrate shares
   INSERT INTO auth_db.shares (id, user_id, post_id, created_at)
   SELECT id, user_id, post_id, created_at
   FROM social_db.shares;
   
   -- Migrate saves
   INSERT INTO auth_db.saves (id, user_id, post_id, created_at)
   SELECT id, user_id, post_id, created_at
   FROM social_db.saves;
   
   -- Migrate messages
   INSERT INTO auth_db.messages (id, sender_id, receiver_id, content, is_read, created_at, updated_at)
   SELECT id, sender_id, receiver_id, content, is_read, created_at, updated_at
   FROM social_db.messages;
   ```

3. **Run migration**:
   ```bash
   mysql -u root -p < migrate.sql
   ```

4. **Verify data**:
   ```sql
   USE auth_db;
   SELECT COUNT(*) FROM posts;
   SELECT COUNT(*) FROM likes;
   SELECT COUNT(*) FROM comments;
   ```

5. **Update services and restart**:
   ```bash
   cd backend
   restart-services.bat
   ```

6. **Drop old social_db** (after confirming everything works):
   ```sql
   DROP DATABASE social_db;
   ```

## Verification Checklist

After migration, verify:

- [ ] Users can login with existing credentials
- [ ] Profile displays correct username and full name
- [ ] Posts are visible on home screen
- [ ] Likes, comments, shares work correctly
- [ ] Following/unfollowing works
- [ ] Direct messages work
- [ ] File uploads work
- [ ] Search functionality works

## Schema Benefits

### Before (2 databases):
```
auth_db
├── users (username, email, full_name, bio, profile_picture)
└── user_roles

social_db
├── user_profile (DUPLICATE: username, email, full_name, bio)
├── posts
├── likes
├── comments
└── ...
```

### After (1 database):
```
auth_db
├── users (single source of truth)
├── user_roles
├── posts (with FK to users)
├── likes (with FK to users & posts)
├── comments (with FK to users & posts)
└── ... (all with proper FKs)
```

## Performance Improvements

1. **Foreign Key Constraints**: Data integrity enforced at database level
2. **Indexes**: Added on frequently queried columns
3. **Triggers**: Auto-update counters (likes_count, comments_count)
4. **Views**: Pre-joined queries for common operations
5. **No Duplication**: Single source of truth for user data

## Rollback Plan

If issues occur:

1. **Stop services**:
   ```bash
   taskkill /F /IM java.exe
   ```

2. **Restore backups**:
   ```bash
   mysql -u root -p < auth_db_backup.sql
   mysql -u root -p < social_db_backup.sql
   ```

3. **Revert configuration**:
   - Change `social-service/application.properties` back to `social_db`
   - Revert `UserProfile` entity changes

4. **Restart services**

## Support

If you encounter issues:
1. Check backend console logs for errors
2. Verify database connection: `mysql -u root -p auth_db`
3. Confirm schema loaded: `SHOW TABLES;`
4. Check foreign keys: `SHOW CREATE TABLE posts;`

## Next Steps

1. Apply this migration
2. Test all features thoroughly
3. Monitor for any issues
4. Once stable, remove `social_db` completely
