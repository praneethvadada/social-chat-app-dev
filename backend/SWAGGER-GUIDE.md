# Swagger/OpenAPI Documentation

## Overview

Swagger UI has been integrated into both Auth Service and Social Service for interactive API documentation and testing.

## Access Swagger UI

### Auth Service
- **Swagger UI:** http://localhost:8081/swagger-ui.html
- **OpenAPI JSON:** http://localhost:8081/api-docs
- **Via Gateway:** http://localhost:8080/api/auth/swagger-ui.html

### Social Service
- **Swagger UI:** http://localhost:8082/swagger-ui.html
- **OpenAPI JSON:** http://localhost:8082/api-docs
- **Via Gateway:** http://localhost:8080/api/social/swagger-ui.html

## Features

### ✅ Interactive API Testing
- Test all endpoints directly from the browser
- View request/response schemas
- See example values
- Execute real API calls

### ✅ JWT Authentication Support
- Click "Authorize" button at the top
- Enter: `Bearer YOUR_JWT_TOKEN`
- Token is applied to all subsequent requests

### ✅ Complete API Documentation
- All endpoints documented
- Request/response examples
- Parameter descriptions
- Error responses

## How to Use

### 1. Start the Services
```bash
cd backend
.\start-all-services.bat
```

### 2. Open Swagger UI
Navigate to:
- Auth Service: http://localhost:8081/swagger-ui.html
- Social Service: http://localhost:8082/swagger-ui.html

### 3. Register & Get Token
1. In Auth Service Swagger UI, find `POST /register`
2. Click "Try it out"
3. Enter user details:
```json
{
  "username": "testuser",
  "email": "test@example.com",
  "password": "password123",
  "fullName": "Test User"
}
```
4. Click "Execute"
5. Copy the `accessToken` from the response

### 4. Authorize Requests
1. Click the **"Authorize"** button (🔒) at the top of Swagger UI
2. Enter: `Bearer YOUR_ACCESS_TOKEN`
3. Click "Authorize"
4. Click "Close"

Now all protected endpoints will include your JWT token!

### 5. Test Social Features
1. Open Social Service Swagger UI: http://localhost:8082/swagger-ui.html
2. Click "Authorize" and enter your token
3. Try endpoints:
   - `POST /posts` - Create a post
   - `GET /posts/explore` - View all posts
   - `POST /likes/post/{postId}` - Like a post
   - `POST /comments` - Add a comment
   - `POST /messages` - Send a message

## API Documentation Structure

### Auth Service Endpoints

**Authentication**
- `POST /register` - Register new user
- `POST /login` - User login
- `POST /logout` - User logout
- `POST /refresh` - Refresh access token
- `GET /health` - Health check

### Social Service Endpoints

**Posts**
- `POST /posts` - Create post
- `GET /posts/{postId}` - Get single post
- `PUT /posts/{postId}` - Update post
- `DELETE /posts/{postId}` - Delete post
- `GET /posts/user/{userId}` - Get user posts
- `GET /posts/explore` - Get public posts

**Comments**
- `POST /comments` - Add comment
- `PUT /comments/{commentId}` - Update comment
- `DELETE /comments/{commentId}` - Delete comment
- `GET /comments/post/{postId}` - Get post comments

**Likes**
- `POST /likes/post/{postId}` - Like post
- `DELETE /likes/post/{postId}` - Unlike post
- `POST /likes/comment/{commentId}` - Like comment
- `DELETE /likes/comment/{commentId}` - Unlike comment

**Saves**
- `POST /saves/{postId}` - Save post
- `DELETE /saves/{postId}` - Unsave post
- `GET /saves` - Get saved posts

**Shares**
- `POST /shares` - Share post

**Messages**
- `POST /messages` - Send message
- `GET /messages/conversation/{userId}` - Get conversation
- `PUT /messages/{messageId}/read` - Mark as read
- `PUT /messages/conversation/{userId}/read` - Mark conversation as read
- `GET /messages/unread-count` - Get unread count
- `GET /messages/unread` - Get unread messages

**Files**
- `POST /files/upload` - Upload image
- `GET /files/{fileName}` - Download image
- `DELETE /files/{fileName}` - Delete image

## Example Workflow in Swagger

### Complete Test Flow

1. **Register User** (Auth Service)
   - `POST /register`
   - Get `accessToken`

2. **Authorize** 
   - Click 🔒 button
   - Enter token

3. **Upload Image** (Social Service)
   - `POST /files/upload`
   - Upload a JPG/PNG file
   - Get `fileUrl`

4. **Create Post**
   - `POST /posts`
   ```json
   {
     "content": "My first post!",
     "imageUrls": ["/files/your-uploaded-file.jpg"],
     "isPublic": true
   }
   ```

5. **Like the Post**
   - `POST /likes/post/1`

6. **Add Comment**
   - `POST /comments`
   ```json
   {
     "postId": 1,
     "content": "Great post!",
     "parentCommentId": null
   }
   ```

7. **Save the Post**
   - `POST /saves/1`

8. **View Saved Posts**
   - `GET /saves`

## Tips & Tricks

### Testing Multiple Users
1. Register User 1 and get token
2. Create posts, comments, etc.
3. Clear authorization
4. Register User 2 and get new token
5. User 2 can now interact with User 1's posts

### File Upload Testing
1. Use `POST /files/upload` endpoint
2. Click "Try it out"
3. Click "Choose File" and select an image
4. Execute to upload
5. Copy the `fileUrl` from response
6. Use this URL in `imageUrls` when creating posts

### Debugging Responses
- Expand each response to see:
  - HTTP Status Code
  - Response Body
  - Response Headers
  - cURL command (for command-line testing)

### Export API Specification
Download OpenAPI spec from:
- http://localhost:8081/api-docs (JSON format)
- Import into Postman, Insomnia, or other tools

## Configuration

### Customize Swagger UI

Edit `application.properties`:

```properties
# Swagger/OpenAPI Configuration
springdoc.api-docs.path=/api-docs
springdoc.swagger-ui.path=/swagger-ui.html
springdoc.swagger-ui.enabled=true

# Optional: Customize Swagger UI
springdoc.swagger-ui.operationsSorter=method
springdoc.swagger-ui.tagsSorter=alpha
springdoc.swagger-ui.tryItOutEnabled=true
```

### Disable in Production

```properties
# Disable Swagger in production
springdoc.swagger-ui.enabled=false
springdoc.api-docs.enabled=false
```

## Troubleshooting

### Can't Access Swagger UI
- Check service is running: http://localhost:8081/health
- Verify port: 8081 for Auth, 8082 for Social
- Check firewall settings

### 401 Unauthorized
- Click "Authorize" button
- Enter token with `Bearer ` prefix
- Verify token hasn't expired (24 hours)
- Get fresh token from `/login` or `/register`

### Endpoints Not Showing
- Clear browser cache
- Restart the service
- Check console for errors

### File Upload Not Working
- Ensure file size < 10MB
- Check `file.upload.dir` exists
- Verify permissions on upload directory

## Screenshots

### Main Swagger UI Page
![Swagger UI]
- Shows all available endpoints
- Grouped by tags (Posts, Comments, Likes, etc.)
- Green = GET, Blue = POST, Orange = PUT, Red = DELETE

### Authorization Dialog
![Authorize]
1. Click lock icon
2. Enter: `Bearer eyJhbGciOiJIUzI1NiJ9...`
3. Click "Authorize"

### Testing an Endpoint
![Try It Out]
1. Click "Try it out" button
2. Fill in parameters
3. Edit request body if needed
4. Click "Execute"
5. View response below

## Additional Resources

- **Springdoc OpenAPI:** https://springdoc.org/
- **Swagger UI:** https://swagger.io/tools/swagger-ui/
- **OpenAPI Specification:** https://spec.openapis.org/oas/latest.html

## Notes

- Swagger UI is enabled in development mode
- All endpoints are documented with examples
- JWT tokens expire after 24 hours
- WebSocket endpoints are documented but can't be tested in Swagger UI
- Use the WebSocket client (JavaScript) for real-time chat testing
