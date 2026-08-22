@echo off
REM Update API Gateway to route to Social Service

set GATEWAY_IP=98.90.116.96
set AUTH_PRIVATE_IP=172.31.74.81
set SOCIAL_PRIVATE_IP=172.31.74.81
set KEY_FILE=C:\Users\gidut\Downloads\social-media-key.pem

echo ========================================
echo Updating API Gateway Configuration
echo ========================================

REM Create updated environment file
echo.
echo Creating updated environment file...
echo AUTH_SERVICE_URL=http://%AUTH_PRIVATE_IP%:8081 > gateway-env-updated.txt
echo SOCIAL_SERVICE_URL=http://%SOCIAL_PRIVATE_IP%:8082 >> gateway-env-updated.txt
echo JWT_SECRET=5367566B59703373367639792F423F4528482B4D6251655468576D5A71347437 >> gateway-env-updated.txt
echo PORT=8080 >> gateway-env-updated.txt
echo SPRING_PROFILES_ACTIVE=prod >> gateway-env-updated.txt

REM Upload new environment file
echo.
echo Uploading updated environment file...
scp -i %KEY_FILE% -o StrictHostKeyChecking=no gateway-env-updated.txt ec2-user@%GATEWAY_IP%:~/

REM Replace environment file and restart
echo.
echo Updating configuration and restarting API Gateway...
ssh -i %KEY_FILE% -o StrictHostKeyChecking=no ec2-user@%GATEWAY_IP% "sudo mv ~/gateway-env-updated.txt /opt/api-gateway/env.txt && sudo systemctl restart api-gateway"

REM Wait and check status
echo.
echo Waiting 10 seconds for service to restart...
timeout /t 10 /nobreak

echo.
echo Checking API Gateway status...
ssh -i %KEY_FILE% -o StrictHostKeyChecking=no ec2-user@%GATEWAY_IP% "sudo systemctl status api-gateway --no-pager"

echo.
echo ========================================
echo API Gateway Updated Successfully!
echo ========================================
echo.
echo API Gateway now routes to:
echo   - Auth Service:   http://%AUTH_PRIVATE_IP%:8081
echo   - Social Service: http://%SOCIAL_PRIVATE_IP%:8082
echo.
echo Test endpoints:
echo   http://%GATEWAY_IP%:8080/auth/health
echo   http://%GATEWAY_IP%:8080/social/actuator/health
echo.

del gateway-env-updated.txt
pause
