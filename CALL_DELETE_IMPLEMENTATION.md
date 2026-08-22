# Call History Deletion Implementation - Complete

## Overview
Implemented multi-select call history deletion with user-specific soft delete functionality. Users can now select multiple calls and delete them, affecting only their view while preserving the other user's history.

## Database Changes

### CallLog Entity (Backend)
**File**: `backend/social-service/src/main/java/.../entity/CallLog.java`

**New Fields Added**:
```java
private Boolean deletedForCaller = false;      // Tracks if call is deleted for the caller
private Boolean deletedForCallee = false;      // Tracks if call is deleted for the callee

// Getters and Setters
public Boolean getDeletedForCaller() { return deletedForCaller; }
public void setDeletedForCaller(Boolean deletedForCaller) { this.deletedForCaller = deletedForCaller; }

public Boolean getDeletedForCallee() { return deletedForCallee; }
public void setDeletedForCallee(Boolean deletedForCallee) { this.deletedForCallee = deletedForCallee; }
```

**Approach**: Uses soft delete pattern with user-specific flags instead of hard delete. This:
- Preserves data integrity and audit trails
- Allows each user to independently manage their own view
- Doesn't affect the other user's history

---

## Backend API Changes

### 1. CallLogRepository Query Update
**File**: `backend/social-service/src/main/java/.../repository/CallLogRepository.java`

**Updated Query**:
```java
@Query("SELECT c FROM CallLog c WHERE " +
       "((c.callerId = :userId AND c.deletedForCaller = false) OR " +
       "(c.calleeId = :userId AND c.deletedForCallee = false)) " +
       "ORDER BY c.createdAt DESC")
List<CallLog> findCallLogsForUser(@Param("userId") Long userId);
```

**Logic**:
- If user is the caller, exclude calls where `deletedForCaller = true`
- If user is the callee, exclude calls where `deletedForCallee = true`
- Each user gets their independent filtered view

### 2. New DELETE Endpoint
**File**: `backend/social-service/src/main/java/.../controller/CallsController.java`

**Endpoint**:
```java
@DeleteMapping("/{callId}")
@Operation(summary = "Delete a call from history for the authenticated user (soft delete).")
public ResponseEntity<?> deleteCall(
        @PathVariable Long callId,
        @RequestAttribute("userId") Long userId)
```

**Logic**:
1. Verifies call exists
2. Verifies user is either caller or callee
3. Sets appropriate deletion flag:
   - If user is caller → `deletedForCaller = true`
   - If user is callee → `deletedForCallee = true`
4. Saves and returns success response

**Response**:
```json
{
  "message": "Call deleted successfully",
  "callId": 123
}
```

---

## Mobile API Changes

### Call API Service
**File**: `social-media-mobile/lib/src/services/call_api.dart`

**New Method**:
```dart
static Future<bool> deleteCall(int callId) async {
  final uri = Uri.parse('${ApiConfig.callLogEndpoint}/$callId');
  try {
    final token = await ApiService.getToken();
    final headers = <String, String>{};
    if (token != null) headers['Authorization'] = 'Bearer $token';

    final res = await http.delete(uri, headers: headers);
    if (res.statusCode == 200) return true;
    print('[CallApi] deleteCall failed: ${res.statusCode} ${res.body}');
    return false;
  } catch (e) {
    print('[CallApi] deleteCall exception: $e');
    return false;
  }
}
```

---

## UI Implementation

### CallsScreenV2 Multi-Select
**File**: `social-media-mobile/lib/src/screens/calls/calls_screen_v2.dart`

#### New State Variables
```dart
bool _selectionMode = false;           // Enables/disables selection UI
Set<int> _selectedCallIds = {};        // Tracks selected call IDs
```

#### Features Implemented

##### 1. **Long-Press to Enter Selection Mode**
```dart
onLongPress: () => _enterSelectionMode(call.id),
onTap: _selectionMode ? () => _toggleSelection(call.id) : null,
```
- Long-press first call to enter selection mode
- Tap any call to toggle selection during selection mode

##### 2. **AppBar Changes in Selection Mode**
- Shows title with count: "2 selected"
- Delete button with trash icon
- Close button to exit selection
- Only appears when `_selectionMode = true`

##### 3. **Trailing UI Changes**
- **Normal Mode**: Two call buttons (audio/video)
- **Selection Mode**: Checkbox showing selection status

##### 4. **Delete Dialog Confirmation**
```dart
AlertDialog(
  title: const Text('Delete calls?'),
  content: Text('Delete ${_selectedCallIds.length} call(s) from your history?'),
  actions: [
    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
    TextButton(
      onPressed: () => Navigator.pop(context, true),
      child: const Text('Delete', style: TextStyle(color: Colors.red)),
    ),
  ],
)
```

#### Helper Methods

**Enter Selection Mode**:
```dart
void _enterSelectionMode(int callId) {
  setState(() {
    _selectionMode = true;
    _selectedCallIds = {callId};
  });
}
```

**Toggle Selection**:
```dart
void _toggleSelection(int callId) {
  setState(() {
    if (_selectedCallIds.contains(callId)) {
      _selectedCallIds.remove(callId);
      if (_selectedCallIds.isEmpty) {
        _selectionMode = false;  // Auto-exit if no items selected
      }
    } else {
      _selectedCallIds.add(callId);
    }
  });
}
```

**Exit Selection Mode**:
```dart
void _exitSelectionMode() {
  setState(() {
    _selectionMode = false;
    _selectedCallIds.clear();
  });
}
```

**Delete Selected Calls**:
```dart
Future<void> _deleteSelectedCalls() async {
  // Show confirmation dialog
  final confirmed = await showDialog<bool>(...);
  
  if (confirmed == true) {
    // Delete each selected call
    for (final callId in _selectedCallIds) {
      final success = await CallApi.deleteCall(callId);
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete call $callId')),
        );
      }
    }
    
    // Exit and refresh
    _exitSelectionMode();
    _refresh();
  }
}
```

---

## User Experience Flow

### Deletion Workflow
1. **Open Calls Screen** → View all calls in list
2. **Long-Press a Call** → Selection mode enabled, call selected, AppBar updated
3. **Tap Additional Calls** → Toggle selection (add/remove from list)
4. **Click Delete Button** → Confirmation dialog appears
5. **Confirm Deletion** → API calls sent for each selected call
6. **Auto-Refresh** → List updates showing remaining calls
7. **Selection Mode Exits** → AppBar reverts to normal

### Key Behaviors
- ✅ Selection is cumulative (long-press first, then tap others)
- ✅ Can deselect by tapping a selected call
- ✅ Auto-exits selection mode when last item deselected
- ✅ Shows count of selected items in AppBar
- ✅ Batch delete all selected at once
- ✅ User only sees calls not deleted by them
- ✅ Other user's view unaffected by deletion
- ✅ Deletion persists after logout/login

---

## Data Flow Diagram

```
User A (long-press call)
    ↓
_enterSelectionMode(callId)
    ↓
[Selection UI enabled]
    ↓
User A (click Delete)
    ↓
_deleteSelectedCalls()
    ↓
for each callId:
    CallApi.deleteCall(callId)
        ↓
    DELETE /calls/{callId}
        ↓
    Backend:
        - Verify user is caller OR callee
        - Set deletedForCaller = true (if caller)
        - OR Set deletedForCallee = true (if callee)
        - Save to DB
    ↓
_refresh()
    ↓
CallApi.fetchCallHistory()
    ↓
Backend Query:
    WHERE (callerId = userId AND deletedForCaller = false)
       OR (calleeId = userId AND deletedForCallee = false)
    ↓
UI updates with remaining calls
```

---

## Soft Delete vs Hard Delete

| Aspect | Soft Delete (Implemented) | Hard Delete |
|--------|--------------------------|------------|
| Data Preservation | ✅ Full data retained | ❌ Data lost |
| Audit Trail | ✅ Can track deletions | ❌ No history |
| User Privacy | ✅ Independent views | ❌ Affects both users |
| Recoverability | ✅ Possible (admin only) | ❌ Not possible |
| Query Complexity | Slightly higher | Simpler |

---

## API Contract

### Delete Call Request
```
DELETE /calls/{callId}
Authorization: Bearer {jwt_token}
```

### Delete Call Response (Success)
```
HTTP 200
{
  "message": "Call deleted successfully",
  "callId": 123
}
```

### Delete Call Response (Errors)
```
HTTP 401 - Unauthorized (no token)
HTTP 403 - Forbidden (not caller or callee)
HTTP 404 - Not Found (invalid callId)
```

---

## Testing Checklist

- [ ] User A long-presses a call → Selection mode activates
- [ ] User A taps another call → Added to selection (count increases)
- [ ] User A taps selected call → Removed from selection (count decreases)
- [ ] User A clicks close button → Selection mode exits, selection cleared
- [ ] User A deletes call from history
- [ ] User B views call history → Call still visible for User B
- [ ] User A logs out and back in → Deleted calls remain deleted
- [ ] User A selects multiple calls and deletes all → List refreshes
- [ ] User A cancels delete operation → Nothing deleted
- [ ] Error occurs during delete → SnackBar error shown
- [ ] Network error during delete → Graceful error handling

---

## Files Modified

### Backend
1. ✅ `CallLog.java` - Added deletion flags + getters/setters
2. ✅ `CallLogRepository.java` - Updated query to filter deleted items
3. ✅ `CallsController.java` - Added DELETE endpoint

### Mobile  
1. ✅ `call_api.dart` - Added deleteCall() method
2. ✅ `calls_screen_v2.dart` - Added multi-select UI + deletion logic

---

## Deployment Notes

1. **Database Migration**: No migration needed - soft delete adds boolean columns with defaults
2. **API Versioning**: No change needed - using existing DELETE verb with new semantics
3. **Mobile Backward Compatibility**: New methods don't break existing functionality
4. **Rollout Strategy**: Can deploy backend first, mobile second (graceful if delete unavailable)

---

## Future Enhancements

1. **Bulk Delete API** - Single endpoint to delete multiple calls in one request
2. **Undo Deletion** - 30-day soft delete window with restore option
3. **Archive Instead** - Move to archive instead of delete
4. **Delete Confirmation Toast** - Show "X calls deleted" confirmation
5. **Recent Deletions** - Recovery center for recently deleted calls
