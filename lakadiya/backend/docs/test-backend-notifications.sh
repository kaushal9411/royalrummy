#!/bin/bash

# Firebase OTP Notification - Backend Testing
# Test sending notifications to device tokens stored in database

# Configuration
API_URL="http://localhost:3001/api"
JWT_TOKEN="YOUR_JWT_TOKEN_HERE"  # Get from login response
DEVICE_TOKEN="YOUR_FCM_DEVICE_TOKEN"
OTP="123456"

# ============================================================================
# TEST 1: Store Device Token (after login)
# ============================================================================

echo "📱 [TEST 1] Storing device token..."
echo "Device Token: $DEVICE_TOKEN"
echo ""

curl -X POST "$API_URL/notifications/device-token" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -d "{
    \"fcmToken\": \"$DEVICE_TOKEN\",
    \"deviceType\": \"android\"
  }" | jq .

echo ""
echo ""

# ============================================================================
# TEST 2: Send Test OTP Notification
# ============================================================================

echo "📱 [TEST 2] Sending test OTP notification..."
echo "OTP: $OTP"
echo ""

curl -X POST "$API_URL/notifications/send-test-otp" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -d "{
    \"otp\": \"$OTP\"
  }" | jq .

echo ""
echo ""

# ============================================================================
# TEST 3: Get Notification Logs
# ============================================================================

echo "📝 [TEST 3] Fetching notification logs..."
echo ""

curl -X GET "$API_URL/notifications/logs?limit=10" \
  -H "Authorization: Bearer $JWT_TOKEN" | jq .

echo ""
echo ""

# ============================================================================
# INSTRUCTIONS
# ============================================================================

echo "
╔════════════════════════════════════════════════════════════════╗
║    Backend Push Notification Testing Instructions              ║
╚════════════════════════════════════════════════════════════════╝

1️⃣  Get JWT Token:
    • Call /api/auth/login or /api/auth/guest endpoint
    • Copy the 'token' from response
    • Replace: JWT_TOKEN=\"YOUR_JWT_TOKEN_HERE\"

2️⃣  Get FCM Device Token:
    • Open Lakadiya app on your phone
    • Go to Profile → Device Token menu
    • Copy the token
    • Replace: DEVICE_TOKEN=\"YOUR_FCM_DEVICE_TOKEN\"

3️⃣  Edit this script:
    Replace:
    - JWT_TOKEN with actual token from step 1
    - DEVICE_TOKEN with actual token from step 2
    - OTP can be any 6-digit number

4️⃣  Run this script:
    bash test-backend-notifications.sh

5️⃣  Verify:
    ✅ Device token stored in database
    ✅ Notification sent to device
    ✅ See notification in device notification panel
    ✅ Notification logs show in TEST 3

═══════════════════════════════════════════════════════════════════
"
