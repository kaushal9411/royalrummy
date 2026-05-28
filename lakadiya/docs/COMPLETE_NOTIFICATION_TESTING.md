# Complete Notification Testing Guide

## Scenario 1: Send to Single User

**Endpoint:** `POST /api/notifications/send-test-otp`

```bash
curl -X POST http://localhost:3001/api/notifications/send-test-otp \
  -H "Authorization: Bearer JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"otp": "123456"}'
```

**Result:**
- Notification sent only to authenticated user
- Shows in their device notification panel

---

## Scenario 2: Send to All Connected Devices

**Endpoint:** `POST /api/notifications/broadcast-test`

```bash
curl -X POST http://localhost:3001/api/notifications/broadcast-test \
  -H "Authorization: Bearer JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Important Announcement",
    "body": "New game room available!"
  }'
```

**Result:**
```json
{
  "success": true,
  "totalDevices": 5,
  "sent": 5,
  "failed": 0
}
```

All 5 devices receive the notification simultaneously!

---

## Complete Test Workflow

### Phase 1: Setup (First Time Only)

```bash
# 1. Start backend
cd backend
npm run dev

# 2. Run database migration
npm run migrate

# 3. In another terminal, verify backend is running
curl http://localhost:3001/health
# Expected: {"status":"ok","uptime":123.45}
```

### Phase 2: Login Multiple Devices

**Device 1:**
```bash
# Get JWT token
curl -X POST http://localhost:3001/api/auth/guest \
  -H "Content-Type: application/json"

# Copy token and fcmToken from response
TOKEN_1="eyJhbGc..."
FCM_1="f5_9AwGb..."

# Store device token
curl -X POST http://localhost:3001/api/notifications/device-token \
  -H "Authorization: Bearer $TOKEN_1" \
  -H "Content-Type: application/json" \
  -d "{\"fcmToken\": \"$FCM_1\", \"deviceType\": \"android\"}"
```

**Device 2:**
```bash
TOKEN_2="eyJhbGc..."
FCM_2="f5_9AwGb..."

curl -X POST http://localhost:3001/api/notifications/device-token \
  -H "Authorization: Bearer $TOKEN_2" \
  -H "Content-Type: application/json" \
  -d "{\"fcmToken\": \"$FCM_2\", \"deviceType\": \"ios\"}"
```

**Device 3:**
```bash
TOKEN_3="eyJhbGc..."
FCM_3="f5_9AwGb..."

curl -X POST http://localhost:3001/api/notifications/device-token \
  -H "Authorization: Bearer $TOKEN_3" \
  -H "Content-Type: application/json" \
  -d "{\"fcmToken\": \"$FCM_3\", \"deviceType\": \"android\"}"
```

### Phase 3: Verify Devices Stored

```bash
# Check database
psql -d lakadiya -c "SELECT COUNT(*) as total_devices FROM device_tokens WHERE is_active = true;"

# Expected output: 3
```

### Phase 4: Send to All Devices

```bash
# Use any JWT token (all have access)
curl -X POST http://localhost:3001/api/notifications/broadcast-test \
  -H "Authorization: Bearer $TOKEN_1" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "🎉 Broadcast Test",
    "body": "This goes to all 3 devices!"
  }'

# Expected response:
# {
#   "success": true,
#   "totalDevices": 3,
#   "sent": 3,
#   "failed": 0
# }
```

### Phase 5: Verify on All Devices

Check all 3 phones' notification panels:
- ✅ Device 1: Notification visible
- ✅ Device 2: Notification visible
- ✅ Device 3: Notification visible

---

## Advanced: Custom Messages

```bash
# Broadcast with custom title and body
curl -X POST http://localhost:3001/api/notifications/broadcast-test \
  -H "Authorization: Bearer JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "🏆 New Leaderboard Update",
    "body": "You ranked up to #5 in the global rankings!"
  }'
```

---

## Monitoring

### Check Notification Logs

```bash
curl -X GET "http://localhost:3001/api/notifications/logs?limit=50" \
  -H "Authorization: Bearer JWT_TOKEN"
```

Response:
```json
{
  "success": true,
  "logs": [
    {
      "id": "uuid",
      "title": "Broadcast Test",
      "body": "This goes to all devices",
      "status": "sent",
      "sent_at": "2024-05-28T08:45:00Z"
    }
  ],
  "count": 1
}
```

### Check Database Directly

```sql
-- All notifications sent in last hour
SELECT id, title, body, status, sent_at 
FROM notification_logs 
WHERE sent_at > NOW() - INTERVAL '1 hour'
ORDER BY sent_at DESC;

-- Devices by status
SELECT 
  is_active,
  COUNT(*) as total,
  MAX(last_used) as last_used_at
FROM device_tokens
GROUP BY is_active;

-- Failed notifications
SELECT * FROM notification_logs 
WHERE status = 'failed'
ORDER BY sent_at DESC
LIMIT 10;
```

---

## Endpoints Summary

| Endpoint | Method | Auth | Purpose |
|----------|--------|------|---------|
| `/notifications/device-token` | POST | ✅ | Store user's FCM token |
| `/notifications/send-test-otp` | POST | ✅ | Send OTP to authenticated user |
| `/notifications/logs` | GET | ✅ | View notification history |
| `/notifications/broadcast-test` | POST | ✅ | Send to ALL active devices |

---

## Real-World Usage

After you've verified everything works:

### On OTP Request (automatic)
```javascript
// Backend: src/modules/auth/otp.service.js
await sendOtpNotification(userId, otp);
// Automatically sends to user's device
```

### For Announcements (manual)
```javascript
// Backend: custom controller
await pool.query(`
  INSERT INTO notifications (title, body, type)
  VALUES ('Game Update', 'New room available', 'announcement')
`);

// Then broadcast to all users
await sendNotificationToMultiple(allUserIds, title, body);
```

### For Game Notifications (real-time)
```javascript
// When game starts
const users = await getGamePlayers(gameId);
await sendNotificationToMultiple(users, 'Game Started', 'Join now!', { gameId });
```

---

## Troubleshooting Checklist

- [ ] Backend running (`npm run dev`)
- [ ] Database migration ran (`npm run migrate`)
- [ ] Firebase credentials valid
- [ ] At least 1 device token stored in DB
- [ ] JWT token is valid (not expired)
- [ ] Network can reach Firebase
- [ ] Device has notification permission enabled
- [ ] App running in foreground (for immediate notification)

---

Done! All notifications working end-to-end! 🎉
