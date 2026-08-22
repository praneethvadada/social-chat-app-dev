# Backend Issues Fixed - Testing Guide

## Issues Fixed

### 1. ✅ Delete Account - 403 Forbidden Error
**Problem**: Mobile app was getting "Exception: Forbidden" when trying to delete account.

**Root Cause**: 
- Auth-service required JWT authentication for `/account` endpoint
- No JWT filter existed to extract userId from token
- Endpoint expected `X-User-Id` header which wasn't being sent

**Solution**:
- Changed DELETE `/account` endpoint to accept email + password in request body
- Verify credentials before deletion (password match)
- Remove dependency on JWT token parsing
- Returns proper success/error messages

### 2. ⚠️ OTP Not Sending During Registration  
**Problem**: Users not receiving OTP emails during registration.

**Root Cause**:
- Email service is **disabled** in production (`app.mail.enabled=false`)
- No SMTP credentials configured
- OTP was being generated but silently skipped

**Solution**:
- Added console logging to show OTP when email is disabled
- When registration sends OTP, check auth-service logs to see the OTP code
- **Temporary workaround**: Check server logs for OTP
- **Permanent fix**: Configure SMTP email settings (see below)

---

## Testing Delete Account

### From Mobile App:

1. **Navigate to**: Settings → Privacy Settings → Delete Account
2. **Enter your credentials**:
   - Email address
   - Password
3. **Click** "Delete Account" button
4. **Expected behavior**:
   - Success message: "Account deleted successfully"
   - User should be logged out
   - Redirected to login page
   - All user data deleted (posts, chats, followers, etc.)

### API Test (Direct):

```bash
# Test delete account endpoint
curl -X DELETE http://98.92.24.110:8080/auth/account \
  -H "Content-Type: application/json" \
  -d '{
    "email": "your-email@example.com",
    "password": "your-password"
  }'

# Success response:
{"message":"Account deleted successfully"}

# Error responses:
{"error":"Email and password are required"}
{"error":"Invalid password"}
{"error":"User not found"}
```

---

## Testing OTP Registration

### From Mobile App:

1. **Navigate to**: Registration screen
2. **Enter details**:
   - Full name
   - Username
   - Email
   - Password
3. **Click** "Register" or "Send OTP"

### View OTP in Server Logs:

Since email is disabled, the OTP will be printed to console logs:

```powershell
# From your local machine, SSH and check auth-service logs:
ssh -i "C:\Users\gidut\Downloads\social-media-key.pem" ec2-user@98.92.24.110

# View auth-service logs in real-time:
sudo journalctl -u auth-service -f

# Or view last 50 lines:
sudo journalctl -u auth-service -n 50
```

**Look for output like**:
```
============================================================
⚠️  EMAIL SERVICE DISABLED
============================================================
OTP for user@example.com: 1234
To enable email, set: app.mail.enabled=true
And configure SMTP settings in application.properties
============================================================
```

**Use that OTP** in the mobile app to verify and complete registration.

---

## How Delete Account Works (Backend Flow)

When user clicks "Delete Account" button:

1. **Mobile App** → Sends DELETE request with email + password to `/auth/account`
2. **Auth Service**:
   - Validates email and password
   - Calls `authService.deleteAccount(userId)`
3. **Auth Service** → Calls Social Service via Feign Client
4. **Social Service** deletes:
   - All posts by user
   - All follower/following relationships
   - All likes, comments, saves
   - All messages and chats
   - User profile
5. **Auth Service** deletes:
   - User authentication record
   - Redis tokens (logout)
6. **Returns success** → Mobile app logs out user

---

## Enable Email Service (Optional)

To send real emails instead of console logs:

### 1. Get Gmail App Password

1. Go to https://myaccount.google.com/security
2. Enable 2-Step Verification
3. Go to "App passwords"
4. Generate password for "Mail" app
5. Copy the 16-character password

### 2. Update EC2 Environment

```bash
# SSH to EC2
ssh -i "C:\Users\gidut\Downloads\social-media-key.pem" ec2-user@98.92.24.110

# Edit auth-service environment file
sudo nano /opt/auth-service/env.txt

# Add these lines (replace with your values):
MAIL_ENABLED=true
MAIL_HOST=smtp.gmail.com
MAIL_PORT=587
MAIL_USERNAME=your-email@gmail.com
MAIL_PASSWORD=your-16-char-app-password

# Save and restart service
sudo systemctl restart auth-service

# Verify it started
sudo systemctl status auth-service
```

### 3. Verify Email Works

```bash
# Watch logs
sudo journalctl -u auth-service -f

# Try sending OTP from mobile app
# Should see: "OTP email sent to: user@example.com"
```

---

## Mobile App Changes Needed

For delete account to work properly, update your mobile app API service:

### Delete Account Method:

```dart
// In your auth service file (e.g., auth_service.dart)
Future<void> deleteAccount(String email, String password) async {
  try {
    final response = await http.delete(
      Uri.parse('$baseUrl/auth/account'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );

    if (response.statusCode == 200) {
      // Success - clear local data and navigate to login
      await clearUserData(); // Clear SharedPreferences, etc.
      navigateToLogin();
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Failed to delete account');
    }
  } catch (e) {
    throw Exception('Error deleting account: $e');
  }
}
```

### In Delete Account Screen:

```dart
// When delete button pressed:
onPressed: () async {
  try {
    // Show password confirmation dialog
    final password = await _showPasswordDialog();
    if (password == null) return;

    // Show loading
    showLoadingDialog();

    // Get current user email from stored auth data
    final email = await getCurrentUserEmail();

    // Delete account
    await authService.deleteAccount(email, password);

    // Hide loading
    hideLoadingDialog();

    // Show success message
    showSuccessMessage('Account deleted successfully');

    // Clear local data and navigate to login
    await clearAllLocalData();
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);

  } catch (e) {
    hideLoadingDialog();
    showErrorMessage(e.toString());
  }
}
```

---

## Troubleshooting

### Delete Account Returns 403

**Possible causes**:
- Using old auth-service JAR (before fix)
- Check logs: `sudo journalctl -u auth-service -n 50`

**Solution**:
```bash
# Verify latest JAR is deployed
ssh -i "C:\Users\gidut\Downloads\social-media-key.pem" ec2-user@98.92.24.110
ls -lh /opt/auth-service/auth-service.jar
# Should be dated Jan 9, 2026 or later
```

### OTP Not Showing in Logs

**Check**:
1. Is request reaching server?
   ```bash
   sudo journalctl -u auth-service -f
   # Should see: "[OTP] Received send-otp request for email: ..."
   ```

2. If no request, check mobile app network logs
3. Verify API gateway is routing correctly

### Email Service Errors

**Common issues**:
- "Authentication failed": Wrong app password
- "Connection timeout": Wrong SMTP host/port
- Gmail blocking: Need to enable "Less secure app access" or use App Password

---

## Current Deployment Status

✅ **Auth Service**: Running on port 8081 (systemd managed at `/opt/auth-service/`)
✅ **Social Service**: Running on port 8082 (systemd managed at `/opt/social-service/`)
✅ **API Gateway**: Running on port 8080

Both services redeployed with fixes on **Jan 9, 2026**.

---

## Summary of Changes

### Files Modified:

1. **AuthController.java**:
   - Changed `/account` endpoint to accept email + password in body
   - Added password verification before deletion
   - Added logging for debugging

2. **EmailService.java**:
   - Enhanced OTP console logging when email disabled
   - Shows clear message with OTP value

3. **OtpController.java**:
   - Added request/response logging for debugging

### Services Redeployed:
- ✅ auth-service (systemd at `/opt/auth-service/`)
- ✅ social-service (already deployed with S3 fixes)

---

## Next Steps

1. **Test delete account** from mobile app with real user account
2. **Test registration** and check logs for OTP
3. **Optional**: Configure Gmail SMTP to send real emails
4. **Update mobile app** with new delete account implementation
5. **Test end-to-end** flow: Register → Login → Delete Account → Verify data gone

---

**For issues or questions, check:**
- Auth logs: `sudo journalctl -u auth-service -n 100`
- Social logs: `sudo journalctl -u social-service -n 100`
- API Gateway logs: `sudo journalctl -u api-gateway -n 100`
