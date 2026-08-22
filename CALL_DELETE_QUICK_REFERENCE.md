# Call Deletion - Quick Reference

## How to Use (User Perspective)

### Deleting Calls
1. Open the **Calls** tab
2. **Long-press** on any call → Selection mode activates
3. **Tap** other calls to select multiple calls
4. **Tap** a selected call to deselect it
5. Click the **Delete** button (trash icon) in the top AppBar
6. **Confirm** in the dialog
7. Selected calls are removed from your history

### Important Notes
- ❌ **Does NOT affect the other user's history**
- ❌ **Cannot undo** (unless using database recovery)
- ✅ **Persists after logout** (deletion is permanent)
- ✅ **Only for your view** (user B still sees the call in their history)

---

## How It Works (Technical)

### Selection Mode UI Changes

**Before Deletion**:
- AppBar shows "Calls" heading
- Each call has audio + video call buttons
- Pull-to-refresh works

**During Selection**:
- AppBar shows "X selected" with Delete + Close buttons
- Each call has a checkbox instead of call buttons
- Tap to toggle selection

---

## Database Tracking

Each call record has two flags:

| Flag | Meaning |
|------|---------|
| `deletedForCaller` | Marked true if the caller deleted it |
| `deletedForCallee` | Marked true if the callee deleted it |

**Example**:
```
Call between User A (caller) and User B (callee):

User A deletes: deletedForCaller = true, deletedForCallee = false
  → A's history won't show it
  → B's history will still show it

User B deletes: deletedForCaller = true, deletedForCallee = true
  → Neither user can see it
```

---

## API Endpoints

### DELETE /calls/{callId}

**Request**:
```
DELETE /calls/123
Authorization: Bearer {jwt_token}
```

**Response** (Success):
```json
{
  "message": "Call deleted successfully",
  "callId": 123
}
```

**Response** (Error):
```
401 Unauthorized - No token
403 Forbidden - Not your call
404 Not Found - Invalid call ID
```

---

## Code Flow

### Backend Flow
```
User clicks delete
    ↓
CallsController.deleteCall(callId, userId)
    ↓
Find call by ID
    ↓
Check if user is caller or callee
    ↓
Set appropriate flag to true
    ↓
Save to database
    ↓
Return success response
```

### Mobile Flow
```
User long-presses call
    ↓
_enterSelectionMode(callId)
    ↓
Show checkboxes and Delete button
    ↓
User selects more calls
    ↓
_toggleSelection(callId)
    ↓
User clicks Delete
    ↓
Show confirmation dialog
    ↓
Loop through selected IDs
    ↓
CallApi.deleteCall(each callId)
    ↓
Wait for all requests
    ↓
_refresh() - Reload history from API
    ↓
UI updates with remaining calls
```

---

## Why Soft Delete?

Instead of permanently removing records, we just mark them as deleted:

✅ **Pros**:
- Data is never lost (can recover if needed)
- Audit trails remain intact
- Each user has independent control
- Safer for accidental deletions

❌ **Cons**:
- Slightly more database space used
- Query complexity increases slightly

---

## Files Modified Summary

### Backend (Spring Boot)
- `CallLog.java` - Added `deletedForCaller`, `deletedForCallee` fields
- `CallLogRepository.java` - Updated query to exclude deleted items
- `CallsController.java` - Added DELETE endpoint

### Mobile (Flutter)
- `call_api.dart` - Added `deleteCall()` method
- `calls_screen_v2.dart` - Added multi-select UI and deletion logic

### No Changes Needed
- Database migrations (soft delete uses existing columns)
- App routing or navigation
- WebSocket service
- Call signing/Agora integration

---

## Troubleshooting

### Call still appears after deletion
- Clear app cache and reload
- Check internet connection was stable during delete
- Verify deletion API returned HTTP 200

### Can't enter selection mode
- Must long-press on a call (not tap)
- Screen must be showing CallsScreenV2 (not old CallsScreen)

### Delete button not visible
- Ensure at least one call is selected
- Check AppBar is showing "X selected"

### Other user sees deleted call
- This is expected! Soft delete is per-user
- Other user must delete it separately

---

## Related Features

| Feature | Status | Notes |
|---------|--------|-------|
| Multi-select deletion | ✅ Complete | Batch delete multiple calls |
| Soft delete | ✅ Complete | User-specific deletion flags |
| Selection mode UI | ✅ Complete | Checkboxes + AppBar controls |
| Deletion confirmation | ✅ Complete | AlertDialog prevents accidents |
| Error handling | ✅ Complete | SnackBar feedback on failures |
| Auto-refresh | ✅ Complete | List updates after deletion |
| Long-press detection | ✅ Complete | GestureDetector on ListTile |
