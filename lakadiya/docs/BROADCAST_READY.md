# ✅ Broadcast Notifications - READY TO USE

## What's New

**New Endpoint:**
```
POST /api/notifications/broadcast-test
```

Sends a notification to **ALL** active devices simultaneously.

---

## Quick Start (30 seconds)

### Windows
```bash
cd docs
send-to-all-devices.bat
```

### Mac/Linux
```bash
bash docs/send-to-all-devices.sh
```

---

## CURL Command

**Step 1:** Get token
```bash
curl -X POST http://localhost:3001/api/auth/guest -H "Content-Type: application/json"
```

**Step 2:** Send to all devices
```bash
curl -X POST http://localhost:3001/api/notifications/broadcast-test \
  -H "Authorization: Bearer TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{"title":"Hello Everyone!","body":"Message sent to all devices"}'
```

---

## What It Does

1. **Finds** all active device tokens in DB
2. **Sends** notification to each device via Firebase
3. **Logs** all notifications in database
4. **Returns** summary (total, sent, failed)

---

## Response Example

```json
{
  "success": true,
  "title": "Hello Everyone!",
  "body": "Message sent to all devices",
  "totalDevices": 5,
  "sent": 5,
  "failed": 0
}
```

✅ 5 devices received the notification

---

## Endpoints Reference

| Endpoint | Target | Use Case |
|----------|--------|----------|
| `POST /notifications/device-token` | Specific user | Store FCM token (auto on login) |
| `POST /notifications/send-test-otp` | Authenticated user | Send OTP to current user |
| `POST /notifications/broadcast-test` | **ALL users** | Announcement to everyone |
| `GET /notifications/logs` | Current user | View notification history |

---

## Database

All notifications logged in `notification_logs` table:

```sql
SELECT * FROM notification_logs ORDER BY sent_at DESC LIMIT 10;

-- See broadcast notifications only
SELECT * FROM notification_logs 
WHERE data->>'type' = 'broadcast_test' 
ORDER BY sent_at DESC;
```

---

## Files Created

Backend:
- Updated: `src/modules/notifications/notification.controller.js`
- Updated: `src/modules/notifications/notification.routes.js`
- New: `docs/send-to-all-devices.bat`
- New: `docs/send-to-all-devices.sh`
- New: `docs/BROADCAST_NOTIFICATIONS.md`

---

## Testing Matrix

| Test | Command | Expected |
|------|---------|----------|
| Single User OTP | `send-test-otp` | Notification on 1 device |
| All Devices | `broadcast-test` | Notification on all devices |
| Check Logs | `logs` | History of all notifications |
| DB Verify | SQL query | All tokens visible in DB |

---

## Real Use Cases

✅ **Announcement:** "New game room open!" → All devices

✅ **OTP:** "Your code: 123456" → Single device

✅ **Maintenance:** "Server down for maintenance" → All devices

✅ **Update:** "New feature available!" → All devices

---

## Next Steps

1. ✅ Broadcast endpoint ready
2. ✅ Test scripts created
3. ✅ Documentation complete
4. ⏭️ Deploy to production
5. ⏭️ Monitor notification logs

---

## Testing Now

```bash
# Get token
curl -X POST http://localhost:3001/api/auth/guest -H "Content-Type: application/json"

# Send to all
curl -X POST http://localhost:3001/api/notifications/broadcast-test \
  -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title":"Test","body":"Sent to all devices!"}'

# Check all your phones 📱
```

Done! 🎉 All devices will receive the notification.
