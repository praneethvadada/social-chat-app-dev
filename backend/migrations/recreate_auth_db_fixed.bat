@echo off
REM Fixed: Recreate auth_db from schema and apply chat-only migrations (Windows)
REM Usage: run this from the workspace root in an elevated PowerShell/CMD prompt.

setlocal enabledelayedexpansion
set MYSQL_USER=root
set /p MYSQL_PASS=Enter MySQL root password: 

REM Backup existing DB (if present)
set BACKUP_FILE="%CD%\auth_db_backup_%DATE:~10,4%%DATE:~4,2%%DATE:~7,2%.sql"
echo Backing up existing auth_db to %BACKUP_FILE%
mysqldump -u %MYSQL_USER% -p%MYSQL_PASS% auth_db > %BACKUP_FILE% 2>nul
if errorlevel 1 (
  echo Warning: backup failed or auth_db does not exist, continuing...
)

echo Dropping and recreating auth_db...
mysql -u %MYSQL_USER% -p%MYSQL_PASS% -e "DROP DATABASE IF EXISTS auth_db; CREATE DATABASE auth_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
if errorlevel 1 (
  echo Failed to create database. Aborting.
  exit /b 1
)

echo Importing base schema (schema.sql)...
mysql -u %MYSQL_USER% -p%MYSQL_PASS% auth_db < "%CD%\backend\schema.sql"
if errorlevel 1 (
  echo Failed importing schema.sql. Aborting.
  exit /b 1
)

echo Applying profile columns migration (add_profile_columns.sql)...
mysql -u %MYSQL_USER% -p%MYSQL_PASS% auth_db < "%CD%\backend\add_profile_columns.sql"

echo Applying read receipts migration (migrate_read_receipts.sql)...
mysql -u %MYSQL_USER% -p%MYSQL_PASS% auth_db < "%CD%\backend\migrate_read_receipts.sql"

echo Applying code-required message migration (2025-12-28-add-message-clientid-readat.sql)...
mysql -u %MYSQL_USER% -p%MYSQL_PASS% auth_db < "%CD%\backend\migrations\2025-12-28-add-message-clientid-readat.sql"

echo Applying chat schema fix (V2025__chat_schema_fix.sql)...
mysql -u %MYSQL_USER% -p%MYSQL_PASS% auth_db < "%CD%\backend\migrations\V2025__chat_schema_fix.sql"

echo All migrations applied. You may now restart backend services.
echo To restart services, run your usual service scripts (e.g. start-all-services.bat).
endlocal
pause
