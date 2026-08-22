# Push Notification Flow Debugging Guide

## Step 1: Check if Flutter App is Generating FCM Token
Run this command to see Flutter logs:
```bash
cd "C:\Users\VAMSI KRISHNA\Desktop\PROJECTS\INTERNSHIP\Mobile App Development\social-media-mobile"
flutter logs
```

Look for these log messages:
- `[FCM] 🔑 Getting FCM token...`
- `[FCM] 🔑 FCM Token: <token_string>`
- `[API] 🔄 Saving FCM token to backend for user <userId>...`
- `[API] ✅ FCM token saved successfully`

If you don't see these logs, Firebase is not initialized properly.

---

## Step 2: Verify Token is Being Saved to Backend

Check the auth-service database for the fcm_token field:

```sql
SELECT user_id, username, fcm_token FROM users WHERE user_id IN (2, 3);
```

Expected output:
```
user_id | username | fcm_token
--------|----------|----------------------------------
2       | sai      | <some long token string>
3       | vamsi    | <some long token string>
```

If fcm_token is NULL for both users, the API call is failing.

---

## Step 3: Test FCM Token Save Endpoint Directly

Use Postman or curl to test manually:

```bash
curl -X POST http://localhost:8081/users/3/fcm-token \
  -H "Authorization: Bearer <your_jwt_token>" \
  -H "Content-Type: application/json" \
  -d '{"fcmToken":"test-token-12345"}'
```

Expected response:
```json
{"message": "FCM token saved successfully"}
```

---

## Step 4: Trace the Complete Follow Flow

1. **User 2 clicks follow on User 3:**
   ```
   POST /followers/3 (user 2 following)
   ↓
   FollowerController.followUser() 
   ↓
   fcmService.onUserFollowed(userId=3, followerId=2)
   ↓
   getUserUsername(2) → auth-service GET /users/2/username → "sai"
   ↓
   getFCMToken(3) → auth-service GET /users/3/fcm-token → NULL or token?
   ↓
   sendNotificationToToken() → Firebase Admin SDK sends push
   ```

2. **Check backend logs:**
   - Should see: `[FCM] ✅ Follow notification sent to user 3`
   - If token is NULL: `[FCM] ⚠️ No FCM token for user 3`

---

## Step 5: Verify Firebase Admin SDK is Initialized

Check social-service startup logs for:
```
[Firebase] ✅ Firebase Admin SDK initialized successfully
```

If you see:
```
[Firebase] ⚠️ FIREBASE_KEY_PATH environment variable not set
```

Then Firebase push notifications are disabled!

**To fix:** Set environment variable:
```bash
SET FIREBASE_KEY_PATH=C:\path\to\serviceAccountKey.json
```

---

## Common Issues & Solutions

### Issue 1: FCM Token Not Being Generated
- **Cause:** Firebase not initialized in Flutter
- **Fix:** Check that `firebase_options.dart` has correct API keys
- **Test:** Look for `[FCM] ✅ Firebase initialized` in Flutter logs

### Issue 2: API Call Failing (401/403)
- **Cause:** JWT token invalid or permissions denied
- **Fix:** Verify user is authenticated before calling saveFCMToken()
- **Test:** Check `[API] ℹ️ Not authenticated, skipping FCM token save` in logs

### Issue 3: Endpoint Returns 404
- **Cause:** Incorrect endpoint path
- **Current endpoint:** `POST /users/{userId}/fcm-token`
- **Flutter should call:** `POST http://localhost:8081/users/{userId}/fcm-token`
- **Not:** `POST /users/fcm-token`

### Issue 4: Firebase Service Account Key Missing
- **Cause:** FIREBASE_KEY_PATH env variable not set
- **Fix:** Get key from Firebase Console:
  1. Go to Firebase Project → Settings → Service Accounts
  2. Click "Generate New Private Key"
  3. Save as `serviceAccountKey.json`
  4. Set `FIREBASE_KEY_PATH` to point to it

### Issue 5: Token Saved But Push Not Received
- **Cause:** Firebase Admin SDK not initialized properly
- **Fix:** 
  1. Verify serviceAccountKey.json is valid
  2. Restart backend services
  3. Check for Firebase initialization errors in startup logs

---

## Quick Test Procedure

1. **Clear app data:**
   ```bash
   flutter run --clean-build
   ```

2. **Check Flutter logs in real-time:**
   ```bash
   flutter logs | grep -i "fcm\|firebase\|api"
   ```

3. **Follow a user and capture logs**

4. **Check database:**
   ```sql
   SELECT * FROM users WHERE user_id IN (2, 3);
   ```

5. **If token is saved, test Firebase push manually from console**

---

## Expected Full Flow When Working

```
User 2 clicks Follow on User 3:
  ✅ POST /followers/3 succeeds
  ✅ In-app notification sent via WebSocket
  ✅ FCMService.onUserFollowed() called
  ✅ Username fetched: "sai"
  ✅ FCM Token fetched: "exxx...xxx" (not null)
  ✅ Firebase push notification sent
  ✅ Device receives notification (even if app is closed)
  ✅ Notification shown on device
  ✅ User taps notification → App opens
```

Currently stuck at:
```
❌ FCM Token fetched: NULL (Response 204)
❌ Firebase push skipped
❌ No notification sent
```
