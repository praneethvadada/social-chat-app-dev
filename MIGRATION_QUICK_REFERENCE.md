# Migration Files Quick Reference

## Files Available

### 1. **WORKBENCH_OTP_MIGRATION.sql** (For Individual OTP Table)
**Location:** `backend/migrations/WORKBENCH_OTP_MIGRATION.sql`

**Purpose:** Add only the OTP verification table to an existing database

**Use Case:** 
- You already have an existing database with other tables
- You want to add OTP functionality without recreating everything
- You're updating an existing deployment

**What It Creates:**
- `otp_verifications` table with all indexes
- 3 stored procedures:
  - `cleanup_expired_otps()` - Delete used/expired OTPs
  - `check_otp_status()` - Check OTP validity
  - `cleanup_old_otps()` - Clean records older than N days

**Execution Methods:**

#### Method 1: DBeaver GUI
```
1. Open DBeaver
2. Connect to your MySQL database
3. Right-click on database → Execute SQL Script
4. Select: WORKBENCH_OTP_MIGRATION.sql
5. Click Execute (or Ctrl+Shift+Enter)
```

#### Method 2: MySQL Workbench
```
1. Open MySQL Workbench
2. Click File → Open SQL Script
3. Select: WORKBENCH_OTP_MIGRATION.sql
4. Click Execute (⚡ icon)
```

#### Method 3: Command Line
```bash
mysql -u root -p auth_db < backend/migrations/WORKBENCH_OTP_MIGRATION.sql
```

#### Method 4: From Within MySQL/MariaDB Client
```sql
-- Connect first
mysql -u root -p
USE auth_db;

-- Then execute
source /path/to/WORKBENCH_OTP_MIGRATION.sql;
```

---

### 2. **COMPLETE_SCHEMA_AWS_PRODUCTION.sql** (For Full AWS Deployment)
**Location:** `backend/COMPLETE_SCHEMA_AWS_PRODUCTION.sql`

**Purpose:** Complete database schema for fresh AWS deployment

**Use Case:**
- You're setting up a new AWS RDS instance
- You want the complete production schema
- You need everything: users, posts, messages, OTP, calls, notifications, etc.

**What It Creates:**
- 20 tables (all tables including OTP)
- 3 views for common queries
- 8 triggers for counter updates
- 3 stored procedures (including OTP procedures)
- Sample user data
- Schema versioning

**Execution Methods:**

#### Method 1: DBeaver (Recommended for AWS)
```
1. Create new connection in DBeaver:
   - Server: your-rds-endpoint.us-east-1.rds.amazonaws.com
   - Port: 3306
   - Username: admin
   - Password: your-password
   - Test Connection → OK

2. File → Open SQL Script
   Select: COMPLETE_SCHEMA_AWS_PRODUCTION.sql

3. Select All (Ctrl+A)

4. Execute (Ctrl+Enter or ⚡)

5. Verify:
   - Right-click database → Refresh
   - Expand auth_db → Tables (should see 20 tables)
```

#### Method 2: MySQL Workbench (For Windows/AWS)
```
1. Create connection to RDS:
   - Server: your-endpoint
   - Port: 3306
   - Username: admin
   
2. File → Open SQL Script
   Select: COMPLETE_SCHEMA_AWS_PRODUCTION.sql

3. Execute (⚡ or Ctrl+Shift+Enter)

4. View Results panel for completion status
```

#### Method 3: Command Line (From EC2 or Local)
```bash
# From your local machine or EC2 instance
mysql -h your-rds-endpoint.us-east-1.rds.amazonaws.com \
      -u admin -p \
      auth_db < COMPLETE_SCHEMA_AWS_PRODUCTION.sql

# For Windows Command Prompt
mysql -h your-rds-endpoint.us-east-1.rds.amazonaws.com -u admin -p auth_db < COMPLETE_SCHEMA_AWS_PRODUCTION.sql
```

#### Method 4: Direct Connection in DBeaver
```sql
-- Open SQL Editor in DBeaver
-- Right-click on connection → SQL Editor
-- Copy-paste content of COMPLETE_SCHEMA_AWS_PRODUCTION.sql
-- Execute (Ctrl+Enter)
```

---

## Execution Flowchart

```
Start
  │
  ├─→ Existing Database? 
  │    └─→ YES → Use WORKBENCH_OTP_MIGRATION.sql
  │    └─→ NO → Continue
  │
  └─→ AWS Deployment?
       ├─→ YES → Use COMPLETE_SCHEMA_AWS_PRODUCTION.sql
       └─→ NO → Use COMPLETE_SCHEMA_AWS_PRODUCTION.sql
                  (works everywhere)
```

---

## Verification Queries

### Check What Was Installed

```sql
-- View all tables
SHOW TABLES IN auth_db;

-- Count tables (should be 20)
SELECT COUNT(*) as table_count 
FROM INFORMATION_SCHEMA.TABLES 
WHERE TABLE_SCHEMA = 'auth_db';

-- Check schema version
SELECT version, applied_at, description 
FROM schema_version 
ORDER BY version DESC;

-- Check OTP table structure
DESCRIBE otp_verifications;

-- List all stored procedures
SHOW PROCEDURE STATUS WHERE db = 'auth_db';

-- Check table indexes
SELECT TABLE_NAME, INDEX_NAME 
FROM INFORMATION_SCHEMA.STATISTICS 
WHERE TABLE_SCHEMA = 'auth_db' 
AND TABLE_NAME = 'otp_verifications';
```

---

## Common Issues & Solutions

### Issue 1: "Table already exists" Error
```
Solution:
- This is normal if running multiple times
- COMPLETE_SCHEMA_AWS_PRODUCTION.sql uses "IF NOT EXISTS"
- Safe to run again - won't duplicate
```

### Issue 2: "Access Denied" Error
```
Solution:
- Check username/password
- For AWS: Use "admin" user created during RDS setup
- Verify security group allows your IP on port 3306
```

### Issue 3: OTP Table Not Visible
```sql
Solution:
-- Manually verify it exists
SELECT COUNT(*) FROM otp_verifications;

-- If error, create it manually:
source backend/migrations/WORKBENCH_OTP_MIGRATION.sql;
```

### Issue 4: "DELIMITER" Syntax Error
```
Solution:
- If using Command Line, copy-paste entire script at once
- Don't execute line-by-line
- If DBeaver/Workbench, use Execute Script option (not Execute SQL)
```

### Issue 5: Stored Procedures Not Created
```sql
Solution:
-- Check if they exist
SHOW PROCEDURE STATUS WHERE db = 'auth_db';

-- If missing, create individually:
DELIMITER //
CREATE PROCEDURE sp_cleanup_expired_otps()
BEGIN
    DELETE FROM otp_verifications
    WHERE expires_at < NOW() AND is_used = TRUE;
END//
DELIMITER ;
```

---

## Migration Execution Checklist

### Before Running:
- [ ] Database credentials are correct
- [ ] Network access configured (security groups for AWS)
- [ ] Sufficient disk space (20GB free recommended)
- [ ] Database user has CREATE/DROP privileges
- [ ] MySQL 8.0+ installed/available

### During Execution:
- [ ] Script is running in SQL Editor
- [ ] No errors appearing (warnings are OK)
- [ ] Progress visible in Results panel
- [ ] Estimated time: 30-60 seconds

### After Execution:
- [ ] Run verification queries above
- [ ] Count of 20 tables visible
- [ ] schema_version shows latest version
- [ ] OTP table exists and accessible
- [ ] Stored procedures created successfully

---

## File Sizes & Execution Times

| File | Size | Tables | Execution Time | Best For |
|------|------|--------|-----------------|----------|
| WORKBENCH_OTP_MIGRATION.sql | ~8 KB | 1 | <5 seconds | Adding OTP to existing DB |
| COMPLETE_SCHEMA_AWS_PRODUCTION.sql | ~110 KB | 20 | 30-60 seconds | Fresh AWS deployment |

---

## Next Steps After Migration

1. **Configure Backend Properties**
   ```
   Edit: auth-service/src/main/resources/application.properties
   Update:
   - spring.datasource.url
   - spring.datasource.username
   - spring.datasource.password
   - Email credentials
   ```

2. **Rebuild and Deploy**
   ```bash
   mvn clean install -DskipTests
   ```

3. **Test Endpoints**
   ```bash
   curl -X POST http://localhost:8080/auth/send-otp \
        -H "Content-Type: application/json" \
        -d '{"email":"test@example.com"}'
   ```

4. **Verify Database**
   ```sql
   SELECT * FROM otp_verifications LIMIT 1;
   ```

---

## Support & Documentation

- **OTP Implementation:** See `OTP_VERIFICATION_IMPLEMENTATION.md`
- **AWS Deployment:** See `AWS_DEPLOYMENT_COMPLETE_GUIDE.md`
- **Full Schema Details:** See `COMPLETE_SCHEMA_AWS_PRODUCTION.sql` comments
- **Email Config:** See `OTP_VERIFICATION_IMPLEMENTATION.md` → Email Configuration

---

**Created:** January 6, 2026  
**Version:** 2.0.2  
**Status:** Production Ready ✅

