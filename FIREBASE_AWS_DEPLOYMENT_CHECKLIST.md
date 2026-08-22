# ✅ Firebase + AWS Deployment Checklist

## 📋 Pre-Deployment Steps

### 1. Get Firebase Service Account Key
- [ ] Go to [Firebase Console](https://console.firebase.google.com/)
- [ ] Select your project
- [ ] Navigate to: **⚙️ Settings** → **Project Settings** → **Service Accounts**
- [ ] Click **"Generate New Private Key"**
- [ ] Download JSON file
- [ ] Rename to: `serviceAccountKey.json`
- [ ] Save in project root: `c:\Users\gidut\OneDrive\html files\Projects\social-chat-app\serviceAccountKey.json`

### 2. Prepare JAR File
- [ ] JAR already built: `backend\social-service\target\social-service-1.0.0.jar` ✅
- [ ] Size: 123 MB ✅
- [ ] Contains all blocking enforcement fixes ✅

### 3. AWS Prerequisites
- [ ] EC2 instance running (Amazon Linux 2023 or Ubuntu)
- [ ] Java 17 installed on EC2
- [ ] MySQL database accessible (RDS or EC2-hosted)
- [ ] S3 bucket created: `social-media-gidut-54513`
- [ ] Security group configured (port 8082 open)
- [ ] `.pem` key file for SSH access
- [ ] IAM role for EC2 (S3 access)

---

## 🚀 Deployment Methods

### **Option 1: Quick Deploy (Using Script)** ⭐ EASIEST

```bash
cd "c:\Users\gidut\OneDrive\html files\Projects\social-chat-app"
deploy-to-aws.bat
```

The script will:
1. ✅ Upload JAR to EC2
2. ✅ Upload Firebase key to EC2
3. ✅ Create directory structure
4. ✅ Set proper permissions

**Then SSH and start:**
```bash
ssh -i "your-key.pem" ec2-user@your-ec2-ip
cd social-service
# Create start.sh (see detailed guide)
./start.sh
```

---

### **Option 2: Manual Deploy**

#### Step 1: Upload Files
```bash
# Upload JAR
scp -i "your-key.pem" backend/social-service/target/social-service-1.0.0.jar ec2-user@your-ec2-ip:/home/ec2-user/

# Upload Firebase key
scp -i "your-key.pem" serviceAccountKey.json ec2-user@your-ec2-ip:/home/ec2-user/
```

#### Step 2: SSH and Setup
```bash
ssh -i "your-key.pem" ec2-user@your-ec2-ip

# Create directory
mkdir -p /home/ec2-user/social-service
mv social-service-1.0.0.jar social-service/
mv serviceAccountKey.json social-service/
cd social-service

# Secure Firebase key
chmod 600 serviceAccountKey.json
```

#### Step 3: Create Start Script
```bash
cat > start.sh << 'EOF'
#!/bin/bash

# Firebase key
export FIREBASE_KEY_PATH="/home/ec2-user/social-service/serviceAccountKey.json"

# Database (UPDATE THESE!)
export SPRING_DATASOURCE_URL="jdbc:mysql://YOUR_RDS_ENDPOINT:3306/auth_db?useSSL=true&serverTimezone=UTC"
export SPRING_DATASOURCE_USERNAME="admin"
export SPRING_DATASOURCE_PASSWORD="YOUR_PASSWORD"

# JWT Secret
export JWT_SECRET="5367566B59703373367639792F423F4528482B4D6251655468576D5A71347437"

# S3
export AWS_S3_BUCKET_NAME="social-media-gidut-54513"
export AWS_S3_REGION="us-east-1"

# Agora
export AGORA_APP_ID="96f2b1afbf744dc5818487f2e31ed9e7"
export AGORA_APP_CERT="ef473b70af0d40989d94ca2d7ce5c248"

# Start
nohup java -jar -Xmx1024m social-service-1.0.0.jar > social-service.log 2>&1 &
echo $! > social-service.pid
echo "Started with PID: $(cat social-service.pid)"
EOF

chmod +x start.sh
```

#### Step 4: Start Service
```bash
./start.sh

# Check logs
tail -f social-service.log
```

---

### **Option 3: S3 Storage for Firebase Key** 🔒 MOST SECURE

```bash
# Upload Firebase key to S3
aws s3 cp serviceAccountKey.json s3://social-media-gidut-54513/config/serviceAccountKey.json --sse AES256

# In start.sh, download from S3
aws s3 cp s3://social-media-gidut-54513/config/serviceAccountKey.json /home/ec2-user/social-service/serviceAccountKey.json
```

---

## 🔍 Post-Deployment Verification

### Check 1: Service Running
```bash
ps aux | grep social-service
```
**Expected:** Process running with java command

### Check 2: Firebase Initialized
```bash
grep "Firebase" social-service.log
```
**Expected:** `[Firebase] ✅ Firebase Admin SDK initialized successfully`

### Check 3: Health Endpoint
```bash
curl http://localhost:8082/actuator/health
```
**Expected:** `{"status":"UP"}`

### Check 4: API Response
```bash
curl http://localhost:8082/api/posts/feed?page=0&size=10
```
**Expected:** 401 or actual data (depending on auth)

### Check 5: Blocked Users Working
```bash
# Should have blocking enforcement in logs
grep "isEitherBlocked" social-service.log
```

---

## 🔧 Configuration Checklist

### Environment Variables (REQUIRED)
```bash
✅ FIREBASE_KEY_PATH - Path to serviceAccountKey.json
✅ SPRING_DATASOURCE_URL - MySQL connection string
✅ SPRING_DATASOURCE_USERNAME - Database username
✅ SPRING_DATASOURCE_PASSWORD - Database password
⚠️  JWT_SECRET - JWT signing secret (use existing)
⚠️  AWS_S3_BUCKET_NAME - S3 bucket for media
⚠️  AWS_S3_REGION - S3 region
⚠️  AGORA_APP_ID - Agora app ID for calls
⚠️  AGORA_APP_CERT - Agora certificate
```

### EC2 Security Group
```
Inbound:
✅ Port 8082 (TCP) - Social Service API
✅ Port 22 (TCP) - SSH (your IP only)

Outbound:
✅ All traffic (for RDS, S3, Firebase)
```

### RDS Security Group
```
Inbound:
✅ Port 3306 (TCP) - MySQL (from EC2 security group)
```

---

## 🐛 Troubleshooting

### Firebase Not Loading
```bash
# Check file exists
ls -la /home/ec2-user/social-service/serviceAccountKey.json

# Check permissions
# Should be: -rw------- (600)

# Check environment variable
echo $FIREBASE_KEY_PATH

# Check JSON validity
cat serviceAccountKey.json | python -m json.tool
```

### Can't Connect to Database
```bash
# Test from EC2
mysql -h your-rds-endpoint.rds.amazonaws.com -u admin -p

# Check security group
# RDS must allow inbound from EC2 security group
```

### Port Already in Use
```bash
# Find process
sudo lsof -i :8082

# Kill it
sudo kill -9 <PID>
```

### Out of Memory
```bash
# Increase heap in start.sh
java -jar -Xmx2048m -Xms1024m social-service-1.0.0.jar
```

---

## 📊 Current Status

### ✅ Completed
- [x] Backend code has all blocking enforcement fixes
- [x] JAR file built (123 MB)
- [x] Firebase configuration in code
- [x] Deployment scripts created

### 🔄 Pending
- [ ] Download Firebase service account key
- [ ] Upload JAR to EC2
- [ ] Upload Firebase key to EC2
- [ ] Configure environment variables
- [ ] Start service on EC2
- [ ] Test Firebase initialization
- [ ] Test blocked users feature
- [ ] Test push notifications

---

## 🎯 Quick Commands Reference

### Build & Deploy
```bash
# Build (Windows)
cd "c:\Users\gidut\OneDrive\html files\Projects\social-chat-app"
cd backend\social-service
set "JAVA_HOME=C:\Program Files\Java\jdk-17"
set "PATH=C:\Program Files\Java\jdk-17\bin;%PATH%"
mvn clean package -DskipTests

# Deploy (Windows)
cd ..\..
deploy-to-aws.bat

# Start (EC2)
cd /home/ec2-user/social-service
./start.sh
tail -f social-service.log
```

### Stop Service
```bash
# On EC2
cat social-service.pid | xargs kill
rm social-service.pid
```

### Restart Service
```bash
# On EC2
./stop.sh
./start.sh
```

### View Logs
```bash
# Real-time
tail -f social-service.log

# Last 100 lines
tail -n 100 social-service.log

# Search for errors
grep ERROR social-service.log

# Search for Firebase
grep Firebase social-service.log
```

---

## 📚 Documentation Files

1. **AWS_DEPLOY_SOCIAL_SERVICE_WITH_FIREBASE.md** - Complete deployment guide
2. **BLOCKED_USERS_FIXES_COMPLETE.md** - Blocking feature details
3. **deploy-to-aws.bat** - Automated deployment script
4. **This file** - Quick checklist

---

## ⚡ Next Steps

1. **Download Firebase Service Key** (if not done)
   - Firebase Console → Project Settings → Service Accounts → Generate New Private Key
   
2. **Run Deployment Script**
   ```bash
   deploy-to-aws.bat
   ```

3. **SSH and Configure**
   - Update database credentials in start.sh
   - Start service
   
4. **Verify Everything Works**
   - Check logs for Firebase ✅
   - Test API endpoints
   - Test push notifications
   - Test blocked users feature

---

## 🆘 Need Help?

**Common Issues:**
- Firebase key not loading → Check file path and permissions
- Can't connect to database → Check RDS security group
- Port already in use → Kill existing process
- Service crashes → Check logs, increase memory

**Log Locations:**
- Application: `/home/ec2-user/social-service/social-service.log`
- System (if using systemd): `journalctl -u social-service -f`
