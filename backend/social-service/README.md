# Social Media Backend - Social Service

## Overview
The Social Service handles all social media features including posts, comments, likes, saves, shares, and real-time chat.

## Features

### 1. Posts (CRUD Operations)
- Create posts with text and images
- Update/delete posts
- Get user posts
- Explore public posts
- Images stored locally in `uploads/images/` folder

### 2. Comments
- Add comments to posts
- Reply to comments (nested comments)
- Update/delete comments
- Get post comments with pagination

### 3. Likes
- Like/unlike posts
- Like/unlike comments
- Track likes count

### 4. Saves
- Save/unsave posts for later
- View saved posts

### 5. Shares
- Share posts with optional notes
- Track share count

### 6. Real-time Chat
- WebSocket-based messaging
- One-on-one conversations
- Message read receipts
- Unread message counter
- Real-time notifications

## Database Schema

### Tables
- **posts** - User posts with media
- **comments** - Comments on posts (supports nesting)
- **likes** - Likes on posts and comments
- **saves** - Saved posts
- **shares** - Shared posts
- **messages** - Chat messages between users

## API Endpoints

### Posts
- `POST /posts` - Create post
- `PUT /posts/{postId}` - Update post
- `DELETE /posts/{postId}` - Delete post
- `GET /posts/{postId}` - Get single post
- `GET /posts/user/{userId}` - Get user posts
- `GET /posts/explore` - Get public posts

### Comments
- `POST /comments` - Create comment
- `PUT /comments/{commentId}` - Update comment
- `DELETE /comments/{commentId}` - Delete comment
- `GET /comments/post/{postId}` - Get post comments

### Likes
- `POST /likes/post/{postId}` - Like post
- `DELETE /likes/post/{postId}` - Unlike post
- `POST /likes/comment/{commentId}` - Like comment
- `DELETE /likes/comment/{commentId}` - Unlike comment

### Saves
- `POST /saves/{postId}` - Save post
- `DELETE /saves/{postId}` - Unsave post
- `GET /saves` - Get saved posts

### Shares
- `POST /shares` - Share post

### Messages
- `POST /messages` - Send message
- `GET /messages/conversation/{userId}` - Get conversation
- `PUT /messages/{messageId}/read` - Mark message as read
- `PUT /messages/conversation/{userId}/read` - Mark all as read
- `GET /messages/unread-count` - Get unread count
- `GET /messages/unread` - Get unread messages

### Files
- `POST /files/upload` - Upload image
- `GET /files/{fileName}` - Download image
- `DELETE /files/{fileName}` - Delete image

## WebSocket Endpoints

### Connection
```javascript
const socket = new SockJS('http://localhost:8082/ws');
const stompClient = Stomp.over(socket);

stompClient.connect({
  'Authorization': 'Bearer YOUR_TOKEN_HERE'
}, function(frame) {
  console.log('Connected:', frame);
  
  // Subscribe to messages
  stompClient.subscribe('/user/queue/messages', function(message) {
    console.log('New message:', JSON.parse(message.body));
  });
});
```

### Send Message
```javascript
stompClient.send('/app/chat.send', {}, JSON.stringify({
  receiverId: 2,
  content: 'Hello!'
}));
```

## Running the Service

### Prerequisites
- MySQL running on port 3306 with `social_db` database
- Redis running on port 6379

### Start Service
```bash
cd social-service
mvn spring-boot:run
```

The service will run on **port 8082**.

## Configuration

Edit `src/main/resources/application.properties`:

```properties
# Database
spring.datasource.url=jdbc:mysql://localhost:3306/social_db
spring.datasource.username=root
spring.datasource.password=your_password

# File Upload
file.upload.dir=uploads/images
spring.servlet.multipart.max-file-size=10MB

# JWT
jwt.secret=your_secret_key
```

## File Storage

Images are stored locally in the `uploads/images/` folder. This folder is created automatically on startup.

### Upload Example
```bash
curl -X POST http://localhost:8080/api/social/files/upload \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -F "file=@/path/to/image.jpg"
```

Response:
```json
{
  "fileName": "uuid-generated-name.jpg",
  "fileUrl": "/files/uuid-generated-name.jpg"
}
```

## Testing

### Create Post with Images
```bash
TOKEN="your-jwt-token"

curl -X POST http://localhost:8080/api/social/posts \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "Check out this amazing photo!",
    "imageUrls": ["/files/image1.jpg", "/files/image2.jpg"],
    "isPublic": true
  }'
```

### Like a Post
```bash
curl -X POST http://localhost:8080/api/social/likes/post/1 \
  -H "Authorization: Bearer $TOKEN"
```

### Send a Message
```bash
curl -X POST http://localhost:8080/api/social/messages \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "receiverId": 2,
    "content": "Hello! How are you?"
  }'
```

## Security

All endpoints (except `/health` and `/ws`) require JWT authentication. The JWT token is validated via the `JwtAuthenticationFilter`.

The authenticated user ID is extracted from the token and passed to services via `@RequestAttribute("userId")`.
