# Media Upload - Quick Fix Guide

**Status:** 🔴 Images not displaying in chat (URL construction missing)

---

## 🎯 Main Issue

Frontend receives S3 **keys** instead of full **URLs**:
```
Received:  "550e8400-e29b-41d4-a716-446655440000.jpg"
Expected:  "https://social-media-gidut-54513.s3.us-east-1.amazonaws.com/550e8400-e29b-41d4-a716-446655440000.jpg"
```

Result: `Image.network("550e8400...")` fails to load.

---

## 🔧 Fix #1: MessageService.mapToResponse() - Line 277

**File:** `backend/social-service/src/main/java/com/socialmedia/social/service/MessageService.java`

**Current Code:**
```java
private MessageResponse mapToResponse(Message message) {
    MessageResponse response = new MessageResponse();
    response.setId(message.getId());
    response.setSenderId(message.getSenderId());
    response.setReceiverId(message.getReceiverId());
    response.setContent(message.getContent());
    response.setMediaUrl(message.getMediaUrl());  // ← RETURNS S3 KEY!
    response.setIsRead(message.getIsRead());
    response.setCreatedAt(message.getCreatedAt());
    response.setReadAt(message.getReadAt());
    response.setClientMessageId(message.getClientMessageId());
    return response;
}
```

**Fixed Code:**
```java
private MessageResponse mapToResponse(Message message) {
    MessageResponse response = new MessageResponse();
    response.setId(message.getId());
    response.setSenderId(message.getSenderId());
    response.setReceiverId(message.getReceiverId());
    response.setContent(message.getContent());
    
    // ✅ CONSTRUCT FULL S3 URL
    String mediaUrl = message.getMediaUrl();
    if (mediaUrl != null && !mediaUrl.isEmpty()) {
        // Only construct URL if it's not already a full URL
        if (!mediaUrl.startsWith("http://") && !mediaUrl.startsWith("https://")) {
            mediaUrl = String.format("https://%s.s3.%s.amazonaws.com/%s", 
                bucketName, region, mediaUrl);
        }
    }
    response.setMediaUrl(mediaUrl);
    
    response.setIsRead(message.getIsRead());
    response.setCreatedAt(message.getCreatedAt());
    response.setReadAt(message.getReadAt());
    response.setClientMessageId(message.getClientMessageId());
    return response;
}
```

---

## 🔧 Fix #2: FileController.uploadFile() - Line 26

**File:** `backend/social-service/src/main/java/com/socialmedia/social/controller/FileController.java`

**Current Code:**
```java
@PostMapping("/upload")
public ResponseEntity<Map<String, String>> uploadFile(
        @RequestParam("file") MultipartFile file,
        @RequestAttribute(value = "userId", required = false) Long userId) {
    
    System.out.println("[FILE UPLOAD] Uploading file for userId: " + userId);
    String fileUrl = s3StorageService.storeFile(file);
    
    Map<String, String> response = new HashMap<>();
    response.put("fileUrl", fileUrl);  // ← RETURNS S3 KEY!
    
    return ResponseEntity.ok(response);
}
```

**Fixed Code:**
```java
@RestController
@RequestMapping("/files")
@RequiredArgsConstructor
public class FileController {

    private final S3StorageService s3StorageService;
    
    @Value("${aws.s3.bucket-name}")
    private String bucketName;
    
    @Value("${aws.s3.region}")
    private String region;

    @PostMapping("/upload")
    public ResponseEntity<Map<String, String>> uploadFile(
            @RequestParam("file") MultipartFile file,
            @RequestAttribute(value = "userId", required = false) Long userId) {
        
        System.out.println("[FILE UPLOAD] Uploading file for userId: " + userId);
        String s3Key = s3StorageService.storeFile(file);
        
        // ✅ CONSTRUCT FULL S3 URL
        String fullUrl = String.format("https://%s.s3.%s.amazonaws.com/%s", 
            bucketName, region, s3Key);
        
        Map<String, String> response = new HashMap<>();
        response.put("fileUrl", fullUrl);  // ← NOW RETURNS FULL URL!
        
        return ResponseEntity.ok(response);
    }
}
```

---

## 🧪 Testing After Fix

**Step 1: Upload Image**
```
POST /social/files/upload
Authorization: Bearer {token}
Body: multipart/form-data with file

Response (BEFORE FIX):
{"fileUrl": "550e8400-e29b-41d4-a716-446655440000.jpg"}  ❌

Response (AFTER FIX):
{"fileUrl": "https://social-media-gidut-54513.s3.us-east-1.amazonaws.com/550e8400-e29b-41d4-a716-446655440000.jpg"}  ✅
```

**Step 2: Send Message with Image**
```
WebSocket /app/chat.send:
{
  "receiverId": 2,
  "content": "photo",
  "mediaUrl": "https://social-media-gidut-54513.s3.us-east-1.amazonaws.com/550e8400-e29b-41d4-a716-446655440000.jpg",
  "clientMessageId": "opt_msg_1234567890"
}
```

**Step 3: Message Received**
```
MessageResponse:
{
  "id": 12345,
  "senderId": 1,
  "content": "photo",
  "mediaUrl": "https://social-media-gidut-54513.s3.us-east-1.amazonaws.com/550e8400-e29b-41d4-a716-446655440000.jpg",
  "createdAt": "2026-01-09T10:30:45.000Z",
  ...
}
```

**Step 4: UI Displays Image**
```dart
// This will NOW work because mediaUrl is a full URL!
Image.network(message.mediaUrl)  ✅
```

---

## 📋 Implementation Steps

1. **Backup MessageService.java:**
   ```
   cp social-service/src/main/java/com/socialmedia/social/service/MessageService.java \
      social-service/src/main/java/com/socialmedia/social/service/MessageService.java.bak
   ```

2. **Edit both files:**
   - Add @Value annotations for bucketName and region (if not already present)
   - Update mapToResponse() method
   - Update FileController.uploadFile() method

3. **Rebuild backend:**
   ```bash
   cd backend/social-service
   mvn clean install
   # or
   gradle clean build
   ```

4. **Restart backend service**

5. **Test from Flutter app:**
   - Select image in chat
   - Upload
   - Send message
   - Verify image displays

---

## ✅ Validation

After fix, verify:
- ✅ Image uploads complete
- ✅ Image appears in chat
- ✅ Image loads from S3
- ✅ Video works the same way
- ✅ Profile pictures still work
- ✅ Post images still work

---

## 🐛 Additional Issues Found

### Issue: 401 on Upload (JWT Token Expired)

**Frontend Error:**
```
Failed to upload media: Exception: Failed to upload file (code 401)
```

**Cause:** JWT token expired  
**Solution:** Implement token refresh in ApiService before upload

**Quick Fix in api_service.dart:**
```dart
static Future<String> uploadImage(String filePath) async {
  var token = await getToken();
  if (token == null) throw Exception('Not authenticated');
  
  // NEW: Refresh token if needed
  // TODO: Implement token refresh logic
  
  final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/social/files/upload'));
  request.headers['Authorization'] = 'Bearer $token';
  // ...
}
```

---

## 📊 Impact Summary

| Component | Issue | Fix | Impact |
|-----------|-------|-----|--------|
| MessageService | S3 key returned | Construct full URL | Images now display |
| FileController | S3 key returned | Construct full URL | Upload response valid |
| Frontend | Receives S3 key | No change needed | Will work after backend fix |

**Time to implement:** ~10 minutes  
**Testing time:** ~5 minutes

---

**Date:** January 9, 2026  
**Priority:** 🔴 CRITICAL (blocks image display in chat)
