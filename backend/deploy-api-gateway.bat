@echo off
REM Deploy api-gateway to EC2

set GATEWAY_IP=98.90.116.96
set AUTH_PRIVATE_IP=172.31.74.81
set KEY_FILE=C:\Users\gidut\Downloads\social-media-key.pem
set JAR_FILE=api-gateway\target\api-gateway-1.0.0.jar

echo ========================================
echo Deploying API Gateway to EC2
echo ========================================

REM Wait for SSH to be ready
echo Waiting for SSH to be ready...
timeout /t 10 /nobreak

REM Upload JAR file
echo.
echo Uploading JAR file...
scp -i %KEY_FILE% -o StrictHostKeyChecking=no %JAR_FILE% ec2-user@%GATEWAY_IP%:~/api-gateway.jar

REM Create and upload environment file
echo.
echo Creating environment file...
echo AUTH_SERVICE_URL=http://%AUTH_PRIVATE_IP%:8081 > gateway-env.txt
echo JWT_SECRET=5367566B59703373367639792F423F4528482B4D6251655468576D5A71347437 >> gateway-env.txt
echo SERVER_PORT=8080 >> gateway-env.txt

scp -i %KEY_FILE% -o StrictHostKeyChecking=no gateway-env.txt ec2-user@%GATEWAY_IP%:~/

REM SSH and configure the service
echo.
echo Configuring api-gateway service...
ssh -i %KEY_FILE% -o StrictHostKeyChecking=no ec2-user@%GATEWAY_IP% "sudo yum update -y && sudo yum install -y java-17-amazon-corretto-headless && sudo mkdir -p /opt/api-gateway && sudo mv ~/api-gateway.jar /opt/api-gateway/ && sudo mv ~/gateway-env.txt /opt/api-gateway/env.txt"

REM Upload systemd service file
echo.
echo Uploading systemd service file...
scp -i %KEY_FILE% -o StrictHostKeyChecking=no api-gateway.service ec2-user@%GATEWAY_IP%:~/
ssh -i %KEY_FILE% -o StrictHostKeyChecking=no ec2-user@%GATEWAY_IP% "sudo mv ~/api-gateway.service /etc/systemd/system/"

REM Start the service
echo.
echo Starting api-gateway service...
ssh -i %KEY_FILE% -o StrictHostKeyChecking=no ec2-user@%GATEWAY_IP% "sudo systemctl daemon-reload && sudo systemctl enable api-gateway && sudo systemctl start api-gateway"

REM Wait and check logs
echo.
echo Waiting 20 seconds for service to start...
timeout /t 20 /nobreak

echo.
echo Checking service status and logs...
ssh -i %KEY_FILE% -o StrictHostKeyChecking=no ec2-user@%GATEWAY_IP% "sudo systemctl status api-gateway && echo '--- Last 30 lines of logs ---' && sudo journalctl -u api-gateway -n 30 --no-pager"

echo.
echo ========================================
echo API Gateway Deployment Complete!
echo Access at: http://%GATEWAY_IP%:8080
echo ========================================

del gateway-env.txt
