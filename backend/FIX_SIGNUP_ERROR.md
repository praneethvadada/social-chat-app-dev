# Fix "is_private doesn't have a default value" Error

## The Problem
When signing up, you're getting this error:
```
Field 'is_private' doesn't have a default value
```

This happens because the `users` table is missing several columns that were added later.

## Quick Fix (Choose ONE method)

### Method 1: Using the Batch Script (EASIEST)
1. Open Command Prompt in the `backend` folder
2. Run:
   ```bash
   run-migration.bat
   ```
3. Done! The script will add all missing columns automatically.

### Method 2: Using MySQL Client (DBeaver, phpMyAdmin, etc.)
1. Open your MySQL client
2. Connect to `auth_db` database
3. Open the file `SIMPLE_MIGRATION.sql`
4. Execute the entire script
5. Done!

### Method 3: Using Command Line
```bash
cd backend
mysql -uroot -proot auth_db < SIMPLE_MIGRATION.sql
```
(Replace `root` with your MySQL username/password)

## What Gets Added

The migration adds these columns to the `users` table:

| Column Name | Type | Default | Description |
|------------|------|---------|-------------|
| `is_private` | BOOLEAN | FALSE | Account privacy setting |
| `is_verified` | BOOLEAN | FALSE | Verified badge status |
| `show_read_receipts` | BOOLEAN | TRUE | Read receipts privacy |
| `show_activity_status` | BOOLEAN | TRUE | Online status privacy |
| `cover_photo` | VARCHAR(255) | NULL | Cover photo URL |
| `location` | VARCHAR(100) | NULL | User location |
| `website` | VARCHAR(255) | NULL | User website |
| `date_of_birth` | DATE | NULL | Date of birth |

## After Migration

1. Restart your Spring Boot backend services
2. Sign up should now work without errors
3. All new users will have default values:
   - `is_private` = FALSE (public account)
   - `show_read_receipts` = TRUE (enabled)
   - `show_activity_status` = TRUE (enabled)

## Troubleshooting

**Error: "Access denied for user"**
- Update MySQL credentials in `run-migration.bat`
- Or use Method 2/3 with your correct credentials

**Error: "Unknown database 'auth_db'"**
- Create the database first:
  ```sql
  CREATE DATABASE auth_db;
  ```

**Still getting errors?**
- Check if columns already exist:
  ```sql
  SHOW COLUMNS FROM users;
  ```
- If columns exist, the issue might be elsewhere. Check backend logs.
