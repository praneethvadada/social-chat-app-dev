# OTP Not Working - Email Configuration Fix

## Problem
OTP (One-Time Password) emails are not being sent because:
- ❌ Email service is disabled (`app.mail.enabled=false`)
- ❌ No SMTP credentials configured
- ❌ Gmail App Password not set up

## Solution: Configure Gmail SMTP for OTP Emails

### Step 1: Create Gmail App Password

1. **Go to Google Account**: https://myaccount.google.com/
2. **Click "Security"** in left sidebar
3. **Enable 2-Step Verification** (if not already enabled):
   - Click "2-Step Verification"
   - Follow setup instructions
   - **Required** before creating App Passwords

4. **Create App Password**:
   - Go to: https://myaccount.google.com/apppasswords
   - Or search for "App passwords" in Google Account settings
   - Select app: **Mail**
   - Select device: **Other (Custom name)**
   - Enter name: **Social Media App**
   - Click **Generate**
   - **IMPORTANT**: Copy the 16-character password (e.g., `abcd efgh ijkl mnop`)
   - Remove spaces: `abcdefghijklmnop`

### Step 2: Update auth-service.env File

Edit: `backend/auth-service.env`

Replace:
```bash
SPRING_MAIL_USERNAME=your-email@gmail.com
SPRING_MAIL_PASSWORD=your-gmail-app-password
```

With your actual credentials:
```bash
SPRING_MAIL_USERNAME=youractual@gmail.com
SPRING_MAIL_PASSWORD=abcdefghijklmnop
```

**Example** (using fake data):
```bash
# Email Configuration
APP_MAIL_ENABLED=true
SPRING_MAIL_HOST=smtp.gmail.com
SPRING_MAIL_PORT=587
SPRING_MAIL_USERNAME=vamsi3515@gmail.com
SPRING_MAIL_PASSWORD=zyxw vuts rqpo nmlk
SPRING_MAIL_PROPERTIES_MAIL_SMTP_AUTH=true
SPRING_MAIL_PROPERTIES_MAIL_SMTP_STARTTLS_ENABLE=true
APP_FRONTEND_URL=http://98.92.24.110:8080
```

### Step 3: Upload Updated Config to EC2

```bash
# From your local machine
scp -i "C:\Users\gidut\Downloads\social-media-key.pem" ^
    backend\auth-service.env ^
    ec2-user@98.92.24.110:/tmp/auth-service.env

# SSH to EC2 and update
ssh -i "C:\Users\gidut\Downloads\social-media-key.pem" ec2-user@98.92.24.110

# Move to correct location
sudo mv /tmp/auth-service.env /opt/auth-service/.env

# Restart auth-service
sudo systemctl restart auth-service

# Check if it started successfully
sudo systemctl status auth-service

# Check logs for email configuration
sudo journalctl -u auth-service -f | grep -i "mail\|email"
```

### Step 4: Test OTP Email

From your mobile app or Postman:

```bash
# Test send OTP
curl -X POST http://98.92.24.110:8080/api/auth/send-otp \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com"}'

# Expected response:
# {"message":"OTP sent to email"}

# Check your email inbox for OTP code
```

## Alternative: Use Different Email Service

### Option A: Outlook/Hotmail

```bash
SPRING_MAIL_HOST=smtp-mail.outlook.com
SPRING_MAIL_PORT=587
SPRING_MAIL_USERNAME=your-email@outlook.com
SPRING_MAIL_PASSWORD=your-outlook-password
```

### Option B: SendGrid (Recommended for Production)

1. Sign up: https://signup.sendgrid.com/
2. Create API Key
3. Configure:

```bash
SPRING_MAIL_HOST=smtp.sendgrid.net
SPRING_MAIL_PORT=587
SPRING_MAIL_USERNAME=apikey
SPRING_MAIL_PASSWORD=your-sendgrid-api-key
```

### Option C: AWS SES (Best for AWS)

1. Verify your email in AWS SES Console
2. Get SMTP credentials
3. Configure:

```bash
SPRING_MAIL_HOST=email-smtp.us-east-1.amazonaws.com
SPRING_MAIL_PORT=587
SPRING_MAIL_USERNAME=your-ses-smtp-username
SPRING_MAIL_PASSWORD=your-ses-smtp-password
```

## Troubleshooting

### Issue 1: "Authentication failed"

**Cause**: Wrong Gmail App Password or regular password used instead of App Password

**Fix**:
- Use **App Password**, not your regular Gmail password
- Remove spaces from 16-character App Password
- Ensure 2-Step Verification is enabled

### Issue 2: "Mail server connection failed"

**Cause**: Port blocked or wrong SMTP settings

**Fix**:
```bash
# Test SMTP connection from EC2
ssh -i "C:\Users\gidut\Downloads\social-media-key.pem" ec2-user@98.92.24.110

# Install telnet
sudo yum install telnet -y

# Test Gmail SMTP
telnet smtp.gmail.com 587
# Should connect successfully
```

### Issue 3: "OTP sent but not receiving email"

**Checks**:
1. Check spam/junk folder
2. Verify FROM email is correct
3. Check backend logs:
```bash
sudo journalctl -u auth-service -n 100 | grep -i "email\|mail\|otp"
```

### Issue 4: "Mail disabled" in logs

**Fix**: Ensure `APP_MAIL_ENABLED=true` in auth-service.env

## Verification Commands

### Check if Email Config is Loaded

```bash
ssh -i "C:\Users\gidut\Downloads\social-media-key.pem" ec2-user@98.92.24.110

# Check environment variables
sudo systemctl show auth-service | grep MAIL

# Check logs for startup
sudo journalctl -u auth-service -n 50 | grep -i "mail\|smtp"
```

### Test Email Sending from Backend

```bash
# Watch logs while testing
sudo journalctl -u auth-service -f
```

In another terminal:
```bash
curl -X POST http://98.92.24.110:8080/api/auth/send-otp \
  -H "Content-Type: application/json" \
  -d '{"email":"youremail@gmail.com"}'
```

Expected log output:
```
OTP email sent to: youremail@gmail.com
```

## Complete Setup Example

Here's a complete working example with Gmail:

### 1. auth-service.env
```bash
SPRING_DATASOURCE_URL=jdbc:mysql://social-media-db.ca30yaou8j00.us-east-1.rds.amazonaws.com:3306/social_app?createDatabaseIfNotExist=true&useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC
SPRING_DATASOURCE_USERNAME=admin
SPRING_DATASOURCE_PASSWORD=SecurePass123!
SPRING_DATA_REDIS_HOST=social-media-redis.0k0afe.0001.use1.cache.amazonaws.com
SPRING_DATA_REDIS_PORT=6379
JWT_SECRET=5367566B59703373367639792F423F4528482B4D6251655468576D5A71347437
SERVER_PORT=8081

# Email Configuration
APP_MAIL_ENABLED=true
SPRING_MAIL_HOST=smtp.gmail.com
SPRING_MAIL_PORT=587
SPRING_MAIL_USERNAME=vamsi3515@gmail.com
SPRING_MAIL_PASSWORD=abcdefghijklmnop
SPRING_MAIL_PROPERTIES_MAIL_SMTP_AUTH=true
SPRING_MAIL_PROPERTIES_MAIL_SMTP_STARTTLS_ENABLE=true
APP_FRONTEND_URL=http://98.92.24.110:8080
```

### 2. Deploy Commands
```bash
# 1. Update local file with your Gmail credentials (above)

# 2. Upload to EC2
scp -i "C:\Users\gidut\Downloads\social-media-key.pem" backend\auth-service.env ec2-user@98.92.24.110:/tmp/

# 3. SSH and update
ssh -i "C:\Users\gidut\Downloads\social-media-key.pem" ec2-user@98.92.24.110

sudo mv /tmp/auth-service.env /opt/auth-service/.env
sudo systemctl restart auth-service

# 4. Verify
curl http://localhost:8081/actuator/health
```

### 3. Test from Mobile App
1. Open app signup screen
2. Enter email
3. Tap "Send OTP"
4. Check email inbox for 4-digit code
5. Enter code
6. Complete signup

## Security Best Practices

1. **Never commit real credentials** to Git
2. **Use environment variables** on EC2
3. **Rotate App Passwords** regularly
4. **Monitor email sending** for abuse
5. **Consider AWS SES** for production (better deliverability)

## Summary

**What You Need to Do:**

1. ✅ Create Gmail App Password (done above)
2. ⏳ Update `backend/auth-service.env` with your Gmail & App Password
3. ⏳ Upload to EC2: `scp auth-service.env ec2-user@98.92.24.110:/tmp/`
4. ⏳ Move to `/opt/auth-service/.env` on EC2
5. ⏳ Restart service: `sudo systemctl restart auth-service`
6. ✅ Test OTP from mobile app

After this, OTP emails will be sent successfully! ✉️
