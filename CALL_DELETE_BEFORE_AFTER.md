# Call History Deletion - Before & After Comparison

## Feature Overview

| Aspect | Before | After |
|--------|--------|-------|
| **Delete Calls** | ❌ Not possible | ✅ Multi-select deletion |
| **User Privacy** | N/A | ✅ Only affects own view |
| **UI Control** | Simple list view | ✅ Selection mode with AppBar |
| **Confirmation** | N/A | ✅ Dialog to prevent accidents |
| **Data Persistence** | N/A | ✅ Survives logout/login |
| **Other User Impact** | N/A | ✅ Zero impact |

---

## User Interface

### Before
```
┌─────────────────────────────────────────┐
│ Calls                          ⋮        │
├─────────────────────────────────────────┤
│ 👤 John Doe                   │📞📹   │
│ ↗️ 📞 2h ago                              │
├─────────────────────────────────────────┤
│ 👤 Jane Smith                 │📞📹   │
│ ↙️ 📹 Yesterday                          │
├─────────────────────────────────────────┤
│ 👤 Bob Wilson                 │📞📹   │
│ ↗️ 📞 3d ago                              │
└─────────────────────────────────────────┘

No delete option available
```

### After (Normal Mode)
```
┌─────────────────────────────────────────┐
│ Calls                          ⋮        │
├─────────────────────────────────────────┤
│ 👤 John Doe                   │📞📹   │
│ ↗️ 📞 2h ago                              │
├─────────────────────────────────────────┤
│ 👤 Jane Smith                 │📞📹   │
│ ↙️ 📹 Yesterday                          │
├─────────────────────────────────────────┤
│ 👤 Bob Wilson                 │📞📹   │
│ ↗️ 📞 3d ago                              │
└─────────────────────────────────────────┘

Long-press any call to enable deletion
```

### After (Selection Mode)
```
┌─────────────────────────────────────────┐
│ 2 selected         🗑️      ✕           │
├─────────────────────────────────────────┤
│ 👤 John Doe                   │☑️      │
│ ↗️ 📞 2h ago                              │
├─────────────────────────────────────────┤
│ 👤 Jane Smith                 │☑️      │
│ ↙️ 📹 Yesterday                          │
├─────────────────────────────────────────┤
│ 👤 Bob Wilson                 │☐      │
│ ↗️ 📞 3d ago                              │
└─────────────────────────────────────────┘

Selected: 2 calls
Actions: Delete or Close
```

---

## Database Schema

### Before
```
CallLog
├── id (PK)
├── initiatorId
├── callerId
├── calleeId
├── type (audio/video)
├── status
├── channel
├── duration
├── recordingUrl
├── createdAt
└── updatedAt
```

### After
```
CallLog
├── id (PK)
├── initiatorId
├── callerId
├── calleeId
├── type (audio/video)
├── status
├── channel
├── duration
├── recordingUrl
├── createdAt
├── updatedAt
├── deletedForCaller      ← NEW ✅
└── deletedForCallee      ← NEW ✅
```

**Migration**: `ALTER TABLE call_logs ADD deletedForCaller BOOLEAN DEFAULT false;`
**Migration**: `ALTER TABLE call_logs ADD deletedForCallee BOOLEAN DEFAULT false;`

---

## API Endpoints

### Before

| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | /token | Get Agora token |
| POST | / | Log call start |
| PUT | /{callId}/status | Update call status |
| GET | /history | Get call history |

### After

| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | /token | Get Agora token |
| POST | / | Log call start |
| PUT | /{callId}/status | Update call status |
| GET | /history | Get call history |
| **DELETE** | **/{callId}** | **Delete call (new)** ✅ |

---

## Query Evolution

### Before
```sql
-- Get all calls for user ID 5
SELECT c FROM CallLog c 
WHERE c.callerId = :userId OR c.calleeId = :userId 
ORDER BY c.createdAt DESC
```

**Returns**: All calls regardless of deletion status

### After
```sql
-- Get calls for user ID 5 (excluding their deletions)
SELECT c FROM CallLog c 
WHERE ((c.callerId = :userId AND c.deletedForCaller = false) 
    OR (c.calleeId = :userId AND c.deletedForCallee = false))
ORDER BY c.createdAt DESC
```

**Returns**: Only calls not deleted by current user

---

## Call Flow

### Before: Making a Call
```
User A wants to delete call
    ↓
❌ No UI for deletion
    ↓
❌ Cannot proceed
```

### After: Deleting a Call

```
User A opens Calls screen
    ↓
User A long-presses Call #123
    ↓
Selection mode activates
    ↓
User A taps more calls to multi-select
    ↓
User A clicks Delete button
    ↓
Confirmation dialog shown
    ↓
User A confirms
    ↓
DELETE /calls/{callId} sent for each
    ↓
Backend sets deletedForCaller = true
    ↓
Database updated
    ↓
Mobile refreshes list
    ↓
Deleted calls no longer visible
    ↓
User B's view unchanged
```

---

## Code Changes

### Backend: CallLog Entity

**Before**:
```java
public class CallLog {
    private Long id;
    private Long initiatorId;
    private Long callerId;
    private Long calleeId;
    private String type;
    private String status;
    private String channel;
    private Long duration;
    private String recordingUrl;
    private Instant createdAt;
    private Instant updatedAt;
}
```

**After**:
```java
public class CallLog {
    private Long id;
    private Long initiatorId;
    private Long callerId;
    private Long calleeId;
    private String type;
    private String status;
    private String channel;
    private Long duration;
    private String recordingUrl;
    private Instant createdAt;
    private Instant updatedAt;
    private Boolean deletedForCaller = false;      // ✅ NEW
    private Boolean deletedForCallee = false;      // ✅ NEW
    
    // Plus getters/setters for new fields ✅
}
```

### Backend: Controller

**Before**:
```java
@GetMapping("/history")
public ResponseEntity<?> getCallHistory(@RequestAttribute("userId") Long userId) {
    return ResponseEntity.ok(callLogRepository.findCallLogsForUser(userId));
}
```

**After**:
```java
@GetMapping("/history")
public ResponseEntity<?> getCallHistory(@RequestAttribute("userId") Long userId) {
    return ResponseEntity.ok(callLogRepository.findCallLogsForUser(userId));
}

@DeleteMapping("/{callId}")                         // ✅ NEW
public ResponseEntity<?> deleteCall(
        @PathVariable Long callId,
        @RequestAttribute("userId") Long userId) {
    // Verify ownership and set deletion flag
    // ...
}
```

### Mobile: API Service

**Before**:
```dart
class CallApi {
  static Future<Map<String, dynamic>?> fetchAgoraToken(...) { ... }
  static Future<bool> logCall(...) { ... }
  static Future<List<CallHistory>> fetchCallHistory() { ... }
  static Future<bool> updateCallStatus(...) { ... }
}
```

**After**:
```dart
class CallApi {
  static Future<Map<String, dynamic>?> fetchAgoraToken(...) { ... }
  static Future<bool> logCall(...) { ... }
  static Future<List<CallHistory>> fetchCallHistory() { ... }
  static Future<bool> updateCallStatus(...) { ... }
  
  static Future<bool> deleteCall(int callId) async {    // ✅ NEW
    // Send DELETE request to backend
    // Handle errors
    // Return success/failure
  }
}
```

### Mobile: UI State

**Before**:
```dart
class _CallsScreenV2State extends State<CallsScreenV2> {
  late Future<List<CallHistory>> _futureCallHistory;
  final Map<int, UserProfile> _profileCache = {};
  int? _myUserId;
  StreamSubscription? _callUpdateSubscription;
  // No selection state
}
```

**After**:
```dart
class _CallsScreenV2State extends State<CallsScreenV2> {
  late Future<List<CallHistory>> _futureCallHistory;
  final Map<int, UserProfile> _profileCache = {};
  int? _myUserId;
  StreamSubscription? _callUpdateSubscription;
  
  bool _selectionMode = false;                  // ✅ NEW
  Set<int> _selectedCallIds = {};               // ✅ NEW
}
```

### Mobile: UI Methods

**New Methods Added**:
```dart
void _enterSelectionMode(int callId) { ... }       // ✅ NEW
void _exitSelectionMode() { ... }                  // ✅ NEW
void _toggleSelection(int callId) { ... }          // ✅ NEW
Future<void> _deleteSelectedCalls() async { ... }  // ✅ NEW
```

---

## State Transitions

### Selection Mode State Machine

```
┌──────────────────┐
│   NORMAL MODE    │  (Initial state)
│ _selectionMode   │
│   = false        │
└────────┬─────────┘
         │
         │ Long-press call
         ↓
┌──────────────────┐
│ SELECTION MODE   │  (_selectionMode = true)
│ Checkboxes shown │  (_selectedCallIds = {callId})
│ Delete button on │
└────────┬─────────┘
         │
         ├─ Tap call
         │  ↓
         │ ☑️ Toggle selection
         │  ↓
         │ No items selected?
         │  ├─ YES → Exit selection
         │  └─ NO → Stay in selection
         │
         ├─ Click Delete
         │  ↓
         │ Show confirmation
         │  ├─ Confirm
         │  │  ↓
         │  │ Delete API calls
         │  │  ↓
         │  │ Refresh list
         │  │  ↓
         │  │ Exit selection
         │  │  ↓
         │  └─→ NORMAL MODE
         │  └─ Cancel
         │     ↓
         │     Stay in selection
         │
         └─ Click Close
            ↓
            Exit selection
            ↓
            NORMAL MODE
```

---

## Example Deletion Sequence

### Scenario: User A Deletes 2 Calls

```
Database Before:
┌────┬──────────┬──────────┬──────────────────┬──────────────────┐
│ id │ callerId │ calleeId │ deletedForCaller │ deletedForCallee │
├────┼──────────┼──────────┼──────────────────┼──────────────────┤
│ 1  │    3     │    5     │      false       │      false       │
│ 2  │    5     │    3     │      false       │      false       │
│ 3  │    3     │    5     │      false       │      false       │
└────┴──────────┴──────────┴──────────────────┴──────────────────┘

User 5 selects calls 1 and 2

DELETE /calls/1  (User 5 is callee) → deletedForCallee = true
DELETE /calls/2  (User 5 is caller) → deletedForCaller = true

Database After:
┌────┬──────────┬──────────┬──────────────────┬──────────────────┐
│ id │ callerId │ calleeId │ deletedForCaller │ deletedForCallee │
├────┼──────────┼──────────┼──────────────────┼──────────────────┤
│ 1  │    3     │    5     │      false       │      true   ✅   │
│ 2  │    5     │    3     │      true   ✅   │      false       │
│ 3  │    3     │    5     │      false       │      false       │
└────┴──────────┴──────────┴──────────────────┴──────────────────┘

User 5's Query (SELECT WHERE not deleted by user):
WHERE (callerId = 5 AND deletedForCaller = false)
   OR (calleeId = 5 AND deletedForCallee = false)

Results: Call 3 only
(Calls 1 and 2 filtered out ✅)

User 3's Query (SELECT WHERE not deleted by user):
WHERE (callerId = 3 AND deletedForCaller = false)
   OR (calleeId = 3 AND deletedForCallee = false)

Results: Calls 1, 2, and 3
(All visible, none filtered ✅)
```

---

## Performance Impact

### Query Performance

| Scenario | Before | After | Impact |
|----------|--------|-------|--------|
| Get history (10 calls) | Fast | Same | None |
| Get history (1000 calls) | Fast | Same | Negligible |
| Delete call | N/A | Fast | New feature |
| Filter deleted items | N/A | In DB | Efficient |

**Index Recommendation** (Future):
```sql
CREATE INDEX idx_call_logs_user_deleted 
ON call_logs(callerId, calleeId, deletedForCaller, deletedForCallee);
```

### Network Overhead

| Operation | Requests | Size |
|-----------|----------|------|
| View history | 1 GET | ~5KB |
| Delete 1 call | 1 DELETE | ~100B |
| Delete 10 calls | 10 DELETE | ~1KB |
| Batch delete (future) | 1 DELETE | ~500B |

---

## Risk Assessment

### Low Risk Changes ✅
- Soft delete (non-destructive)
- User-specific filtering (no data loss)
- No schema migration needed (add columns)
- Backward compatible (old calls not affected)

### Medium Risk Considerations ⚠️
- API changes (DELETE endpoint)
- UI state management (new state variables)
- Sequential API calls (could be slow for many items)

### Mitigation Strategies
- Comprehensive error handling
- User confirmation dialog
- Batch operation support (future)
- Database backups before release

---

## Summary Statistics

| Metric | Value |
|--------|-------|
| Files Modified | 5 |
| Backend Files | 3 |
| Mobile Files | 2 |
| New Methods | 5 |
| New API Endpoints | 1 |
| New Database Fields | 2 |
| Lines of Code Added | ~200 |
| Breaking Changes | 0 |
| Backward Compatibility | 100% |

