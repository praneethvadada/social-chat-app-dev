# Fixed: Follow Request & Post Visibility Issues

## Issues Resolved

### Issue 1: Follow Request Button Inconsistency
**Problem**: When clicking "Request" on a private account in the followers list, it shows "Requested". But when visiting that same account's profile, it incorrectly shows "Follow" button instead of "Requested".

**Root Cause**: The profile screen wasn't checking if a follow request had been sent. It only tracked the local `_followRequested` state, which wasn't persisted from the backend.

**Solution**:
- Added `hasFollowRequest()` method to ApiService to check pending requests from backend
- Added backend endpoint: `GET /follow-requests/check/{userId}` to check if user has pending request
- Updated `_checkFollowStatus()` to fetch follow request status from backend
- Now correctly shows "Requested" button when a request is pending

### Issue 2: Private Account Posts Still Showing After Approval
**Problem**: Even after the private account owner approved the follow request, the posts were still showing as locked with "account is private" message.

**Root Cause**: Post visibility logic wasn't considering the follow status. It only checked if the account was private, not if the user was following.

**Solution**:
- Updated `_loadUserPosts()` to check follow status: only show posts if user is following OR it's their own profile
- When follow approval happens (follow status changes), posts are automatically reloaded
- Fixed `_toggleFollow()` to reload posts after follow/unfollow actions

## Changes Made

### Frontend Changes

#### 1. `api_service.dart`
- **Added**: `hasFollowRequest(int userId)` method
  - Calls `GET /social/follow-requests/check/{userId}` endpoint
  - Returns true if user has pending request to target user
  - Handles errors gracefully

#### 2. `user_profile_screen.dart`
- **Modified**: `_checkFollowStatus()` method
  - Now checks both follow status AND follow request status
  - Calls `ApiService.hasFollowRequest()` for pending requests on private accounts
  - Sets `_followRequested` from backend instead of just local state
  - Added detailed logging for debugging

- **Modified**: `_loadUserPosts()` method
  - Only loads/shows posts if: user is following OR it's own profile
  - Returns empty list if private account and not following
  - Logs post visibility decisions

- **Enhanced**: `_toggleFollow()` method
  - Reloads posts after follow/unfollow to update visibility
  - Better state management for follow, request, and unfollow actions
  - Prevents clicking "Request" when already requested (disables button)
  - Added logging for each action

- **Fixed**: Follow button UI
  - Button is now disabled when `_followRequested` is true
  - Shows "Requested" state correctly
  - Shows "Following" state for public accounts after instant follow

#### 3. `followers_list_screen.dart`
- **Enhanced**: `_toggleFollow()` method
  - Now checks for existing request before sending duplicate request
  - Calls `ApiService.hasFollowRequest()` to verify
  - Better prevents duplicate follow requests

### Backend Changes

#### 1. `FollowRequestController.java`
- **Added**: `GET /follow-requests/check/{userId}` endpoint
  - Checks if current user has pending request to target user
  - Returns JSON with `hasPendingRequest` boolean flag
  - Includes debugging info (requesterId, targetUserId)

#### 2. `FollowRequestService.java`
- **Added**: `hasPendingRequest(Long requesterId, Long targetId)` method
  - Queries repository for existing request
  - Returns boolean indicating pending request status
  - Includes logging for debugging

## Testing Checklist

### Scenario 1: Private Account Follow Request
- [ ] Click "Request" button on private account in followers list
- [ ] Verify button changes to "Requested"
- [ ] Visit that private account's profile directly
- [ ] **VERIFY**: Shows "Requested" button (not "Follow")
- [ ] **VERIFY**: Posts are hidden with private account message

### Scenario 2: Follow Request Approval
- [ ] Create second account
- [ ] Send follow request to private account
- [ ] Accept request from private account
- [ ] Go back to first account's profile
- [ ] **VERIFY**: Button now shows "Following"
- [ ] **VERIFY**: Posts are now visible (no longer locked)

### Scenario 3: Public Account Instant Follow
- [ ] Toggle an account to PUBLIC
- [ ] Click "Follow" button as another user
- [ ] **VERIFY**: Button immediately shows "Following"
- [ ] **VERIFY**: Posts are visible
- [ ] Logout and login
- [ ] **VERIFY**: Follow status still shows "Following"

### Scenario 4: Unfollow Private Account
- [ ] From following a private account, click "Following" button
- [ ] **VERIFY**: Button shows "Request"
- [ ] **VERIFY**: Posts become hidden again

## Debug Logging

All key operations now include logging:

### Frontend:
```
[FOLLOW REQUEST CHECK] userId: X, hasRequest: true/false
[FOLLOW STATUS CHECK] userId: X, isFollowing: true/false, hasRequest: true/false, isPrivate: true/false
[POST VISIBILITY] Private account, user not following - hiding posts
[POST VISIBILITY] Loaded N posts for user X
[TOGGLE FOLLOW] userId: X, isFollowing: true/false, isPrivate: true/false, followRequested: true/false
[FOLLOW REQUEST] Sent
[UNFOLLOW] Success
[FOLLOW] Success
```

### Backend:
```
[FOLLOW REQUEST CHECK] requesterId: X, targetId: Y, hasPending: true/false
```

## Migration Notes

**Database**: The migration from previous issue to add `is_private` column to `users` table is still required:
```sql
ALTER TABLE users 
ADD COLUMN is_private BOOLEAN NOT NULL DEFAULT FALSE;
```

This should have been completed in the previous fix.
