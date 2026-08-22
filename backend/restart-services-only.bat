@echo off
REM Quick Restart Services (no rebuild)

set KEY=C:\Users\gidut\Downloads\social-media-key.pem
set IP=98.90.116.96

echo Restarting services on %IP%...
ssh -i %KEY% -o StrictHostKeyChecking=no ec2-user@%IP% "sudo systemctl restart social-service api-gateway"

echo Waiting for services to start...
timeout /t 10 /nobreak >nul

echo.
echo Checking status...
ssh -i %KEY% -o StrictHostKeyChecking=no ec2-user@%IP% "sudo systemctl status social-service api-gateway --no-pager"

echo.
echo Services restarted!
pause
