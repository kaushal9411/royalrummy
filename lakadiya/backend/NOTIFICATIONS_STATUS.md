# Social Feature - Real-time Notifications Implementation Status

## ✅ BACKEND IMPLEMENTATION COMPLETE

### 1. Friend Request Features
**Endpoint:** `POST /users/friends/:userId`
- ✅ Sends friend request to database
- ✅ Emits real-time socket event: `friend_request`
- ✅ Sends FCM push notification to recipient
- ✅ Notification title: "Friend Request"
- ✅ Notification body: "{username} sent you a friend request"

### 2. Accept Friend Request
**Endpoint:** `POST /users/friends/:userId/accept`
- ✅ Updates friendship status to 'accepted'
- ✅ Emits real-time socket event: `friend_accepted`
- ✅ Sends FCM push notification to requester
- ✅ Notification title: "Friend Request Accepted"
- ✅ Notification body: "{username} accepted your friend request"

### 3. Decline Friend Request
**Endpoint:** `POST /users/friends/:userId/decline`
- ✅ Deletes pending friendship request
- ✅ Sends FCM push notification to requester
- ✅ Notification title: "Friend Request Declined"
- ✅ Notification body: "{username} declined your friend request"

### 4. Get Pending Requests
**Endpoint:** `GET /users/me/friend-requests`
- ✅ Returns all pending requests where user is recipient
- ✅ Includes: from_user_id, from_user_name, from_user_avatar, level, created_at

### 5. Private Messages
**Endpoint:** `POST /messages/:userId`
- ✅ Sends message to database
- ✅ Emits real-time socket event: `private_message`
- ✅ Sends FCM push notification to recipient
- ✅ Notification title: "{sender_username}"
- ✅ Notification body: "{message text truncated to 100 chars}"

---

## ✅ SOCKET EVENTS (Real-time)

### Events Emitted:
1. **friend_request**
   - Triggered when: User sends friend request
   - Recipients: `user:{recipientId}`
   - Payload: `{ fromUserId, fromUsername }`

2. **friend_accepted**
   - Triggered when: User accepts friend request
   - Recipients: `user:{requesterId}`
   - Payload: `{ userId, username }`

3. **private_message**
   - Triggered when: User sends message
   - Recipients: `user:{receiverId}`
   - Payload: `{ id, sender_id, sender_name, receiver_id, text, created_at }`

---

## ✅ FCM PUSH NOTIFICATIONS

### Configuration:
- **Database:** device_tokens table (stores FCM tokens per user)
- **Provider:** Firebase Cloud Messaging (FCM)
- **Channel:** Varies by notification type
  - Friend requests/accepts: `social_channel`
  - Messages: `message_channel`
  - Room notifications: `room_channel`

### Notification Flow:
1. Backend receives API request (send friend request, send message, etc.)
2. Backend emits socket event to recipient (real-time)
3. Backend queries device_tokens table for recipient's FCM token
4. Backend sends FCM message via Firebase Admin SDK
5. Recipient receives push notification on mobile (even if app is closed)

---

## 📱 FLUTTER APP REQUIREMENTS

### What Needs to Be Done in Flutter:

1. **Store FCM Token on Login**
   ```dart
   // When user logs in, get FCM token and send to backend
   POST /notifications/device-token
   {
     "fcmToken": "token_from_firebase",
     "deviceType": "android"
   }
   ```

2. **Handle Socket Events in real-time**
   - Listen to: `friend_request`, `friend_accepted`, `private_message`
   - Auto-refresh UI when events arrive

3. **Handle FCM Notifications**
   - Foreground: Show overlay/snackbar
   - Background: Update UI when app opens
   - Notification tap: Navigate to relevant screen

4. **Listen to notification taps:**
   - If type='friend_request' → Navigate to Requests tab
   - If type='friend_accepted' → Navigate to Friends tab, show toast
   - If type='private_message' → Navigate to DM with sender

---

## 🔄 FLOW EXAMPLE: Send Friend Request

### Step 1: User sends request
```
User A (Deeksha) → POST /users/friends/{User B ID}
```

### Step 2: Backend actions
```
✅ Insert into friendships table
✅ Emit socket event to user B: friend_request
✅ Query device_tokens for user B's FCM token
✅ Send FCM notification via Firebase
```

### Step 3: User B receives in real-time
```
🔵 Socket event received (app open) → Update Requests tab immediately
🔴 FCM notification received (app closed) → Badge notification, handle on tap
```

### Step 4: User B accepts request
```
User B → POST /users/friends/{User A ID}/accept
```

### Step 5: Backend actions
```
✅ Update friendship to 'accepted'
✅ Emit socket event to user A: friend_accepted
✅ Send FCM notification to user A
```

### Step 6: User A receives
```
🔵 Socket: Notification appears (app open)
🔴 FCM: Notification badge (app closed)
```

---

## ⚠️ CURRENTLY MISSING IN FLUTTER APP

1. **FCM Token Storage Endpoint**
   - Need to add: `POST /notifications/device-token` route
   - Currently exists in backend but not called from Flutter

2. **Notification Handling in Social Page**
   - Real-time refresh when socket events arrive
   - Already partially implemented (socket listeners exist)

3. **FCM Foreground Notifications Display**
   - When message arrives while app is open, show snackbar/toast
   - Currently no UI feedback in foreground

---

## 🚀 TODO FOR FLUTTER

### High Priority:
- [ ] Call `POST /notifications/device-token` on user login
- [ ] Listen to FCM messages in foreground
- [ ] Show notification snackbar when friend request arrives
- [ ] Show notification snackbar when message arrives
- [ ] Auto-refresh Requests tab when `friend_request` socket event received
- [ ] Auto-refresh Friends tab when `friend_accepted` socket event received

### Medium Priority:
- [ ] Handle notification taps to navigate to correct screen
- [ ] Show badge/unread count on tabs
- [ ] Sound/vibration for notifications

### Low Priority:
- [ ] Persist notification history in app
- [ ] Add notification settings (mute, categories)

---

## VERIFICATION CHECKLIST

- [✅] Backend sends FCM notifications: Configured
- [✅] Backend emits socket events: Configured
- [✅] Socket events reach app: Working
- [✅] Friend requests saved to DB: Working
- [✅] Pending requests API: Working
- [❌] Flutter stores FCM token: NOT IMPLEMENTED
- [❌] Flutter displays FCM in foreground: NOT IMPLEMENTED
- [❌] Flutter handles notification taps: NOT IMPLEMENTED

---

## NEXT STEPS

1. Add notification token endpoint in Flutter notification service
2. Call this endpoint after user successfully logs in
3. Implement foreground FCM message handlers in Flutter
4. Test end-to-end: Send request → Recipient gets notification → Accept → Sender gets notification
