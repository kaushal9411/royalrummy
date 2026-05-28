#!/bin/bash

# Send Test Notification to ALL Active Devices

API_URL="http://localhost:3001/api"
JWT_TOKEN="YOUR_JWT_TOKEN_HERE"

# Custom message (optional)
TITLE="🎉 Test Notification"
BODY="This notification was sent to all connected devices!"

echo "📢 Sending test notification to ALL active devices..."
echo ""

curl -X POST "$API_URL/notifications/broadcast-test" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -d "{
    \"title\": \"$TITLE\",
    \"body\": \"$BODY\"
  }" | jq .

echo ""
echo ""
echo "✅ Notification sent to all devices!"
echo ""
echo "Check your phone notification panel (and all other devices)"
