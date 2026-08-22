# OTP Implementation Complete

## What Was Added

### 1. New Classes Created

#### DTOs (Data Transfer Objects)
- **OTPRequest.java** - Request to send OTP to an email
- **OTPVerifyRequest.java** - Request to verify OTP code

#### Entity
- **OTPVerification.java** - Database entity for storing OTP codes
  - 4-digit OTP codes
  - 10-minute expiration
  - Maximum 5 verification attempts
  - Purpose tracking (REGISTRATION, PASSWORD_RESET, EMAIL_VERIFICATION)

#### Repository
- **OTPVerificationRepository.java** - JPA repository for OTP operations
  - Find latest unverified OTP by email
  - Delete expired OTPs (scheduled cleanup)
  - Delete unverified OTPs when generating new ones

#### Service
- **OTPService.java** - Core OTP business logic
  - Generate secure 4-digit random OTP
  - Send OTP via email
  - Verify OTP with attempt tracking
  - Automatic cleanup of expired OTPs every hour

#### Controller
- **OTPController.java** - REST API endpoints
  - `POST /otp/send` - Send OTP to email
  - `POST /otp/verify` - Verify OTP code

### 2. Updated Files

#### EmailService.java
- Added **sendOTPEmail()** method
- Sends formatted OTP email with expiration time

#### SecurityConfig.java
- Added `/otp/send` and `/otp/verify` to permitted endpoints (no authentication required)
- Added `/password-reset/**` to permitted endpoints

## API Endpoints

### Send OTP
```bash
POST http://98.92.24.110:8081/otp/send
Content-Type: application/json

{
  "email": "user@example.com"
}
```

**Response (Success):**
```json
{
  "message": "OTP sent successfully to user@example.com",
  "expiresIn": "10 minutes"
}
```

### Verify OTP
```bash
POST http://98.92.24.110:8081/otp/verify
Content-Type: application/json

{
  "email": "user@example.com",
  "otp": "1234"
}
```

**Response (Success):**
```json
{
  "verified": true,
  "message": "OTP verified successfully"
}
```

**Response (Failure):**
```json
{
  "verified": false,
  "message": "Invalid or expired OTP"
}
```

## How It Works

1. **User requests OTP**:
   - App sends POST to `/otp/send` with email
   - Backend generates 4-digit random OTP (0000-9999)
   - OTP saved to `otp_verifications` table with 10-minute expiration
   - Email sent via Gmail SMTP with OTP code

2. **User enters OTP**:
   - App sends POST to `/otp/verify` with email and OTP
   - Backend checks if OTP exists, not expired, and attempts < 5
   - If valid, marks OTP as verified
   - Returns verification status

3. **Security Features**:
   - 10-minute expiration time
   - Maximum 5 verification attempts per OTP
   - Old unverified OTPs deleted when generating new one
   - Automatic hourly cleanup of expired OTPs
   - Secure random number generation

## Database Table

The `otp_verifications` table already exists in your RDS database (created from schema v2.0.2):

```sql
CREATE TABLE otp_verifications (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    email VARCHAR(255) NOT NULL,
    otp_code VARCHAR(4) NOT NULL,
    created_at TIMESTAMP NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    verified BOOLEAN DEFAULT FALSE,
    attempt_count INT DEFAULT 0,
    purpose VARCHAR(50) NOT NULL,
    INDEX idx_email_verified (email, verified),
    INDEX idx_expires_at (expires_at)
);
```

## Deployment

### Option 1: Manual Deployment (If you have SSH key)

1. **Put your EC2 private key in the social-media-key.pem file**

2. **Run the deployment script:**
   ```bash
   cd backend
   deploy-auth-service.bat
   ```

### Option 2: Manual Upload (Without SSH key)

1. **Upload JAR via AWS Console:**
   - Go to EC2 → Instance Connect
   - Upload `backend/auth-service/target/auth-service-1.0.0.jar`

2. **Deploy via Session Manager:**
   ```bash
   # Stop service
   sudo systemctl stop auth-service
   
   # Backup old JAR
   sudo cp /opt/auth-service/auth-service.jar /opt/auth-service/auth-service.jar.backup
   
   # Copy new JAR
   sudo mv /tmp/auth-service-1.0.0.jar /opt/auth-service/auth-service.jar
   sudo chown ec2-user:ec2-user /opt/auth-service/auth-service.jar
   
   # Start service
   sudo systemctl start auth-service
   
   # Check status
   sudo systemctl status auth-service
   ```

## Testing OTP

### Test 1: Send OTP
```bash
curl -X POST http://98.92.24.110:8081/otp/send \
  -H "Content-Type: application/json" \
  -d '{"email":"guideup3515@gmail.com"}'
```

Expected: Email arrives with 4-digit code

### Test 2: Verify OTP
```bash
curl -X POST http://98.92.24.110:8081/otp/verify \
  -H "Content-Type: application/json" \
  -d '{"email":"guideup3515@gmail.com","otp":"1234"}'
```

Expected: `{"verified":true}` or `{"verified":false}`

## Mobile App Integration

Update your mobile app to use these endpoints:

```dart
// Send OTP
Future<void> sendOTP(String email) async {
  final response = await http.post(
    Uri.parse('http://98.92.24.110:8080/api/auth/otp/send'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'email': email}),
  );
  // Handle response
}

// Verify OTP
Future<bool> verifyOTP(String email, String otp) async {
  final response = await http.post(
    Uri.parse('http://98.92.24.110:8080/api/auth/otp/verify'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'email': email, 'otp': otp}),
  );
  final data = jsonDecode(response.body);
  return data['verified'] == true;
}
```

## Configuration

OTP uses your existing email configuration in `/opt/auth-service/.env`:

```env
APP_MAIL_ENABLED=true
SPRING_MAIL_HOST=smtp.gmail.com
SPRING_MAIL_PORT=587
SPRING_MAIL_USERNAME=guideup3515@gmail.com
SPRING_MAIL_PASSWORD=awfpwbrcnrdqwbpv
```

## Troubleshooting

### OTP email not received
- Check auth-service logs: `sudo journalctl -u auth-service -f`
- Verify email config loaded: `sudo cat /opt/auth-service/.env | grep MAIL`
- Test SMTP: `telnet smtp.gmail.com 587`

### 403 Forbidden error
- Verify SecurityConfig updated with `/otp/**` in permitAll
- Rebuild and redeploy auth-service

### OTP always invalid
- Check system time is correct: `date`
- Verify database connection working
- Check OTP not expired (10 minutes)

## Next Steps

1. **Deploy updated auth-service** to EC2
2. **Test OTP sending** with your email
3. **Integrate in mobile app** for user registration
4. **Test end-to-end** registration flow with OTP

## Files Changed

- ✅ auth-service/src/main/java/com/socialmedia/auth/dto/OTPRequest.java (NEW)
- ✅ auth-service/src/main/java/com/socialmedia/auth/dto/OTPVerifyRequest.java (NEW)
- ✅ auth-service/src/main/java/com/socialmedia/auth/entity/OTPVerification.java (NEW)
- ✅ auth-service/src/main/java/com/socialmedia/auth/repository/OTPVerificationRepository.java (NEW)
- ✅ auth-service/src/main/java/com/socialmedia/auth/service/OTPService.java (NEW)
- ✅ auth-service/src/main/java/com/socialmedia/auth/controller/OTPController.java (NEW)
- ✅ auth-service/src/main/java/com/socialmedia/auth/service/EmailService.java (UPDATED)
- ✅ auth-service/src/main/java/com/socialmedia/auth/config/SecurityConfig.java (UPDATED)
- ✅ backend/deploy-auth-service.bat (NEW)
