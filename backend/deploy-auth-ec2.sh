#!/bin/bash
set -e

echo "========================================="
echo "Deploying Auth Service with OTP Support"
echo "========================================="

echo ""
echo "Step 1: Downloading JAR from S3..."
aws s3 cp s3://social-media-gidut-54513/deployments/auth-service-new.jar /tmp/auth-service-1.0.0.jar --region us-east-1

echo ""
echo "Step 2: Stopping auth-service..."
sudo systemctl stop auth-service

echo ""
echo "Step 3: Backing up old JAR..."
sudo cp /opt/auth-service/auth-service.jar /opt/auth-service/auth-service.jar.backup 2>/dev/null || echo "No backup needed"

echo ""
echo "Step 4: Installing new JAR..."
sudo mv /tmp/auth-service-1.0.0.jar /opt/auth-service/auth-service.jar
sudo chown ec2-user:ec2-user /opt/auth-service/auth-service.jar
sudo chmod 644 /opt/auth-service/auth-service.jar

echo ""
echo "Step 5: Starting auth-service..."
sudo systemctl start auth-service

echo ""
echo "Step 6: Waiting for service to start..."
sleep 15

echo ""
echo "Step 7: Checking service status..."
sudo systemctl status auth-service --no-pager | head -25

echo ""
echo "Step 8: Checking recent logs..."
sudo journalctl -u auth-service --since '30 seconds ago' | tail -20

echo ""
echo "Step 9: Testing OTP send endpoint..."
sleep 5
curl -v -X POST http://localhost:8081/otp/send \
  -H "Content-Type: application/json" \
  -d '{"email":"guideup3515@gmail.com"}'

echo ""
echo ""
echo "========================================="
echo "Deployment Complete!"
echo "========================================="
echo ""
echo "Test OTP from external:"
echo "curl -X POST http://98.92.24.110:8081/otp/send -H \"Content-Type: application/json\" -d '{\"email\":\"guideup3515@gmail.com\"}'"
echo ""
