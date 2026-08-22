@echo off
echo ========================================
echo Starting Social Media Backend Services
echo ========================================
echo.

REM Check if MySQL is running
echo Checking MySQL...
sc query MySQL80 | find "RUNNING" >nul
if errorlevel 1 (
    echo [WARNING] MySQL is not running. Starting MySQL...
    net start MySQL80
) else (
    echo [OK] MySQL is running
)
echo.

REM Check if Redis is running
echo Checking Redis...
tasklist /FI "IMAGENAME eq redis-server.exe" 2>NUL | find /I /N "redis-server.exe">NUL
if "%ERRORLEVEL%"=="0" (
    echo [OK] Redis is running
) else (
    echo [WARNING] Redis is not running. Please start Redis manually.
    echo Starting Redis in a new window...
    start "Redis Server" redis-server
    timeout /t 3 >nul
)
echo.

echo Building all services...
call mvn clean install -DskipTests
if errorlevel 1 (
    echo [ERROR] Build failed!
    pause
    exit /b 1
)
echo.

echo ========================================
echo Starting services...
echo ========================================
echo.

REM Start API Gateway
echo Starting API Gateway on port 8080...
start "API Gateway" cmd /k "cd api-gateway && mvn spring-boot:run"
timeout /t 5 >nul

REM Start Auth Service
echo Starting Auth Service on port 8081...
start "Auth Service" cmd /k "cd auth-service && mvn spring-boot:run"
timeout /t 5 >nul

REM Start Social Service
echo Starting Social Service on port 8082...
start "Social Service" cmd /k "cd social-service && set FIREBASE_KEY_PATH=C:\firebase\serviceAccountKey.json && mvn spring-boot:run"
timeout /t 5 >nul

echo.
echo ========================================
echo All services are starting!
echo ========================================
echo.
echo Services:
echo   - API Gateway:    http://localhost:8080
echo   - Auth Service:   http://localhost:8081
echo   - Social Service: http://localhost:8082
echo.
echo Wait for all services to fully start (check terminal windows)
echo Then access via: http://localhost:8080/api/...
echo.
echo Press any key to exit this window...
pause >nul
