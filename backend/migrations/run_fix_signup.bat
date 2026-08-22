@echo off
REM Migration script to fix signup issue - Add is_private and is_verified columns

setlocal enabledelayedexpansion
cd /d "%~dp0"

echo.
echo ====================================
echo Fix Signup Issue Migration
echo ====================================
echo.

echo Running migration to add is_private and is_verified columns...
mysql -u root -pvkceo3515 < fix_signup_is_private_is_verified.sql

if errorlevel 1 (
    echo [ERROR] Migration failed!
    pause
    exit /b 1
) else (
    echo [SUCCESS] Migration completed successfully!
    pause
    exit /b 0
)
