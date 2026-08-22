# 🚀 AWS Deployment - Social Service with Firebase

## 📋 Prerequisites

### 1️⃣ **Get Firebase Service Account Key**

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Click **⚙️ Settings** → **Project Settings**
4. Go to **Service Accounts** tab
5. Click **Generate New Private Key**
6. Download the JSON file (rename it to `serviceAccountKey.json`)

---

## 🎯 Deployment Options

### **Option A: EC2 Deployment (Recommended)**

#### Step 1: Upload JAR and Firebase Key to EC2

```bash
# From your local machine (PowerShell/Git Bash)
cd "c:\Users\gidut\OneDrive\html files\Projects\social-chat-app"

# Upload JAR file
scp -i "your-key.pem" backend/social-service/target/social-service-1.0.0.jar ec2-user@your-ec2-ip:/home/ec2-user/

# Upload Firebase service key
scp -i "your-key.pem" serviceAccountKey.json ec2-user@your-ec2-ip:/home/ec2-user/
```

#### Step 2: SSH into EC2 and Setup

```bash
# SSH into EC2
ssh -i "your-key.pem" ec2-user@your-ec2-ip

# Create application directory
mkdir -p /home/ec2-user/social-service
mv social-service-1.0.0.jar /home/ec2-user/social-service/
mv serviceAccountKey.json /home/ec2-user/social-service/

# Set secure permissions for Firebase key
chmod 600 /home/ec2-user/social-service/serviceAccountKey.json
```

#### Step 3: Create Startup Script

```bash
# Create startup script
cat > /home/ec2-user/social-service/start.sh << 'EOF'
#!/bin/bash

# Set Firebase key path
export FIREBASE_KEY_PATH="/home/ec2-user/social-service/serviceAccountKey.json"

# Set Java 17
export JAVA_HOME=/usr/lib/jvm/java-17-amazon-corretto
export PATH=$JAVA_HOME/bin:$PATH

# AWS credentials (if using IAM role, these are not needed)
# export AWS_ACCESS_KEY_ID=your-access-key
# export AWS_SECRET_ACCESS_KEY=your-secret-key

# Database configuration
export SPRING_DATASOURCE_URL="jdbc:mysql://your-rds-endpoint:3306/auth_db?useSSL=true&serverTimezone=UTC"
export SPRING_DATASOURCE_USERNAME="admin"
export SPRING_DATASOURCE_PASSWORD="your-db-password"

# JWT Secret (generate a strong one for production)
export JWT_SECRET="5367566B59703373367639792F423F4528482B4D6251655468576D5A71347437"

# S3 Configuration
export AWS_S3_BUCKET_NAME="social-media-gidut-54513"
export AWS_S3_REGION="us-east-1"

# Agora configuration
export AGORA_APP_ID="96f2b1afbf744dc5818487f2e31ed9e7"
export AGORA_APP_CERT="ef473b70af0d40989d94ca2d7ce5c248"

# Start application
cd /home/ec2-user/social-service
nohup java -jar -Xmx1024m -Xms512m \
  -Dserver.port=8082 \
  -Dspring.profiles.active=prod \
  social-service-1.0.0.jar > social-service.log 2>&1 &

echo $! > social-service.pid
echo "Social Service started with PID: $(cat social-service.pid)"
echo "Check logs: tail -f social-service.log"
EOF

chmod +x /home/ec2-user/social-service/start.sh
```

#### Step 4: Create Stop Script

```bash
cat > /home/ec2-user/social-service/stop.sh << 'EOF'
#!/bin/bash
if [ -f social-service.pid ]; then
    PID=$(cat social-service.pid)
    echo "Stopping Social Service (PID: $PID)..."
    kill $PID
    rm social-service.pid
    echo "Social Service stopped"
else
    echo "No PID file found"
fi
EOF

chmod +x /home/ec2-user/social-service/stop.sh
```

#### Step 5: Start the Service

```bash
cd /home/ec2-user/social-service
./start.sh

# Check logs
tail -f social-service.log

# Check if running
ps aux | grep social-service
```

#### Step 6: Setup as System Service (Optional)

```bash
sudo cat > /etc/systemd/system/social-service.service << 'EOF'
[Unit]
Description=Social Media Social Service
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user/social-service
Environment="FIREBASE_KEY_PATH=/home/ec2-user/social-service/serviceAccountKey.json"
Environment="SPRING_DATASOURCE_URL=jdbc:mysql://your-rds-endpoint:3306/auth_db"
Environment="SPRING_DATASOURCE_USERNAME=admin"
Environment="SPRING_DATASOURCE_PASSWORD=your-db-password"
ExecStart=/usr/bin/java -jar -Xmx1024m /home/ec2-user/social-service/social-service-1.0.0.jar
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable social-service
sudo systemctl start social-service
sudo systemctl status social-service

# View logs
sudo journalctl -u social-service -f
```

---

### **Option B: S3 + EC2 (More Secure)**

Store Firebase key in S3, download at startup:

#### Step 1: Upload Firebase Key to S3

```bash
# From local machine
aws s3 cp serviceAccountKey.json s3://your-bucket-name/config/serviceAccountKey.json --sse AES256

# Make it private
aws s3api put-object-acl --bucket your-bucket-name --key config/serviceAccountKey.json --acl private
```

#### Step 2: Modified Startup Script

```bash
cat > /home/ec2-user/social-service/start.sh << 'EOF'
#!/bin/bash

# Download Firebase key from S3
aws s3 cp s3://your-bucket-name/config/serviceAccountKey.json /home/ec2-user/social-service/serviceAccountKey.json
chmod 600 /home/ec2-user/social-service/serviceAccountKey.json

# Set Firebase key path
export FIREBASE_KEY_PATH="/home/ec2-user/social-service/serviceAccountKey.json"

# ... rest of the startup script
EOF
```

**Note:** Your EC2 instance needs an IAM role with S3 read permissions.

---

### **Option C: AWS Secrets Manager (Most Secure)**

Store Firebase key as a secret:

#### Step 1: Store in Secrets Manager

```bash
# Create secret from file
aws secretsmanager create-secret \
  --name social-service/firebase-key \
  --description "Firebase service account key" \
  --secret-string file://serviceAccountKey.json \
  --region us-east-1
```

#### Step 2: Modify Application to Load from Secrets Manager

Add dependency to `pom.xml`:
```xml
<dependency>
    <groupId>software.amazon.awssdk</groupId>
    <artifactId>secretsmanager</artifactId>
    <version>2.20.0</version>
</dependency>
```

Modify `FirebaseConfig.java` to load from Secrets Manager (I can help with this).

---

## 🔧 EC2 Instance Requirements

### **Minimum Specs:**
- **Instance Type:** t3.small (2 vCPU, 2 GB RAM)
- **Storage:** 20 GB gp3
- **OS:** Amazon Linux 2023 or Ubuntu 22.04 LTS

### **Security Group (Port Configuration):**
```
Inbound Rules:
- 8082 (TCP) - Social Service API
- 22 (TCP) - SSH (from your IP only)

Outbound Rules:
- All traffic (for S3, RDS, Firebase access)
```

### **IAM Role (if using S3/RDS/Secrets Manager):**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::social-media-gidut-54513/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "arn:aws:secretsmanager:us-east-1:*:secret:social-service/*"
    }
  ]
}
```

---

## 📊 Database Setup (RDS MySQL)

If using AWS RDS:

```sql
-- Connect to RDS
mysql -h your-rds-endpoint.rds.amazonaws.com -u admin -p

-- Create database
CREATE DATABASE IF NOT EXISTS auth_db;
USE auth_db;

-- Tables will be auto-created by Spring Boot JPA
```

Update connection string:
```bash
export SPRING_DATASOURCE_URL="jdbc:mysql://your-rds-endpoint.rds.amazonaws.com:3306/auth_db?useSSL=true&serverTimezone=UTC"
```

---

## 🧪 Testing Deployment

### 1. Health Check
```bash
curl http://your-ec2-ip:8082/actuator/health
```

### 2. Test Firebase
```bash
# Check logs for Firebase initialization
tail -f /home/ec2-user/social-service/social-service.log | grep Firebase

# Should see:
# [Firebase] ✅ Firebase Admin SDK initialized successfully
```

### 3. Test API
```bash
# Test a protected endpoint
curl -H "Authorization: Bearer your-jwt-token" \
  http://your-ec2-ip:8082/api/posts/feed
```

---

## 🔍 Troubleshooting

### Firebase Key Not Loading
```bash
# Check file exists
ls -la /home/ec2-user/social-service/serviceAccountKey.json

# Check environment variable
echo $FIREBASE_KEY_PATH

# Check logs
grep "Firebase" /home/ec2-user/social-service/social-service.log
```

### Port Already in Use
```bash
# Find process using port 8082
sudo lsof -i :8082

# Kill it
sudo kill -9 <PID>
```

### Out of Memory
```bash
# Increase heap size in start.sh
java -jar -Xmx2048m -Xms1024m social-service-1.0.0.jar
```

### Can't Connect to RDS
```bash
# Test MySQL connection
mysql -h your-rds-endpoint -u admin -p

# Check security group allows EC2 instance
```

---

## 📁 Directory Structure on EC2

```
/home/ec2-user/social-service/
├── social-service-1.0.0.jar      # Application JAR
├── serviceAccountKey.json         # Firebase key (600 permissions)
├── start.sh                       # Startup script
├── stop.sh                        # Stop script
├── social-service.log             # Application logs
└── social-service.pid             # Process ID file
```

---

## 🔐 Security Best Practices

1. ✅ **Never commit `serviceAccountKey.json` to git**
2. ✅ Set file permissions to `600` (owner read/write only)
3. ✅ Use AWS Secrets Manager for production
4. ✅ Enable SSL/TLS on RDS
5. ✅ Use IAM roles instead of hardcoded AWS keys
6. ✅ Rotate Firebase service accounts regularly
7. ✅ Use HTTPS with SSL certificate (not HTTP)
8. ✅ Restrict EC2 security group to specific IPs

---

## 📦 Quick Deployment Commands

```bash
# 1. Build JAR locally (Windows)
cd "c:\Users\gidut\OneDrive\html files\Projects\social-chat-app\backend\social-service"
set "JAVA_HOME=C:\Program Files\Java\jdk-17"
set "PATH=C:\Program Files\Java\jdk-17\bin;%PATH%"
mvn clean package -DskipTests

# 2. Upload to EC2
scp -i "your-key.pem" target/social-service-1.0.0.jar ec2-user@your-ec2-ip:/home/ec2-user/
scp -i "your-key.pem" path/to/serviceAccountKey.json ec2-user@your-ec2-ip:/home/ec2-user/

# 3. SSH and setup
ssh -i "your-key.pem" ec2-user@your-ec2-ip
mkdir -p social-service
mv *.jar *.json social-service/
cd social-service
# Create start.sh (see above)
chmod +x start.sh
./start.sh

# 4. Verify
curl http://localhost:8082/actuator/health
tail -f social-service.log
```

---

## 🎯 Production Checklist

- [ ] Firebase service key uploaded and secured (600 permissions)
- [ ] Environment variables configured
- [ ] RDS database created and accessible
- [ ] S3 bucket created with proper IAM permissions
- [ ] EC2 security group configured
- [ ] Application starts successfully
- [ ] Firebase initializes (check logs)
- [ ] Health check passes
- [ ] API endpoints respond
- [ ] Push notifications work
- [ ] File uploads to S3 work
- [ ] WebSocket connections work
- [ ] Set up monitoring/alerts
- [ ] Configure auto-restart on failure

---

## 📞 Support

If you encounter issues:
1. Check logs: `tail -f social-service.log`
2. Check Firebase: `grep Firebase social-service.log`
3. Check database: Test MySQL connection
4. Check ports: `sudo lsof -i :8082`
5. Check process: `ps aux | grep social-service`
