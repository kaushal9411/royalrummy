# ❌ Notifications Not Working? Troubleshooting Guide

## Quick Diagnostic

**Windows:**
```bash
cd docs
diagnose-notifications.bat
```

**Mac/Linux:**
```bash
bash docs/diagnose-notifications.sh
```

This will test:
✓ Backend running
✓ JWT authentication
✓ Device token storage
✓ Notification sending
✓ Database logging

---

## Step-by-Step Troubleshooting

### 1. Backend Server Issues

**Check if backend is running:**
```bash
curl http://localhost:3001/health

# Expected response:
# {"status":"ok","uptime":123.45}
```

**If not running:**
```bash
cd backend
npm run dev
```

**Check Firebase credentials in logs:**
```
// Look for in console:
[Firebase] Admin SDK initialised
// OR
✗ Firebase initialization failed
```

If Firebase failed, go to Step 2 →

---

### 2. Firebase Credentials Not Loaded

**Check .env file:**
```bash
cat backend/.env | grep FIREBASE
```

**Must see:**
```
FIREBASE_PROJECT_ID=lakadiya-3e18a
FIREBASE_CLIENT_EMAIL=firebase-adminsdk-fbsvc@lakadiya-3e18a...
FIREBASE_PRIVATE_KEY=-----BEGIN PRIVATE KEY-----\n...
```

**If missing or incomplete:**
1. Open `backend/.env`
2. Fill in Firebase credentials from service account key
3. Restart backend: `npm run dev`

---

### 3. Device Token Not Stored

**Login and check database:**

```sql
SELECT * FROM device_tokens WHERE is_active = true;

-- Should show at least 1 row with:
-- user_id | fcm_token | device_type | is_active
```

**If empty:**
1. Open app on phone
2. Go to Profile > Device Token
3. Copy the token
4. Call API:
```bash
curl -X POST http://localhost:3001/api/notifications/device-token \
  -H "Authorization: Bearer JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"fcmToken": "YOUR_FCM_TOKEN", "deviceType": "android"}'
```

**If still not stored:**
- Check JWT token is valid (not expired)
- Check backend error logs
- Check database connection

---

### 4. Notification Sent But Not Received on Phone

**Check notification_logs table:**
```sql
SELECT * FROM notification_logs ORDER BY sent_at DESC LIMIT 5;

-- Look at "status" column:
-- ✓ "sent" = Firebase received it
-- ✗ "failed" = Error sending to Firebase
```

**If status is "failed":**
- Check error_msg column for Firebase error
- Common errors:
  - "Invalid registration token" → token expired, re-login on app
  - "Authentication error" → Firebase credentials invalid
  - "Message rate exceeded" → Too many messages sent

**If status is "sent" but no notification on phone:**
1. **Check phone notification settings:**
   - Settings > Apps > Lakadiya > Notifications > ON
   - Settings > Notifications > Lakadiya > Allow notifications

2. **Check app is properly receiving Firebase:**
   - Open app > look at Flutter console for:
   ```
   ==================================================
   FCM DEVICE TOKEN: f5_9AwGbwXs:APA91b...
   ==================================================
   ```
   - If no token, Firebase not initialized

3. **Check notification channel on device:**
   - Android: Settings > Notifications > App notifications > Lakadiya > otp_channel
   - Should be enabled with sound on

---

### 5. Flutter App Not Receiving FCM Token

**Check main.dart initialization:**
```dart
// Should see in Flutter console:
[Main] Error storing device token: $e
// OR
✓ Device token stored: true
```

**If error:**
1. Check Flutter logs for detailed error
2. Ensure backend is running
3. Ensure JWT token is valid
4. Restart app

---

### 6. Verify Database Tables Exist

```sql
-- Check device_tokens table
\dt device_tokens

-- Check notification_logs table
\dt notification_logs

-- If tables don't exist, run migration:
-- npm run migrate
```

---

## Complete Test Workflow

### Phase 1: Setup
```bash
# 1. Start backend
cd backend
npm run dev

# 2. In another terminal, run migration
npm run migrate

# 3. Verify Firebase initialized
# Look for: [Firebase] Admin SDK initialised
```

### Phase 2: Get Tokens
```bash
# 1. Get JWT from backend
curl -X POST http://localhost:3001/api/auth/guest \
  -H "Content-Type: application/json"
# Copy "token" value

# 2. Open app on phone
# Go to Profile > Device Token
# Copy the FCM token
```

### Phase 3: Send Notification
```bash
# Store device token
curl -X POST http://localhost:3001/api/notifications/device-token \
  -H "Authorization: Bearer JWT_HERE" \
  -H "Content-Type: application/json" \
  -d '{"fcmToken": "FCM_HERE", "deviceType": "android"}'

# Send OTP
curl -X POST http://localhost:3001/api/notifications/send-test-otp \
  -H "Authorization: Bearer JWT_HERE" \
  -H "Content-Type: application/json" \
  -d '{"otp": "123456"}'
```

### Phase 4: Verify
```sql
-- Check token stored
SELECT * FROM device_tokens WHERE is_active = true;

-- Check notification sent
SELECT * FROM notification_logs ORDER BY sent_at DESC LIMIT 1;

-- Check status
-- If "sent" → notification was queued to Firebase
-- If "failed" → error sending to Firebase
```

---

## Most Common Issues & Fixes

| Issue | Solution |
|-------|----------|
| Firebase not initialized | Fill .env with Firebase credentials, restart backend |
| No device token found | Open app, go to Profile > Device Token, store in DB |
| "Invalid registration token" | Token expired, re-login on app |
| Notification sent but not received | Check phone notification settings, enable notifications |
| Backend won't start | Check port 3001 free: `npx kill-port 3001` |
| Database error | Run migration: `npm run migrate` |
| JWT token expired | Get fresh token from `/api/auth/guest` |
| FCM token invalid | Make sure you copied full token, no spaces |

---

## Debug Logs to Check

### Backend Console
```
✓ Firebase Admin SDK initialized
✓ OTP notification sent to user [ID]: [MESSAGE_ID]
✓ Device token stored for user [ID]
```

### Flutter Console
```
==================================================
FCM DEVICE TOKEN: [TOKEN]
==================================================
[Notification] Device token stored: true
Foreground FCM message: Your OTP Code
```

### Database Logs
```sql
SELECT status, COUNT(*) FROM notification_logs GROUP BY status;

-- Should see mostly "sent", few "failed"
```

---

## Firebase Console Verification

1. Go to https://console.firebase.google.com
2. Select project: lakadiya-3e18a
3. Click Messaging (left sidebar)
4. View message history
5. Check delivery status

---

## Still Not Working?

Create ticket with:
1. ✓ Backend console output (npm run dev)
2. ✓ Flutter console output
3. ✓ Database queries results
4. ✓ Steps you've taken
5. ✓ Error messages (full text)

---

## Quick Reference

```bash
# Reset everything
cd backend
npm run migrate              # Recreate tables
npm run dev                 # Start fresh

# On phone: Re-login to store new token

# Test again:
curl -X POST http://localhost:3001/api/notifications/send-test-otp \
  -H "Authorization: Bearer JWT" \
  -H "Content-Type: application/json" \
  -d '{"otp": "654321"}'
```

Good luck! 📱✅
