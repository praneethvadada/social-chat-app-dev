# API Testing Collection

This directory contains sample API requests for testing the social media backend.

## Quick Start with curl

### 1. Register a User

```bash
curl -X POST http://localhost/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "johndoe",
    "email": "john@example.com",
    "password": "securePass123",
    "fullName": "John Doe"
  }'
```

### 2. Login

```bash
curl -X POST http://localhost/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "john@example.com",
    "password": "securePass123"
  }'
```

Save the `accessToken` from the response for subsequent requests.

### 3. Create a Post

```bash
TOKEN="your-access-token-here"

curl -X POST http://localhost/api/social/posts \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "content": "Hello, this is my first post!",
    "mediaUrls": [],
    "isPublic": true
  }'
```

### 4. Get Feed

```bash
curl -X GET "http://localhost/api/social/posts/feed?page=0&size=20" \
  -H "Authorization: Bearer $TOKEN"
```

### 5. Like a Post

```bash
POST_ID=1

curl -X POST "http://localhost/api/social/likes/POST/$POST_ID" \
  -H "Authorization: Bearer $TOKEN"
```

### 6. Add a Comment

```bash
curl -X POST http://localhost/api/social/comments \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "postId": 1,
    "content": "Great post!",
    "parentCommentId": null
  }'
```

### 7. Follow a User

```bash
USER_ID=2

curl -X POST "http://localhost/api/social/followers/$USER_ID" \
  -H "Authorization: Bearer $TOKEN"
```

### 8. Send a Message

```bash
curl -X POST http://localhost/api/social/messages \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "receiverId": 2,
    "content": "Hello! How are you?",
    "mediaUrl": null
  }'
```

### 9. Get Unread Messages Count

```bash
curl -X GET http://localhost/api/social/messages/unread-count \
  -H "Authorization: Bearer $TOKEN"
```

### 10. Get Conversation

```bash
OTHER_USER_ID=2

curl -X GET "http://localhost/api/social/messages/conversation/$OTHER_USER_ID?page=0&size=50" \
  -H "Authorization: Bearer $TOKEN"
```

## Postman Collection

Import the provided Postman collection for easier testing with a GUI.

### Variables to Set in Postman:
- `baseUrl`: `http://localhost/api`
- `token`: Your JWT access token (auto-populated after login)

## WebSocket Testing

Use a WebSocket client like:
- **wscat**: `npm install -g wscat`
- **Postman** (WebSocket support)
- Browser JavaScript console

### Connect to WebSocket:

```javascript
const socket = new SockJS('http://localhost/api/social/ws');
const stompClient = Stomp.over(socket);

stompClient.connect({
  'Authorization': 'Bearer YOUR_TOKEN_HERE'
}, function(frame) {
  console.log('Connected:', frame);
  
  // Subscribe to messages
  stompClient.subscribe('/user/queue/messages', function(message) {
    console.log('Received:', JSON.parse(message.body));
  });
  
  // Send a message
  stompClient.send('/app/chat.send', {}, JSON.stringify({
    receiverId: 2,
    content: 'Hello via WebSocket!'
  }));
});
```

## Testing Rate Limiting

Test rate limiting by making rapid requests:

```bash
# This should trigger rate limiting after 5 requests
for i in {1..10}; do
  curl -X POST http://localhost/api/auth/login \
    -H "Content-Type: application/json" \
    -d '{"email":"test@test.com","password":"wrong"}' \
    -w "\nStatus: %{http_code}\n"
  sleep 0.1
done
```

## Testing Security Headers

```bash
curl -I http://localhost/health
```

Expected headers:
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`
- `X-XSS-Protection: 1; mode=block`
- `Strict-Transport-Security`
- `Content-Security-Policy`

## Load Testing with Apache Bench

```bash
# Install Apache Bench
# Ubuntu: sudo apt-get install apache2-utils
# macOS: brew install httpd (ab is included)

# Test login endpoint
ab -n 1000 -c 10 -p login.json -T application/json http://localhost/api/auth/login
```

Create `login.json`:
```json
{"email":"test@test.com","password":"pass123"}
```
