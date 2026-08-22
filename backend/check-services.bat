@echo off
REM Quick status check for all services

set EC2_IP=98.90.116.96
set KEY_FILE=C:\Users\gidut\Downloads\social-media-key.pem

echo =========================================
echo Service Status Check
echo =========================================
echo.

echo Testing API Gateway (port 8080)...
curl -s http://98.90.116.96:8080/actuator/health
echo.
echo.

echo Testing Auth Service (port 8081)...
curl -s http://98.90.116.96:8081/health
echo.
echo.

echo Testing Social Service (port 8082)...
curl -s http://98.90.116.96:8082/health
echo.
echo.

echo =========================================
echo Systemd Service Status
echo =========================================
ssh -i "%KEY_FILE%" -o StrictHostKeyChecking=no ec2-user@%EC2_IP% "sudo systemctl is-active auth-service social-service api-gateway"

pause

