@echo off
echo ========================================
echo Running Database Migration
echo ========================================
echo.

REM Change these if your MySQL credentials are different
set DB_USER=root
set DB_PASS=root
set DB_HOST=localhost
set DB_PORT=3306
set DB_NAME=auth_db

echo Connecting to MySQL and running migration...
echo.

mysql -u%DB_USER% -p%DB_PASS% -h%DB_HOST% -P%DB_PORT% %DB_NAME% < SIMPLE_MIGRATION.sql

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================
    echo Migration completed successfully!
    echo ========================================
    echo.
    echo You can now run your application.
) else (
    echo.
    echo ========================================
    echo Migration failed!
    echo ========================================
    echo.
    echo Please check:
    echo 1. MySQL is running
    echo 2. Username/password are correct
    echo 3. Database 'auth_db' exists
)

pause
