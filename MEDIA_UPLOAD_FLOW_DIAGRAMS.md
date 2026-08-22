# Media Upload Architecture & Flow Diagrams

---

## 📐 System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         FLUTTER APP                             │
│                                                                 │
│  ┌────────────────────────────────────────────────────────┐   │
│  │ ChatScreen                                             │   │
│  │ ├─ _pickAttachment()                                  │   │
│  │ │  └─ ImagePicker.pickImage() / pickVideo()          │   │
│  │ └─ _sendMediaMessage(mediaUrl)                        │   │
│  └────────────────────────────────────────────────────────┘   │
│              ↓                                    ↓             │
│  ┌────────────────────────────┐  ┌──────────────────────────┐ │
│  │ ApiService.uploadMedia()   │  │ ChatWebSocketService     │ │
│  │ ├─ POST /files/upload      │  │ ├─ sendMessage()        │ │
│  │ │  (multipart)             │  │ │  └─ /app/chat.send   │ │
│  │ └─ Returns: S3_KEY ❌       │  │ └─ WebSocket payload   │ │
│  └────────────────────────────┘  └──────────────────────────┘ │
│              ↓                              ↓                   │
└──────────────┼──────────────────────────────┼───────────────────┘
               │ HTTP(S)                      │ WebSocket(S)
               ↓                              ↓
        ┌──────────────────────────────────────────┐
        │        SPRING BOOT BACKEND               │
        │                                          │
        │  ┌──────────────────────────────────┐   │
        │  │ FileController.uploadFile()      │   │
        │  │ ├─ @PostMapping("/files/upload") │   │
        │  │ ├─ S3StorageService.storeFile()  │   │
        │  │ └─ Returns: S3_KEY ❌             │   │
        │  └──────────────────────────────────┘   │
        │              ↓                          │
        │  ┌──────────────────────────────────┐   │
        │  │ S3StorageService                 │   │
        │  │ ├─ UUID generation               │   │
        │  │ ├─ S3 upload                     │   │
        │  │ └─ Return S3 key                 │   │
        │  └──────────────────────────────────┘   │
        │              ↓                          │
        │  ┌──────────────────────────────────┐   │
        │  │ MessageController                │   │
        │  │ ├─ @MessageMapping("/chat.send") │   │
        │  │ └─ MessageService.sendMessage()  │   │
        │  └──────────────────────────────────┘   │
        │              ↓                          │
        │  ┌──────────────────────────────────┐   │
        │  │ MessageService                   │   │
        │  │ ├─ Save to DB                    │   │
        │  │ └─ mapToResponse()               │   │
        │  │    └─ Returns S3_KEY ❌           │   │
        │  └──────────────────────────────────┘   │
        │              ↓                          │
        └──────────────┼──────────────────────────┘
                       │ WebSocket
                       ↓
        ┌──────────────────────────┐
        │ MySQL Database           │
        │ ├─ messages table        │
        │ │  ├─ id                 │
        │ │  ├─ sender_id          │
        │ │  ├─ receiver_id        │
        │ │  ├─ content            │
        │ │  ├─ media_url: S3_KEY  │
        │ │  └─ created_at         │
        │ └─ ✅ Schema correct      │
        └──────────────────────────┘
```

---

## 🔄 Upload Flow (Current - BROKEN)

```
User selects image
        ↓
    [ChatScreen]
    _pickAttachment()
        ↓
    ImagePicker.pickImage()
    ✅ Works fine
        ↓
    Image saved to temp
    /tmp/chat_img_123.jpg
        ↓
    ApiService.uploadMedia(filePath)
        ↓
    [HTTP POST] /social/files/upload
    Headers: Authorization: Bearer {token}
    Body: multipart/form-data {file: binary}
        ↓
    [FileController.uploadFile()]
        ↓
    S3StorageService.storeFile()
    ├─ Generate UUID: 550e8400-...
    └─ Upload to S3
        ↓
    S3 confirms upload
    Returns: 550e8400-e29b-41d4-a716-446655440000.jpg
        ↓
    [Response to Frontend]
    ❌ {"fileUrl": "550e8400-e29b-41d4-a716-446655440000.jpg"}
    
    PROBLEM: This is just an S3 KEY, not a valid URL!
    Image.network("550e8400-...") will FAIL
        ↓
    Frontend shows broken image icon
```

---

## 🔄 Send Message Flow (Current - BROKEN)

```
ChatScreen._sendMediaMessage(S3_KEY, label='photo')
        ↓
    S3_KEY = "550e8400-e29b-41d4-a716-446655440000.jpg"
        ↓
    ChatWebSocketService.sendMessage(
        recipientId=2,
        content='photo',
        mediaUrl=S3_KEY  ← WRONG: S3 key not URL!
    )
        ↓
    [WebSocket Frame]
    Destination: /app/chat.send
    Payload: {
        "receiverId": 2,
        "content": "photo",
        "mediaUrl": "550e8400-e29b-41d4-a716-446655440000.jpg",  ❌
        "clientMessageId": "opt_msg_1234567890"
    }
        ↓
    [MessageController.sendMessageViaWebSocket()]
    ├─ Extract userId from session: 1
    ├─ Validate receiverId: 2
    └─ Call MessageService.sendMessage()
        ↓
    [MessageService.sendMessage()]
    ├─ Create Message entity
    ├─ Set mediaUrl = "550e8400-e29b-41d4-a716-446655440000.jpg"  ❌
    ├─ Save to database: INSERT ... media_url = S3_KEY
    ├─ Create MessageResponse
    ├─ mapToResponse() sets mediaUrl = S3_KEY  ❌ BUG!
    └─ Return response
        ↓
    [Response to Sender & Receiver]
    {
        "id": 12345,
        "senderId": 1,
        "receiverId": 2,
        "content": "photo",
        "mediaUrl": "550e8400-e29b-41d4-a716-446655440000.jpg",  ❌
        "createdAt": "2026-01-09T10:30:45.000Z"
    }
        ↓
    [Frontend Message.fromJson()]
    ├─ Parse mediaUrl: "550e8400-e29b-41d4-a716-446655440000.jpg"
    └─ Store in Message object
        ↓
    [UI Render]
    _buildMediaBubble(message)
    └─ Image.network(message.mediaUrl)
        └─ Image.network("550e8400-...")
            └─ ❌ FAILS - Not a valid URL!
        ↓
    User sees BROKEN IMAGE ICON 😞
```

---

## ✅ Fixed Upload Flow

```
User selects image
        ↓
    [ChatScreen]
    _pickAttachment()
        ↓
    ImagePicker.pickImage()
    ✅ Works fine
        ↓
    Image saved to temp
    /tmp/chat_img_123.jpg
        ↓
    ApiService.uploadMedia(filePath)
        ↓
    [HTTP POST] /social/files/upload
    Headers: Authorization: Bearer {token}
    Body: multipart/form-data {file: binary}
        ↓
    [FileController.uploadFile()]
    String s3Key = s3StorageService.storeFile(file)
    // s3Key = "550e8400-e29b-41d4-a716-446655440000.jpg"
    
    ✅ NEW: CONSTRUCT FULL URL
    String fullUrl = String.format(
        "https://%s.s3.%s.amazonaws.com/%s",
        bucketName, region, s3Key
    );
    // fullUrl = "https://social-media-gidut-54513.s3.us-east-1.amazonaws.com/550e8400-..."
    
    response.put("fileUrl", fullUrl)  ✅ CORRECT
        ↓
    [Response to Frontend]
    ✅ {"fileUrl": "https://social-media-gidut-54513.s3.us-east-1.amazonaws.com/550e8400-..."}
    
    This is a VALID URL now!
        ↓
    Frontend stores this full URL
```

---

## ✅ Fixed Send Message Flow

```
ChatScreen._sendMediaMessage(FULL_URL, label='photo')
        ↓
    FULL_URL = "https://social-media-gidut-54513.s3.us-east-1.amazonaws.com/550e8400-..."
        ↓
    ChatWebSocketService.sendMessage(
        recipientId=2,
        content='photo',
        mediaUrl=FULL_URL  ✅ CORRECT: Full URL
    )
        ↓
    [WebSocket Frame]
    Destination: /app/chat.send
    Payload: {
        "receiverId": 2,
        "content": "photo",
        "mediaUrl": "https://social-media-gidut-54513.s3.us-east-1.amazonaws.com/550e8400-...",  ✅
        "clientMessageId": "opt_msg_1234567890"
    }
        ↓
    [MessageController.sendMessageViaWebSocket()]
    ├─ Extract userId from session: 1
    ├─ Validate receiverId: 2
    └─ Call MessageService.sendMessage()
        ↓
    [MessageService.sendMessage()]
    ├─ Create Message entity
    ├─ Set mediaUrl = "550e8400-..."  (store just key in DB)
    ├─ Save to database
    ├─ Create MessageResponse
    ├─ mapToResponse() {
    │     String mediaUrl = message.getMediaUrl();  // "550e8400-..."
    │     ✅ NEW: CONSTRUCT FULL URL
    │     if (mediaUrl != null && !mediaUrl.isEmpty()) {
    │         if (!mediaUrl.startsWith("http")) {
    │             mediaUrl = String.format(
    │                 "https://%s.s3.%s.amazonaws.com/%s",
    │                 bucketName, region, mediaUrl
    │             );
    │         }
    │     }
    │     response.setMediaUrl(mediaUrl);  ✅ CORRECT
    │  }
    └─ Return response
        ↓
    [Response to Sender & Receiver]
    {
        "id": 12345,
        "senderId": 1,
        "receiverId": 2,
        "content": "photo",
        "mediaUrl": "https://social-media-gidut-54513.s3.us-east-1.amazonaws.com/550e8400-...",  ✅
        "createdAt": "2026-01-09T10:30:45.000Z"
    }
        ↓
    [Frontend Message.fromJson()]
    ├─ Parse mediaUrl: "https://social-media-gidut-54513.s3..."
    └─ Store in Message object
        ↓
    [UI Render]
    _buildMediaBubble(message)
    └─ Image.network(message.mediaUrl)
        └─ Image.network("https://social-media-gidut-54513.s3...")
            └─ ✅ SUCCEEDS - Valid URL!
        ↓
    User sees IMAGE 🖼️
```

---

## 🔐 Authentication Flow

```
User logs in
        ↓
    JWT token generated
    {
        "accessToken": "eyJhbGc...",
        "userId": 1,
        "username": "john_doe"
    }
        ↓
    Stored in SharedPreferences
        ↓
    User picks image to upload
        ↓
    ApiService.uploadImage() {
        final token = await getToken();  // Retrieve from SharedPreferences
        
        final request = http.MultipartRequest('POST', uri);
        request.headers['Authorization'] = 'Bearer $token';  ✅
        // ...
    }
        ↓
    [Backend Filter]
    JwtAuthenticationFilter
    ├─ Extract token from header
    ├─ Validate signature
    ├─ Extract userId
    ├─ Set in request attribute
    └─ Pass to controller
        ↓
    FileController
    @RequestAttribute("userId") Long userId
    ├─ userId is available
    └─ Can log for audit
        ↓
    File uploaded
        ↓
    If token is EXPIRED:
    ├─ Filter returns 401
    └─ Frontend catches and shows error
        ↓
    User needs to re-login
```

---

## 💾 Database Storage

```
messages table:
┌─────┬──────────┬──────────┬─────────┬────────────────────────────┬─────────────┐
│ id  │ sender   │ receiver │ content │ media_url                  │ created_at  │
├─────┼──────────┼──────────┼─────────┼────────────────────────────┼─────────────┤
│ 1   │ 1        │ 2        │ photo   │ 550e8400-e29b-41d4-...jpg  │ 2026-01-09  │
│ 2   │ 2        │ 1        │ video   │ 7f9c4f8d-3a2e-44f2-...mp4  │ 2026-01-09  │
│ 3   │ 1        │ 3        │ hello   │ NULL                       │ 2026-01-09  │
└─────┴──────────┴──────────┴─────────┴────────────────────────────┴─────────────┘

✅ media_url column exists
✅ Stores S3 keys (not full URLs)
✅ Correct type: VARCHAR(500)
✅ Can be NULL (for text-only messages)

When fetching messages:
1. Read media_url from DB: "550e8400-e29b-41d4-a716-446655440000.jpg"
2. Construct full URL: "https://bucket.s3.region.amazonaws.com/550e8400-..."
3. Return to frontend
```

---

## 📋 S3 Bucket Structure

```
AWS S3 Bucket: social-media-gidut-54513
Region: us-east-1

/
├── 550e8400-e29b-41d4-a716-446655440000.jpg  (Chat image)
├── 7f9c4f8d-3a2e-44f2-9c1b-5d8e7f9c4f8d.mp4  (Chat video)
├── abc123-def456-ghi789.jpg                  (Profile picture)
├── xyz789-abc456-def123.png                  (Cover photo)
└── ...

Full URL format:
https://social-media-gidut-54513.s3.us-east-1.amazonaws.com/{key}

Example:
https://social-media-gidut-54513.s3.us-east-1.amazonaws.com/550e8400-e29b-41d4-a716-446655440000.jpg
```

---

## 🔍 Comparison: Working vs Broken

```
┌────────────────────┬──────────────────────────────┬────────────────────────────────────────────────────────┐
│ Component          │ ❌ BROKEN (Current)          │ ✅ FIXED (Expected)                                    │
├────────────────────┼──────────────────────────────┼────────────────────────────────────────────────────────┤
│ Upload Response    │ {"fileUrl": "550e8400-..."}  │ {"fileUrl": "https://bucket.s3.../550e8400-..."}      │
├────────────────────┼──────────────────────────────┼────────────────────────────────────────────────────────┤
│ WebSocket Payload  │ mediaUrl: "550e8400-..."     │ mediaUrl: "https://bucket.s3.../550e8400-..."         │
├────────────────────┼──────────────────────────────┼────────────────────────────────────────────────────────┤
│ Message Response   │ mediaUrl: "550e8400-..."     │ mediaUrl: "https://bucket.s3.../550e8400-..."         │
├────────────────────┼──────────────────────────────┼────────────────────────────────────────────────────────┤
│ DB Storage         │ media_url: "550e8400-..."    │ media_url: "550e8400-..."  (same - correct!)          │
├────────────────────┼──────────────────────────────┼────────────────────────────────────────────────────────┤
│ Image.network()    │ Image.network("550e8400-")   │ Image.network("https://bucket.s3.../550e8400-...")    │
│                    │ ❌ FAILS                      │ ✅ SUCCESS                                             │
├────────────────────┼──────────────────────────────┼────────────────────────────────────────────────────────┤
│ User sees          │ 🔴 Broken image icon         │ 🖼️ Actual image                                       │
└────────────────────┴──────────────────────────────┴────────────────────────────────────────────────────────┘
```

---

## 📊 Configuration Values

```
AWS S3 Configuration
├─ Bucket: social-media-gidut-54513
├─ Region: us-east-1
├─ URL Pattern: https://{bucket}.s3.{region}.amazonaws.com/{key}
│  └─ Example: https://social-media-gidut-54513.s3.us-east-1.amazonaws.com/550e8400-...
└─ Full URL for test image:
   https://social-media-gidut-54513.s3.us-east-1.amazonaws.com/550e8400-e29b-41d4-a716-446655440000.jpg

File Upload Limits
├─ Max File Size: 100MB
├─ Max Request Size: 100MB
└─ Enforced by: Spring Servlet Multipart

Message Limits
├─ Content max: 2000 characters
├─ Media URL max: 500 characters
└─ Client ID max: 100 characters
```

---

**These diagrams show the complete architecture, current broken flow, and fixed flow for media uploads in chat.**

---

Date: January 9, 2026
