# Firebase Push Notification Testing Guide

## Step 1: Get Your Device FCM Token

1. Open the Lakadiya app on your device
2. Navigate to **Profile** → tap **⋮** menu → **Device Token**
3. Copy the long token string (it appears in console as `FCM DEVICE TOKEN: ...`)

Example token:
```
f5_9AwGbwXs:APA91bFxyz...longstringhere...
```

---

## Step 2: Setup Local Notification Server

### Install Node.js

Download from https://nodejs.org/ (v16+ recommended)

### Create project folder

```bash
mkdir fcm-notif-server
cd fcm-notif-server
npm init -y
```

### Install dependencies

```bash
npm install express cors firebase-admin dotenv
```

### Add Firebase credentials

Copy your Firebase Admin SDK key file to this folder:
- File: `lakadiya-3e18a-firebase-adminsdk-fbsvc-0fe9480f2e.json`
- Location: Project root (same as `notification-server.js`)

### Copy server file

Copy `notification-server.js` from the Lakadiya mobile project to your project folder

### Start server

```bash
node notification-server.js
```

Expected output:
```
🔥 Firebase Notification Server running on http://localhost:3000
📱 Ready to send notifications!
```

---

## Step 3: Send Test Notification via CURL

### Test 1: Send OTP Notification

```bash
curl -X POST http://localhost:3000/send-otp \
  -H "Content-Type: application/json" \
  -d '{
    "deviceToken": "YOUR_DEVICE_TOKEN_HERE",
    "otp": "123456"
  }'
```

### Test 2: Send Generic Notification

```bash
curl -X POST http://localhost:3000/send-notification \
  -H "Content-Type: application/json" \
  -d '{
    "deviceToken": "YOUR_DEVICE_TOKEN_HERE",
    "title": "Test Notification",
    "body": "This is a test message from your local server",
    "data": {
      "type": "test",
      "value": "hello"
    }
  }'
```

### Test 3: Check Server Health

```bash
curl http://localhost:3000/health
```

---

## Step 4: Replace Device Token

Replace `YOUR_DEVICE_TOKEN_HERE` with your actual token. Examples:

### PowerShell (Windows)

```powershell
$token = "f5_9AwGbwXs:APA91bFxyz..."
$body = @{
    deviceToken = $token
    otp = "654321"
} | ConvertTo-Json

Invoke-WebRequest -Uri http://localhost:3000/send-otp `
  -Method POST `
  -Headers @{"Content-Type" = "application/json"} `
  -Body $body
```

### Bash (Mac/Linux)

```bash
TOKEN="f5_9AwGbwXs:APA91bFxyz..."

curl -X POST http://localhost:3000/send-otp \
  -H "Content-Type: application/json" \
  -d "{
    \"deviceToken\": \"$TOKEN\",
    \"otp\": \"654321\"
  }"
```

---

## Step 5: Check Logs

### On Local Server
Watch the console for responses:
```
✓ Notification sent successfully
  Message ID: projects/lakadiya-3e18a/messages/1234567890
  Device Token: f5_9AwGbwXs:APA91b...
  OTP: 123456
```

### On Flutter Device
Open Flutter console and search for:
```
Foreground FCM message: Your OTP Code
Message data: {type: OTP, otp: 123456, ...}
```

Or check device notification panel for the push notification.

---

## Troubleshooting

### ❌ Error: "credentials is not defined"
**Fix:** Copy `lakadiya-3e18a-firebase-adminsdk-fbsvc-0fe9480f2e.json` to project root

### ❌ Error: "deviceToken is required"
**Fix:** Make sure you're using the FULL token from the device, not partial

### ❌ Error: "Authentication failed"
**Fix:** Firebase credentials are invalid. Download a fresh one from Firebase Console → Service Accounts

### ❌ Notification not received
**Checklist:**
- [ ] Device token is correct and copied from app
- [ ] App is in foreground (notifications show in logs)
- [ ] Firebase credentials file exists in correct location
- [ ] Network can reach Firebase (firewall/proxy?)
- [ ] Device has notification permission enabled

### ❌ "Port 3000 already in use"
**Fix:** Use different port:
```bash
PORT=3001 node notification-server.js
```

Then test with `http://localhost:3001/send-otp`

---

## API Response Examples

### Success (200 OK)
```json
{
  "success": true,
  "messageId": "projects/lakadiya-3e18a/messages/1234567890",
  "deviceToken": "f5_9AwGbwXs:APA91b...",
  "otp": "123456"
}
```

### Error (400 Bad Request)
```json
{
  "error": "OTP must be 6 digits",
  "details": null
}
```

### Error (500 Internal Error)
```json
{
  "error": "Invalid registration token provided",
  "details": "invalid-argument"
}
```

---

## Integration with Backend

Once you confirm notifications work locally, integrate into your backend:

### Node.js/Express
```javascript
const sendOtp = async (deviceToken, otp) => {
  const admin = require('firebase-admin');
  const messaging = admin.messaging();
  
  return await messaging.send({
    notification: { title: 'Your OTP Code', body: `OTP: ${otp}` },
    data: { type: 'OTP', otp },
    android: {
      priority: 'high',
      notification: {
        title: 'Your OTP Code',
        body: `OTP: ${otp}`,
        channelId: 'otp_channel',
      },
    },
  }, deviceToken);
};
```

### Call when user requests OTP
```javascript
app.post('/auth/otp/send', async (req, res) => {
  const { mobile, deviceToken } = req.body;
  
  const otp = Math.random().toString().slice(2, 8); // 6-digit OTP
  
  // Send via FCM
  try {
    await sendOtp(deviceToken, otp);
  } catch (err) {
    console.error('FCM failed:', err);
    // Fallback to SMS/email
  }
  
  // Store OTP in DB for verification
  res.json({ success: true, message: 'OTP sent' });
});
```
