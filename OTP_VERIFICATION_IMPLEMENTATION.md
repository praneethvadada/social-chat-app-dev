# Email OTP Verification Implementation Guide

## Overview
This document provides complete instructions for implementing email-based OTP verification for user registration in the Social Chat App.

---

## ✅ What's Been Implemented

### Frontend (Flutter)
1. **Modern OTP Screen** (`otp_screen.dart`)
   - 4 digit input boxes with auto-focus
   - Beautiful UI with logo, instructions
   - Verify button with loading state
   - Resend OTP button with countdown timer (60 seconds)

2. **Updated Signup Flow**
   - Signup form collects user data
   - On submit: Sends OTP to email (doesn't create account yet)
   - Navigates to OTP verification screen
   - After OTP verification: Creates account with `is_verified = true`

3. **API Service Methods Added**
   - `sendOtp(email)` - Send OTP to email
   - `verifyOtp(email, otp)` - Verify OTP code
   - `resendOtp(email)` - Resend OTP (max 5 attempts)

### Backend (Java Spring Boot)
1. **OTP Entity** (`OtpVerification.java`)
   - Stores email, OTP code, creation/expiry time
   - Tracks usage and resend attempts
   - 10-minute validity period

2. **OTP Service** (`OtpService.java`)
   - Generates 4-digit random OTP
   - Sends OTP via email
   - Verifies OTP with expiry/usage checks
   - Handles resends (max 5 attempts)

3. **OTP Controller** (`OtpController.java`)
   - `POST /auth/send-otp` - Generate and send OTP
   - `POST /auth/verify-otp` - Verify OTP code
   - `POST /auth/resend-otp` - Resend OTP

4. **Email Service Enhancement**
   - `sendOtpEmail()` method to send OTP emails

5. **OTP Repository** (`OtpVerificationRepository.java`)
   - Database queries for OTP management

6. **Database Migration** (`create_otp_table.sql`)
   - Creates `otp_verifications` table

---

## 🔧 Email Configuration Required

### Step 1: Configure Email Credentials in Backend

Edit `auth-service/src/main/resources/application.properties`:

```properties
# Email Configuration (Gmail Example)
spring.mail.host=smtp.gmail.com
spring.mail.port=587
spring.mail.username=YOUR_EMAIL@gmail.com
spring.mail.password=YOUR_APP_PASSWORD
spring.mail.properties.mail.smtp.auth=true
spring.mail.properties.mail.smtp.starttls.enable=true
spring.mail.properties.mail.smtp.starttls.required=true

# Enable/disable email sending
app.mail.enabled=true

# Frontend URL for email links (if needed)
app.frontend.url=http://localhost:3000
```

### Step 2: Get Gmail App Password (Recommended)

Since Gmail blocks "Less Secure Apps", use an App Password:

1. Go to: https://myaccount.google.com/apppasswords
2. Select "Mail" and "Windows Computer" (or your device)
3. Copy the generated 16-character password
4. Use this in `spring.mail.password` above

**Example:**
```
spring.mail.password=abcd efgh ijkl mnop
```

### Step 3: Alternative - Use Other Email Services

**SendGrid:**
```properties
spring.mail.host=smtp.sendgrid.net
spring.mail.port=587
spring.mail.username=apikey
spring.mail.password=SG.xxxxxxxxxxxxxxxxxxxx
```

**AWS SES:**
```properties
spring.mail.host=email-smtp.us-east-1.amazonaws.com
spring.mail.port=587
spring.mail.username=YOUR_SMTP_USERNAME
spring.mail.password=YOUR_SMTP_PASSWORD
```

**Office 365:**
```properties
spring.mail.host=smtp.office365.com
spring.mail.port=587
spring.mail.username=YOUR_EMAIL@company.com
spring.mail.password=YOUR_PASSWORD
```

---

## 📦 Database Setup

### Step 1: Apply Migration

Run the migration to create the OTP table:

```bash
# Using PowerShell (Windows)
mysql -u root -p auth_db < backend/migrations/create_otp_table.sql

# Or manually in DBeaver/MySQL Workbench:
# Copy content from: backend/migrations/create_otp_table.sql
# Execute in auth_db
```

### Verify Table Creation:

```sql
USE auth_db;
DESCRIBE otp_verifications;
```

Expected output:
```
Field          Type          Null  Key  Default
id             bigint        NO    PRI  NULL
email          varchar(255)  NO    UNI  NULL
otp            varchar(4)    NO         NULL
created_at     datetime      NO         CURRENT_TIMESTAMP
expires_at     datetime      NO         NULL
is_used        tinyint       NO         0
attempts       int           NO         0
```

---

## 🚀 Deployment Steps

### 1. Build Backend

```bash
cd backend
mvn clean install -DskipTests
```

### 2. Start Services

```bash
# Terminal 1: Auth Service
cd auth-service
mvn spring-boot:run

# Terminal 2: Social Service  
cd social-service
mvn spring-boot:run

# Terminal 3: API Gateway
cd api-gateway
mvn spring-boot:run

# Or use batch file:
./start-all-services.bat
```

### 3. Update Flutter

```bash
cd social-media-mobile
flutter pub get
flutter clean
flutter run
```

---

## 📝 Complete Registration Flow

### New User Signup:

1. **User fills signup form** (username, email, password, full name)
   - All fields are required
   - Password must be >= 6 characters

2. **User clicks Signup button**
   - Validation checks
   - Call: `ApiService.sendOtp(email)`
   - Backend generates 4-digit OTP
   - Email with OTP sent to user
   - App navigates to OTP verification screen

3. **User enters OTP**
   - 4 digit input boxes with auto-advance
   - User enters OTP digits

4. **User clicks Verify button**
   - Call: `ApiService.verifyOtp(email, otp)`
   - Backend verifies:
     - OTP matches
     - OTP not expired (10 min validity)
     - OTP not already used
   - If valid: marks OTP as used
   - Call: `ApiService.register()` with user data
   - Backend creates account with `is_verified = true`
   - Session created automatically
   - User logged in → Home Screen

5. **Resend OTP (if needed)**
   - User can click "Resend OTP" after 60 seconds
   - Max 5 resend attempts
   - Each resend generates new OTP

---

## 🔒 Security Features

1. **OTP Validity**: 10 minutes
2. **OTP Length**: 4 digits (0000-9999)
3. **Resend Limit**: Max 5 attempts
4. **One-Time Use**: Each OTP can only be verified once
5. **Email Verification**: Only verified emails can register
6. **Attempt Tracking**: Backend tracks invalid attempts

---

## 📱 Testing the Flow

### Test Case 1: Successful Registration

```
Email: test@example.com
Username: testuser
Password: password123
Full Name: Test User

→ Signup button
→ OTP sent to email
→ Enter OTP (check email)
→ Click Verify
→ Account created ✅
→ Logged in as testuser
```

### Test Case 2: Invalid OTP

```
→ Enter wrong OTP
→ Click Verify
→ Error: "Invalid or expired OTP"
→ Click Resend
→ Enter correct OTP
→ Success ✅
```

### Test Case 3: Expired OTP

```
→ Wait 10+ minutes
→ Enter OTP
→ Click Verify
→ Error: "Invalid or expired OTP"
→ Click Resend
→ New OTP sent
```

---

## 🐛 Troubleshooting

### Email not sending?

1. **Check mail enabled flag:**
   ```properties
   app.mail.enabled=true
   ```

2. **Verify credentials:**
   ```bash
   # Test email configuration
   telnet smtp.gmail.com 587
   ```

3. **Check logs:**
   ```
   Look for "OTP email sent to:" in console
   If not present, mail.enabled=false
   ```

### OTP not received?

1. Check spam/junk folder
2. Verify email address is correct
3. Check backend logs for errors
4. Verify mail credentials are correct

### Database errors?

```sql
-- Check if table exists
SHOW TABLES IN auth_db LIKE 'otp_verifications';

-- Check table structure
DESCRIBE auth_db.otp_verifications;

-- Check for data
SELECT COUNT(*) FROM otp_verifications;
```

---

## 📊 Database Queries

### View All Pending OTPs:
```sql
SELECT email, otp, expires_at, attempts
FROM otp_verifications
WHERE is_used = FALSE
AND expires_at > NOW();
```

### View Used OTPs:
```sql
SELECT email, created_at, expires_at
FROM otp_verifications
WHERE is_used = TRUE
ORDER BY created_at DESC
LIMIT 10;
```

### Clean Expired OTPs:
```sql
DELETE FROM otp_verifications
WHERE expires_at < NOW()
AND is_used = TRUE;
```

---

## 🔄 API Endpoints Summary

| Method | Endpoint | Body | Response |
|--------|----------|------|----------|
| POST | `/auth/send-otp` | `{email}` | `{success, message}` |
| POST | `/auth/verify-otp` | `{email, otp}` | `{success, message}` |
| POST | `/auth/resend-otp` | `{email}` | `{success, message}` |

---

## ✨ Features Summary

✅ **Email-based OTP verification**
✅ **4-digit numeric OTP**
✅ **10-minute expiry**
✅ **Resend functionality**
✅ **Modern UI with 4 input boxes**
✅ **Auto-advance between input fields**
✅ **Account only created after verification**
✅ **is_verified field set to true automatically**
✅ **Email service integration**
✅ **Rate limiting (5 resend attempts)**

---

## 📞 Support

For issues or questions:
1. Check logs in terminal
2. Verify email configuration
3. Check database for OTP records
4. Test with simple email first (if using Gmail, ensure app password is used)

