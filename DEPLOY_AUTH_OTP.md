# Deploy Auth Service with OTP - Manual Steps

## Files Uploaded to S3 ✅

- ✅ **auth-service-new.jar** (78.7 MB) - New JAR with OTP functionality
- ✅ **deploy-auth.sh** - Automated deployment script

Both files are in: `s3://social-media-gidut-54513/deployments/`

---

## Option 1: Quick Deploy (Using AWS Console Session Manager)

### Step 1: Connect to EC2
1. Go to **AWS Console** → **EC2** → **Instances**
2. Select instance `i-0139d8ec8d73b924f`
3. Click **Connect** → **Session Manager** → **Connect**

### Step 2: Run Deployment Script
Copy and paste these commands one by one:

```bash
# Download and run deployment script
aws s3 cp s3://social-media-gidut-54513/deployments/deploy-auth.sh /tmp/deploy-auth.sh --region us-east-1
chmod +x /tmp/deploy-auth.sh
/tmp/deploy-auth.sh
```

The script will:
- Download new JAR from S3
- Stop auth-service
- Backup old JAR
- Install new JAR
- Start service
- Test OTP endpoint

---

## Option 2: Manual Deploy (Step by Step)

If the script fails, run these commands manually on EC2:

```bash
# 1. Download JAR
aws s3 cp s3://social-media-gidut-54513/deployments/auth-service-new.jar /tmp/auth-service-1.0.0.jar --region us-east-1

# 2. Stop service
sudo systemctl stop auth-service

# 3. Backup old JAR (optional)
sudo cp /opt/auth-service/auth-service.jar /opt/auth-service/auth-service.jar.backup

# 4. Install new JAR
sudo mv /tmp/auth-service-1.0.0.jar /opt/auth-service/auth-service.jar
sudo chown ec2-user:ec2-user /opt/auth-service/auth-service.jar

# 5. Start service
sudo systemctl start auth-service

# 6. Check status
sudo systemctl status auth-service

# 7. View logs
sudo journalctl -u auth-service -f
```

---

## Testing OTP Functionality

### Test 1: From EC2 (Internal)
```bash
curl -X POST http://localhost:8081/otp/send \
  -H "Content-Type: application/json" \
  -d '{"email":"guideup3515@gmail.com"}'
```

**Expected Response:**
```json
{
  "message": "OTP sent successfully to guideup3515@gmail.com",
  "expiresIn": "10 minutes"
}
```

### Test 2: From Your Computer (External)
```bash
curl -X POST http://98.92.24.110:8081/otp/send \
  -H "Content-Type: application/json" \
  -d '{"email":"guideup3515@gmail.com"}'
```

### Test 3: Verify OTP
Check your email (guideup3515@gmail.com) for the 4-digit OTP code, then:

```bash
curl -X POST http://98.92.24.110:8081/otp/verify \
  -H "Content-Type: application/json" \
  -d '{"email":"guideup3515@gmail.com","otp":"1234"}'
```

Replace `1234` with the actual OTP from email.

**Expected Response:**
```json
{
  "verified": true,
  "message": "OTP verified successfully"
}
```

---

## Troubleshooting

### Service won't start
```bash
# Check logs
sudo journalctl -u auth-service -n 50 --no-pager

# Check if port 8081 is in use
sudo netstat -tlnp | grep 8081

# Check JAR file
ls -lh /opt/auth-service/auth-service.jar
```

### OTP not sending
```bash
# Check email configuration
sudo cat /opt/auth-service/.env | grep MAIL

# Check for email errors in logs
sudo journalctl -u auth-service | grep -i "mail\|email\|otp" | tail -20
```

### 403 Forbidden error
- SecurityConfig should allow `/otp/**` endpoints
- No authentication needed for send/verify
- Check logs for security filter errors

---

## API Endpoints Available

| Endpoint | Method | Public? | Description |
|----------|--------|---------|-------------|
| `/otp/send` | POST | ✅ Yes | Send OTP to email |
| `/otp/verify` | POST | ✅ Yes | Verify OTP code |
| `/password-reset/request` | POST | ✅ Yes | Request password reset |
| `/password-reset/confirm` | POST | ✅ Yes | Reset password |
| `/register` | POST | ✅ Yes | Register new user |
| `/login` | POST | ✅ Yes | User login |
| `/health` | GET | ✅ Yes | Health check |

---

## What Changed in This Deployment

### New Files:
- OTPController.java - `/otp/send` and `/otp/verify` endpoints
- OTPService.java - OTP generation and verification logic
- OTPVerification.java - Entity for database
- OTPVerificationRepository.java - Database operations
- OTPRequest.java, OTPVerifyRequest.java - DTOs

### Updated Files:
- EmailService.java - Added `sendOTPEmail()` method
- SecurityConfig.java - Added `/otp/**` to public endpoints

### Features:
- ✅ 4-digit OTP generation (0000-9999)
- ✅ 10-minute expiration
- ✅ Maximum 5 verification attempts
- ✅ Email delivery via Gmail SMTP
- ✅ Automatic cleanup of expired OTPs
- ✅ Purpose tracking (REGISTRATION, PASSWORD_RESET, etc.)

---

## Next Steps After Deployment

1. **Test OTP sending** - Send OTP to your email
2. **Check email arrival** - Verify email reaches inbox
3. **Test OTP verification** - Verify the code works
4. **Integrate with mobile app** - Update API calls
5. **Test registration flow** - Complete end-to-end test

---

## Quick Command Reference

```bash
# Deploy
aws s3 cp s3://social-media-gidut-54513/deployments/deploy-auth.sh /tmp/ --region us-east-1 && chmod +x /tmp/deploy-auth.sh && /tmp/deploy-auth.sh

# Status
sudo systemctl status auth-service

# Logs (live)
sudo journalctl -u auth-service -f

# Logs (recent)
sudo journalctl -u auth-service --since '5 minutes ago'

# Restart
sudo systemctl restart auth-service

# Test OTP
curl -X POST http://localhost:8081/otp/send -H "Content-Type: application/json" -d '{"email":"guideup3515@gmail.com"}'
```
