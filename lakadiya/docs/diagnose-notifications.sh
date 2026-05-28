#!/bin/bash

# Notification Debugging Script
# Tests each step of the notification flow

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║         Notification System Diagnostic                        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

API_URL="http://localhost:3001"
JWT_TOKEN=""
FCM_TOKEN=""
USER_ID=""

# ============================================================================
# STEP 1: Check Backend Health
# ============================================================================

echo "[STEP 1] Checking backend server..."
HEALTH=$(curl -s -w "\n%{http_code}" "$API_URL/health")
HTTP_CODE=$(echo "$HEALTH" | tail -1)

if [ "$HTTP_CODE" = "200" ]; then
  echo "✓ Backend is running"
else
  echo "✗ Backend is NOT running (HTTP $HTTP_CODE)"
  echo "  Start with: npm run dev"
  exit 1
fi

# ============================================================================
# STEP 2: Login & Get JWT Token
# ============================================================================

echo ""
echo "[STEP 2] Getting JWT token..."
LOGIN_RESPONSE=$(curl -s -X POST "$API_URL/api/auth/guest" \
  -H "Content-Type: application/json")

JWT_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.token' 2>/dev/null)
USER_ID=$(echo "$LOGIN_RESPONSE" | jq -r '.user.id' 2>/dev/null)

if [ -z "$JWT_TOKEN" ] || [ "$JWT_TOKEN" = "null" ]; then
  echo "✗ Failed to get JWT token"
  echo "  Response: $LOGIN_RESPONSE"
  exit 1
fi

echo "✓ JWT token obtained"
echo "  Token: ${JWT_TOKEN:0:20}..."
echo "  User ID: $USER_ID"

# ============================================================================
# STEP 3: Get FCM Token from App
# ============================================================================

echo ""
echo "[STEP 3] FCM device token"
read -p "  Enter FCM token from app (Profile > Device Token): " FCM_TOKEN

if [ -z "$FCM_TOKEN" ]; then
  echo "✗ No FCM token provided"
  exit 1
fi

echo "✓ FCM token: ${FCM_TOKEN:0:20}..."

# ============================================================================
# STEP 4: Store Device Token in Backend
# ============================================================================

echo ""
echo "[STEP 4] Storing device token in database..."
STORE_RESPONSE=$(curl -s -X POST "$API_URL/api/notifications/device-token" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"fcmToken\": \"$FCM_TOKEN\", \"deviceType\": \"android\"}")

STORE_SUCCESS=$(echo "$STORE_RESPONSE" | jq -r '.success' 2>/dev/null)

if [ "$STORE_SUCCESS" = "true" ]; then
  echo "✓ Device token stored in database"
else
  echo "✗ Failed to store device token"
  echo "  Response: $STORE_RESPONSE"
  exit 1
fi

# ============================================================================
# STEP 5: Send Test OTP
# ============================================================================

echo ""
echo "[STEP 5] Sending test OTP notification..."
OTP="123456"

SEND_RESPONSE=$(curl -s -X POST "$API_URL/api/notifications/send-test-otp" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"otp\": \"$OTP\"}")

SEND_SUCCESS=$(echo "$SEND_RESPONSE" | jq -r '.success' 2>/dev/null)
MESSAGE_ID=$(echo "$SEND_RESPONSE" | jq -r '.messageId' 2>/dev/null)

if [ "$SEND_SUCCESS" = "true" ]; then
  echo "✓ OTP notification sent"
  echo "  Message ID: $MESSAGE_ID"
  echo "  OTP: $OTP"
else
  ERROR=$(echo "$SEND_RESPONSE" | jq -r '.error' 2>/dev/null)
  echo "✗ Failed to send OTP notification"
  echo "  Error: $ERROR"
  echo "  Response: $SEND_RESPONSE"
fi

# ============================================================================
# STEP 6: Check Logs
# ============================================================================

echo ""
echo "[STEP 6] Checking notification logs..."
LOGS_RESPONSE=$(curl -s -X GET "$API_URL/api/notifications/logs?limit=5" \
  -H "Authorization: Bearer $JWT_TOKEN")

LOG_COUNT=$(echo "$LOGS_RESPONSE" | jq -r '.count' 2>/dev/null)

if [ ! -z "$LOG_COUNT" ] && [ "$LOG_COUNT" != "null" ]; then
  echo "✓ Found $LOG_COUNT notification logs"
  echo "$LOGS_RESPONSE" | jq '.logs[] | {title, body, status, sent_at}' 2>/dev/null
else
  echo "✗ Could not fetch logs"
  echo "  Response: $LOGS_RESPONSE"
fi

# ============================================================================
# RESULTS
# ============================================================================

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                     DIAGNOSTIC COMPLETE                        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "✓ Backend running"
echo "✓ JWT authentication working"
echo "✓ Device token stored"
if [ "$SEND_SUCCESS" = "true" ]; then
  echo "✓ Notification sent to Firebase"
  echo ""
  echo "Next: Check your phone notification panel for the OTP notification"
  echo ""
  echo "If notification NOT received on phone:"
  echo "  1. Check phone Settings > Apps > Lakadiya > Notifications (ON)"
  echo "  2. Check backend logs: npm run dev"
  echo "  3. Check Firebase Console for delivery status"
  echo "  4. Verify FCM token is correct"
else
  echo "✗ Notification failed to send"
  echo ""
  echo "Check:"
  echo "  1. Firebase credentials in .env file"
  echo "  2. Backend console logs"
  echo "  3. Database connection"
fi
echo ""
