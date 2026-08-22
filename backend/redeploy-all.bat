@echo off
REM Quick Redeploy All Services to 98.90.116.96
REM This script rebuilds and redeploys both Social Service and API Gateway

set KEY=C:\Users\gidut\Downloads\social-media-key.pem
set IP=98.90.116.96
set PRIVATE_IP=172.31.74.81

REM Force Java 17 (project requires Java 17, not Java 25)
set JAVA_HOME=C:\Program Files\Java\jdk-17
set PATH=%JAVA_HOME%\bin;%PATH%

echo ========================================
echo Redeploying All Services to %IP%
echo ========================================
echo Using Java: %JAVA_HOME%
echo.

REM Step 1: Build
echo [1/5] Building all services...
call mvn clean package -DskipTests
if %ERRORLEVEL% NEQ 0 (
    echo Build failed!
    pause
    exit /b 1
)
echo Build successful!
echo.

REM Step 2: Deploy Social Service
echo [2/5] Deploying Social Service...
echo   - Uploading JAR...
scp -i %KEY% -o StrictHostKeyChecking=no social-service\target\social-service-1.0.0.jar ec2-user@%IP%:~/social-service.jar

echo   - Uploading Firebase key...
if exist "..\serviceAccountKey.json" (
    scp -i %KEY% -o StrictHostKeyChecking=no ..\serviceAccountKey.json ec2-user@%IP%:~/serviceAccountKey.json
    echo   Firebase key uploaded from root
) else if exist "social-service\src\main\resources\serviceAccountKey.json" (
    scp -i %KEY% -o StrictHostKeyChecking=no social-service\src\main\resources\serviceAccountKey.json ec2-user@%IP%:~/serviceAccountKey.json
    echo   Firebase key uploaded from resources
) else (
    echo   [WARNING] Firebase key not found! Push notifications may not work.
)

echo   - Creating environment file...
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
echo AGORA_APP_ID=b7a780435e494cdf8c4d6e4bc59be7ab >> social-env.txt
echo AGORA_APP_CERT=7c3359b7e6214ec6a5bcca098d47ee77 >> social-env.txt
echo FIREBASE_KEY_PATH=/opt/social-service/serviceAccountKey.json >> social-env.txt

scp -i %KEY% -o StrictHostKeyChecking=no social-env.txt ec2-user@%IP%:~/
scp -i %KEY% -o StrictHostKeyChecking=no social-service.service ec2-user@%IP%:~/

echo   - Installing and starting service...
ssh -i %KEY% -o StrictHostKeyChecking=no ec2-user@%IP% "sudo yum install -y java-17-amazon-corretto-headless &>/dev/null && sudo mkdir -p /opt/social-service && sudo mv ~/social-service.jar /opt/social-service/ && sudo mv ~/social-env.txt /opt/social-service/env.txt && [ -f ~/serviceAccountKey.json ] && sudo mv ~/serviceAccountKey.json /opt/social-service/ && sudo chmod 600 /opt/social-service/serviceAccountKey.json || echo 'No Firebase key to move' && sudo mv ~/social-service.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable social-service && sudo systemctl restart social-service"

del social-env.txt
echo Social Service deployed!
echo.

REM Step 3: Deploy API Gateway
echo [3/5] Deploying API Gateway...
echo   - Uploading JAR...
scp -i %KEY% -o StrictHostKeyChecking=no api-gateway\target\api-gateway-1.0.0.jar ec2-user@%IP%:~/api-gateway.jar

echo   - Creating environment file...
echo AUTH_SERVICE_URL=http://%PRIVATE_IP%:8081 > gateway-env.txt
echo SOCIAL_SERVICE_URL=http://%PRIVATE_IP%:8082 >> gateway-env.txt
echo JWT_SECRET=5367566B59703373367639792F423F4528482B4D6251655468576D5A71347437 >> gateway-env.txt
echo PORT=8080 >> gateway-env.txt
echo SPRING_PROFILES_ACTIVE=prod >> gateway-env.txt

scp -i %KEY% -o StrictHostKeyChecking=no gateway-env.txt ec2-user@%IP%:~/
scp -i %KEY% -o StrictHostKeyChecking=no api-gateway.service ec2-user@%IP%:~/

echo   - Installing and starting service...
ssh -i %KEY% -o StrictHostKeyChecking=no ec2-user@%IP% "sudo mkdir -p /opt/api-gateway && sudo mv ~/api-gateway.jar /opt/api-gateway/ && sudo mv ~/gateway-env.txt /opt/api-gateway/env.txt && sudo mv ~/api-gateway.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable api-gateway && sudo systemctl restart api-gateway"

del gateway-env.txt
echo API Gateway deployed!
echo.

REM Step 4: Wait for services to start
echo [4/5] Waiting for services to start...
timeout /t 15 /nobreak >nul
echo.

REM Step 5: Verify deployment
echo [5/5] Verifying deployment...
echo.
ssh -i %KEY% -o StrictHostKeyChecking=no ec2-user@%IP% "sudo systemctl status social-service api-gateway --no-pager"
echo.

echo ========================================
echo Deployment Complete!
echo ========================================
echo.
echo Services deployed to: %IP%
echo   - API Gateway:    http://%IP%:8080
echo   - Social Service: http://%IP%:8082
echo   - WebSocket:      http://%IP%:8082/ws
echo.
echo To view logs:
echo   ssh -i %KEY% ec2-user@%IP% "sudo journalctl -u social-service -f"
echo   ssh -i %KEY% ec2-user@%IP% "sudo journalctl -u api-gateway -f"
echo.

pause
