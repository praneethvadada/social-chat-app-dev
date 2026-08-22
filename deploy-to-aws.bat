@echo off
REM ========================================
REM AWS Social Service Deployment Script
REM ========================================

echo.
echo ====================================
echo AWS Social Service Deployment
echo ====================================
echo.

REM Check if JAR file exists
if not exist "backend\social-service\target\social-service-1.0.0.jar" (
    echo [ERROR] JAR file not found!
    echo Please build the project first:
    echo   cd backend\social-service
    echo   mvn clean package -DskipTests
    pause
    exit /b 1
)

echo [OK] JAR file found: backend\social-service\target\social-service-1.0.0.jar
echo.

REM Check for Firebase service key
set "FIREBASE_KEY="
if exist "serviceAccountKey.json" (
    set "FIREBASE_KEY=serviceAccountKey.json"
    echo [OK] Firebase key found: serviceAccountKey.json
) else if exist "backend\social-service\src\main\resources\serviceAccountKey.json" (
    set "FIREBASE_KEY=backend\social-service\src\main\resources\serviceAccountKey.json"
    echo [OK] Firebase key found in resources
) else (
    echo [WARNING] Firebase service key not found!
    echo.
    echo Please download it from Firebase Console:
    echo   1. Go to https://console.firebase.google.com/
    echo   2. Select your project
    echo   3. Settings ^> Project Settings ^> Service Accounts
    echo   4. Generate New Private Key
    echo   5. Save as: serviceAccountKey.json
    echo.
    set /p "CONTINUE=Continue without Firebase key? (y/n): "
    if /i not "%CONTINUE%"=="y" (
        exit /b 1
    )
)
echo.

REM Prompt for EC2 details
echo ====================================
echo EC2 Instance Configuration
echo ====================================
echo.

set /p "EC2_IP=Enter your EC2 public IP/hostname: "
set /p "KEY_FILE=Enter path to your .pem key file: "
set "EC2_USER=ec2-user"

echo.
echo Configuration:
echo   EC2 IP: %EC2_IP%
echo   Key File: %KEY_FILE%
echo   User: %EC2_USER%
echo.

set /p "CONFIRM=Proceed with deployment? (y/n): "
if /i not "%CONFIRM%"=="y" (
    echo Deployment cancelled.
    exit /b 0
)

echo.
echo ====================================
echo Step 1: Uploading JAR file
echo ====================================
echo.

scp -i "%KEY_FILE%" backend\social-service\target\social-service-1.0.0.jar %EC2_USER%@%EC2_IP%:/home/%EC2_USER%/
if errorlevel 1 (
    echo [ERROR] Failed to upload JAR file
    pause
    exit /b 1
)
echo [OK] JAR file uploaded successfully

if defined FIREBASE_KEY (
    echo.
    echo ====================================
    echo Step 2: Uploading Firebase key
    echo ====================================
    echo.
    
    scp -i "%KEY_FILE%" "%FIREBASE_KEY%" %EC2_USER%@%EC2_IP%:/home/%EC2_USER%/serviceAccountKey.json
    if errorlevel 1 (
        echo [ERROR] Failed to upload Firebase key
        pause
        exit /b 1
    )
    echo [OK] Firebase key uploaded successfully
)

echo.
echo ====================================
echo Step 3: Creating deployment scripts
echo ====================================
echo.

REM Create temporary script for EC2
echo #!/bin/bash > deploy_setup.sh
echo echo "Setting up Social Service..." >> deploy_setup.sh
echo mkdir -p /home/%EC2_USER%/social-service >> deploy_setup.sh
echo mv /home/%EC2_USER%/social-service-1.0.0.jar /home/%EC2_USER%/social-service/ >> deploy_setup.sh
if defined FIREBASE_KEY (
    echo mv /home/%EC2_USER%/serviceAccountKey.json /home/%EC2_USER%/social-service/ >> deploy_setup.sh
    echo chmod 600 /home/%EC2_USER%/social-service/serviceAccountKey.json >> deploy_setup.sh
)
echo cd /home/%EC2_USER%/social-service >> deploy_setup.sh
echo echo "Setup complete!" >> deploy_setup.sh

REM Upload setup script
scp -i "%KEY_FILE%" deploy_setup.sh %EC2_USER%@%EC2_IP%:/home/%EC2_USER%/
del deploy_setup.sh

echo [OK] Setup scripts created

echo.
echo ====================================
echo Step 4: Running setup on EC2
echo ====================================
echo.

ssh -i "%KEY_FILE%" %EC2_USER%@%EC2_IP% "chmod +x /home/%EC2_USER%/deploy_setup.sh && /home/%EC2_USER%/deploy_setup.sh"

echo.
echo ====================================
echo Deployment Complete!
echo ====================================
echo.
echo Next steps:
echo   1. SSH into your EC2: ssh -i "%KEY_FILE%" %EC2_USER%@%EC2_IP%
echo   2. Go to: cd social-service
echo   3. Configure environment variables (see AWS_DEPLOY_SOCIAL_SERVICE_WITH_FIREBASE.md)
echo   4. Start the service: ./start.sh
echo.
echo For detailed instructions, see: AWS_DEPLOY_SOCIAL_SERVICE_WITH_FIREBASE.md
echo.

pause
