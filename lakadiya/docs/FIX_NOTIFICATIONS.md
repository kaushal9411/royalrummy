# 🔧 FIX NOTIFICATIONS - ACTION PLAN

## What Was Fixed

The notification service was trying to load Firebase credentials from a **non-existent JSON file** instead of using **environment variables**.

**Before (Broken):**
```javascript
const serviceAccount = require('../../config/firebase-adminsdk.json');
// This file doesn't exist!
```

**After (Fixed):**
```javascript
const projectId = process.env.FIREBASE_PROJECT_ID;
const clientEmail = process.env.FIREBASE_CLIENT_EMAIL;
const privateKey = process.env.FIREBASE_PRIVATE_KEY;
// Uses .env file that has Firebase credentials
```

---

## Fix Applied

✅ Updated `src/modules/notifications/notification.service.js`
- Now reads credentials from `.env` environment variables
- Better error logging
- Proper Firebase initialization

---

## What To Do NOW

### Step 1: Restart Backend
```bash
cd backend

# Press Ctrl+C to stop current backend

npm run dev
```

**Watch console for:**
```
✓ Firebase Admin SDK initialized successfully
```

If you see this → Firebase is now loaded ✓

### Step 2: Test Notification

**Get JWT:**
```bash
curl -X POST http://localhost:3001/api/auth/guest \
  -H "Content-Type: application/json"
```
Copy the `token`

**Get FCM Token:**
- Open app on phone
- Go to Profile > Device Token
- Copy token

**Send Test:**
```bash
curl -X POST http://localhost:3001/api/notifications/send-test-otp \
  -H "Authorization: Bearer JWT_HERE" \
  -H "Content-Type: application/json" \
  -d '{"otp": "123456"}'
```

**Check Phone:**
- Look for notification: "Your OTP Code"
- Should show: "OTP: 123456"
- Should have app icon

---

## If Still No Notification

Run diagnostic:

**Windows:**
```bash
cd docs
diagnose-notifications.bat
```

**Mac/Linux:**
```bash
bash docs/diagnose-notifications.sh
```

This will test each step and tell you exactly where the problem is.

---

## Common Issues & Solutions

### Issue 1: "Firebase Admin SDK initialized" NOT showing in logs

**Solution:**
Check Firebase credentials in `.env`:
```bash
grep FIREBASE backend/.env
```

Should show:
```
FIREBASE_PROJECT_ID=lakadiya-3e18a
FIREBASE_CLIENT_EMAIL=firebase-adminsdk-fbsvc@...
FIREBASE_PRIVATE_KEY=-----BEGIN PRIVATE KEY-----...
```

If missing or incomplete:
1. Open `backend/.env`
2. Copy Firebase credentials from service account
3. Paste into .env
4. Restart backend

### Issue 2: "No device token found"

**Solution:**
```bash
# Login on app first (or run guest auth)
curl -X POST http://localhost:3001/api/auth/guest

# Copy token, open app on phone
# Go to Profile > Device Token
# Copy FCM token

# Store it:
curl -X POST http://localhost:3001/api/notifications/device-token \
  -H "Authorization: Bearer JWT_HERE" \
  -H "Content-Type: application/json" \
  -d '{"fcmToken": "FCM_HERE", "deviceType": "android"}'

# Verify in database:
psql -d lakadiya -c "SELECT COUNT(*) FROM device_tokens WHERE is_active=true;"
# Should show: 1
```

### Issue 3: Notification sent but phone doesn't receive

**Solution:**
1. Check phone Settings > Apps > Lakadiya > Notifications > ON
2. Check database:
   ```sql
   SELECT status, error_msg FROM notification_logs ORDER BY sent_at DESC LIMIT 1;
   ```
3. If status="failed" → check error_msg for Firebase error
4. If status="sent" → notification reached Firebase, but phone didn't receive (app issue)

---

## Verification Checklist

- [ ] Backend running (`npm run dev`)
- [ ] See "✓ Firebase Admin SDK initialized successfully" in logs
- [ ] At least 1 device token in DB
- [ ] Notification shows status="sent" in database
- [ ] Phone has notification permission enabled
- [ ] Phone receives notification

---

## Testing Now

```bash
# 1. Restart backend
cd backend
npm run dev

# 2. Wait for "Firebase Admin SDK initialized"

# 3. In new terminal:
curl -X POST http://localhost:3001/api/auth/guest -H "Content-Type: application/json"

# 4. On phone, open app, copy FCM token from Profile > Device Token

# 5. Send test:
curl -X POST http://localhost:3001/api/notifications/send-test-otp \
  -H "Authorization: Bearer [JWT_FROM_STEP_3]" \
  -H "Content-Type: application/json" \
  -d '{"otp": "999888"}'

# 6. Check phone notification panel 📱
```

---

## Expected Result

✓ Backend logs show: "✓ OTP notification sent to user [ID]"
✓ Database shows: notification_logs with status="sent"
✓ **Phone receives notification with app icon** 🎉

---

## Next: Broadcast to All

Once single-user notifications work, broadcast is ready:

```bash
curl -X POST http://localhost:3001/api/notifications/broadcast-test \
  -H "Authorization: Bearer JWT" \
  -H "Content-Type: application/json" \
  -d '{"title":"Test","body":"Sent to all devices!"}'
```

All logged-in devices receive simultaneously! 📱📱📱

---

## Still Not Working?

See: [TROUBLESHOOTING_NOTIFICATIONS.md](TROUBLESHOOTING_NOTIFICATIONS.md)

Run diagnostic script for step-by-step debugging.

---

**Status: Ready to test! 🚀**

1. Restart backend
2. Verify Firebase loads
3. Send test notification
4. Check phone

Let me know if notifications work now! 📱✅
