@echo off
REM Test follow endpoint directly
echo Testing follow endpoint...
echo.

REM You'll need to replace YOUR_JWT_TOKEN with actual token from your app
set TOKEN=YOUR_JWT_TOKEN_HERE
set TARGET_USER_ID=15

curl -X POST "http://98.92.24.110:8080/api/social/followers/%TARGET_USER_ID%" ^
  -H "Authorization: Bearer %TOKEN%" ^
  -H "Content-Type: application/json" ^
  -v

echo.
echo.
echo Press any key to exit...
pause >nul
