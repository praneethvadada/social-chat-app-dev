# Social Media Backend - Complete API Guide

## Quick Start

1. **Start Services:**
   ```bash
   .\start-all-services.bat
   ```

2. **Create Database:**
   ```sql
   CREATE DATABASE social_db;
   ```

3. **Services Running:**
   - API Gateway: http://localhost:8080
   - Auth Service: http://localhost:8081
   - Social Service: http://localhost:8082

## Complete API Flow

### 1. Authentication

#### Register User
```bash
curl -X POST http://localhost:8080/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "john_doe",
    "email": "john@example.com",
    "password": "password123",
    "fullName": "John Doe"
  }'
```

Response:
```json
{
  "accessToken": "eyJhbGciOiJIUzI1NiJ9...",
  "refreshToken": "eyJhbGciOiJIUzI1NiJ9...",
  "tokenType": "Bearer",
  "userId": 1,
  "username": "john_doe",
  "email": "john@example.com"
}
```

#### Login
```bash
curl -X POST http://localhost:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "john@example.com",
    "password": "password123"
  }'
```

**Save the accessToken for subsequent requests!**

### 2. Posts

#### Upload Image First
```bash
TOKEN="your-access-token"

curl -X POST http://localhost:8080/api/social/files/upload \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@C:\path\to\image.jpg"
```

Response:
```json
{
  "fileName": "550e8400-e29b-41d4-a716-446655440000.jpg",
  "fileUrl": "/files/550e8400-e29b-41d4-a716-446655440000.jpg"
}
```

#### Create Post
```bash
curl -X POST http://localhost:8080/api/social/posts \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "My first post! Check out this amazing photo 📸",
    "imageUrls": ["/files/550e8400-e29b-41d4-a716-446655440000.jpg"],
    "isPublic": true
  }'
```

Response:
```json
{
  "id": 1,
  "userId": 1,
  "content": "My first post! Check out this amazing photo 📸",
  "imageUrls": ["/files/550e8400-e29b-41d4-a716-446655440000.jpg"],
  "isPublic": true,
  "likesCount": 0,
  "commentsCount": 0,
  "sharesCount": 0,
  "savesCount": 0,
  "isLikedByCurrentUser": false,
  "isSavedByCurrentUser": false,
  "createdAt": "2025-11-29T10:30:00",
  "updatedAt": "2025-11-29T10:30:00"
}
```

#### Get All Posts (Explore)
```bash
curl -X GET "http://localhost:8080/api/social/posts/explore?page=0&size=20" \
  -H "Authorization: Bearer $TOKEN"
```

#### Get User Posts
```bash
curl -X GET "http://localhost:8080/api/social/posts/user/1?page=0&size=20" \
  -H "Authorization: Bearer $TOKEN"
```

#### Update Post
```bash
curl -X PUT http://localhost:8080/api/social/posts/1 \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "Updated post content!",
    "imageUrls": ["/files/image.jpg"],
    "isPublic": true
  }'
```

#### Delete Post
```bash
curl -X DELETE http://localhost:8080/api/social/posts/1 \
  -H "Authorization: Bearer $TOKEN"
```

### 3. Likes

#### Like a Post
```bash
curl -X POST http://localhost:8080/api/social/likes/post/1 \
  -H "Authorization: Bearer $TOKEN"
```

#### Unlike a Post
```bash
curl -X DELETE http://localhost:8080/api/social/likes/post/1 \
  -H "Authorization: Bearer $TOKEN"
```

#### Like a Comment
```bash
curl -X POST http://localhost:8080/api/social/likes/comment/1 \
  -H "Authorization: Bearer $TOKEN"
```

#### Unlike a Comment
```bash
curl -X DELETE http://localhost:8080/api/social/likes/comment/1 \
  -H "Authorization: Bearer $TOKEN"
```

### 4. Comments

#### Add Comment
```bash
curl -X POST http://localhost:8080/api/social/comments \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "postId": 1,
    "content": "Great post! 👍",
    "parentCommentId": null
  }'
```

#### Reply to Comment
```bash
curl -X POST http://localhost:8080/api/social/comments \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "postId": 1,
    "content": "Thanks for sharing!",
    "parentCommentId": 1
  }'
```

#### Get Post Comments
```bash
curl -X GET "http://localhost:8080/api/social/comments/post/1?page=0&size=20" \
  -H "Authorization: Bearer $TOKEN"
```

#### Update Comment
```bash
curl -X PUT http://localhost:8080/api/social/comments/1 \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "Updated comment text"
```

#### Delete Comment
```bash
curl -X DELETE http://localhost:8080/api/social/comments/1 \
  -H "Authorization: Bearer $TOKEN"
```

### 5. Saves

#### Save Post
```bash
curl -X POST http://localhost:8080/api/social/saves/1 \
  -H "Authorization: Bearer $TOKEN"
```

#### Unsave Post
```bash
curl -X DELETE http://localhost:8080/api/social/saves/1 \
  -H "Authorization: Bearer $TOKEN"
```

#### Get Saved Posts
```bash
curl -X GET "http://localhost:8080/api/social/saves?page=0&size=20" \
  -H "Authorization: Bearer $TOKEN"
```

### 6. Shares

#### Share Post
```bash
curl -X POST http://localhost:8080/api/social/shares \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "postId": 1,
    "shareNote": "Check this out!"
  }'
```

### 7. Real-time Chat

#### Send Message (REST)
```bash
curl -X POST http://localhost:8080/api/social/messages \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "receiverId": 2,
    "content": "Hey! How are you?"
  }'
```

#### Get Conversation
```bash
curl -X GET "http://localhost:8080/api/social/messages/conversation/2?page=0&size=50" \
  -H "Authorization: Bearer $TOKEN"
```

#### Mark Message as Read
```bash
curl -X PUT http://localhost:8080/api/social/messages/1/read \
  -H "Authorization: Bearer $TOKEN"
```

#### Mark Entire Conversation as Read
```bash
curl -X PUT http://localhost:8080/api/social/messages/conversation/2/read \
  -H "Authorization: Bearer $TOKEN"
```

#### Get Unread Count
```bash
curl -X GET http://localhost:8080/api/social/messages/unread-count \
  -H "Authorization: Bearer $TOKEN"
```

#### Get Unread Messages
```bash
curl -X GET http://localhost:8080/api/social/messages/unread \
  -H "Authorization: Bearer $TOKEN"
```

### 8. WebSocket Chat (Real-time)

#### JavaScript Client
```html
<!DOCTYPE html>
<html>
<head>
    <script src="https://cdn.jsdelivr.net/npm/sockjs-client@1/dist/sockjs.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/stompjs@2.3.3/lib/stomp.min.js"></script>
</head>
<body>
<script>
const token = 'YOUR_ACCESS_TOKEN';
const socket = new SockJS('http://localhost:8082/ws');
const stompClient = Stomp.over(socket);

stompClient.connect({
    'Authorization': 'Bearer ' + token
}, function(frame) {
    console.log('Connected: ' + frame);
    
    // Subscribe to receive messages
    stompClient.subscribe('/user/queue/messages', function(message) {
        const msg = JSON.parse(message.body);
        console.log('New message:', msg);
        displayMessage(msg);
    });
});

function sendMessage() {
    const messageRequest = {
        receiverId: 2,
        content: document.getElementById('messageInput').value
    };
    
    stompClient.send('/app/chat.send', {}, JSON.stringify(messageRequest));
    document.getElementById('messageInput').value = '';
}

function displayMessage(message) {
    const messagesDiv = document.getElementById('messages');
    const messageDiv = document.createElement('div');
    messageDiv.textContent = message.content;
    messagesDiv.appendChild(messageDiv);
}
</script>

<div>
    <div id="messages"></div>
    <input type="text" id="messageInput" placeholder="Type a message...">
    <button onclick="sendMessage()">Send</button>
</div>
</body>
</html>
```

## Error Handling

All endpoints return appropriate HTTP status codes:
- `200 OK` - Success
- `201 Created` - Resource created
- `204 No Content` - Success with no response body
- `400 Bad Request` - Invalid input
- `401 Unauthorized` - Missing or invalid token
- `403 Forbidden` - Insufficient permissions
- `404 Not Found` - Resource not found
- `500 Internal Server Error` - Server error

## Testing Workflow

1. **Register 2 users** (john and jane)
2. **Login as john** - save token
3. **Create posts** with images
4. **Login as jane** - save token
5. **Jane likes john's post**
6. **Jane comments on john's post**
7. **Jane saves john's post**
8. **Jane shares john's post**
9. **Jane sends message to john** (REST or WebSocket)
10. **John receives real-time notification** (via WebSocket)
11. **John replies to jane**

## File Structure

```
backend/
├── api-gateway/          # Port 8080
├── auth-service/         # Port 8081
├── social-service/       # Port 8082
│   └── uploads/
│       └── images/       # Uploaded images stored here
└── start-all-services.bat
```

## Notes

- All images are stored locally in `social-service/uploads/images/`
- Maximum file size: 10MB
- Supported formats: JPG, PNG, GIF, WebP
- WebSocket endpoint: `ws://localhost:8082/ws`
- All social endpoints require authentication
- User ID is automatically extracted from JWT token
