@echo off
REM Deploy auth-service to EC2

set AUTH_IP=98.90.116.96
set KEY_FILE=C:\Users\gidut\Downloads\social-media-key.pem
set JAR_FILE=auth-service\target\auth-service-1.0.0.jar

echo ========================================
echo Deploying Auth Service to EC2
echo ========================================

REM Wait for SSH to be ready
echo Waiting for SSH to be ready...
timeout /t 30 /nobreak

REM Upload JAR file
echo.
echo Uploading JAR file...
scp -i %KEY_FILE% -o StrictHostKeyChecking=no %JAR_FILE% ec2-user@%AUTH_IP%:~/auth-service.jar

REM Create and upload environment file
echo.
echo Creating environment file...
echo DATABASE_URL=jdbc:mysql://social-media-db.ca30yaou8j00.us-east-1.rds.amazonaws.com:3306/auth_db?createDatabaseIfNotExist=true^&useSSL=false^&allowPublicKeyRetrieval=true^&serverTimezone=UTC > auth-env.txt
echo DATABASE_USERNAME=admin >> auth-env.txt
echo DATABASE_PASSWORD=SecurePass123! >> auth-env.txt
echo REDIS_HOST=social-media-redis.0k0afe.0001.use1.cache.amazonaws.com >> auth-env.txt
echo REDIS_PORT=6379 >> auth-env.txt
echo JWT_SECRET=5367566B59703373367639792F423F4528482B4D6251655468576D5A71347437 >> auth-env.txt
echo SERVER_PORT=8081 >> auth-env.txt

scp -i %KEY_FILE% -o StrictHostKeyChecking=no auth-env.txt ec2-user@%AUTH_IP%:~/

REM SSH and configure the service
echo.
echo Configuring auth service...
ssh -i %KEY_FILE% -o StrictHostKeyChecking=no ec2-user@%AUTH_IP% "sudo yum update -y && sudo yum install -y java-17-amazon-corretto-headless && sudo mkdir -p /opt/auth-service && sudo mv ~/auth-service.jar /opt/auth-service/ && sudo mv ~/auth-env.txt /opt/auth-service/env.txt"

REM Upload systemd service file
echo.
echo Uploading systemd service file...
scp -i %KEY_FILE% -o StrictHostKeyChecking=no auth-service.service ec2-user@%AUTH_IP%:~/
ssh -i %KEY_FILE% -o StrictHostKeyChecking=no ec2-user@%AUTH_IP% "sudo mv ~/auth-service.service /etc/systemd/system/"

REM Start the service
echo.
echo Starting auth service...
ssh -i %KEY_FILE% -o StrictHostKeyChecking=no ec2-user@%AUTH_IP% "sudo systemctl daemon-reload && sudo systemctl enable auth-service && sudo systemctl start auth-service"

REM Wait and check logs
echo.
echo Waiting 20 seconds for service to start...
timeout /t 20 /nobreak

echo.
echo Checking service status and logs...
ssh -i %KEY_FILE% -o StrictHostKeyChecking=no ec2-user@%AUTH_IP% "sudo systemctl status auth-service && echo '--- Last 30 lines of logs ---' && sudo journalctl -u auth-service -n 30 --no-pager"

echo.
echo ========================================
echo Auth Service Deployment Complete!
echo Access at: http://%AUTH_IP%:8081
echo ========================================

del auth-env.txt
