# Complete FCM Token Save Diagnostic

## The Problem
Flutter app rebuilt but token still not saved to database.

## Step 1: Check if Flutter Generated Token
Run Flutter app and check logs:

```bash
cd "C:\Users\VAMSI KRISHNA\Desktop\PROJECTS\INTERNSHIP\Mobile App Development\social-media-mobile"
flutter clean
flutter pub get
flutter run
```

**LOOK FOR THESE LOGS:**
```
[FCM] 🔄 Initializing Firebase...
[FCM] ✅ Firebase initialized
[FCM] 🔑 Getting FCM token...
[FCM] 🔑 FCM Token: <some_long_token>
```

If you DON'T see these logs:
- Firebase is not initializing
- Check `firebase_options.dart` for correct API keys
- Check `google-services.json` in android folder

---

## Step 2: Check if API Call was Made

**LOOK FOR THESE LOGS:**
```
[API] 🔄 Saving FCM token to backend for user 3...
[API] ✅ FCM token saved successfully
```

OR (if failed):
```
[API] ℹ️ Not authenticated, skipping FCM token save
[API] ❌ Cannot determine user ID for FCM token save
[API] ⚠️ Failed to save FCM token: <error>
```

If you DON'T see the "Saving FCM token" log:
- Firebase token not being generated
- `_getFCMTokenAndSync()` not being called
- Check if `FirebaseMessagingService.initializeFirebase()` is called in main.dart

---

## Step 3: Verify Backend Endpoint is Accessible

```bash
# Test the endpoint directly
curl -X POST http://localhost:8081/users/3/fcm-token \
  -H "Content-Type: application/json" \
  -d "{\"fcmToken\": \"test-token-xyz\"}"
```

Expected response:
```json
{"message": "FCM token saved successfully"}
```

If you get 401/403:
- Authentication issue
- Need JWT token in Authorization header

---

## Step 4: Check Database

```bash
mysql -u root -p
USE auth_db;
SELECT user_id, username, fcm_token FROM users WHERE user_id IN (2, 3);
```

Expected result (BEFORE fix):
```
| 2 | sai   | NULL |
| 3 | vamsi | NULL |
```

Expected result (AFTER fix):
```
| 2 | sai   | dz...xA |
| 3 | vamsi | fK...bC |
```

If still NULL → token not being saved

---

## Root Cause Analysis

### If you see "[FCM] 🔑 FCM Token: exxx...xxx" BUT NO API logs:

**Problem:** `_getFCMTokenAndSync()` is not calling `ApiService.saveFCMToken()`

**Solution:** 
1. Check line 318 in firebase_messaging_service.dart
2. Should have: `await ApiService.saveFCMToken(token);`
3. Rebuild with `flutter clean && flutter pub get && flutter run`

---

### If you see API logs saying "Failed to save FCM token":

**Check the error message:**

If error is "Cannot determine user ID":
- Problem: `getUserId()` returning null
- Solution: User might not be authenticated
- Fix: Login first, then wait 2 seconds for Firebase init

If error is "Connection refused":
- Problem: auth-service not running on 8081
- Solution: Start backend: `.\start-all-services.bat`

If error is "401 Unauthorized":
- Problem: JWT token expired
- Solution: Logout and login again

---

### If you don't see ANY logs (nothing about FCM):

**Problem:** Firebase is not initializing

**Solution:**
1. Check `lib/main.dart` - should have:
   ```dart
   await FirebaseMessagingService.initializeFirebase();
   ```
2. Check `firebase_options.dart` exists
3. Check `android/app/google-services.json` exists
4. Rebuild: `flutter clean && flutter pub get && flutter run`

---

## Complete Debug Checklist

```
☐ 1. Run: flutter clean && flutter pub get
☐ 2. Run: flutter run
☐ 3. Look for: [FCM] 🔑 FCM Token: 
☐ 4. Look for: [API] 🔄 Saving FCM token
☐ 5. Look for: [API] ✅ FCM token saved successfully
☐ 6. Check DB: SELECT * FROM users WHERE fcm_token IS NOT NULL
☐ 7. Result should show 2 tokens (user 2 and 3)
☐ 8. Then follow a user and check push notification
```

---

## If Everything Fails

**Nuclear Option - Complete Reset:**

### Backend:
```bash
cd backend
mvn clean install
.\start-all-services.bat
```

### Frontend:
```bash
cd social-media-mobile
flutter clean
flutter pub get
flutter pub cache repair
flutter run
```

### Database (reset tokens):
```sql
USE auth_db;
UPDATE users SET fcm_token = NULL;
SELECT * FROM users;
```

Then app will regenerate tokens on restart.

---

## What Logs to Share

When you run the app, capture and share:
1. First 10 lines mentioning "FCM" or "Firebase"
2. Any "API" logs mentioning "fcm-token"
3. Any error logs
4. Result of: `SELECT user_id, fcm_token FROM users WHERE user_id IN (2,3);`
