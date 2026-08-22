@echo off
REM Start services that are already deployed on EC2

set EC2_IP=98.90.116.96
set KEY_FILE=C:\Users\gidut\Downloads\social-media-key.pem

echo =========================================
echo Starting All Services on EC2
echo =========================================
echo.

echo Starting Auth Service...
ssh -i "%KEY_FILE%" -o StrictHostKeyChecking=no ec2-user@%EC2_IP% "sudo systemctl start auth-service"
echo Waiting 10 seconds...
timeout /t 10 /nobreak > nul
echo.

echo Starting Social Service...
ssh -i "%KEY_FILE%" -o StrictHostKeyChecking=no ec2-user@%EC2_IP% "sudo systemctl start social-service"
echo Waiting 10 seconds...
timeout /t 10 /nobreak > nul
echo.

echo Starting API Gateway...
ssh -i "%KEY_FILE%" -o StrictHostKeyChecking=no ec2-user@%EC2_IP% "sudo systemctl start api-gateway"
echo Waiting 5 seconds...
timeout /t 5 /nobreak > nul
echo.

echo =========================================
echo Checking Service Status
echo =========================================
echo.

echo Auth Service:
ssh -i "%KEY_FILE%" -o StrictHostKeyChecking=no ec2-user@%EC2_IP% "sudo systemctl status auth-service --no-pager"
echo.
echo ================================================
echo.

echo Social Service:
ssh -i "%KEY_FILE%" -o StrictHostKeyChecking=no ec2-user@%EC2_IP% "sudo systemctl status social-service --no-pager"
echo.
echo ================================================
echo.

echo API Gateway:
ssh -i "%KEY_FILE%" -o StrictHostKeyChecking=no ec2-user@%EC2_IP% "sudo systemctl status api-gateway --no-pager"
echo.

echo =========================================
echo All Services Started!
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
