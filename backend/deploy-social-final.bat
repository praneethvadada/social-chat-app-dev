@echo off
REM Social Service Deployment Script
REM Deploys social-service to EC2: 98.92.152.200

echo =========================================
echo Social Service Deployment
echo =========================================
echo.

set EC2_IP=98.90.116.96
set PRIVATE_IP=172.31.74.81
set KEY_FILE=C:\Users\gidut\Downloads\social-media-key.pem

REM Check if JAR exists
if not exist "social-service\target\social-service-1.0.0.jar" (
    echo ERROR: JAR file not found!
    echo Building the project...
    set "JAVA_HOME=C:\Program Files\Java\jdk-17"
    set "PATH=%JAVA_HOME%\bin;%PATH%"
    call mvn clean package -pl social-service -am -DskipTests
    if errorlevel 1 (
        echo Build failed!
        pause
        exit /b 1
    )
)

echo.
echo Step 1: Uploading JAR to EC2...
echo =========================================
echo yes | scp -o StrictHostKeyChecking=no -i "%KEY_FILE%" social-service\target\social-service-1.0.0.jar ec2-user@%EC2_IP%:/tmp/social-service.jar

echo.
echo Step 2: Uploading environment file...
echo =========================================
scp -o StrictHostKeyChecking=no -i "%KEY_FILE%" social-env-final.txt ec2-user@%EC2_IP%:/tmp/social-env.txt

echo.
echo Step 3: Uploading service file...
echo =========================================
scp -o StrictHostKeyChecking=no -i "%KEY_FILE%" social-service.service ec2-user@%EC2_IP%:/tmp/social-service.service

echo.
echo Step 4: Setting up on EC2...
echo =========================================
ssh -o StrictHostKeyChecking=no -i "%KEY_FILE%" ec2-user@%EC2_IP% "sudo mkdir -p /opt/social-service && sudo mv /tmp/social-service.jar /opt/social-service/social-service.jar && sudo mv /tmp/social-env.txt /opt/social-service/env.txt && sudo mv /tmp/social-service.service /etc/systemd/system/ && sudo chmod 644 /etc/systemd/system/social-service.service && sudo systemctl daemon-reload && sudo systemctl enable social-service && sudo systemctl restart social-service"

echo.
echo Step 5: Checking service status...
echo =========================================
timeout /t 5 /nobreak >nul
ssh -o StrictHostKeyChecking=no -i "%KEY_FILE%" ec2-user@%EC2_IP% "sudo systemctl status social-service --no-pager"

echo.
echo Step 6: Testing health endpoint...
echo =========================================
timeout /t 3 /nobreak >nul
ssh -o StrictHostKeyChecking=no -i "%KEY_FILE%" ec2-user@%EC2_IP% "curl -s http://localhost:8082/actuator/health || echo 'Service starting...'"

echo.
echo =========================================
echo Deployment Complete!
echo =========================================
echo.
echo Service Details:
echo   - Public IP:  %EC2_IP%
echo   - Private IP: %PRIVATE_IP%
echo   - Port:       8082
echo.
echo Health Check: http://%EC2_IP%:8082/actuator/health
echo Swagger UI:   http://%EC2_IP%:8082/swagger-ui.html
echo.
echo Next: Update API Gateway to route to social-service
echo   Add to gateway-env-final.txt: SOCIAL_SERVICE_URL=http://%PRIVATE_IP%:8082
echo.
pause
