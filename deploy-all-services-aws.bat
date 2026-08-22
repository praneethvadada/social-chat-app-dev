@echo off
REM ========================================
REM Deploy ALL Services to AWS with Firebase
REM ========================================

setlocal EnableDelayedExpansion

echo:
echo ================================================
echo   AWS Complete Backend Deployment
echo   - API Gateway (43 MB)
echo   - Auth Service (78 MB)
echo   - Social Service (123 MB) + Firebase
echo ================================================
echo:

REM Verify all JAR files exist
set "ERRORS=0"

if not exist "backend\api-gateway\target\api-gateway-1.0.0.jar" (
    echo [ERROR] API Gateway JAR not found!
    set /a ERRORS+=1
) else (
    echo [OK] API Gateway JAR found
)

if not exist "backend\auth-service\target\auth-service-1.0.0.jar" (
    echo [ERROR] Auth Service JAR not found!
    set /a ERRORS+=1
) else (
    echo [OK] Auth Service JAR found
)

if not exist "backend\social-service\target\social-service-1.0.0.jar" (
    echo [ERROR] Social Service JAR not found!
    set /a ERRORS+=1
) else (
    echo [OK] Social Service JAR found
)

if not exist "serviceAccountKey.json" (
    echo [WARNING] Firebase key not found at root!
    if not exist "backend\social-service\src\main\resources\serviceAccountKey.json" (
        echo [ERROR] Firebase key not found anywhere!
        set /a ERRORS+=1
    ) else (
        echo [OK] Using Firebase key from resources
        copy "backend\social-service\src\main\resources\serviceAccountKey.json" "serviceAccountKey.json" >nul
    )
) else (
    echo [OK] Firebase key found
)

if !ERRORS! GTR 0 (
    echo:
    echo [ERROR] Missing !ERRORS! required file(s). Cannot proceed.
    pause
    exit /b 1
)

echo:
echo ================================================
echo   EC2 Configuration
echo ================================================
echo:

set /p "EC2_IP=Enter EC2 Public IP/Hostname: "
set /p "KEY_FILE=Enter path to .pem key file: "
set "EC2_USER=ec2-user"

echo:
echo Configuration:
echo   EC2: %EC2_IP%
echo   Key: %KEY_FILE%
echo   User: %EC2_USER%
echo:

set /p "CONFIRM=Deploy all 3 services to EC2? (y/n): "
if /i not "%CONFIRM%"=="y" (
    echo Deployment cancelled.
    exit /b 0
)

echo:
echo ================================================
echo   Step 1: Uploading JAR Files
echo ================================================
echo:

echo [1/3] Uploading API Gateway...
scp -i "%KEY_FILE%" backend\api-gateway\target\api-gateway-1.0.0.jar %EC2_USER%@%EC2_IP%:/home/%EC2_USER%/
if errorlevel 1 (
    echo [ERROR] Failed to upload API Gateway
    goto :error
)
echo [OK] API Gateway uploaded

echo [2/3] Uploading Auth Service...
scp -i "%KEY_FILE%" backend\auth-service\target\auth-service-1.0.0.jar %EC2_USER%@%EC2_IP%:/home/%EC2_USER%/
if errorlevel 1 (
    echo [ERROR] Failed to upload Auth Service
    goto :error
)
echo [OK] Auth Service uploaded

echo [3/3] Uploading Social Service...
scp -i "%KEY_FILE%" backend\social-service\target\social-service-1.0.0.jar %EC2_USER%@%EC2_IP%:/home/%EC2_USER%/
if errorlevel 1 (
    echo [ERROR] Failed to upload Social Service
    goto :error
)
echo [OK] Social Service uploaded

echo:
echo ================================================
echo   Step 2: Uploading Firebase Key
echo ================================================
echo:

scp -i "%KEY_FILE%" serviceAccountKey.json %EC2_USER%@%EC2_IP%:/home/%EC2_USER%/
if errorlevel 1 (
    echo [ERROR] Failed to upload Firebase key
    goto :error
)
echo [OK] Firebase key uploaded

echo:
echo ================================================
echo   Step 3: Creating Directory Structure
echo ================================================
echo:

REM Create setup script
echo #^!/bin/bash > setup_services.sh
echo echo "Setting up services on EC2..." >> setup_services.sh
echo: >> setup_services.sh
echo # Create directories >> setup_services.sh
echo mkdir -p /home/%EC2_USER%/api-gateway >> setup_services.sh
echo mkdir -p /home/%EC2_USER%/auth-service >> setup_services.sh
echo mkdir -p /home/%EC2_USER%/social-service >> setup_services.sh
echo: >> setup_services.sh
echo # Move JAR files >> setup_services.sh
echo mv /home/%EC2_USER%/api-gateway-1.0.0.jar /home/%EC2_USER%/api-gateway/ >> setup_services.sh
echo mv /home/%EC2_USER%/auth-service-1.0.0.jar /home/%EC2_USER%/auth-service/ >> setup_services.sh
echo mv /home/%EC2_USER%/social-service-1.0.0.jar /home/%EC2_USER%/social-service/ >> setup_services.sh
echo: >> setup_services.sh
echo # Move and secure Firebase key >> setup_services.sh
echo mv /home/%EC2_USER%/serviceAccountKey.json /home/%EC2_USER%/social-service/ >> setup_services.sh
echo chmod 600 /home/%EC2_USER%/social-service/serviceAccountKey.json >> setup_services.sh
echo: >> setup_services.sh
echo echo "Setup complete!" >> setup_services.sh
echo echo "Directories created:" >> setup_services.sh
echo echo "  - /home/%EC2_USER%/api-gateway" >> setup_services.sh
echo echo "  - /home/%EC2_USER%/auth-service" >> setup_services.sh
echo echo "  - /home/%EC2_USER%/social-service (with Firebase key)" >> setup_services.sh

REM Upload and execute setup script
scp -i "%KEY_FILE%" setup_services.sh %EC2_USER%@%EC2_IP%:/home/%EC2_USER%/
ssh -i "%KEY_FILE%" %EC2_USER%@%EC2_IP% "chmod +x /home/%EC2_USER%/setup_services.sh && /home/%EC2_USER%/setup_services.sh"

del setup_services.sh

echo [OK] Directory structure created

echo:
echo ================================================
echo   Step 4: Creating Startup Scripts
echo ================================================
echo:

REM Create startup scripts file
echo #^!/bin/bash > create_start_scripts.sh
echo: >> create_start_scripts.sh
echo # AUTH SERVICE START SCRIPT >> create_start_scripts.sh
echo cat ^> /home/%EC2_USER%/auth-service/start.sh ^<^< 'EOFAUTH' >> create_start_scripts.sh
echo #^!/bin/bash >> create_start_scripts.sh
echo: >> create_start_scripts.sh
echo # Database configuration >> create_start_scripts.sh
echo export SPRING_DATASOURCE_URL="jdbc:mysql://YOUR_RDS_ENDPOINT:3306/auth_db?useSSL=true&serverTimezone=UTC" >> create_start_scripts.sh
echo export SPRING_DATASOURCE_USERNAME="admin" >> create_start_scripts.sh
echo export SPRING_DATASOURCE_PASSWORD="YOUR_DB_PASSWORD" >> create_start_scripts.sh
echo: >> create_start_scripts.sh
echo # JWT Secret >> create_start_scripts.sh
echo export JWT_SECRET="5367566B59703373367639792F423F4528482B4D6251655468576D5A71347437" >> create_start_scripts.sh
echo: >> create_start_scripts.sh
echo # Email configuration (for OTP) >> create_start_scripts.sh
echo export SPRING_MAIL_HOST="smtp.gmail.com" >> create_start_scripts.sh
echo export SPRING_MAIL_PORT="587" >> create_start_scripts.sh
echo export SPRING_MAIL_USERNAME="your-email@gmail.com" >> create_start_scripts.sh
echo export SPRING_MAIL_PASSWORD="your-app-password" >> create_start_scripts.sh
echo: >> create_start_scripts.sh
echo cd /home/%EC2_USER%/auth-service >> create_start_scripts.sh
echo nohup java -jar -Xmx512m auth-service-1.0.0.jar ^> auth-service.log 2^>^&1 ^& >> create_start_scripts.sh
echo echo $^! ^> auth-service.pid >> create_start_scripts.sh
echo echo "Auth Service started on port 8081. PID: $(cat auth-service.pid)" >> create_start_scripts.sh
echo EOFAUTH >> create_start_scripts.sh
echo: >> create_start_scripts.sh
echo # SOCIAL SERVICE START SCRIPT >> create_start_scripts.sh
echo cat ^> /home/%EC2_USER%/social-service/start.sh ^<^< 'EOFSOCIAL' >> create_start_scripts.sh
echo #^!/bin/bash >> create_start_scripts.sh
echo: >> create_start_scripts.sh
echo # Firebase key >> create_start_scripts.sh
echo export FIREBASE_KEY_PATH="/home/%EC2_USER%/social-service/serviceAccountKey.json" >> create_start_scripts.sh
echo: >> create_start_scripts.sh
echo # Database configuration >> create_start_scripts.sh
echo export SPRING_DATASOURCE_URL="jdbc:mysql://YOUR_RDS_ENDPOINT:3306/auth_db?useSSL=true&serverTimezone=UTC" >> create_start_scripts.sh
echo export SPRING_DATASOURCE_USERNAME="admin" >> create_start_scripts.sh
echo export SPRING_DATASOURCE_PASSWORD="YOUR_DB_PASSWORD" >> create_start_scripts.sh
echo: >> create_start_scripts.sh
echo # JWT Secret >> create_start_scripts.sh
echo export JWT_SECRET="5367566B59703373367639792F423F4528482B4D6251655468576D5A71347437" >> create_start_scripts.sh
echo: >> create_start_scripts.sh
echo # S3 configuration >> create_start_scripts.sh
echo export AWS_S3_BUCKET_NAME="social-media-gidut-54513" >> create_start_scripts.sh
echo export AWS_S3_REGION="us-east-1" >> create_start_scripts.sh
echo: >> create_start_scripts.sh
echo # Agora configuration >> create_start_scripts.sh
echo export AGORA_APP_ID="96f2b1afbf744dc5818487f2e31ed9e7" >> create_start_scripts.sh
echo export AGORA_APP_CERT="ef473b70af0d40989d94ca2d7ce5c248" >> create_start_scripts.sh
echo: >> create_start_scripts.sh
echo cd /home/%EC2_USER%/social-service >> create_start_scripts.sh
echo nohup java -jar -Xmx1024m social-service-1.0.0.jar ^> social-service.log 2^>^&1 ^& >> create_start_scripts.sh
echo echo $^! ^> social-service.pid >> create_start_scripts.sh
echo echo "Social Service started on port 8082. PID: $(cat social-service.pid)" >> create_start_scripts.sh
echo EOFSOCIAL >> create_start_scripts.sh
echo: >> create_start_scripts.sh
echo # API GATEWAY START SCRIPT >> create_start_scripts.sh
echo cat ^> /home/%EC2_USER%/api-gateway/start.sh ^<^< 'EOFGATEWAY' >> create_start_scripts.sh
echo #^!/bin/bash >> create_start_scripts.sh
echo: >> create_start_scripts.sh
echo # Service URLs >> create_start_scripts.sh
echo export AUTH_SERVICE_URL="http://localhost:8081" >> create_start_scripts.sh
echo export SOCIAL_SERVICE_URL="http://localhost:8082" >> create_start_scripts.sh
echo: >> create_start_scripts.sh
echo cd /home/%EC2_USER%/api-gateway >> create_start_scripts.sh
echo nohup java -jar -Xmx512m api-gateway-1.0.0.jar ^> api-gateway.log 2^>^&1 ^& >> create_start_scripts.sh
echo echo $^! ^> api-gateway.pid >> create_start_scripts.sh
echo echo "API Gateway started on port 8080. PID: $(cat api-gateway.pid)" >> create_start_scripts.sh
echo EOFGATEWAY >> create_start_scripts.sh
echo: >> create_start_scripts.sh
echo # Make scripts executable >> create_start_scripts.sh
echo chmod +x /home/%EC2_USER%/auth-service/start.sh >> create_start_scripts.sh
echo chmod +x /home/%EC2_USER%/social-service/start.sh >> create_start_scripts.sh
echo chmod +x /home/%EC2_USER%/api-gateway/start.sh >> create_start_scripts.sh
echo: >> create_start_scripts.sh
echo echo "Startup scripts created!" >> create_start_scripts.sh

REM Upload and execute script creation
scp -i "%KEY_FILE%" create_start_scripts.sh %EC2_USER%@%EC2_IP%:/home/%EC2_USER%/
ssh -i "%KEY_FILE%" %EC2_USER%@%EC2_IP% "chmod +x /home/%EC2_USER%/create_start_scripts.sh && /home/%EC2_USER%/create_start_scripts.sh"

del create_start_scripts.sh

echo [OK] Startup scripts created

echo:
echo ================================================
echo   DEPLOYMENT COMPLETE!
echo ================================================
echo:
echo All services uploaded successfully:
echo   - API Gateway    : /home/%EC2_USER%/api-gateway/
echo   - Auth Service   : /home/%EC2_USER%/auth-service/
echo   - Social Service : /home/%EC2_USER%/social-service/ (with Firebase)
echo:
echo ================================================
echo   NEXT STEPS:
echo ================================================
echo:
echo 1. SSH into your EC2 instance:
echo    ssh -i "%KEY_FILE%" %EC2_USER%@%EC2_IP%
echo:
echo 2. Update database credentials in each service:
echo    nano auth-service/start.sh
echo    nano social-service/start.sh
echo:
echo 3. Start services in order:
echo    cd auth-service ^&^& ./start.sh
echo    cd ../social-service ^&^& ./start.sh
echo    cd ../api-gateway ^&^& ./start.sh
echo:
echo 4. Check logs:
echo    tail -f auth-service/auth-service.log
echo    tail -f social-service/social-service.log
echo    tail -f api-gateway/api-gateway.log
echo:
echo 5. Verify services:
echo    curl http://localhost:8081/actuator/health  # Auth Service
echo    curl http://localhost:8082/actuator/health  # Social Service
echo    curl http://localhost:8080/actuator/health  # API Gateway
echo:
echo ================================================
echo   Service Ports:
echo ================================================
echo   - Auth Service   : 8081
echo   - Social Service : 8082
echo   - API Gateway    : 8080 (Main entry point)
echo:
echo Make sure EC2 security group allows:
echo   - Port 22 (SSH)
echo   - Port 8080 (API Gateway - external access)
echo   - Port 8081, 8082 (optional - for direct service access)
echo   - Port 3306 (MySQL - from EC2 to RDS)
echo:
pause
exit /b 0

:error
echo:
echo [ERROR] Deployment failed!
pause
exit /b 1
