@echo off
REM Firebase OTP Notification Tester - Windows PowerShell

setlocal enabledelayedexpansion

REM ============================================================================
REM STEP 1: Configure your device token here
REM ============================================================================

set DEVICE_TOKEN=YOUR_DEVICE_TOKEN_HERE
set OTP=123456
set SERVER=http://localhost:3000

echo.
echo ============================================================================
echo  Firebase OTP Notification Tester
echo ============================================================================
echo.

REM ============================================================================
REM TEST 1: Check Server Health
REM ============================================================================

echo [1/3] Checking server health...
echo.
curl -X GET %SERVER%/health
echo.
echo.

REM ============================================================================
REM TEST 2: Send OTP Notification
REM ============================================================================

echo [2/3] Sending OTP notification...
echo Device Token: %DEVICE_TOKEN%
echo OTP: %OTP%
echo.

curl -X POST %SERVER%/send-otp ^
  -H "Content-Type: application/json" ^
  -d "{\"deviceToken\": \"%DEVICE_TOKEN%\", \"otp\": \"%OTP%\"}"

echo.
echo.

REM ============================================================================
REM TEST 3: Send Generic Notification
REM ============================================================================

echo [3/3] Sending generic notification...
echo.

curl -X POST %SERVER%/send-notification ^
  -H "Content-Type: application/json" ^
  -d "{\"deviceToken\": \"%DEVICE_TOKEN%\", \"title\": \"Test Notification\", \"body\": \"This is a test message from local server\", \"data\": {\"type\": \"test\"}}"

echo.
echo.
echo ============================================================================
echo INSTRUCTIONS
echo ============================================================================
echo.
echo 1. Get your device token:
echo    - Open Lakadiya app on your phone
echo    - Go to Profile menu (top right)
echo    - Tap the 3-dot menu and select "Device Token"
echo    - Copy the token shown
echo.
echo 2. Edit this file (test-notifications.bat):
echo    Replace: set DEVICE_TOKEN=YOUR_DEVICE_TOKEN_HERE
echo    With: set DEVICE_TOKEN=your_actual_token_here
echo.
echo 3. Make sure Node.js server is running:
echo    cd notification-server-folder
echo    node notification-server.js
echo.
echo 4. Run this script again to send test notifications
echo.
echo 5. Check your phone notification panel for the notification
echo.
echo ============================================================================
echo.
pause
