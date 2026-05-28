# Send Notification to All Devices

## Quick Command

**Windows:**
```bash
cd docs
send-to-all-devices.bat
```

**Mac/Linux:**
```bash
bash docs/send-to-all-devices.sh
```

---

## Manual CURL

```bash
curl -X POST http://localhost:3001/api/notifications/broadcast-test \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -d '{
    "title": "🎉 Hello Everyone!",
    "body": "This notification goes to all connected devices"
  }'
```

---

## Step by Step

### 1. Get JWT Token
```bash
curl -X POST http://localhost:3001/api/auth/guest \
  -H "Content-Type: application/json"
```
Copy the `token` from response.

### 2. Send to All Devices
```bash
curl -X POST http://localhost:3001/api/notifications/broadcast-test \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer TOKEN_HERE" \
  -d '{
    "title": "Test Message",
    "body": "Sent to all active devices"
  }'
```

### 3. Check Response
```json
{
  "success": true,
  "message": "Notification sent to all devices",
  "title": "Test Message",
  "body": "Sent to all active devices",
  "totalDevices": 5,
  "sent": 5,
  "failed": 0
}
```

---

## What Happens

1. Backend queries `device_tokens` table for all active devices
2. For each device token found:
   - Sends notification via Firebase
   - Logs in `notification_logs` table
3. Returns summary: how many sent, how many failed

---

## Check in Database

```sql
-- See all active devices
SELECT user_id, fcm_token, device_type, last_used 
FROM device_tokens 
WHERE is_active = true;

-- See notification history
SELECT * FROM notification_logs 
WHERE data->>'type' = 'broadcast_test' 
ORDER BY sent_at DESC;
```

---

## Response Example

```json
{
  "success": true,
  "message": "Notification sent to all devices",
  "title": "🎉 Test Notification",
  "body": "This notification was sent to all connected devices!",
  "totalDevices": 3,
  "sent": 3,
  "failed": 0,
  "errors": null
}
```

---

## Troubleshooting

### ❌ "No active devices found"
- No users have stored their FCM tokens yet
- Run `test-backend-notifications.bat` first to store a token

### ❌ "Authorization failed"
- JWT token is invalid or expired
- Get fresh token from `/auth/guest` endpoint

### ❌ Some devices failed
- Check `errors` array in response
- Invalid or expired tokens will fail
- Tokens auto-refresh on next app launch

---

## Testing with Multiple Devices

1. **Device 1:** Login → stores token
2. **Device 2:** Login → stores token
3. **Device 3:** Login → stores token
4. Run this command
5. All 3 devices receive notification simultaneously

Perfect for testing broadcast features! 🎉
