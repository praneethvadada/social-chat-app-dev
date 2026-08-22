# Apply New Schema to RDS Database

## ⚠️ IMPORTANT WARNING
This script will **DROP the existing database** and recreate it from scratch. All existing data will be lost!

## Prerequisites
- MySQL client installed on your local machine
- RDS credentials ready

## Your RDS Details
- **Host**: social-media-db.ca30yaou8j00.us-east-1.rds.amazonaws.com
- **Port**: 3306
- **Username**: admin
- **Password**: SecurePass123!
- **Current Database**: social_app (will be replaced with auth_db)

## Step 1: Backup Current Database (RECOMMENDED!)

```bash
# Backup entire social_app database
mysqldump -h social-media-db.ca30yaou8j00.us-east-1.rds.amazonaws.com -u admin -p social_app > backup_social_app_$(date +%Y%m%d).sql

# Or backup specific tables
mysqldump -h social-media-db.ca30yaou8j00.us-east-1.rds.amazonaws.com -u admin -p social_app users posts messages > backup_important_tables.sql
```

## Step 2: Apply New Schema

### Option A: Direct Import (Recommended)
```bash
cd "c:\Users\gidut\OneDrive\html files\Projects\social-chat-app\backend"

mysql -h social-media-db.ca30yaou8j00.us-east-1.rds.amazonaws.com -u admin -p < complete_schema_v2.sql
```

### Option B: Interactive MySQL Session
```bash
mysql -h social-media-db.ca30yaou8j00.us-east-1.rds.amazonaws.com -u admin -p

# Then inside MySQL:
source complete_schema_v2.sql
```

## Step 3: Verify Schema Applied Successfully

```bash
mysql -h social-media-db.ca30yaou8j00.us-east-1.rds.amazonaws.com -u admin -p -e "
USE auth_db;
SELECT * FROM schema_version;
SHOW TABLES;
SELECT COUNT(*) as table_count FROM information_schema.tables WHERE table_schema = 'auth_db';
"
```

Expected output:
- **Version**: 2.0.2
- **Table Count**: 20 tables
- **Sample user**: john_doe@example.com (password: password123)

## Step 4: Update Backend Configuration

### For Auth Service
Edit: `backend/auth-service/src/main/resources/application.properties`

```properties
spring.datasource.url=jdbc:mysql://social-media-db.ca30yaou8j00.us-east-1.rds.amazonaws.com:3306/auth_db
spring.datasource.username=admin
spring.datasource.password=SecurePass123!
```

### For Social Service
Edit: `backend/social-service/src/main/resources/application.properties`

```properties
spring.datasource.url=jdbc:mysql://social-media-db.ca30yaou8j00.us-east-1.rds.amazonaws.com:3306/auth_db
spring.datasource.username=admin
spring.datasource.password=SecurePass123!
```

### Environment Variables (if using .env files)
Update `backend/auth-service.env` and `backend/social-service.env`:

```bash
DB_URL=jdbc:mysql://social-media-db.ca30yaou8j00.us-east-1.rds.amazonaws.com:3306/auth_db
DB_USERNAME=admin
DB_PASSWORD=SecurePass123!
```

## Step 5: Rebuild and Redeploy

```bash
cd backend
deploy.bat
```

## What's New in Schema v2.0.2

### New Tables
1. **otp_verifications** - Email OTP verification during signup
   - 4-digit OTP codes
   - 10-minute expiry
   - Max 5 resend attempts

2. **chat_deletions** - WhatsApp-style chat deletion
   - Per-user conversation deletion
   - Independent delete tracking

### Updated Tables
1. **users** - Added columns:
   - `is_private` - Account privacy setting
   - `is_verified` - Email/OTP verification status
   - `is_online` - Real-time online status
   - `last_seen_at` - Last activity timestamp

2. **user_profile_extensions** - Added:
   - `show_read_receipts` - Privacy setting
   - `show_activity_status` - Privacy setting

3. **messages** - Added:
   - `media_url` - Media attachments
   - `client_message_id` - Optimistic updates
   - `read_at` - Read receipt timestamp

### New Features
- ✅ Email OTP verification system
- ✅ Online/offline status tracking
- ✅ Read receipts for messages
- ✅ WhatsApp-like chat deletion
- ✅ Privacy controls (private accounts)
- ✅ 8 triggers for automatic counter updates
- ✅ 3 stored procedures (user feed, OTP cleanup, OTP status)
- ✅ 3 views for common queries

## Troubleshooting

### Connection Refused
```bash
# Check security group allows your IP
# In AWS Console: EC2 > Security Groups > Edit Inbound Rules
# Add rule: Type=MySQL/Aurora, Port=3306, Source=My IP
```

### Access Denied
```bash
# Verify credentials
mysql -h social-media-db.ca30yaou8j00.us-east-1.rds.amazonaws.com -u admin -p
# Enter password: SecurePass123!
```

### Import Errors
```bash
# Check MySQL client version
mysql --version

# For large imports, increase timeout
mysql -h social-media-db.ca30yaou8j00.us-east-1.rds.amazonaws.com -u admin -p --connect-timeout=300 < complete_schema_v2.sql
```

## Database Name Change Notice

**IMPORTANT**: The new schema creates `auth_db` instead of `social_app`.

You have two options:

### Option 1: Use auth_db (Recommended)
- Apply schema as-is
- Update all backend configs to use `auth_db`
- Cleaner separation

### Option 2: Keep social_app name
- Edit `complete_schema_v2.sql`
- Change line 11: `CREATE DATABASE auth_db` → `CREATE DATABASE social_app`
- Change line 15: `USE auth_db;` → `USE social_app;`
- No backend config changes needed

## Quick Test After Migration

```bash
# Test sample user login
curl -X POST http://98.92.24.110:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "john_doe",
    "password": "password123"
  }'

# Should return JWT token
```

## Rollback Plan

If something goes wrong:

```bash
# Restore from backup
mysql -h social-media-db.ca30yaou8j00.us-east-1.rds.amazonaws.com -u admin -p social_app < backup_social_app_20260106.sql
```

---

**Created**: January 6, 2026  
**Schema Version**: 2.0.2  
**Database**: auth_db
