# 🚀 ALL SERVICES READY - COMPLETE DEPLOYMENT GUIDE

## ✅ BUILD COMPLETE - All Services Ready

| Service | JAR File | Size | Port | Status |
|---------|----------|------|------|--------|
| **API Gateway** | api-gateway-1.0.0.jar | 43 MB | 8080 | ✅ READY |
| **Auth Service** | auth-service-1.0.0.jar | 78 MB | 8081 | ✅ READY |
| **Social Service** | social-service-1.0.0.jar | 123 MB | 8082 | ✅ READY |
| **Firebase Key** | serviceAccountKey.json | - | - | ✅ READY |

**Total Upload Size:** 245 MB  
**Blocking Enforcement:** ✅ All 7 fixes included  
**Firebase Integration:** ✅ Configured and ready

---

## 🎯 ONE-COMMAND DEPLOYMENT

```bash
cd "c:\Users\gidut\OneDrive\html files\Projects\social-chat-app"
deploy-all-services-aws.bat
```

### What Happens:
1. ✅ Verifies all JAR files exist
2. ✅ Uploads API Gateway (43 MB)
3. ✅ Uploads Auth Service (78 MB)
4. ✅ Uploads Social Service (123 MB)
5. ✅ Uploads Firebase serviceAccountKey.json
6. ✅ Creates /home/ec2-user/api-gateway/
7. ✅ Creates /home/ec2-user/auth-service/
8. ✅ Creates /home/ec2-user/social-service/
9. ✅ Generates start.sh for each service
10. ✅ Sets Firebase key permissions to 600

---

## 📋 Prerequisites

### 1. EC2 Instance
```
✅ Instance Type: t3.medium or larger (4 GB RAM minimum)
✅ OS: Amazon Linux 2023 or Ubuntu 22.04
✅ Java 17 installed
✅ Public IP assigned
✅ Security Group configured
```

### 2. RDS Database (Optional - can use EC2 MySQL)
```
✅ Engine: MySQL 8.0
✅ Database name: auth_db
✅ Username: admin (or your choice)
✅ Password: Set and saved
✅ Accessible from EC2
```

### 3. Security Groups
```
EC2 Security Group - Inbound:
  - Port 22 (SSH) from your IP
  - Port 8080 (API Gateway) from 0.0.0.0/0
  - Port 8081 (Auth - optional) from your IP
  - Port 8082 (Social - optional) from your IP

RDS/MySQL Security Group - Inbound:
  - Port 3306 from EC2 security group
```

### 4. IAM Role (For S3 & Firebase)
```
Attach to EC2 instance with policies:
  - AmazonS3FullAccess (or custom policy for your bucket)
  - SecretsManagerReadWrite (optional, for storing credentials)
```

---

## 🚀 DEPLOYMENT STEPS

### STEP 1: Run Deployment Script

Open PowerShell/Command Prompt:

```bash
cd "c:\Users\gidut\OneDrive\html files\Projects\social-chat-app"
deploy-all-services-aws.bat
```

**When prompted, enter:**
- EC2 Public IP: `54.123.45.67` (example)
- Path to .pem file: `C:\Users\gidut\Downloads\my-key.pem`
- Confirm deployment: `y`

**Wait for:** "DEPLOYMENT COMPLETE!"

---

### STEP 2: SSH into EC2

```bash
ssh -i "C:\Users\gidut\Downloads\my-key.pem" ec2-user@54.123.45.67
```

**You should see:**
```
/home/ec2-user/
├── api-gateway/
├── auth-service/
└── social-service/
```

---

### STEP 3: Configure Database Credentials

#### Option A: RDS MySQL
```bash
# Update Auth Service
nano auth-service/start.sh

# Find and update these lines:
export SPRING_DATASOURCE_URL="jdbc:mysql://your-rds.us-east-1.rds.amazonaws.com:3306/auth_db?useSSL=true&serverTimezone=UTC"
export SPRING_DATASOURCE_USERNAME="admin"
export SPRING_DATASOURCE_PASSWORD="YourStrongPassword123"
```

```bash
# Update Social Service (same credentials)
nano social-service/start.sh

# Update the same database variables
```

#### Option B: Local MySQL on EC2
```bash
# Install MySQL on EC2 (if not done)
sudo yum install mysql-server -y  # Amazon Linux
sudo systemctl start mysqld
sudo systemctl enable mysqld

# Create database
mysql -u root -p
CREATE DATABASE auth_db;
exit;

# Use in start.sh:
export SPRING_DATASOURCE_URL="jdbc:mysql://localhost:3306/auth_db?useSSL=false&serverTimezone=UTC"
export SPRING_DATASOURCE_USERNAME="root"
export SPRING_DATASOURCE_PASSWORD="your-mysql-password"
```

---

### STEP 4: Start Services (IMPORTANT ORDER!)

#### 1. Start Auth Service First

```bash
cd auth-service
./start.sh
```

**Output:** `Auth Service started on port 8081. PID: 12345`

**Check logs:**
```bash
tail -f auth-service.log
```

**Wait for:** `Started AuthServiceApplication in X.XXX seconds`  
**Press:** Ctrl+C to exit log view

---

#### 2. Start Social Service Second

```bash
cd ../social-service
./start.sh
```

**Output:** `Social Service started on port 8082. PID: 12346`

**Check logs:**
```bash
tail -f social-service.log
```

**Wait for:**
- `Started SocialServiceApplication in X.XXX seconds`
- `[Firebase] ✅ Firebase Admin SDK initialized successfully`

**Press:** Ctrl+C to exit log view

---

#### 3. Start API Gateway Last

```bash
cd ../api-gateway
./start.sh
```

**Output:** `API Gateway started on port 8080. PID: 12347`

**Check logs:**
```bash
tail -f api-gateway.log
```

**Wait for:** `Started ApiGatewayApplication in X.XXX seconds`

---

### STEP 5: Verify All Services

```bash
# Check all Java processes running
ps aux | grep java
```

**Should show 3 java processes**

```bash
# Test health endpoints
curl http://localhost:8081/actuator/health
# Expected: {"status":"UP"}

curl http://localhost:8082/actuator/health
# Expected: {"status":"UP"}

curl http://localhost:8080/actuator/health
# Expected: {"status":"UP"}
```

---

### STEP 6: Test Firebase

```bash
grep "Firebase" social-service/social-service.log
```

**Expected output:**
```
[Firebase] 📂 Loaded serviceAccountKey from ENV path: /home/ec2-user/social-service/serviceAccountKey.json
[Firebase] ✅ Firebase Admin SDK initialized successfully
```

---

### STEP 7: Test API from Outside EC2

From your local machine:

```bash
# Health check
curl http://54.123.45.67:8080/actuator/health

# Test signup (example)
curl -X POST http://54.123.45.67:8080/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "email": "test@example.com",
    "password": "Test@123",
    "fullName": "Test User"
  }'
```

---

## 🛑 Managing Services

### Stop a Service
```bash
# Stop by PID file
cd service-name
cat service-name.pid | xargs kill
rm service-name.pid
```

### Stop All Services
```bash
kill $(cat api-gateway/api-gateway.pid)
kill $(cat auth-service/auth-service.pid)
kill $(cat social-service/social-service.pid)

rm api-gateway/api-gateway.pid
rm auth-service/auth-service.pid
rm social-service/social-service.pid
```

### Restart a Service
```bash
cd service-name
cat service-name.pid | xargs kill
./start.sh
```

### View Logs
```bash
# Real-time
tail -f social-service/social-service.log

# Last 100 lines
tail -n 100 social-service/social-service.log

# Search for errors
grep ERROR social-service/social-service.log

# Search for Firebase
grep Firebase social-service/social-service.log
```

---

## 🔧 Configuration Reference

### Environment Variables

Each service's `start.sh` contains environment variables you can customize:

#### Auth Service
```bash
SPRING_DATASOURCE_URL       # MySQL connection string
SPRING_DATASOURCE_USERNAME  # Database user
SPRING_DATASOURCE_PASSWORD  # Database password
JWT_SECRET                  # JWT signing key
SPRING_MAIL_HOST           # SMTP server for OTP emails
SPRING_MAIL_USERNAME       # Email account
SPRING_MAIL_PASSWORD       # Email app password
```

#### Social Service
```bash
FIREBASE_KEY_PATH          # Path to serviceAccountKey.json
SPRING_DATASOURCE_URL      # MySQL connection string
SPRING_DATASOURCE_USERNAME # Database user
SPRING_DATASOURCE_PASSWORD # Database password
JWT_SECRET                 # JWT signing key (same as Auth)
AWS_S3_BUCKET_NAME        # S3 bucket for media
AWS_S3_REGION             # S3 region
AGORA_APP_ID              # Agora app ID for calls
AGORA_APP_CERT            # Agora certificate
```

#### API Gateway
```bash
AUTH_SERVICE_URL          # http://localhost:8081
SOCIAL_SERVICE_URL        # http://localhost:8082
```

---

## 🧪 Testing Checklist

After deployment, test these features:

### Authentication Service
- [ ] User registration
- [ ] User login
- [ ] JWT token generation
- [ ] OTP generation/verification
- [ ] Password reset

### Social Service
- [ ] Get user profile
- [ ] Create post
- [ ] Like post
- [ ] Comment on post
- [ ] Follow/unfollow user
- [ ] Send message
- [ ] Receive push notification (Firebase)
- [ ] Block user (all 7 restrictions)
- [ ] Upload media to S3

### API Gateway
- [ ] Routes to Auth Service
- [ ] Routes to Social Service
- [ ] Rate limiting works
- [ ] CORS configured

---

## 🐛 Common Issues & Solutions

### Issue: "Cannot connect to database"
```bash
# Test MySQL connection
mysql -h your-rds-endpoint -u admin -p

# Solution:
# 1. Check RDS security group allows EC2
# 2. Check database credentials in start.sh
# 3. Check RDS is publicly accessible (if needed)
```

### Issue: "Firebase not initialized"
```bash
# Check file exists
ls -la social-service/serviceAccountKey.json

# Should be: -rw------- (600)

# If wrong permissions:
chmod 600 social-service/serviceAccountKey.json

# Check environment variable
grep FIREBASE_KEY_PATH social-service/start.sh
```

### Issue: "Port already in use"
```bash
# Find process using port
sudo lsof -i :8082

# Kill it
sudo kill -9 <PID>
```

### Issue: "Out of memory"
```bash
# Check free memory
free -m

# Increase heap in start.sh
# Change -Xmx1024m to -Xmx2048m
nano social-service/start.sh
```

### Issue: "S3 upload fails"
```bash
# Verify IAM role attached to EC2
aws sts get-caller-identity

# Test S3 access
aws s3 ls s3://social-media-gidut-54513

# If fails, attach IAM role with S3 permissions to EC2
```

---

## 📊 Deployed Features

### ✅ Social Service Includes All:

**Blocking Enforcement (7 Fixes):**
- ✅ Profile access blocked
- ✅ Messages blocked
- ✅ Comments blocked  
- ✅ Likes blocked
- ✅ Follow requests blocked
- ✅ Calls blocked
- ✅ Post viewing blocked

**Core Features:**
- ✅ Firebase Cloud Messaging (Push Notifications)
- ✅ WebSocket (Real-time chat, typing indicators)
- ✅ AWS S3 (Media storage)
- ✅ Agora RTC (Video/audio calls)
- ✅ Call history
- ✅ Read receipts
- ✅ Offline sync
- ✅ User presence

---

## 🎯 Architecture Deployed

```
Internet → EC2 (Public IP: 54.123.45.67)
   │
   ├─ API Gateway (Port 8080) ────┐
   │                               │
   ├─ Auth Service (Port 8081) ←──┤
   │      ↓                        │
   │   MySQL/RDS                   │
   │                               │
   └─ Social Service (Port 8082) ←┘
         ↓         ↓        ↓
      MySQL/RDS   S3    Firebase
```

---

## 🔐 Security Notes

1. **Firebase Key:** 600 permissions, never commit to Git
2. **Database Password:** Use strong passwords
3. **JWT Secret:** Generate unique secret for production
4. **SSH Access:** Restrict to your IP only
5. **API Gateway:** Only port 8080 needs public access
6. **SSL/TLS:** Enable on RDS connection
7. **Secrets:** Consider AWS Secrets Manager for production

---

## 🎉 SUCCESS!

Your complete backend is now running on AWS:

✅ 3 services deployed  
✅ Firebase configured  
✅ Database connected  
✅ S3 storage ready  
✅ Push notifications enabled  
✅ Blocking feature enforced  
✅ API accessible at: `http://your-ec2-ip:8080`

**Update your Flutter app:**
- Change API base URL to: `http://your-ec2-ip:8080`
- Test all features
- Deploy to production!

---

## 📞 Support

**Log Files:**
- `/home/ec2-user/auth-service/auth-service.log`
- `/home/ec2-user/social-service/social-service.log`
- `/home/ec2-user/api-gateway/api-gateway.log`

**Check Service Status:**
```bash
ps aux | grep java
curl http://localhost:8080/actuator/health
```

**Need Help?** Check logs first, they contain detailed error messages.
