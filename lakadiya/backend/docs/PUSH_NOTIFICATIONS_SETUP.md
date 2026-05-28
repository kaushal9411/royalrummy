# Push Notifications with Device Token Storage

Complete guide to send push notifications to device tokens stored in PostgreSQL database.

## Architecture Overview

```
Mobile App                Backend API              Firebase Cloud
   ↓                          ↓                      Messaging
   ├─ Login/Signup            ├─ Store               ├─ Send OTP
   ├─ Get FCM Token       token in DB       →       notification
   ├─ Send to /                                      ├─ Send generic
     notifications/        ├─ On OTP request        notification
     device-token         │                         ├─ Store logs
                          ├─ Fetch token from DB    └─ Return status
                          ├─ Send via FCM
                          └─ Log notification
                              ↓
                        Mobile Device
                        (Notification Panel)
```

---

## Backend Setup

### 1. Database Migration

Run the migration to add device token tables:

```bash
cd backend
npm run migrate
```

This creates:
- `device_tokens` table — stores FCM tokens per user
- `notification_logs` table — audit trail of sent notifications

### 2. Environment Variables

Add to `.env`:

```env
# Firebase Admin SDK credentials
FIREBASE_PROJECT_ID=lakadiya-3e18a
FIREBASE_CREDENTIALS_PATH=./path/to/firebase-adminsdk-key.json

# Notification settings
NOTIFICATION_ENABLED=true
NOTIFICATION_TTL=3600  # 1 hour
```

### 3. Install Dependencies

```bash
npm install firebase-admin
```

Already in `package.json`.

---

## API Endpoints

### Store Device Token
**POST** `/api/notifications/device-token`

Called after user logs in. Stores FCM token in database.

**Headers:**
```
Authorization: Bearer {JWT_TOKEN}
Content-Type: application/json
```

**Body:**
```json
{
  "fcmToken": "f5_9AwGbwXs:APA91bFxyz...",
  "deviceType": "android"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Device token stored successfully",
  "fcmToken": "f5_9AwGbwXs:APA91b..."
}
```

---

### Send Test OTP
**POST** `/api/notifications/send-test-otp`

Send OTP notification to user's stored device token.

**Headers:**
```
Authorization: Bearer {JWT_TOKEN}
Content-Type: application/json
```

**Body:**
```json
{
  "otp": "123456"
}
```

**Response:**
```json
{
  "success": true,
  "message": "OTP notification sent",
  "messageId": "projects/lakadiya-3e18a/messages/1234567890"
}
```

---

### Get Notification Logs
**GET** `/api/notifications/logs?limit=20`

Fetch notification history for authenticated user.

**Headers:**
```
Authorization: Bearer {JWT_TOKEN}
```

**Response:**
```json
{
  "success": true,
  "logs": [
    {
      "id": "uuid",
      "title": "Your OTP Code",
      "body": "OTP: 123456",
      "status": "sent",
      "sent_at": "2024-05-28T08:30:00Z"
    }
  ],
  "count": 1
}
```

---

## Mobile App Integration

### 1. Store FCM Token on Login

The app automatically stores the FCM token after successful login/signup via:

```dart
// Automatically called after login
NotificationRepository(apiService).storeDeviceToken(fcmToken)
```

### 2. Send Device Token to Backend

**Endpoint:** `POST /api/notifications/device-token`

**Called:** After authentication (login/signup)

**Data:**
```dart
{
  "fcmToken": FcmService.instance.token,
  "deviceType": "android"  // or "ios"
}
```

### 3. Receive OTP Notification

When backend sends OTP via FCM:

1. Mobile receives notification
2. FcmService auto-extracts OTP
3. Notification shows in device notification panel
4. OTP auto-fills in login screen (if stream listener attached)

---

## Testing Flow

### Step 1: Get Device Token

**On Mobile:**
- Open app
- Go to Profile → Device Token
- Copy the full token

### Step 2: Login to Get JWT Token

**Backend:**
```bash
curl -X POST http://localhost:3001/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "mobile": "+919876543210",
    "otp": "123456"
  }'
```

**Response:**
```json
{
  "token": "eyJhbGciOiJIUzI1NiIs...",
  "user": {...}
}
```

Copy the `token` value.

### Step 3: Store Device Token

**Run:**
```bash
# Windows
test-backend-notifications.bat

# Mac/Linux
bash test-backend-notifications.sh
```

Or use curl:

```bash
curl -X POST http://localhost:3001/api/notifications/device-token \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -d '{
    "fcmToken": "YOUR_FCM_TOKEN",
    "deviceType": "android"
  }'
```

### Step 4: Send Test OTP

```bash
curl -X POST http://localhost:3001/api/notifications/send-test-otp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -d '{"otp": "654321"}'
```

### Step 5: Verify on Device

- Check notification panel on phone
- You should see: **"Your OTP Code"** with **"OTP: 654321"**
- Notification has app icon
- Sound and vibration play

---

## Production Usage

### 1. On User Registration/Login

Call from mobile app:

```dart
// After successful login
if (fcmToken != null) {
  await NotificationRepository(apiService)
    .storeDeviceToken(fcmToken);
}
```

### 2. Send OTP on Request

Backend controller:

```javascript
const { sendOtpNotification } = require('../notifications/notification.service');

// When user requests OTP
const otp = generateOtp();
const result = await sendOtpNotification(userId, otp);

if (!result.success) {
  // Fallback to SMS or email
}
```

### 3. Send General Notifications

```javascript
const { sendNotification } = require('../notifications/notification.service');

// Send game invitation, match result, etc.
await sendNotification(userId, 'Match Started', 'Join your room now', {
  roomId: 'room-123',
  type: 'match_start'
});
```

---

## Troubleshooting

### ❌ Error: "No device token found"

**Cause:** User hasn't called `/notifications/device-token` endpoint after login.

**Fix:** Ensure mobile app stores token after authentication.

### ❌ Error: "Invalid registration token"

**Cause:** FCM token is expired or invalid.

**Fix:** Token should be refreshed automatically. If persists, clear app data and re-login.

### ❌ Notification not received

**Checklist:**
- [ ] Device token stored in database (check `device_tokens` table)
- [ ] App has notification permission on device
- [ ] Firebase credentials file is valid
- [ ] Network can reach Firebase
- [ ] Device has active network connection

### ❌ Error: "Authentication failed"

**Cause:** JWT token is invalid or expired.

**Fix:** Get fresh token by logging in again.

---

## Database Queries

### Check stored device tokens:

```sql
SELECT id, user_id, fcm_token, device_type, is_active, last_used 
FROM device_tokens 
WHERE is_active = true 
ORDER BY last_used DESC;
```

### Check notification logs:

```sql
SELECT id, user_id, title, status, sent_at, error_msg 
FROM notification_logs 
ORDER BY sent_at DESC 
LIMIT 50;
```

### Find user's device tokens:

```sql
SELECT * FROM device_tokens 
WHERE user_id = '78c0379d-e09a-4cbb-9144-0c051838c54f' 
AND is_active = true;
```

---

## Files Created

Backend:
- `src/modules/notifications/notification.service.js` — FCM sender logic
- `src/modules/notifications/notification.controller.js` — API handlers
- `src/modules/notifications/notification.routes.js` — Route definitions
- `database/migrations/007_add_device_tokens.sql` — Database tables
- `docs/test-backend-notifications.bat` — Windows test script
- `docs/test-backend-notifications.sh` — Unix test script

Mobile:
- `lib/features/notifications/data/repositories/notification_repository.dart` — API client
- `lib/core/services/fcm_service.dart` — Updated with notification handling

---

## Next Steps

1. ✅ Run database migration
2. ✅ Add Firebase credentials file
3. ✅ Restart backend server
4. ✅ Test with `test-backend-notifications.bat` or `.sh`
5. ✅ Integrate into login flow (already in main.dart)
6. ✅ Deploy to production

Done! 🎉
