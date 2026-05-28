# Quick Test - Send Notification to All Devices (One Command)

## One-Liner (Copy & Paste)

```bash
curl -X POST http://localhost:3001/api/notifications/broadcast-test -H "Authorization: Bearer $(curl -s -X POST http://localhost:3001/api/auth/guest -H 'Content-Type: application/json' | jq -r '.token')" -H "Content-Type: application/json" -d '{"title":"🎉 Broadcast Test","body":"Sent to all devices!"}'
```

## Step by Step (Recommended)

### Step 1: Get JWT Token
```bash
curl -X POST http://localhost:3001/api/auth/guest \
  -H "Content-Type: application/json"
```

Copy the `token` value

### Step 2: Broadcast to All
```bash
curl -X POST http://localhost:3001/api/notifications/broadcast-test \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Test from Backend",
    "body": "This goes to ALL connected devices!"
  }'
```

### Step 3: Watch Your Phones
All devices should show the notification in their notification panel! 📱

---

## Expected Response

```json
{
  "success": true,
  "message": "Notification sent to all devices",
  "title": "Test from Backend",
  "body": "This goes to ALL connected devices!",
  "totalDevices": 5,
  "sent": 5,
  "failed": 0
}
```

---

## Windows PowerShell

```powershell
$token = $(curl -s -X POST http://localhost:3001/api/auth/guest -H 'Content-Type: application/json' | ConvertFrom-Json).token

curl -X POST http://localhost:3001/api/notifications/broadcast-test `
  -H "Authorization: Bearer $token" `
  -H "Content-Type: application/json" `
  -d '{"title":"Broadcast Test","body":"Sent to all devices!"}'
```

Done! 🎉
