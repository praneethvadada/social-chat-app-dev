# S3 Upload 401 Error - Complete Fix Guide

## Problem
Mobile app getting **401 Unauthorized** when uploading images because EC2 instance has **NO AWS credentials** to access S3 bucket.

## Root Cause
Your EC2 instance needs AWS credentials to upload files to S3 bucket `social-media-gidut-54513`. Currently:
- ❌ No IAM role attached to EC2
- ❌ No AWS credentials configured
- ❌ Backend can't authenticate to S3

## Solution: Configure AWS Credentials on EC2

### Option 1: Use Your AWS Access Keys (Quick Fix)

#### Step 1: Get Your AWS Access Keys

1. **Login to AWS Console**: https://console.aws.amazon.com/
2. **Go to IAM**: Search for "IAM" in top search bar
3. **Go to Users**: Click "Users" in left sidebar
4. **Click your username**: e.g., "purna"
5. **Security credentials tab**
6. **Create access key**:
   - Click "Create access key"
   - Choose "Command Line Interface (CLI)"
   - Check "I understand" checkbox
   - Click "Create access key"
7. **IMPORTANT**: Copy both:
   - **Access Key ID**: `AKIA...`
   - **Secret Access Key**: `wJalr...` (⚠️ shown only once!)

#### Step 2: Configure on EC2

```bash
# SSH to EC2
ssh -i "C:\Users\gidut\Downloads\social-media-key.pem" ec2-user@98.92.24.110

# Configure AWS CLI
aws configure

# When prompted, enter:
# AWS Access Key ID: [paste your access key]
# AWS Secret Access Key: [paste your secret key]
# Default region name: us-east-1
# Default output format: json

# Test S3 access
aws s3 ls s3://social-media-gidut-54513/
```

#### Step 3: Restart Services

```bash
# Restart social-service to pick up credentials
sudo systemctl restart social-service

# Check logs
sudo journalctl -u social-service -f
```

#### Step 4: Test Upload

```bash
# Create test image
echo "test" > /tmp/test.txt

# Try uploading via API
TOKEN="your-jwt-token-here"

curl -X POST http://localhost:8082/files/upload \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@/tmp/test.txt"

# Should return S3 URL
```

### Option 2: Attach IAM Role to EC2 (Recommended - Requires Admin)

Ask your AWS admin to:

1. **Create IAM Role**:
   - Role name: `EC2-S3-Full-Access`
   - Trust policy: EC2 service
   - Attach policy: `AmazonS3FullAccess`

2. **Attach to EC2 Instance**:
   ```bash
   aws ec2 associate-iam-instance-profile \
       --instance-id i-0139d8ec8d73b924f \
       --iam-instance-profile Name=EC2-S3-Full-Access
   ```

3. **Restart services** (same as Option 1 Step 3)

## Verification

### Test 1: AWS CLI Access
```bash
ssh -i "C:\Users\gidut\Downloads\social-media-key.pem" ec2-user@98.92.24.110

# Should show your identity
aws sts get-caller-identity

# Should list S3 buckets
aws s3 ls

# Should list files in your bucket
aws s3 ls s3://social-media-gidut-54513/
```

### Test 2: Upload via Backend API

```bash
# 1. Login to get JWT token
curl -X POST http://98.92.24.110:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"vamsi3515","password":"YOUR_PASSWORD"}'

# Copy the token from response

# 2. Upload test image
curl -X POST http://98.92.24.110:8080/api/social/files/upload \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -F "file=@C:\path\to\test-image.jpg" \
  -v

# Expected response:
# {
#   "fileUrl": "https://social-media-gidut-54513.s3.us-east-1.amazonaws.com/uuid.jpg"
# }
```

### Test 3: Upload from Mobile App

1. **Logout** from app
2. **Login** again to get fresh token
3. Try creating a post with image
4. Should work without 401 error

## Troubleshooting

### Still Getting 401 After Configuration?

#### Check 1: Credentials Configured Correctly
```bash
ssh -i "C:\Users\gidut\Downloads\social-media-key.pem" ec2-user@98.92.24.110

# Check config
cat ~/.aws/credentials
cat ~/.aws/config

# Should show your credentials
```

#### Check 2: Service Restarted
```bash
# Check if service picked up credentials
sudo systemctl status social-service

# Check logs for S3 errors
sudo journalctl -u social-service -n 100 | grep -i "s3\|aws"
```

#### Check 3: S3 Bucket Permissions
```bash
# Test S3 write access
aws s3 cp /tmp/test.txt s3://social-media-gidut-54513/test.txt

# If this fails, bucket policy issue
```

#### Check 4: Backend Configuration
```bash
# Verify S3 settings in environment
cat /opt/social-service/.env | grep AWS

# Should show:
# AWS_S3_BUCKET=social-media-gidut-54513
# AWS_REGION=us-east-1
```

### Check Backend Logs During Upload

```bash
ssh -i "C:\Users\gidut\Downloads\social-media-key.pem" ec2-user@98.92.24.110

# Watch logs while uploading from mobile
sudo journalctl -u social-service -f

# Look for:
# - "File uploaded successfully to S3"
# - "Could not store file" (error)
# - AWS SDK errors
```

## Mobile App 401 Error - After AWS Fix

If you still get 401 after configuring AWS credentials, the issue is **JWT token**:

### Fix 1: Token Expired
```dart
// In mobile app, force re-login
// User should logout and login again
```

### Fix 2: Token Not Sent
```dart
// In api_service.dart, verify token is sent
static Future<String> uploadImage(String filePath) async {
  final token = await _getToken();
  
  // ADD THIS CHECK
  if (token == null || token.isEmpty) {
    throw Exception('Please login again');
  }
  
  print('DEBUG: Sending token: ${token.substring(0, 20)}...');
  
  final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/social/files/upload'));
  request.headers['Authorization'] = 'Bearer $token';
  // ... rest of code
}
```

## Summary of Changes

### What We Fixed:
1. ✅ Identified EC2 has no AWS credentials
2. ✅ Configured AWS CLI on EC2
3. ⏳ Need to add your Access Key & Secret Key
4. ⏳ Restart social-service after configuration

### What Needs to Be Done:

**Option A - Quick Fix (Do This Now):**
```bash
# 1. SSH to EC2
ssh -i "C:\Users\gidut\Downloads\social-media-key.pem" ec2-user@98.92.24.110

# 2. Run aws configure and enter your credentials
aws configure

# 3. Restart service
sudo systemctl restart social-service

# 4. Test
aws s3 ls s3://social-media-gidut-54513/
```

**Option B - Best Practice (Ask Admin):**
- Have AWS admin create IAM role with S3 permissions
- Attach IAM role to EC2 instance i-0139d8ec8d73b924f
- No credentials in files (more secure)

## Expected Result

After fixing AWS credentials:

### Backend Logs (Success):
```
[S3StorageService] File uploaded successfully to S3: https://social-media-gidut-54513.s3.us-east-1.amazonaws.com/uuid.jpg
```

### Mobile App:
- ✅ Image uploads successfully
- ✅ Returns S3 URL
- ✅ Post created with images
- ✅ Images visible in feed

### Common Issues After Fix:
1. **Still 401**: Token issue (user needs to re-login)
2. **403 Forbidden**: S3 bucket policy issue
3. **500 Error**: Check backend logs for S3 SDK errors

---

**Your Instance Details:**
- Instance ID: `i-0139d8ec8d73b924f`
- S3 Bucket: `social-media-gidut-54513`
- Region: `us-east-1`
- Current Status: ❌ No credentials configured
