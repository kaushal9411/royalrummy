@echo off
REM Send Test Notification to ALL Active Devices

setlocal enabledelayedexpansion

set "API_URL=http://localhost:3001/api"
set "JWT_TOKEN=YOUR_JWT_TOKEN_HERE"
set "TITLE=🎉 Test Notification"
set "BODY=This notification was sent to all connected devices!"

echo.
echo ============================================================================
echo  Send Test Notification to ALL Devices
echo ============================================================================
echo.
echo Title: %TITLE%
echo Body: %BODY%
echo.

curl -X POST "%API_URL%/notifications/broadcast-test" ^
  -H "Content-Type: application/json" ^
  -H "Authorization: Bearer %JWT_TOKEN%" ^
  -d "{\"title\": \"%TITLE%\", \"body\": \"%BODY%\"}"

echo.
echo.
echo ============================================================================
echo ✅ Notification sent to all devices!
echo ============================================================================
echo.
echo Check your phone notification panel for the notification
echo Check all other connected devices too
echo.
echo Instructions:
echo 1. Edit this file and replace JWT_TOKEN with your actual token
echo 2. Run the script
echo 3. Check all phones for the notification
echo.
pause
