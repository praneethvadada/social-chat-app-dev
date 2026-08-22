@echo off
REM ========================================
REM Deploy ALL Services to AWS with Firebase
REM ========================================

echo.
echo ================================================
echo   AWS Complete Backend Deployment
echo   - API Gateway (43 MB)
echo   - Auth Service (78 MB)
echo   - Social Service (123 MB) + Firebase
echo ================================================
echo.

REM Verify all JAR files exist
if not exist "backend\api-gateway\target\api-gateway-1.0.0.jar" (
    echo [ERROR] API Gateway JAR not found!
    echo Run: mvn clean package in backend\api-gateway
    pause
    exit /b 1
)
echo [OK] API Gateway JAR found

if not exist "backend\auth-service\target\auth-service-1.0.0.jar" (
    echo [ERROR] Auth Service JAR not found!
    echo Run: mvn clean package in backend\auth-service
    pause
    exit /b 1
)
echo [OK] Auth Service JAR found

if not exist "backend\social-service\target\social-service-1.0.0.jar" (
    echo [ERROR] Social Service JAR not found!
    echo Run: mvn clean package in backend\social-service
    pause
    exit /b 1
)
echo [OK] Social Service JAR found

if not exist "serviceAccountKey.json" (
    echo [WARNING] Firebase key not found at root!
    if exist "backend\social-service\src\main\resources\serviceAccountKey.json" (
        echo [OK] Copying Firebase key from resources...
        copy "backend\social-service\src\main\resources\serviceAccountKey.json" "serviceAccountKey.json" >nul
    ) else (
        echo [ERROR] Firebase key not found anywhere!
        pause
        exit /b 1
    )
)
echo [OK] Firebase key found
echo.

REM Get EC2 configuration
echo ================================================
echo   EC2 Configuration
echo ================================================
echo.
set /p EC2_IP=Enter EC2 Public IP/Hostname: 
set /p KEY_FILE=Enter path to .pem key file: 
set EC2_USER=ec2-user
echo.
echo Configuration:
echo   EC2: %EC2_IP%
echo   Key: %KEY_FILE%
echo   User: %EC2_USER%
echo.
set /p CONFIRM=Deploy all 3 services to EC2? (y/n): 
if /i not "%CONFIRM%"=="y" (
    echo Deployment cancelled.
    exit /b 0
)

echo.
echo ================================================
echo   Step 1/6: Uploading JAR Files
echo ================================================
echo.

echo [1/3] Uploading API Gateway (43 MB)...
scp -i "%KEY_FILE%" -o StrictHostKeyChecking=no backend\api-gateway\target\api-gateway-1.0.0.jar %EC2_USER%@%EC2_IP%:~/api-gateway.jar
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Failed to upload API Gateway
    goto :error
)
echo [OK] API Gateway uploaded

echo [2/3] Uploading Auth Service (78 MB)...
scp -i "%KEY_FILE%" -o StrictHostKeyChecking=no backend\auth-service\target\auth-service-1.0.0.jar %EC2_USER%@%EC2_IP%:~/auth-service.jar
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Failed to upload Auth Service
    goto :error
)
echo [OK] Auth Service uploaded

echo [3/3] Uploading Social Service (123 MB)...
scp -i "%KEY_FILE%" -o StrictHostKeyChecking=no backend\social-service\target\social-service-1.0.0.jar %EC2_USER%@%EC2_IP%:~/social-service.jar
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Failed to upload Social Service
    goto :error
)
echo [OK] Social Service uploaded

echo.
echo ================================================
echo   Step 2/6: Uploading Firebase Key
echo ================================================
echo.

scp -i "%KEY_FILE%" -o StrictHostKeyChecking=no serviceAccountKey.json %EC2_USER%@%EC2_IP%:~/serviceAccountKey.json
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Failed to upload Firebase key
    goto :error
)
echo [OK] Firebase key uploaded

echo.
echo ================================================
echo   Step 3/6: Creating Directory Structure
echo ================================================
echo.

ssh -i "%KEY_FILE%" -o StrictHostKeyChecking=no %EC2_USER%@%EC2_IP% "mkdir -p ~/api-gateway ~/auth-service ~/social-service && mv ~/api-gateway.jar ~/api-gateway/ && mv ~/auth-service.jar ~/auth-service/ && mv ~/social-service.jar ~/social-service/ && mv ~/serviceAccountKey.json ~/social-service/ && chmod 600 ~/social-service/serviceAccountKey.json"
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Failed to create directory structure
    goto :error
)
echo [OK] Directory structure created

echo.
echo ================================================
echo   Step 4/6: Creating Auth Service Startup Script
echo ================================================
echo.

REM Create auth service startup script locally
echo #!/bin/bash > auth-start.sh
echo. >> auth-start.sh
echo # Database configuration >> auth-start.sh
echo export SPRING_DATASOURCE_URL="jdbc:mysql://YOUR_RDS_ENDPOINT:3306/auth_db?useSSL=true&serverTimezone=UTC" >> auth-start.sh
echo export SPRING_DATASOURCE_USERNAME="admin" >> auth-start.sh
echo export SPRING_DATASOURCE_PASSWORD="YOUR_DB_PASSWORD" >> auth-start.sh
echo. >> auth-start.sh
echo # JWT Secret >> auth-start.sh
echo export JWT_SECRET="5367566B59703373367639792F423F4528482B4D6251655468576D5A71347437" >> auth-start.sh
echo. >> auth-start.sh
echo # Email configuration >> auth-start.sh
echo export SPRING_MAIL_HOST="smtp.gmail.com" >> auth-start.sh
echo export SPRING_MAIL_PORT="587" >> auth-start.sh
echo export SPRING_MAIL_USERNAME="your-email@gmail.com" >> auth-start.sh
echo export SPRING_MAIL_PASSWORD="your-app-password" >> auth-start.sh
echo. >> auth-start.sh
echo cd ~/auth-service >> auth-start.sh
echo nohup java -jar -Xmx512m auth-service.jar ^> auth-service.log 2^>^&1 ^& >> auth-start.sh
echo echo $! ^> auth-service.pid >> auth-start.sh
echo echo "Auth Service started on port 8081. PID: $(cat auth-service.pid)" >> auth-start.sh

scp -i "%KEY_FILE%" -o StrictHostKeyChecking=no auth-start.sh %EC2_USER%@%EC2_IP%:~/auth-service/start.sh
ssh -i "%KEY_FILE%" -o StrictHostKeyChecking=no %EC2_USER%@%EC2_IP% "chmod +x ~/auth-service/start.sh"
del auth-start.sh
echo [OK] Auth Service startup script created

echo.
echo ================================================
echo   Step 5/6: Creating Social Service Startup Script
echo ================================================
echo.

REM Create social service startup script locally
echo #!/bin/bash > social-start.sh
echo. >> social-start.sh
echo # Firebase key >> social-start.sh
echo export FIREBASE_KEY_PATH="~/social-service/serviceAccountKey.json" >> social-start.sh
echo. >> social-start.sh
echo # Database configuration >> social-start.sh
echo export SPRING_DATASOURCE_URL="jdbc:mysql://YOUR_RDS_ENDPOINT:3306/auth_db?useSSL=true&serverTimezone=UTC" >> social-start.sh
echo export SPRING_DATASOURCE_USERNAME="admin" >> social-start.sh
echo export SPRING_DATASOURCE_PASSWORD="YOUR_DB_PASSWORD" >> social-start.sh
echo. >> social-start.sh
echo # JWT Secret >> social-start.sh
echo export JWT_SECRET="5367566B59703373367639792F423F4528482B4D6251655468576D5A71347437" >> social-start.sh
echo. >> social-start.sh
echo # S3 configuration >> social-start.sh
echo export AWS_S3_BUCKET_NAME="social-media-gidut-54513" >> social-start.sh
echo export AWS_S3_REGION="us-east-1" >> social-start.sh
echo. >> social-start.sh
echo # Agora configuration >> social-start.sh
echo export AGORA_APP_ID="96f2b1afbf744dc5818487f2e31ed9e7" >> social-start.sh
echo export AGORA_APP_CERT="ef473b70af0d40989d94ca2d7ce5c248" >> social-start.sh
echo. >> social-start.sh
echo cd ~/social-service >> social-start.sh
echo nohup java -jar -Xmx1024m social-service.jar ^> social-service.log 2^>^&1 ^& >> social-start.sh
echo echo $! ^> social-service.pid >> social-start.sh
echo echo "Social Service started on port 8082. PID: $(cat social-service.pid)" >> social-start.sh

scp -i "%KEY_FILE%" -o StrictHostKeyChecking=no social-start.sh %EC2_USER%@%EC2_IP%:~/social-service/start.sh
ssh -i "%KEY_FILE%" -o StrictHostKeyChecking=no %EC2_USER%@%EC2_IP% "chmod +x ~/social-service/start.sh"
del social-start.sh
echo [OK] Social Service startup script created

echo.
echo ================================================
echo   Step 6/6: Creating API Gateway Startup Script
echo ================================================
echo.

REM Create api gateway startup script locally
echo #!/bin/bash > gateway-start.sh
echo. >> gateway-start.sh
echo # Service URLs >> gateway-start.sh
echo export AUTH_SERVICE_URL="http://localhost:8081" >> gateway-start.sh
echo export SOCIAL_SERVICE_URL="http://localhost:8082" >> gateway-start.sh
echo. >> gateway-start.sh
echo cd ~/api-gateway >> gateway-start.sh
echo nohup java -jar -Xmx512m api-gateway.jar ^> api-gateway.log 2^>^&1 ^& >> gateway-start.sh
echo echo $! ^> api-gateway.pid >> gateway-start.sh
echo echo "API Gateway started on port 8080. PID: $(cat api-gateway.pid)" >> gateway-start.sh

scp -i "%KEY_FILE%" -o StrictHostKeyChecking=no gateway-start.sh %EC2_USER%@%EC2_IP%:~/api-gateway/start.sh
ssh -i "%KEY_FILE%" -o StrictHostKeyChecking=no %EC2_USER%@%EC2_IP% "chmod +x ~/api-gateway/start.sh"
del gateway-start.sh
echo [OK] API Gateway startup script created

echo.
echo ================================================
echo   DEPLOYMENT COMPLETE!
echo ================================================
echo.
echo All services uploaded successfully:
echo   - API Gateway    : ~/api-gateway/
echo   - Auth Service   : ~/auth-service/
echo   - Social Service : ~/social-service/ (with Firebase)
echo.
echo ================================================
echo   NEXT STEPS:
echo ================================================
echo.
echo 1. SSH into your EC2 instance:
echo    ssh -i "%KEY_FILE%" %EC2_USER%@%EC2_IP%
echo.
echo 2. Update database credentials:
echo    nano auth-service/start.sh
echo    nano social-service/start.sh
echo.
echo 3. Start services IN ORDER:
echo    cd auth-service && ./start.sh
echo    cd ../social-service && ./start.sh
echo    cd ../api-gateway && ./start.sh
echo.
echo 4. Check logs:
echo    tail -f auth-service/auth-service.log
echo    tail -f social-service/social-service.log
echo    tail -f api-gateway/api-gateway.log
echo.
echo 5. Verify services:
echo    curl http://localhost:8081/actuator/health
echo    curl http://localhost:8082/actuator/health
echo    curl http://localhost:8080/actuator/health
echo.
echo ================================================
echo   Service Ports:
echo ================================================
echo   - Auth Service   : 8081
echo   - Social Service : 8082
echo   - API Gateway    : 8080 (Main entry point)
echo.
echo Make sure EC2 security group allows:
echo   - Port 22 (SSH)
echo   - Port 8080 (API Gateway - external access)
echo   - Port 8081, 8082 (optional - for direct service access)
echo   - Port 3306 (MySQL - from EC2 to RDS)
echo.
pause
exit /b 0

:error
echo.
echo [ERROR] Deployment failed!
echo Check your EC2 connection and try again.
pause
exit /b 1
