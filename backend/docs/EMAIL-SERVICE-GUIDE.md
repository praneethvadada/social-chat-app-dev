# Email Service - Complete Guide

## 🎯 Overview

Complete email service for sending notifications and password reset emails using Spring Boot Mail with SMTP.

## 📧 Email Types

### 1. **Password Reset Email**
Sent when user requests password reset

### 2. **Welcome Email**
Sent when new user registers

### 3. **Password Changed Email**
Sent after successful password reset

### 4. **New Follower Notification**
Sent when someone follows you

### 5. **Post Liked Notification**
Sent when someone likes your post

### 6. **New Comment Notification**
Sent when someone comments on your post

---

## ⚙️ Configuration

### Email Settings (application.properties)

```properties
# Email Configuration (Gmail)
spring.mail.host=smtp.gmail.com
spring.mail.port=587
spring.mail.username=your-email@gmail.com
spring.mail.password=your-app-password
spring.mail.properties.mail.smtp.auth=true
spring.mail.properties.mail.smtp.starttls.enable=true
spring.mail.properties.mail.smtp.starttls.required=true

# Frontend URL for email links
app.frontend.url=http://localhost:3000
```

### Gmail Setup:
1. Enable 2-Factor Authentication in Google Account
2. Generate App Password:
   - Go to https://myaccount.google.com/apppasswords
   - Select "Mail" and your device
   - Copy the 16-character password
3. Use this password in `spring.mail.password`

### Other SMTP Providers:

**Outlook/Hotmail:**
```properties
spring.mail.host=smtp-mail.outlook.com
spring.mail.port=587
```

**Yahoo:**
```properties
spring.mail.host=smtp.mail.yahoo.com
spring.mail.port=587
```

**SendGrid:**
```properties
spring.mail.host=smtp.sendgrid.net
spring.mail.port=587
spring.mail.username=apikey
spring.mail.password=your-sendgrid-api-key
```

---

## 🔌 API Endpoints

### Base URL
```
http://localhost:8080/api/auth
```

---

### 1. Request Password Reset

**Endpoint:** `POST /password-reset/request`

**Request:**
```bash
curl -X POST http://localhost:8080/api/auth/password-reset/request \
  -H "Content-Type: application/json" \
  -d '{
    "email": "user@example.com"
  }'
```

**Response:** `200 OK`
```json
{
  "message": "If the email exists in our system, a password reset link has been sent"
}
```

**Email Sent:**
```
Subject: Password Reset Request - Social Media App

Hi johndoe,

We received a request to reset your password for your Social Media account.

Click the link below to reset your password:
http://localhost:3000/reset-password?token=abc-123-xyz

This link will expire in 1 hour.

If you didn't request a password reset, please ignore this email.

Best regards,
Social Media Team
```

---

### 2. Confirm Password Reset

**Endpoint:** `POST /password-reset/confirm`

**Request:**
```bash
curl -X POST http://localhost:8080/api/auth/password-reset/confirm \
  -H "Content-Type: application/json" \
  -d '{
    "token": "abc-123-xyz",
    "newPassword": "newpassword123"
  }'
```

**Response:** `200 OK`
```json
{
  "message": "Password has been reset successfully"
}
```

**Email Sent:**
```
Subject: Password Changed - Social Media App

Hi johndoe,

Your password has been successfully changed.

If you made this change, you can safely ignore this email.

If you didn't change your password, please contact support immediately.

Best regards,
Social Media Team
```

---

## 📊 Database Schema

### Password Reset Tokens Table
```sql
CREATE TABLE password_reset_tokens (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    token VARCHAR(255) NOT NULL UNIQUE,
    user_id BIGINT NOT NULL,
    expiry_date TIMESTAMP NOT NULL,
    used BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP NOT NULL,
    
    FOREIGN KEY (user_id) REFERENCES users(id)
);
```

---

## 🔄 Password Reset Flow

### 1. User Requests Reset
```
POST /password-reset/request
Body: { "email": "user@example.com" }
```

### 2. System Actions:
- Validates email exists
- Generates unique token (UUID)
- Stores token in database with 1-hour expiry
- Sends email with reset link

### 3. User Receives Email
- Clicks reset link
- Redirected to frontend: `/reset-password?token=xyz`

### 4. User Submits New Password
```
POST /password-reset/confirm
Body: { 
  "token": "xyz",
  "newPassword": "newpassword123"
}
```

### 5. System Actions:
- Validates token (exists, not expired, not used)
- Updates password
- Marks token as used
- Sends confirmation email

---

## 🎨 Email Templates

### Welcome Email (Sent on Registration)
```
Subject: Welcome to Social Media App!

Hi johndoe,

Welcome to Social Media App! 🎉

Your account has been successfully created. You can now:
• Create and share posts
• Follow other users
• Like, comment, and interact with content
• Customize your profile

Get started by visiting: http://localhost:3000

Happy posting!
Social Media Team
```

### New Follower Notification
```
Subject: New Follower - Social Media App

Hi johndoe,

janedoe started following you!

Check out their profile: http://localhost:3000/profile/janedoe

Best regards,
Social Media Team
```

### Post Liked Notification
```
Subject: Someone Liked Your Post - Social Media App

Hi johndoe,

janedoe liked your post!

Check your notifications: http://localhost:3000/notifications

Best regards,
Social Media Team
```

### New Comment Notification
```
Subject: New Comment on Your Post - Social Media App

Hi johndoe,

janedoe commented on your post:
"Great post! Really enjoyed reading this..."

View the full comment: http://localhost:3000/notifications

Best regards,
Social Media Team
```

---

## 💻 Service Methods

### EmailService.java

```java
// Password reset email
public void sendPasswordResetEmail(String toEmail, String username, String resetToken)

// Welcome email (called after registration)
public void sendWelcomeEmail(String toEmail, String username)

// Password changed notification
public void sendPasswordChangedEmail(String toEmail, String username)

// New follower notification
public void sendNewFollowerNotification(String toEmail, String username, String followerUsername)

// Post liked notification
public void sendPostLikedNotification(String toEmail, String username, String likerUsername)

// New comment notification
public void sendNewCommentNotification(String toEmail, String username, String commenterUsername, String commentText)
```

All methods are **@Async** - they run in background threads and don't block the main request.

---

## 🎯 Integration Examples

### Registration Flow (Already Integrated)
```java
// In AuthService.register()
User savedUser = userRepository.save(user);

// Send welcome email automatically
emailService.sendWelcomeEmail(savedUser.getEmail(), savedUser.getUsername());
```

### Password Reset Flow (Already Integrated)
```java
// In AuthService.initiatePasswordReset()
emailService.sendPasswordResetEmail(user.getEmail(), user.getUsername(), token);

// In AuthService.resetPassword()
emailService.sendPasswordChangedEmail(user.getEmail(), user.getUsername());
```

### Future Integration (Notifications)

**When someone follows you:**
```java
// In FollowerService.followUser()
emailService.sendNewFollowerNotification(
    followedUser.getEmail(),
    followedUser.getUsername(),
    follower.getUsername()
);
```

**When someone likes your post:**
```java
// In LikeService.likePost()
emailService.sendPostLikedNotification(
    postAuthor.getEmail(),
    postAuthor.getUsername(),
    liker.getUsername()
);
```

**When someone comments on your post:**
```java
// In CommentService.createComment()
emailService.sendNewCommentNotification(
    postAuthor.getEmail(),
    postAuthor.getUsername(),
    commenter.getUsername(),
    comment.getContent()
);
```

---

## 🔐 Security Features

### Token Security:
- **UUID tokens** - Cryptographically random
- **1-hour expiry** - Short-lived for security
- **One-time use** - Token marked as used after reset
- **Automatic cleanup** - Expired tokens can be deleted

### Email Security:
- **No password in email** - Only send reset link
- **Generic success message** - Don't reveal if email exists
- **HTTPS links** - Use secure frontend URLs in production
- **Rate limiting** - Prevent spam (implement as needed)

---

## 🧪 Testing

### Test Password Reset Flow:

1. **Request Reset:**
```bash
curl -X POST http://localhost:8080/api/auth/password-reset/request \
  -H "Content-Type: application/json" \
  -d '{"email": "test@example.com"}'
```

2. **Check Email Inbox**
   - Open email
   - Copy token from URL

3. **Reset Password:**
```bash
curl -X POST http://localhost:8080/api/auth/password-reset/confirm \
  -H "Content-Type: application/json" \
  -d '{
    "token": "YOUR_TOKEN_HERE",
    "newPassword": "newpassword123"
  }'
```

4. **Verify:**
```bash
# Try logging in with new password
curl -X POST http://localhost:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "newpassword123"
  }'
```

---

## ⚠️ Troubleshooting

### Emails Not Sending:

1. **Check SMTP credentials**
   - Verify username/password
   - For Gmail, use App Password, not regular password

2. **Check firewall**
   - Ensure port 587 is open

3. **Check logs**
   ```
   logging.level.com.socialmedia.auth.service.EmailService=DEBUG
   ```

4. **Test SMTP connection**
   ```java
   JavaMailSender mailSender;
   mailSender.testConnection(); // Should return true
   ```

### Common Errors:

**Authentication Failed:**
- Use App Password for Gmail
- Enable "Less Secure Apps" (if not using 2FA)

**Connection Timeout:**
- Check SMTP host and port
- Verify firewall settings

**Invalid Token:**
- Token expired (1 hour limit)
- Token already used
- Token doesn't exist in database

---

## 🎉 Summary

**Email Service - Fully Implemented!**

✅ **Password reset flow** with email tokens  
✅ **Welcome emails** on registration  
✅ **Password change notifications**  
✅ **6 email templates** for various notifications  
✅ **Async email sending** - non-blocking  
✅ **Secure token generation** with expiry  
✅ **Full Swagger documentation**  
✅ **Gmail/SMTP configuration**  

**Configured But Not Integrated:**
- New follower notifications
- Post liked notifications
- Comment notifications

**Next Steps:**
- Configure SMTP credentials in application.properties
- Test password reset flow
- Integrate notification emails with social features
- Consider HTML email templates for better formatting
- Add email preferences (user can opt-out)

**Test in Swagger:** http://localhost:8081/swagger-ui.html
