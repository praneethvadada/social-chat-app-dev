# Social Service Deployment Script (PowerShell)
# Deploys social-service to EC2: 98.92.152.200

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Social Service Deployment" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

$EC2_IP = "98.92.152.200"
$PRIVATE_IP = "172.31.66.187"
$KEY_FILE = "C:\Users\gidut\Downloads\social-media-key.pem"

# Check if JAR exists
if (-not (Test-Path "social-service\target\social-service-1.0.0.jar")) {
    Write-Host "ERROR: JAR file not found!" -ForegroundColor Red
    Write-Host "Building the project..." -ForegroundColor Yellow
    $env:JAVA_HOME = "C:\Program Files\Java\jdk-17"
    $env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
    mvn clean package -pl social-service -am -DskipTests
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Build failed!" -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }
}

Write-Host ""
Write-Host "Step 1: Uploading JAR to EC2..." -ForegroundColor Green
Write-Host "========================================="
scp -o StrictHostKeyChecking=no -i $KEY_FILE social-service\target\social-service-1.0.0.jar ec2-user@${EC2_IP}:/tmp/social-service.jar

Write-Host ""
Write-Host "Step 2: Uploading environment file..." -ForegroundColor Green
Write-Host "========================================="
scp -o StrictHostKeyChecking=no -i $KEY_FILE social-env-final.txt ec2-user@${EC2_IP}:/tmp/social-env.txt

Write-Host ""
Write-Host "Step 3: Uploading service file..." -ForegroundColor Green
Write-Host "========================================="
scp -o StrictHostKeyChecking=no -i $KEY_FILE social-service.service ec2-user@${EC2_IP}:/tmp/social-service.service

Write-Host ""
Write-Host "Step 4: Setting up on EC2..." -ForegroundColor Green
Write-Host "========================================="
ssh -o StrictHostKeyChecking=no -i $KEY_FILE ec2-user@${EC2_IP} "sudo mkdir -p /opt/social-service && sudo mv /tmp/social-service.jar /opt/social-service/social-service.jar && sudo mv /tmp/social-env.txt /opt/social-service/env.txt && sudo mv /tmp/social-service.service /etc/systemd/system/ && sudo chmod 644 /etc/systemd/system/social-service.service && sudo systemctl daemon-reload && sudo systemctl enable social-service && sudo systemctl restart social-service"

Write-Host ""
Write-Host "Step 5: Checking service status..." -ForegroundColor Green
Write-Host "========================================="
Start-Sleep -Seconds 5
ssh -o StrictHostKeyChecking=no -i $KEY_FILE ec2-user@${EC2_IP} "sudo systemctl status social-service --no-pager"

Write-Host ""
Write-Host "Step 6: Testing health endpoint..." -ForegroundColor Green
Write-Host "========================================="
Start-Sleep -Seconds 3
ssh -o StrictHostKeyChecking=no -i $KEY_FILE ec2-user@${EC2_IP} "curl -s http://localhost:8082/actuator/health || echo 'Service starting...'"

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Deployment Complete!" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Service Details:"
Write-Host "  - Public IP:  $EC2_IP"
Write-Host "  - Private IP: $PRIVATE_IP"
Write-Host "  - Port:       8082"
Write-Host ""
Write-Host "Health Check: http://${EC2_IP}:8082/actuator/health"
Write-Host "Swagger UI:   http://${EC2_IP}:8082/swagger-ui.html"
Write-Host ""
Write-Host "Next: Update API Gateway to route to social-service" -ForegroundColor Yellow
Write-Host "  Add to gateway-env-final.txt: SOCIAL_SERVICE_URL=http://${PRIVATE_IP}:8082"
Write-Host ""
Read-Host "Press Enter to exit"
