# Push Notifications - Quick Start (5 Minutes)

## What to Do Now

### 1. Backend Setup (1 min)

```bash
cd backend

# Run migration to create tables
npm run migrate

# Restart backend
npm run dev
```

### 2. Mobile (0 min - already done!)

App automatically:
- Initializes Firebase on startup
- Gets FCM device token
- Stores token in backend after login
- Shows notifications with app icon

### 3. Test It (4 min)

**Option A: Windows Batch (Easiest)**
```bash
cd backend/docs
test-backend-notifications.bat
```

**Option B: Manual curl**

Step 1 - Get JWT token:
```bash
curl -X POST http://localhost:3001/api/auth/guest \
  -H "Content-Type: application/json"

# Copy the "token" value
```

Step 2 - Store device token:
```bash
# Get FCM token from: App → Profile → Device Token

curl -X POST http://localhost:3001/api/notifications/device-token \
  -H "Authorization: Bearer JWT_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{"fcmToken": "FCM_TOKEN_HERE", "deviceType": "android"}'
```

Step 3 - Send test OTP:
```bash
curl -X POST http://localhost:3001/api/notifications/send-test-otp \
  -H "Authorization: Bearer JWT_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{"otp": "123456"}'
```

Step 4 - Check phone:
- Look at notification panel
- Should see: **"Your OTP Code"** with **"OTP: 123456"**

✅ Done!

---

## Real-World Flow

When user logs in:

1. Mobile app runs `FcmService.init()`
2. Gets FCM device token
3. Calls `POST /notifications/device-token`
4. Backend stores in `device_tokens` table

When user requests OTP:

1. Mobile: `POST /auth/otp/send`
2. Backend: Generates OTP → Calls `sendOtpNotification(userId, otp)`
3. Service fetches FCM token from DB
4. Sends via Firebase
5. Mobile receives notification with OTP
6. Shows in notification panel

---

## Files to Know

### Backend
- `src/modules/notifications/notification.service.js` — Does the sending
- `database/migrations/007_add_device_tokens.sql` — Database tables

### Mobile
- `lib/core/services/fcm_service.dart` — Receives notifications
- `lib/features/notifications/` — API integration

---

## Verify It Works

Check database:
```sql
-- Device tokens stored?
SELECT * FROM device_tokens WHERE is_active = true;

-- Notification logs?
SELECT * FROM notification_logs ORDER BY sent_at DESC LIMIT 5;
```

Check backend logs:
```bash
# Running backend should show:
[Notification] Device token stored: true
[Notification] Test OTP sent: true
```

Check mobile logs:
```
In Flutter console:
[Notification] Device token stored: true
Foreground FCM message: Your OTP Code
```

---

## Troubleshooting (2 min)

### ❌ "No device token found"
→ Make sure you called the device-token endpoint

### ❌ "Authentication failed"  
→ JWT token expired, login again

### ❌ Notification not visible
→ Check phone Settings → Apps → Lakadiya → Notifications → ON

### ❌ Backend won't start
→ Run: `npx kill-port 3001` then `npm run dev`

---

## Production Checklist

- [ ] Firebase credentials added to production server
- [ ] Run `npm run migrate` on production DB
- [ ] Test with real OTP on production
- [ ] Monitor `notification_logs` table for failures
- [ ] Deploy mobile app update

---

## That's It! 🎉

Notifications are fully integrated. Users will now receive OTP as push notifications with app icon.
