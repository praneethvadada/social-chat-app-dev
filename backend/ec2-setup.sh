#!/bin/bash
# Commands to run on EC2 after uploading JAR

# Stop existing service
sudo systemctl stop social-service 2>/dev/null || true
sudo pkill -f 'social-service.jar' 2>/dev/null || true

# Create directory
sudo mkdir -p /opt/social-service

# Move JAR file
sudo mv /home/ec2-user/social-service.jar /opt/social-service/social-service.jar
sudo chown -R ec2-user:ec2-user /opt/social-service

# Create environment file
sudo bash -c 'cat > /opt/social-service/env.txt <<EOF
SPRING_DATASOURCE_URL=jdbc:mysql://social-media-db.ca30yaou8j00.us-east-1.rds.amazonaws.com:3306/auth_db?createDatabaseIfNotExist=true&useSSL=false&serverTimezone=UTC&allowPublicKeyRetrieval=true
SPRING_DATASOURCE_USERNAME=admin
SPRING_DATASOURCE_PASSWORD=SecurePass123!
AWS_S3_BUCKET_NAME=social-media-gidut-54513
AWS_S3_REGION=us-east-1
AGORA_APP_ID=96f2b1afbf744dc5818487f2e31ed9e7
AGORA_APP_CERT=ef473b70af0d40989d94ca2d7ce5c248
JWT_SECRET=5367566B59703373367639792F423F4528482B4D6251655468576D5A71347437
EOF'

# Create systemd service file
sudo bash -c 'cat > /etc/systemd/system/social-service.service <<EOF
[Unit]
Description=Social Service
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/social-service
EnvironmentFile=/opt/social-service/env.txt
ExecStart=/usr/bin/java -Xms512m -Xmx1024m -jar /opt/social-service/social-service.jar
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF'

# Reload and start service
sudo systemctl daemon-reload
sudo systemctl enable social-service
sudo systemctl start social-service

echo "Waiting for service to start..."
sleep 10

# Check status
sudo systemctl status social-service --no-pager

echo ""
echo "Service logs (last 20 lines):"
sudo journalctl -u social-service -n 20 --no-pager
