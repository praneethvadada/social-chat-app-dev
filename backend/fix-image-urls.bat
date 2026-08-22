@echo off
REM Fix malformed image URLs in RDS database
REM This script removes the incorrectly prepended baseUrl from S3 URLs

echo ========================================
echo  Fix Malformed Image URLs in Database
echo ========================================
echo.

REM Database connection details
set DB_HOST=social-app.ct1p5chjnfrd.us-east-1.rds.amazonaws.com
set DB_NAME=auth_db
set DB_USER=root

echo Connecting to: %DB_HOST%
echo Database: %DB_NAME%
echo.
echo This will fix image URLs that have been incorrectly prepended with the baseUrl.
echo Example: http://98.92.24.110:8080/api/socialhttps://social-media...
echo     Will become: https://social-media...
echo.

REM Check if AWS CLI is available (alternative method)
where aws >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo AWS CLI detected. You can use AWS Systems Manager Session Manager to connect.
    echo Run: aws rds execute-statement --resource-arn arn:aws:rds:us-east-1:ACCOUNT_ID:cluster:DB_CLUSTER --secret-arn SECRET_ARN --sql "@fix_image_urls.sql"
    echo.
)

REM Try connecting with psql if available
where psql >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo PostgreSQL client detected. Applying fix...
    echo.
    psql -h %DB_HOST% -U %DB_USER% -d %DB_NAME% -f fix_image_urls.sql
    
    if errorlevel 1 (
        echo.
        echo ERROR: Failed to apply fix.
        echo Please check your database credentials and try again.
    ) else (
        echo.
        echo ========================================
        echo  Fix applied successfully!
        echo ========================================
    )
) else (
    echo.
    echo ERROR: PostgreSQL client ^(psql^) not found.
    echo.
    echo Please install PostgreSQL client tools or use one of these alternatives:
    echo.
    echo 1. Install PostgreSQL: https://www.postgresql.org/download/
    echo 2. Use DBeaver or pgAdmin to run fix_image_urls.sql manually
    echo 3. Connect via AWS Systems Manager Session Manager
    echo 4. Use AWS RDS Data API
    echo.
)

echo.
pause
