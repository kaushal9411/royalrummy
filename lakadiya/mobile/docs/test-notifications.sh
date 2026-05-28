#!/bin/bash

# Firebase OTP Notification Tester
# Quick curl commands for local testing

# ============================================================================
# STEP 1: Get your device token from the app (Profile > Device Token)
# ============================================================================

DEVICE_TOKEN="YOUR_DEVICE_TOKEN_HERE"
OTP="123456"
SERVER="http://localhost:3000"

# ============================================================================
# TEST 1: Send OTP Notification
# ============================================================================

echo "📱 Sending OTP notification..."
curl -X POST $SERVER/send-otp \
  -H "Content-Type: application/json" \
  -d "{
    \"deviceToken\": \"$DEVICE_TOKEN\",
    \"otp\": \"$OTP\"
  }" | jq .

# ============================================================================
# TEST 2: Send Generic Notification
# ============================================================================

echo -e "\n📱 Sending generic notification..."
curl -X POST $SERVER/send-notification \
  -H "Content-Type: application/json" \
  -d "{
    \"deviceToken\": \"$DEVICE_TOKEN\",
    \"title\": \"Test Notification\",
    \"body\": \"This is a test message\",
    \"data\": {
      \"type\": \"test\",
      \"message\": \"Hello from local server\"
    }
  }" | jq .

# ============================================================================
# TEST 3: Check Server Health
# ============================================================================

echo -e "\n✅ Checking server health..."
curl -X GET $SERVER/health | jq .

# ============================================================================
# SETUP INSTRUCTIONS
# ============================================================================

echo -e "\n
╔════════════════════════════════════════════════════════════════╗
║         SETUP: Firebase OTP Notification Tester               ║
╚════════════════════════════════════════════════════════════════╝

1️⃣  Get Device Token:
    • Open Lakadiya app → Profile → ⋮ menu → Device Token
    • Copy the token and replace DEVICE_TOKEN above

2️⃣  Start Local Server:
    cd notification-server-folder
    node notification-server.js

3️⃣  Edit this script:
    Replace: DEVICE_TOKEN=\"YOUR_DEVICE_TOKEN_HERE\"
    With your actual token from step 1

4️⃣  Run tests:
    bash test-notifications.sh

5️⃣  Check device notification panel:
    Look for notification with app icon and OTP code
"
