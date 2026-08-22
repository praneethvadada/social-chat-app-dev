@echo off
REM Deploy social-service to EC2 (Auth Service Instance)

set SOCIAL_IP=98.90.116.96
set SOCIAL_PRIVATE_IP=172.31.74.81
set KEY_FILE=C:\Users\gidut\Downloads\social-media-key.pem
set JAR_FILE=social-service\target\social-service-1.0.0.jar
set SSH_OPTS=-o StrictHostKeyChecking=no -o ConnectTimeout=12 -o BatchMode=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=3

echo ========================================
echo Deploying Social Service to EC2
echo ========================================

REM Wait for SSH to be ready
echo Waiting for SSH to be ready...
timeout /t 10 /nobreak

echo.
echo Checking SSH connectivity to %SOCIAL_IP%...
ssh -i %KEY_FILE% %SSH_OPTS% ec2-user@%SOCIAL_IP% "echo SSH_OK"
if errorlevel 1 (
	echo ERROR: Cannot reach %SOCIAL_IP% on port 22. Deployment stopped.
	echo Hint: check EC2 status, Security Group inbound rule for SSH 22, and current public IP.
	pause
	exit /b 1
)

REM Upload JAR file
echo.
echo Uploading JAR file...
scp -i %KEY_FILE% %SSH_OPTS% %JAR_FILE% ec2-user@%SOCIAL_IP%:~/social-service.jar
if errorlevel 1 (
	echo ERROR: JAR upload failed - host unreachable or auth failed.
	pause
	exit /b 1
)

REM Create and upload environment file
echo.
echo Creating environment file...
echo SPRING_DATASOURCE_URL=jdbc:mysql://social-media-db.ca30yaou8j00.us-east-1.rds.amazonaws.com:3306/auth_db?createDatabaseIfNotExist=true^&useSSL=false^&allowPublicKeyRetrieval=true^&serverTimezone=UTC > social-env.txt
echo SPRING_DATASOURCE_USERNAME=admin >> social-env.txt
echo SPRING_DATASOURCE_PASSWORD=SecurePass123! >> social-env.txt
echo SPRING_DATA_REDIS_HOST=social-media-redis.0k0afe.0001.use1.cache.amazonaws.com >> social-env.txt
echo SPRING_DATA_REDIS_PORT=6379 >> social-env.txt
echo JWT_SECRET=5367566B59703373367639792F423F4528482B4D6251655468576D5A71347437 >> social-env.txt
echo JWT_EXPIRATION=86400000 >> social-env.txt
echo PORT=8082 >> social-env.txt
echo SPRING_PROFILES_ACTIVE=prod >> social-env.txt
echo AWS_S3_BUCKET=social-media-gidut-54513 >> social-env.txt
echo AWS_REGION=us-east-1 >> social-env.txt
echo file.upload.dir=/tmp/uploads >> social-env.txt
echo AGORA_APP_ID=b7a780435e494cdf8c4d6e4bc59be7ab >> social-env.txt
echo AGORA_APP_CERT=7c3359b7e6214ec6a5bcca098d47ee77 >> social-env.txt

scp -i %KEY_FILE% %SSH_OPTS% social-env.txt ec2-user@%SOCIAL_IP%:~/
if errorlevel 1 (
	echo ERROR: Environment file upload failed.
	pause
	exit /b 1
)

REM SSH and configure the service
echo.
echo Configuring social service...
ssh -i %KEY_FILE% %SSH_OPTS% ec2-user@%SOCIAL_IP% "sudo -n true && (java -version >/dev/null 2>&1 || sudo yum install -y java-17-amazon-corretto-headless) && sudo mkdir -p /opt/social-service && sudo mv ~/social-service.jar /opt/social-service/ && sudo mv ~/social-env.txt /opt/social-service/env.txt"
if errorlevel 1 (
	echo ERROR: Remote configuration failed - check SSH access, sudo permissions, or yum repository connectivity.
	pause
	exit /b 1
)

REM Upload systemd service file
echo.
echo Uploading systemd service file...
scp -i %KEY_FILE% %SSH_OPTS% social-service.service ec2-user@%SOCIAL_IP%:~/
if errorlevel 1 (
	echo ERROR: Service file upload failed.
	pause
	exit /b 1
)
ssh -i %KEY_FILE% %SSH_OPTS% ec2-user@%SOCIAL_IP% "sudo mv ~/social-service.service /etc/systemd/system/"
if errorlevel 1 (
	echo ERROR: Installing service file on EC2 failed.
	pause
	exit /b 1
)

REM Start the service
echo.
echo Starting social service...
ssh -i %KEY_FILE% %SSH_OPTS% ec2-user@%SOCIAL_IP% "sudo systemctl daemon-reload && sudo systemctl enable social-service && sudo systemctl start social-service"
if errorlevel 1 (
	echo ERROR: Failed to start social-service.
	pause
	exit /b 1
)

REM Wait and check logs
echo.
echo Waiting 20 seconds for service to start...
timeout /t 20 /nobreak

echo.
echo Checking service status and logs...
ssh -i %KEY_FILE% %SSH_OPTS% ec2-user@%SOCIAL_IP% "sudo systemctl status social-service --no-pager && echo '--- Last 30 lines of logs ---' && sudo journalctl -u social-service -n 30 --no-pager"

echo.
echo ========================================
echo Social Service Deployment Complete!
echo Access at: http://%SOCIAL_IP%:8082
echo ========================================
echo.
echo Next Step: Update API Gateway
echo Run: update-gateway-for-social.bat
echo.

del social-env.txt
pause
