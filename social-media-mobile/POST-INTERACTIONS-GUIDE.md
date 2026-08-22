# Post Interactions Implementation Guide

## Overview
The post interactions feature enables users to:
- **Like/Unlike Posts** - Show appreciation for content
- **Save Posts** - Save posts for later viewing
- **Add Comments** - Comment on posts and view comments from others

## Architecture

### Components

#### 1. PostInteractionService (`post_interaction_service.dart`)
Service layer for all post interaction API calls. Handles authentication and error handling.

**Methods:**
```dart
// Like Management
Future<void> likePost(int postId) → Like a post
Future<void> unlikePost(int postId) → Unlike a post

// Save Management
Future<void> savePost(int postId) → Save a post
Future<void> unsavePost(int postId) → Unsave a post

// Comment Management
Future<void> addComment(int postId, String content) → Add comment to post
```

**Key Features:**
- Automatic JWT authentication token retrieval
- Comprehensive error handling with user-friendly messages
- Debug logging for all interactions
- Status code validation for all endpoints

#### 2. PostActionsWidget (`post_actions_widget.dart`)
Stateful widget that displays post action buttons with interactive functionality.

**Features:**
- **Like Button** - Toggle like/unlike with animated color change
  - Shows red heart when liked
  - Updates like count dynamically
  - Prevents duplicate API calls during loading
  
- **Comment Button** - Opens comments screen
  - Shows comment count
  - Navigates to full comments interface
  
- **Share Button** - Placeholder for future implementation
  
- **Save Button** - Toggle save/unsave with animated color change
  - Shows orange bookmark when saved
  - Smooth state transitions
  - Prevents duplicate API calls during loading

**Callbacks:**
- `onLikeChanged(bool)` - Called when like status changes
- `onSaveChanged(bool)` - Called when save status changes

#### 3. CommentsScreen (`comments_screen.dart`)
Full-screen interface for viewing and adding comments to a post.

**Features:**
- Displays existing comments in a scrollable list
- Comment input field at bottom
- Real-time comment submission
- Loading state during submission
- Error handling with user feedback

## API Endpoints

### Backend Integration

All endpoints are accessed through the API Gateway (port 8080) with JWT authentication:

```
POST /social/likes/post/{postId}          → Like a post
DELETE /social/likes/post/{postId}        → Unlike a post

POST /social/saves/{postId}               → Save a post
DELETE /social/saves/{postId}             → Unsave a post

POST /social/comments                     → Add comment
  Body: {
    "postId": number,
    "content": string
  }
```

### Response Handling
- **2xx Status Codes** - Success (200, 201)
- **Error Status Codes** - Extracted error message displayed to user
- **Authentication** - Bearer token in Authorization header

## State Management

### Post Model Fields
```dart
late bool isLiked;           // Current user has liked this post
late bool isSaved;           // Current user has saved this post
late int likes;              // Total likes count
late int comments;           // Total comments count
late int saves;              // Total saves count
```

### Widget State Flow
1. **Initial State** - Widget initialized with post data
2. **User Action** - User taps like/save button
3. **Loading State** - Button disabled, loading indicator shown
4. **API Call** - PostInteractionService method called
5. **Update State** - Local state updated (isLiked/isSaved toggled)
6. **Show Feedback** - Toast notification displayed
7. **Reset Loading** - Button re-enabled for next action

## Error Handling

### Error Cases Handled
1. **Not Authenticated** - Prompts user to log in
2. **Network Errors** - Shows appropriate error message
3. **Server Errors** - Displays server error message
4. **Invalid Request** - Shows validation error

### User Feedback
- Success: Toast notification with action description
- Error: Snackbar with error message
- Loading: Disabled buttons and progress indicator

## Usage Example

### In Feed/PostCard
```dart
PostActionsWidget(
  post: post,
  onLikeChanged: (isLiked) {
    print('Post ${post.id} like status: $isLiked');
  },
  onSaveChanged: (isSaved) {
    print('Post ${post.id} save status: $isSaved');
  },
)
```

### Open Comments
```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => CommentsScreen(post: post),
  ),
);
```

## Testing Checklist

- [ ] Like a post and verify count increases
- [ ] Unlike a post and verify count decreases
- [ ] Save a post and verify bookmark icon changes color
- [ ] Unsave a post and verify icon returns to outline
- [ ] Add a comment and verify it appears in comments screen
- [ ] Try interactions without network - verify error message
- [ ] Try interactions without authentication - verify error message
- [ ] Rapidly click buttons - verify no duplicate requests
- [ ] Like/save same post from different screens - verify state sync
- [ ] Refresh feed after interactions - verify states persist

## Future Enhancements

1. **Real-time Comments** - WebSocket integration for live comment updates
2. **Comment Likes** - Allow users to like/unlike comments
3. **Comment Replies** - Thread-based comment system
4. **Share Options** - Share to story, message, or external apps
5. **Like Animations** - Heart burst animation on double tap
6. **Bookmark Collections** - Organize saved posts into folders
7. **Comment Search** - Search comments within a post
8. **Comment Filters** - Sort by newest, oldest, or most liked

## Dependencies

- **http** - HTTP client for API calls
- **flutter** - UI framework
- **video_player** - For video display in posts

## Related Files

- [Post Model](../models/post.dart)
- [Post Card](post_card.dart)
- [API Service](../services/api_service.dart)
- [Feed Screen](../screens/feed/feed_screen.dart)
