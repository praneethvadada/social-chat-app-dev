@echo off
REM Social Service Deployment Script for Windows
REM This script helps deploy social-service to AWS EC2

echo =========================================
echo Social Service Deployment to AWS
echo =========================================
echo.

REM Check if JAR exists
if not exist "social-service\target\social-service-1.0.0.jar" (
    echo ERROR: JAR file not found!
    echo Please build the project first with: mvn clean package -DskipTests
    pause
    exit /b 1
)

echo JAR file found: social-service\target\social-service-1.0.0.jar
echo.

REM Prompt for deployment details
set /p EC2_IP="Enter EC2 Instance IP: "
set /p KEY_FILE="Enter path to your .pem key file: "
set /p RDS_ENDPOINT="Enter RDS endpoint: "
set /p RDS_PASSWORD="Enter RDS password: "
set /p REDIS_ENDPOINT="Enter Redis endpoint: "
set /p S3_BUCKET="Enter S3 bucket name [social-media-app-bucket]: "
if "%S3_BUCKET%"=="" set S3_BUCKET=social-media-app-bucket

echo.
echo =========================================
echo Deployment Configuration:
echo =========================================
echo EC2 IP: %EC2_IP%
echo RDS: %RDS_ENDPOINT%
echo Redis: %REDIS_ENDPOINT%
echo S3 Bucket: %S3_BUCKET%
echo =========================================
echo.
set /p CONFIRM="Proceed with deployment? (yes/no): "
if /i not "%CONFIRM%"=="yes" (
    echo Deployment cancelled.
    pause
    exit /b 0
)

echo.
echo Creating environment file...
(
echo # Social Service Environment Variables
echo SPRING_PROFILES_ACTIVE=prod
echo PORT=8082
echo.
echo # Database Configuration
echo SPRING_DATASOURCE_URL=jdbc:mysql://%RDS_ENDPOINT%:3306/auth_db?createDatabaseIfNotExist=true^&useSSL=true^&serverTimezone=UTC^&allowPublicKeyRetrieval=true
echo SPRING_DATASOURCE_USERNAME=admin
echo SPRING_DATASOURCE_PASSWORD=%RDS_PASSWORD%
echo.
echo # Redis Configuration
echo SPRING_DATA_REDIS_HOST=%REDIS_ENDPOINT%
echo SPRING_DATA_REDIS_PORT=6379
echo.
echo # JWT Configuration
echo JWT_SECRET=5367566B59703373367639792F423F4528482B4D6251655468576D5A71347437
echo JWT_EXPIRATION=86400000
echo.
echo # AWS S3 Configuration
echo AWS_S3_BUCKET=%S3_BUCKET%
echo AWS_REGION=us-east-1
echo.
echo # Agora Configuration
echo AGORA_APP_ID=b7a780435e494cdf8c4d6e4bc59be7ab
echo AGORA_APP_CERT=7c3359b7e6214ec6a5bcca098d47ee77
) > social-env-deploy.txt

echo Environment file created.
echo.

echo =========================================
echo Step 1: Uploading JAR file...
echo =========================================
scp -i "%KEY_FILE%" social-service\target\social-service-1.0.0.jar ubuntu@%EC2_IP%:/home/ubuntu/

echo.
echo =========================================
echo Step 2: Uploading environment file...
echo =========================================
scp -i "%KEY_FILE%" social-env-deploy.txt ubuntu@%EC2_IP%:/home/ubuntu/social-service.env

echo.
echo =========================================
echo Step 3: Uploading service file...
echo =========================================
scp -i "%KEY_FILE%" social-service.service ubuntu@%EC2_IP%:/tmp/

echo.
echo =========================================
echo Step 4: Setting up service on EC2...
echo =========================================
ssh -i "%KEY_FILE%" ubuntu@%EC2_IP% "sudo mv /tmp/social-service.service /etc/systemd/system/ && sudo chmod 644 /etc/systemd/system/social-service.service && sudo systemctl daemon-reload && sudo systemctl enable social-service && sudo systemctl restart social-service && sleep 5 && sudo systemctl status social-service --no-pager"

echo.
echo =========================================
echo Deployment Complete!
echo =========================================
echo.
echo Service should be available at: http://%EC2_IP%:8082
echo Health check: http://%EC2_IP%:8082/actuator/health
echo Swagger UI: http://%EC2_IP%:8082/swagger-ui.html
echo.
echo To check logs:
echo ssh -i "%KEY_FILE%" ubuntu@%EC2_IP% "sudo journalctl -u social-service -f"
echo.
echo Cleaning up temporary files...
del social-env-deploy.txt
echo.
pause
