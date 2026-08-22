# Media Upload 401 Error - Troubleshooting Guide

## Issue Summary
Mobile app getting **401 Unauthorized** error when trying to upload images/media.

Error messages seen:
- "Failed to upload media: Exception: Failed to upload file (code 401)"
- "Failed to upload image: Exception: Failed to upload file (code 401)"

## Root Cause Analysis

### 1. Check JWT Token in Mobile App

The 401 error indicates **authentication failure**. The FileController requires a valid JWT token.

```dart
// In api_service.dart line 241
final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/social/files/upload'));
request.headers['Authorization'] = 'Bearer $token';  // ← Token must be valid!
```

### Quick Test: Verify Token
Add this debug code to check if token exists:

```dart
// Before upload in api_service.dart
static Future<String> uploadImage(String filePath) async {
  final token = await _getToken();
  print('DEBUG: Token exists? ${token != null}');
  print('DEBUG: Token value: ${token?.substring(0, 20)}...');  // First 20 chars
  
  if (token == null) {
    throw Exception('No authentication token - please login again');
  }
  
  // ... rest of code
}
```

## Solutions

### Solution 1: Re-Login to Get Fresh Token

The JWT token might have expired. Ask user to:
1. **Logout** from the app
2. **Login again**
3. Try uploading again

### Solution 2: Check Token Storage

```dart
// Add to api_service.dart _getToken() method
static Future<String?> _getToken() async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('auth_token');
  
  print('DEBUG: Retrieved token from storage: ${token != null}');
  
  if (token == null) {
    print('ERROR: No token in SharedPreferences!');
    // Force user to login
  }
  
  return token;
}
```

### Solution 3: Fix Mobile App Upload Method

Update `social-media-mobile/lib/src/services/api_service.dart`:

```dart
static Future<String> uploadImage(String filePath) async {
  final token = await _getToken();
  
  if (token == null || token.isEmpty) {
    throw Exception('Authentication required. Please login again.');
  }

  print('\n========== UPLOADING FILE ==========');
  print('File path: $filePath');
  print('Token present: YES');

  final request = http.MultipartRequest(
    'POST', 
    Uri.parse('$baseUrl/social/files/upload')
  );
  
  request.headers['Authorization'] = 'Bearer $token';
  request.headers['Accept'] = 'application/json';
  
  request.files.add(await http.MultipartFile.fromPath('file', filePath));

  try {
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    print('Upload Status: ${response.statusCode}');
    print('Upload Response: ${response.body}');

    if (response.statusCode == 401) {
      print('ERROR: Token invalid or expired!');
      throw Exception('Session expired. Please login again.');
    }

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final fileUrl = data['fileUrl'] as String;
      return fileUrl;  // Return S3 URL directly
    }

    throw Exception('Upload failed: ${response.statusCode}');
    
  } catch (e) {
    print('ERROR in uploadImage: $e');
    rethrow;
  }
}
```

### Solution 4: Test API Directly (Postman/Curl)

```bash
# 1. Login first
curl -X POST http://98.92.24.110:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"vamsi3515","password":"yourpassword"}' \
  -v

# Copy the token from response

# 2. Test file upload
curl -X POST http://98.92.24.110:8080/api/social/files/upload \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -F "file=@C:\path\to\test-image.jpg" \
  -v
```

If this works, the backend is fine - issue is in mobile app.

### Solution 5: Check API Gateway Configuration

The request goes through API Gateway first. Check if API Gateway is stripping the Authorization header.

File: `backend/api-gateway/src/main/resources/application.yml`

```yaml
spring:
  cloud:
    gateway:
      routes:
        - id: social-service
          uri: http://localhost:8082
          predicates:
            - Path=/api/social/**
          filters:
            - StripPrefix=2
            # IMPORTANT: Don't remove Authorization header!
```

### Solution 6: Add Error Handling in Create Post Screen

Update `create_post_screen.dart` to show more detailed errors:

```dart
for (final m in _selected) {
  try {
    final url = await MediaService.uploadMedia(m, (p) {
      setState(() {
        _progress = (completed + p) / total;
      });
    });
    uploadedUrls.add(url);
    completed++;
  } catch (e) {
    // Better error message
    String errorMsg = 'Failed to upload media';
    
    if (e.toString().contains('401')) {
      errorMsg = 'Session expired. Please login again';
      // Navigate to login screen
    } else if (e.toString().contains('403')) {
      errorMsg = 'Permission denied';
    } else if (e.toString().contains('500')) {
      errorMsg = 'Server error. Please try again';
    }
    
    Fluttertoast.showToast(msg: errorMsg);
    print('Upload error details: $e');
    
    setState(() {
      _uploading = false;
      _progress = 0.0;
    });
    return;
  }
}
```

## Verification Steps

### Step 1: Enable Debug Logging in Mobile App

Add these print statements to track the issue:

```dart
// In api_service.dart uploadImage()
print('1. Getting token...');
final token = await _getToken();
print('2. Token retrieved: ${token != null}');

print('3. Creating request...');
final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/social/files/upload'));

print('4. Adding headers...');
request.headers['Authorization'] = 'Bearer $token';

print('5. Adding file...');
request.files.add(await http.MultipartFile.fromPath('file', filePath));

print('6. Sending request...');
final streamedResponse = await request.send();

print('7. Getting response...');
final response = await http.Response.fromStream(streamedResponse);

print('8. Status code: ${response.statusCode}');
print('9. Response body: ${response.body}');
```

### Step 2: Check Backend Logs During Upload Attempt

```bash
ssh -i "C:\Users\gidut\Downloads\social-media-key.pem" ec2-user@98.92.24.110
sudo journalctl -u social-service -f | grep -i "upload\|JWT\|401"
```

Watch logs while attempting upload from mobile app.

### Step 3: Test with Postman

1. Open Postman
2. Use the endpoint from [POSTMAN_API_COLLECTION.md](../POSTMAN_API_COLLECTION.md)
3. Test: `POST http://98.92.24.110:8080/api/social/files/upload`
4. Add Header: `Authorization: Bearer {your_token}`
5. Body: form-data, key="file", select file
6. Send request

If Postman works but mobile doesn't → issue is in mobile app token handling

## Common Causes

| Issue | Symptom | Fix |
|-------|---------|-----|
| Token Expired | 401 on all requests | Re-login |
| Token Not Saved | 401 only on upload | Fix SharedPreferences storage |
| Token Not Sent | 401 consistently | Check Authorization header |
| Wrong URL | Can't connect | Verify baseUrl in api_service.dart |
| API Gateway Issue | 401 but token valid | Check gateway routes |
| CORS Issue | Preflight errors | Check CORS config |

## Quick Fixes to Try (In Order)

1. **Force Re-Login**
   ```dart
   // In your login screen
   await prefs.setString('auth_token', response.token);
   await prefs.setString('refresh_token', response.refreshToken);
   print('Token saved: ${response.token.substring(0, 20)}...');
   ```

2. **Check Token Before Upload**
   ```dart
   // Before showing create post screen
   final token = await ApiService.getToken();
   if (token == null) {
     // Show "Please login first" message
     Navigator.pushReplacementNamed(context, '/login');
     return;
   }
   ```

3. **Add Token Refresh Logic**
   ```dart
   // If 401, try to refresh token
   if (response.statusCode == 401) {
     await refreshToken();
     // Retry upload
   }
   ```

## Expected Behavior

**Successful Upload:**
```
1. Mobile app sends POST /api/social/files/upload
2. API Gateway forwards to social-service
3. JWT filter validates token
4. File uploaded to S3
5. Returns: {"fileUrl": "https://social-media-gidut-54513.s3.us-east-1.amazonaws.com/uuid.jpg"}
```

**Failed Upload (401):**
```
1. Mobile app sends POST /api/social/files/upload
2. JWT filter checks token
3. Token invalid/expired/missing
4. Returns: 401 Unauthorized
5. Mobile app shows "Failed to upload file (code 401)"
```

## Test Command

Run this from your terminal to test if backend is working:

```bash
# Get token
TOKEN=$(curl -s -X POST http://98.92.24.110:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"vamsi3515","password":"YOUR_PASSWORD"}' \
  | jq -r '.token')

echo "Token: $TOKEN"

# Upload test file
curl -X POST http://98.92.24.110:8080/api/social/files/upload \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@test-image.jpg"
```

If this works → Backend is fine, fix mobile app
If this fails → Check backend logs for errors

## Next Steps

1. **Add debug logging** to mobile app as shown above
2. **Try uploading** and check Flutter console output
3. **Share the logs** showing:
   - Token status
   - Request headers
   - Response code
   - Response body
4. Based on logs, we can identify exact issue

---

**Most Likely Cause**: Token expired or not being sent correctly from mobile app.

**Quick Fix**: Ask user to logout and login again, then try uploading.
