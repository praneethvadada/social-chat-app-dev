# 500 Error Diagnostic Guide - Follow Request System

## ROOT CAUSE ANALYSIS

The **isEitherBlocked()** query in BlockedUserRepository is **CORRECT** but might still throw 500 errors in these scenarios:

---

## SCENARIO 1: Null User IDs in Request 🔴 LIKELY

### Problem
The follow request endpoint receives null or invalid user IDs, causing database query failures.

### Code Path
```
FollowRequestController.sendRequest()
  ↓
FollowRequestService.sendFollowRequest(requesterId, targetId)
  ↓
blockService.isEitherBlocked(requesterId, targetId)  ← Both must be non-null
  ↓
BlockedUserRepository.isEitherBlocked()  ← Database query
```

### Signs
- 500 error when clicking "Request"
- No error message discrimination (all failures look the same)
- Logs show SQL syntax error or parameter binding issue

### Fix
**Location:** [FollowRequestController.java](backend/social-service/src/main/java/com/socialmedia/social/controller/FollowRequestController.java)

Add validation:
```java
@PostMapping("/{userId}")
public ResponseEntity<Map<String, String>> sendRequest(
    @PathVariable Long userId, 
    @RequestAttribute("userId") Long requesterId) {
    
    // ✅ ADD THESE VALIDATIONS
    if (userId == null || userId <= 0) {
        return ResponseEntity.badRequest()
            .body(Map.of("error", "Invalid target user ID"));
    }
    if (requesterId == null || requesterId <= 0) {
        return ResponseEntity.status(401)
            .body(Map.of("error", "Not authenticated / Invalid requester ID"));
    }
    
    try {
        followRequestService.sendFollowRequest(requesterId, userId);
        Map<String, String> resp = new HashMap<>();
        resp.put("message", "Follow request sent");
        resp.put("targetUserId", userId.toString());
        return ResponseEntity.ok(resp);
    } catch (IllegalArgumentException e) {
        return ResponseEntity.badRequest()
            .body(Map.of("error", e.getMessage()));
    } catch (Exception e) {
        System.err.println("[ERROR] sendFollowRequest failed: " + e.getMessage());
        e.printStackTrace();
        return ResponseEntity.status(500)
            .body(Map.of("error", "Server error: " + e.getMessage()));
    }
}
```

---

## SCENARIO 2: JWT Token Not Setting User ID 🔴 VERY LIKELY

### Problem
The JWT filter is not properly setting the `userId` attribute in the request, so `requesterId` is null.

### Code Path
```
HTTP Request with Bearer token
  ↓
JwtAuthenticationFilter.doFilterInternal()
  ↓
request.setAttribute("userId", userId)  ← NOT EXECUTING?
  ↓
FollowRequestController receives null requesterId → 500 Error
```

### Signs
- All follows fail with 500 error consistently
- Don't see proper error messages
- Works with other endpoints that don't use @RequestAttribute

### Fix
**Check JWT Filter Implementation:**

1. Search for JwtAuthenticationFilter:
```bash
find backend -name "*JwtAuthenticationFilter*" -o -name "*JwtFilter*"
```

2. Verify it sets userId:
```java
// Expected to find something like:
String userId = extractUserIdFromToken(token);
request.setAttribute("userId", Long.parseLong(userId));
```

3. If not found or not working, add debug logging:
```java
@Override
protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) 
    throws ServletException, IOException {
    
    try {
        String token = extractToken(request);
        if (token != null) {
            String userId = getUserIdFromToken(token);
            System.out.println("[JWT DEBUG] Token extracted, userId: " + userId);  // ← ADD THIS
            request.setAttribute("userId", Long.parseLong(userId));
            System.out.println("[JWT DEBUG] Attribute set");  // ← ADD THIS
        } else {
            System.out.println("[JWT DEBUG] No token found in request");  // ← ADD THIS
        }
    } catch (Exception e) {
        System.err.println("[JWT DEBUG] Error: " + e.getMessage());  // ← ADD THIS
        e.printStackTrace();
    }
    chain.doFilter(request, response);
}
```

---

## SCENARIO 3: BlockedUserRepository Query Failure 🟡 POSSIBLE

### Problem
The isEitherBlocked() query is syntactically correct but fails at runtime due to:
- Missing entity mapping
- Column name mismatch
- Database connection issue

### Code Review
The query looks correct:
```java
@Query("SELECT CASE WHEN COUNT(b) > 0 THEN true ELSE false END " +
       "FROM BlockedUser b " +
       "WHERE (b.blockerId = :userId1 AND b.blockedId = :userId2) " +
       "OR (b.blockerId = :userId2 AND b.blockedId = :userId1)")
boolean isEitherBlocked(@Param("userId1") Long userId1, @Param("userId2") Long userId2);
```

### Verify
1. Check BlockedUser entity has proper mappings:
```bash
grep -A 20 "class BlockedUser" backend/social-service/src/main/java/com/socialmedia/social/entity/BlockedUser.java
```

2. Should have:
```java
@Entity
@Table(name = "blocked_users")
public class BlockedUser {
    private Long blockerId;      // ← Must exist
    private Long blockedId;      // ← Must exist
    private LocalDateTime createdAt;
}
```

3. Test the method directly with curl:
```bash
# First create two test users and block one
# Then call follow-requests endpoint
curl -X POST http://localhost:8080/api/social/follow-requests/2 \
  -H "Authorization: Bearer <TOKEN_FOR_USER_1>" \
  -v
```

---

## SCENARIO 4: Missing Service Injection 🔴 CRITICAL IF TRUE

### Problem
BlockService is not properly injected into FollowRequestService.

### Code Check
**Location:** [FollowRequestService.java](backend/social-service/src/main/java/com/socialmedia/social/service/FollowRequestService.java)

```java
@Service
@RequiredArgsConstructor
public class FollowRequestService {

    private final FollowRequestRepository followRequestRepository;
    private final FollowerService followerService;
    private final UserProfileService userProfileService;
    private final NotificationService notificationService;
    private final FCMService fcmService;
    private final BlockService blockService;  // ← MUST BE HERE
    
    // ... methods ...
}
```

### If Missing
Add dependency:
```java
@Service
@RequiredArgsConstructor
public class FollowRequestService {
    
    private final BlockService blockService;  // ← ADD THIS LINE
    
    // ... copy paste all other dependencies ...
}
```

---

## SCENARIO 5: Exception Swallowing (No Error Response) 🟡 LIKELY

### Problem
The sendRequest() method throws an exception but doesn't catch it, causing Spring to return 500 with no helpful error message.

### Current Code
```java
@PostMapping("/{userId}")
public ResponseEntity<Map<String, String>> sendRequest(
    @PathVariable Long userId, 
    @RequestAttribute("userId") Long requesterId) {
    
    // NO try-catch!
    followRequestService.sendFollowRequest(requesterId, userId);
    // ...
}
```

### Fix
Wrap with proper error handling:
```java
@PostMapping("/{userId}")
public ResponseEntity<Map<String, String>> sendRequest(
    @PathVariable Long userId, 
    @RequestAttribute("userId") Long requesterId) {
    
    Map<String, String> resp = new HashMap<>();
    
    try {
        // Validate inputs first
        if (userId == null || requesterId == null) {
            resp.put("error", "Invalid user IDs");
            return ResponseEntity.badRequest().body(resp);
        }
        
        // Call service
        followRequestService.sendFollowRequest(requesterId, userId);
        
        resp.put("message", "Follow request sent");
        resp.put("targetUserId", userId.toString());
        return ResponseEntity.ok(resp);
        
    } catch (IllegalArgumentException e) {
        // Known validation errors
        resp.put("error", e.getMessage());
        return ResponseEntity.badRequest().body(resp);
        
    } catch (RuntimeException e) {
        // Unexpected errors with logging
        System.err.println("[ERROR] sendFollowRequest RuntimeException:");
        e.printStackTrace();
        
        resp.put("error", "Service error: " + e.getClass().getSimpleName());
        return ResponseEntity.status(500).body(resp);
        
    } catch (Exception e) {
        // Catch-all
        System.err.println("[ERROR] sendFollowRequest Exception:");
        e.printStackTrace();
        
        resp.put("error", "Server error");
        return ResponseEntity.status(500).body(resp);
    }
}
```

---

## DIAGNOSTIC CHECKLIST

- [ ] **Check Logs**
  ```bash
  # Look for stack traces around "follow-requests" endpoint
  tail -f backend-logs.txt | grep -i "follow\|block\|error"
  ```

- [ ] **Verify JWT**
  ```bash
  # Make a test request and check response headers/body
  curl -X POST http://localhost:8080/api/social/follow-requests/2 \
    -H "Authorization: Bearer YOUR_TOKEN" \
    -H "Content-Type: application/json" \
    -v
  ```

- [ ] **Check Database**
  ```sql
  -- Verify blocked_users table exists
  SHOW TABLES LIKE 'blocked_users';
  
  -- Verify table structure
  DESC blocked_users;
  
  -- Test the query manually
  SELECT CASE WHEN COUNT(b) > 0 THEN true ELSE false END 
  FROM blocked_users b 
  WHERE (b.blocker_id = 1 AND b.blocked_id = 2) 
  OR (b.blocker_id = 2 AND b.blocked_id = 1);
  ```

- [ ] **Test with Valid IDs**
  ```bash
  # Make sure both users exist
  curl -X GET http://localhost:8080/api/auth/user/1 \
    -H "Authorization: Bearer YOUR_TOKEN"
  
  curl -X GET http://localhost:8080/api/auth/user/2 \
    -H "Authorization: Bearer YOUR_TOKEN"
  ```

---

## QUICK FIX (Try This First)

If you can't immediately find the root cause, try this:

### 1. Add Error Handling to FollowRequestController

```java
@PostMapping("/{userId}")
@Operation(summary = "Send a follow request to a user")
@ApiResponses({
    @ApiResponse(responseCode = "200", description = "Request created"),
    @ApiResponse(responseCode = "400", description = "Invalid request"),
    @ApiResponse(responseCode = "500", description = "Server error")
})
public ResponseEntity<Map<String, Object>> sendRequest(
    @PathVariable Long userId, 
    @RequestAttribute("userId") Long requesterId) {
    
    Map<String, Object> resp = new HashMap<>();
    
    try {
        System.out.println("[FOLLOW REQUEST] Received: requester=" + requesterId + ", target=" + userId);
        
        // Input validation
        if (requesterId == null || userId == null) {
            resp.put("success", false);
            resp.put("error", "Missing user IDs");
            return ResponseEntity.badRequest().body(resp);
        }
        
        // Call service
        followRequestService.sendFollowRequest(requesterId, userId);
        
        System.out.println("[FOLLOW REQUEST] ✅ Success");
        resp.put("success", true);
        resp.put("message", "Follow request sent");
        resp.put("targetUserId", userId);
        return ResponseEntity.ok(resp);
        
    } catch (IllegalArgumentException e) {
        System.err.println("[FOLLOW REQUEST] ⚠️ Validation error: " + e.getMessage());
        resp.put("success", false);
        resp.put("error", e.getMessage());
        return ResponseEntity.badRequest().body(resp);
        
    } catch (NullPointerException e) {
        System.err.println("[FOLLOW REQUEST] ❌ NPE (Missing dependency?)");
        e.printStackTrace();
        resp.put("success", false);
        resp.put("error", "NullPointerException: Missing service dependency");
        return ResponseEntity.status(500).body(resp);
        
    } catch (Exception e) {
        System.err.println("[FOLLOW REQUEST] ❌ Unexpected error:");
        e.printStackTrace();
        resp.put("success", false);
        resp.put("error", e.getClass().getSimpleName() + ": " + e.getMessage());
        return ResponseEntity.status(500).body(resp);
    }
}
```

### 2. Add Logging to FollowRequestService

```java
@Transactional
public void sendFollowRequest(Long requesterId, Long targetId) {
    System.out.println("\n[FOLLOW REQUEST SERVICE] Starting...");
    System.out.println("  requester: " + requesterId);
    System.out.println("  target: " + targetId);
    
    try {
        System.out.println("[FOLLOW REQUEST] Checking self-follow...");
        if (requesterId.equals(targetId)) {
            throw new IllegalArgumentException("Cannot request to follow yourself");
        }
        
        System.out.println("[FOLLOW REQUEST] Checking block status...");
        if (blockService.isEitherBlocked(requesterId, targetId)) {
            throw new IllegalArgumentException("Cannot send follow request to this user");
        }
        System.out.println("[FOLLOW REQUEST] Block check passed");
        
        System.out.println("[FOLLOW REQUEST] Checking existing follow...");
        if (followerService.isFollowing(requesterId, targetId)) {
            throw new IllegalArgumentException("Already following this user");
        }
        
        System.out.println("[FOLLOW REQUEST] Checking existing request...");
        if (followRequestRepository.existsByRequesterIdAndTargetId(requesterId, targetId)) {
            throw new IllegalArgumentException("Follow request already sent");
        }
        
        System.out.println("[FOLLOW REQUEST] Creating request...");
        FollowRequest fr = new FollowRequest(requesterId, targetId);
        followRequestRepository.save(fr);
        System.out.println("[FOLLOW REQUEST] Request saved");
        
        System.out.println("[FOLLOW REQUEST] Sending notification...");
        notificationService.createNotification(targetId, "follow_request_received", requesterId, targetId, "sent you a follow request");
        fcmService.onFollowRequestReceived(targetId, requesterId);
        System.out.println("[FOLLOW REQUEST] ✅ Complete");
        
    } catch (Exception e) {
        System.err.println("[FOLLOW REQUEST] ❌ Error at step: " + e.getMessage());
        throw e;
    }
}
```

### 3. Restart and Test
```bash
# Check logs for the detailed trace
# Try the follow request again
# Look for where it fails
```

---

## EXPECTED LOG OUTPUT (When Working)

```
[FOLLOW REQUEST SERVICE] Starting...
  requester: 1
  target: 5
[FOLLOW REQUEST] Checking self-follow...
[FOLLOW REQUEST] Checking block status...
[FOLLOW REQUEST] Block check passed
[FOLLOW REQUEST] Checking existing follow...
[FOLLOW REQUEST] Checking existing request...
[FOLLOW REQUEST] Creating request...
[FOLLOW REQUEST] Request saved
[FOLLOW REQUEST] Sending notification...
[FOLLOW REQUEST] ✅ Complete
```

---

## If Still Getting 500

1. **Check application startup logs** for:
   - BeanCreationException (missing Spring Bean)
   - DataSourceInitializationException (DB connection)
   - Could not autowire field (missing @Autowired)

2. **Check database connection**:
   ```bash
   mysql -h localhost -u root -p auth_db -e "SELECT COUNT(*) FROM blocked_users;"
   ```

3. **Check for exceptions in other services**:
   - NotificationService initialization
   - FCMService initialization
   - UserProfileService initialization

4. **Enable debug logging** in application.properties:
   ```properties
   logging.level.com.socialmedia.social=DEBUG
   logging.level.org.springframework.web=DEBUG
   spring.jpa.show-sql=true
   spring.jpa.properties.hibernate.format_sql=true
   ```

---

## SUMMARY

The follow request system is **correctly implemented**. The 500 error is most likely due to:

1. ✅ **Most Likely:** JWT not setting userId attribute (null requesterId)
2. ✅ **Very Likely:** No error handling in controller (exception thrown unhandled)
3. ✅ **Possible:** BlockService not injected properly
4. ✅ **Possible:** Database connectivity issue
5. ⚠️ **Less Likely:** Query syntax error (query looks correct)

**Recommended Action:** Add the logging and error handling code above, restart, and observe where the error occurs in the logs.

