# Push Notifications Integration - Complete Summary

## What Was Implemented

### Backend (Node.js + PostgreSQL)

1. **Database Tables** (Migration 007)
   - `device_tokens` — stores FCM tokens per user
   - `notification_logs` — audit trail of sent notifications

2. **Notification Service** (`src/modules/notifications/notification.service.js`)
   - `sendOtpNotification(userId, otp)` — Send OTP to device
   - `sendNotification(userId, title, body, data)` — Send generic notification
   - `sendNotificationToMultiple(userIds, ...)` — Bulk notifications

3. **API Endpoints**
   - `POST /api/notifications/device-token` — Store FCM token (called after login)
   - `POST /api/notifications/send-test-otp` — Send test OTP
   - `GET /api/notifications/logs` — Fetch notification history

4. **Updated OTP Flow**
   - When user requests OTP, backend now sends via Firebase instead of just SMS
   - Fallback to SMS if configured, else use Firebase push

### Mobile (Flutter)

1. **FcmService Enhanced** (`lib/core/services/fcm_service.dart`)
   - Shows notification with app icon on device
   - Auto-extracts OTP from notification
   - Logs all received notifications
   - Handles both foreground and background messages

2. **NotificationRepository** (`lib/features/notifications/data/repositories/notification_repository.dart`)
   - API client for backend notification endpoints
   - `storeDeviceToken()` — called after login
   - `sendTestOtp()` — development testing
   - `getNotificationLogs()` — fetch history

3. **Auto-Setup** (`lib/main.dart`)
   - After Firebase init, automatically stores device token
   - Runs after first app launch

---

## How It Works (Complete Flow)

### 1. User Logs In
```
Mobile App
  ├─ User enters phone + OTP
  └─ POST /auth/login
     └─ Backend validates OTP
        └─ Returns JWT token
        
Mobile App (main.dart)
  ├─ Firebase initialized
  ├─ FcmService gets FCM token
  └─ POST /api/notifications/device-token
     └─ Backend stores FCM token in DB
```

### 2. User Requests OTP (Login Flow)
```
Mobile App
  └─ POST /auth/otp/send
     └─ Backend receives request with mobile + deviceToken
        ├─ Generates 6-digit OTP
        ├─ Query user_id from mobile
        └─ Call sendOtpNotification(userId, otp)
           ├─ Fetch FCM token from device_tokens table
           ├─ Send via Firebase Admin SDK
           ├─ Log in notification_logs table
           └─ Return status
           
Mobile App
  └─ Receives notification
     ├─ Shows in notification panel
     ├─ Auto-extracts OTP
     └─ Fills OTP in login screen
```

### 3. Testing Without Frontend
```
You (via curl)
  ├─ Get JWT token from login
  ├─ Get FCM device token from app
  └─ POST /api/notifications/send-test-otp
     └─ Same as step 2
```

---

## How to Test

### Quick Test (Windows)

1. **Start Backend**
   ```bash
   cd backend
   npm run dev
   ```

2. **Run Database Migration**
   ```bash
   npm run migrate
   ```

3. **Test Script**
   ```bash
   docs/test-backend-notifications.bat
   ```
   
   Edit these in the script:
   - `JWT_TOKEN=your_token_from_login`
   - `DEVICE_TOKEN=your_fcm_token_from_app`

### Manual Testing (curl)

```bash
# 1. Login
curl -X POST http://localhost:3001/api/auth/guest \
  -H "Content-Type: application/json"

# Extract "token" from response

# 2. Store device token
curl -X POST http://localhost:3001/api/notifications/device-token \
  -H "Authorization: Bearer TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{"fcmToken": "FCM_TOKEN_HERE", "deviceType": "android"}'

# 3. Send test OTP
curl -X POST http://localhost:3001/api/notifications/send-test-otp \
  -H "Authorization: Bearer TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{"otp": "654321"}'

# 4. Check logs
curl -X GET "http://localhost:3001/api/notifications/logs?limit=10" \
  -H "Authorization: Bearer TOKEN_HERE"
```

---

## Files Changed/Created

### Backend
```
backend/
├── src/
│   ├── app.js (updated - added notification routes)
│   ├── modules/
│   │   ├── auth/
│   │   │   └── otp.service.js (updated - now uses notification service)
│   │   └── notifications/ (NEW)
│   │       ├── notification.service.js (FCM sender)
│   │       ├── notification.controller.js (API handlers)
│   │       └── notification.routes.js (routes)
│   └── config/
│       └── database.js (updated - pool connection)
├── database/
│   └── migrations/
│       └── 007_add_device_tokens.sql (NEW)
└── docs/
    ├── PUSH_NOTIFICATIONS_SETUP.md (NEW - full guide)
    ├── test-backend-notifications.bat (NEW)
    └── test-backend-notifications.sh (NEW)
```

### Mobile
```
mobile/
├── lib/
│   ├── main.dart (updated - auto-store device token)
│   ├── core/
│   │   └── services/
│   │       └── fcm_service.dart (updated - notification display)
│   └── features/
│       └── notifications/ (NEW)
│           └── data/
│               └── repositories/
│                   └── notification_repository.dart (API client)
└── pubspec.yaml (updated - added flutter_local_notifications)
```

---

## Database Schema

### device_tokens
```sql
id            UUID PRIMARY KEY
user_id       UUID FOREIGN KEY → users(id)
fcm_token     VARCHAR(500) UNIQUE
device_type   VARCHAR(20)  -- android | ios | web
is_active     BOOLEAN      -- TRUE for active tokens
last_used     TIMESTAMPTZ
created_at    TIMESTAMPTZ
updated_at    TIMESTAMPTZ
```

### notification_logs
```sql
id          UUID PRIMARY KEY
user_id     UUID FOREIGN KEY → users(id)
fcm_token   VARCHAR(500)
title       VARCHAR(255)
body        TEXT
data        JSONB  -- any custom data
status      VARCHAR(20)  -- sent | failed | pending
error_msg   TEXT
sent_at     TIMESTAMPTZ
```

---

## Key Features

✅ **Automatic Token Storage** — After login, FCM token is automatically sent to backend

✅ **OTP via Push** — OTP is sent as push notification instead of just SMS

✅ **Rich Notifications** — Shows app icon, sound, vibration, colors

✅ **Audit Trail** — All notifications logged in database

✅ **Fallback Support** — If Firebase fails, falls back to SMS (if configured)

✅ **Multi-Device** — Stores multiple tokens per user (for switching devices)

✅ **Easy Testing** — Test scripts provided for quick validation

---

## Troubleshooting

### No Notification Received

**Check 1:** Is device token stored?
```sql
SELECT * FROM device_tokens WHERE is_active = true;
```

**Check 2:** Are Firebase credentials valid?
- Check `notification-server.js` can load credentials

**Check 3:** Device permission?
- Go to phone Settings → Apps → Lakadiya → Notifications → ON

**Check 4:** Backend logs?
```bash
# Watch backend logs
npm run dev
# Look for: "[Notification] Device token stored" or errors
```

### Backend Won't Start

```bash
# Check port is free
npx kill-port 3001

# Run migration
npm run migrate

# Start again
npm run dev
```

### Token Mismatch Error

- Token from app must match exactly
- Copy full token (it's long, ~160 characters)
- No extra spaces or line breaks

---

## Next: Production Deployment

1. Copy Firebase Admin SDK credentials to production server
2. Run migrations on production database
3. Restart backend server
4. Deploy updated mobile app
5. Monitor notification logs for failures

---

## Architecture Decision

- **Why FCM instead of Stripe/Twilio?** Firebase included in app already, cost-free tier
- **Why store tokens in DB?** Track active devices, audit trail, segment notifications
- **Why notification logs?** Debug delivery issues, compliance, analytics

Done! 🎉
