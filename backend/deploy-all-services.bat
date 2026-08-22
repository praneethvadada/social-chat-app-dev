@echo off
REM Deploy all services to single EC2 instance
REM Instance: i-0139d8ec8d73b924f (98.90.116.96)

echo =========================================
echo   Deploying All Services to EC2
echo   IP: 98.90.116.96
echo =========================================
echo.

set EC2_IP=98.90.116.96
set PRIVATE_IP=172.31.74.81
set KEY_FILE=C:\Users\gidut\Downloads\social-media-key.pem

REM Force Java 17 (project requires Java 17)
set "JAVA_HOME=C:\Program Files\Java\jdk-17"
set "PATH=%JAVA_HOME%\bin;%PATH%"

REM Step 1: Build all services
echo Step 1: Building all services...
echo =========================================
call mvn clean package -DskipTests
if errorlevel 1 (
    echo Build failed!
    pause
    exit /b 1
)
echo Build successful!
echo.

REM Step 2: Upload JAR files
echo Step 2: Uploading JAR files...
echo =========================================
echo Uploading Auth Service...
scp -i "%KEY_FILE%" -o StrictHostKeyChecking=no auth-service\target\auth-service-1.0.0.jar ec2-user@%EC2_IP%:/tmp/auth-service.jar
echo.

echo Uploading Social Service...
scp -i "%KEY_FILE%" -o StrictHostKeyChecking=no social-service\target\social-service-1.0.0.jar ec2-user@%EC2_IP%:/tmp/social-service.jar
echo.

echo Uploading API Gateway...
scp -i "%KEY_FILE%" -o StrictHostKeyChecking=no api-gateway\target\api-gateway-1.0.0.jar ec2-user@%EC2_IP%:/tmp/api-gateway.jar
echo.

REM Step 3: Upload systemd service files
echo Step 3: Uploading service files...
echo =========================================
scp -i "%KEY_FILE%" -o StrictHostKeyChecking=no auth-service.service ec2-user@%EC2_IP%:/tmp/
scp -i "%KEY_FILE%" -o StrictHostKeyChecking=no social-service.service ec2-user@%EC2_IP%:/tmp/
scp -i "%KEY_FILE%" -o StrictHostKeyChecking=no api-gateway.service ec2-user@%EC2_IP%:/tmp/
echo.

REM Step 4: Upload environment files
echo Step 4: Uploading environment files...
echo =========================================
scp -i "%KEY_FILE%" -o StrictHostKeyChecking=no auth-env-fixed.txt ec2-user@%EC2_IP%:/tmp/auth-env.txt
scp -i "%KEY_FILE%" -o StrictHostKeyChecking=no social-env-final.txt ec2-user@%EC2_IP%:/tmp/social-env.txt
scp -i "%KEY_FILE%" -o StrictHostKeyChecking=no gateway-env-fixed.txt ec2-user@%EC2_IP%:/tmp/gateway-env.txt
echo.

REM Step 5: Setup and start services on EC2
echo Step 5: Setting up services on EC2...
echo =========================================
ssh -i "%KEY_FILE%" -o StrictHostKeyChecking=no ec2-user@%EC2_IP% "sudo systemctl stop api-gateway social-service auth-service 2>/dev/null || true && sudo mkdir -p /opt/auth-service /opt/social-service /opt/api-gateway && sudo mv /tmp/auth-service.jar /opt/auth-service/auth-service.jar && sudo mv /tmp/social-service.jar /opt/social-service/social-service.jar && sudo mv /tmp/api-gateway.jar /opt/api-gateway/api-gateway.jar && sudo mv /tmp/auth-env.txt /opt/auth-service/env.txt && sudo mv /tmp/social-env.txt /opt/social-service/env.txt && sudo mv /tmp/gateway-env.txt /opt/api-gateway/env.txt && sudo mv /tmp/auth-service.service /etc/systemd/system/ && sudo mv /tmp/social-service.service /etc/systemd/system/ && sudo mv /tmp/api-gateway.service /etc/systemd/system/ && sudo chmod 644 /etc/systemd/system/auth-service.service && sudo chmod 644 /etc/systemd/system/social-service.service && sudo chmod 644 /etc/systemd/system/api-gateway.service && sudo systemctl daemon-reload && sudo systemctl enable auth-service && sudo systemctl enable social-service && sudo systemctl enable api-gateway"
echo Setup complete!
echo.

echo Step 6: Starting services...
echo =========================================
echo Starting Auth Service...
ssh -i "%KEY_FILE%" -o StrictHostKeyChecking=no ec2-user@%EC2_IP% "sudo systemctl start auth-service"
timeout /t 10 /nobreak > nul
echo.

echo Starting Social Service...
ssh -i "%KEY_FILE%" -o StrictHostKeyChecking=no ec2-user@%EC2_IP% "sudo systemctl start social-service"
timeout /t 10 /nobreak > nul
echo.

echo Starting API Gateway...
ssh -i "%KEY_FILE%" -o StrictHostKeyChecking=no ec2-user@%EC2_IP% "sudo systemctl start api-gateway"
timeout /t 5 /nobreak > nul
echo.

echo Step 7: Checking service status...
echo =========================================
echo Auth Service:
ssh -i "%KEY_FILE%" -o StrictHostKeyChecking=no ec2-user@%EC2_IP% "sudo systemctl status auth-service --no-pager | head -10"
echo.

echo Social Service:
ssh -i "%KEY_FILE%" -o StrictHostKeyChecking=no ec2-user@%EC2_IP% "sudo systemctl status social-service --no-pager | head -10"
echo.

echo API Gateway:
ssh -i "%KEY_FILE%" -o StrictHostKeyChecking=no ec2-user@%EC2_IP% "sudo systemctl status api-gateway --no-pager | head -10"
echo.

echo =========================================
echo Deployment Complete!
echo =========================================
echo.
echo Services are available at:
echo   - API Gateway: http://98.90.116.96:8080
echo   - Auth Service: http://98.90.116.96:8081
echo   - Social Service: http://98.90.116.96:8082
echo.
echo To check logs:
echo   ssh -i "%KEY_FILE%" ec2-user@%EC2_IP%
echo   sudo journalctl -u auth-service -f
echo   sudo journalctl -u social-service -f
echo   sudo journalctl -u api-gateway -f
echo.
pause
