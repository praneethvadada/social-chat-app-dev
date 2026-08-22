#!/bin/bash

# Social Service Deployment Script
# This script deploys the social-service to AWS EC2

set -e

echo "========================================="
echo "Social Service Deployment Script"
echo "========================================="
echo ""

# Configuration
EC2_USER="ubuntu"
EC2_HOST="YOUR_SOCIAL_SERVICE_EC2_IP"  # Replace with your EC2 IP
KEY_FILE="YOUR_KEY_FILE.pem"           # Replace with your key file path
JAR_FILE="social-service/target/social-service-1.0.0.jar"
SERVICE_FILE="social-service.service"
ENV_FILE="social-env.txt"

# Get RDS and Redis endpoints
read -p "Enter RDS endpoint (e.g., your-db.xxxxx.us-east-1.rds.amazonaws.com): " RDS_ENDPOINT
read -p "Enter RDS password: " -s RDS_PASSWORD
echo ""
read -p "Enter Redis endpoint (e.g., your-redis.xxxxx.cache.amazonaws.com): " REDIS_ENDPOINT
read -p "Enter S3 bucket name [social-media-app-bucket]: " S3_BUCKET
S3_BUCKET=${S3_BUCKET:-social-media-app-bucket}

# Update environment file with actual values
sed -i.bak \
    -e "s|YOUR_RDS_ENDPOINT|$RDS_ENDPOINT|g" \
    -e "s|YOUR_DB_PASSWORD|$RDS_PASSWORD|g" \
    -e "s|YOUR_REDIS_ENDPOINT|$REDIS_ENDPOINT|g" \
    -e "s|social-media-app-bucket|$S3_BUCKET|g" \
    $ENV_FILE

echo "1. Copying JAR file to EC2..."
scp -i $KEY_FILE $JAR_FILE $EC2_USER@$EC2_HOST:/home/$EC2_USER/

echo "2. Copying environment file to EC2..."
scp -i $KEY_FILE $ENV_FILE $EC2_USER@$EC2_HOST:/home/$EC2_USER/social-service.env

echo "3. Copying systemd service file to EC2..."
scp -i $KEY_FILE $SERVICE_FILE $EC2_USER@$EC2_HOST:/tmp/

echo "4. Setting up systemd service on EC2..."
ssh -i $KEY_FILE $EC2_USER@$EC2_HOST << 'ENDSSH'
    # Install Java if not present
    if ! command -v java &> /dev/null; then
        echo "Installing Java 17..."
        sudo apt-get update
        sudo apt-get install -y openjdk-17-jre-headless
    fi
    
    # Move service file to systemd directory
    sudo mv /tmp/social-service.service /etc/systemd/system/
    sudo chmod 644 /etc/systemd/system/social-service.service
    
    # Reload systemd
    sudo systemctl daemon-reload
    
    # Enable and start the service
    sudo systemctl enable social-service
    sudo systemctl restart social-service
    
    # Wait a moment for service to start
    sleep 5
    
    # Check service status
    sudo systemctl status social-service --no-pager
ENDSSH

echo ""
echo "========================================="
echo "Deployment Complete!"
echo "========================================="
echo ""
echo "Service Status:"
ssh -i $KEY_FILE $EC2_USER@$EC2_HOST "sudo systemctl is-active social-service"
echo ""
echo "To check logs, run:"
echo "ssh -i $KEY_FILE $EC2_USER@$EC2_HOST 'sudo journalctl -u social-service -f'"
echo ""
echo "Service should be available at: http://$EC2_HOST:8082"
echo "Health check: http://$EC2_HOST:8082/actuator/health"

# Restore original environment file
mv $ENV_FILE.bak $ENV_FILE
