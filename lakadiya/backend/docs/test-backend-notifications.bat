@echo off
REM Firebase OTP Notification - Backend Testing
REM Test sending notifications to device tokens stored in database

setlocal enabledelayedexpansion

REM Configuration
set "API_URL=http://localhost:3001/api"
set "JWT_TOKEN=YOUR_JWT_TOKEN_HERE"
set "DEVICE_TOKEN=YOUR_FCM_DEVICE_TOKEN"
set "OTP=123456"

echo.
echo ============================================================================
echo  Backend Push Notification Testing
echo ============================================================================
echo.
echo API: %API_URL%
echo JWT: %JWT_TOKEN:~0,20%...
echo Device Token: %DEVICE_TOKEN:~0,20%...
echo OTP: %OTP%
echo.

REM ============================================================================
REM TEST 1: Store Device Token
REM ============================================================================

echo [TEST 1] Storing device token...
echo.

curl -X POST "%API_URL%/notifications/device-token" ^
  -H "Content-Type: application/json" ^
  -H "Authorization: Bearer %JWT_TOKEN%" ^
  -d "{\"fcmToken\": \"%DEVICE_TOKEN%\", \"deviceType\": \"android\"}"

echo.
echo.

REM ============================================================================
REM TEST 2: Send Test OTP
REM ============================================================================

echo [TEST 2] Sending test OTP notification...
echo.

curl -X POST "%API_URL%/notifications/send-test-otp" ^
  -H "Content-Type: application/json" ^
  -H "Authorization: Bearer %JWT_TOKEN%" ^
  -d "{\"otp\": \"%OTP%\"}"

echo.
echo.

REM ============================================================================
REM TEST 3: Get Notification Logs
REM ============================================================================

echo [TEST 3] Fetching notification logs...
echo.

curl -X GET "%API_URL%/notifications/logs?limit=10" ^
  -H "Authorization: Bearer %JWT_TOKEN%"

echo.
echo.
echo ============================================================================
echo INSTRUCTIONS
echo ============================================================================
echo.
echo 1. Get JWT Token:
echo    - Call POST /api/auth/login or /api/auth/guest
echo    - Copy the 'token' from response
echo    - Edit this file: set JWT_TOKEN=your_token_here
echo.
echo 2. Get FCM Device Token:
echo    - Open Lakadiya app on phone
echo    - Go to Profile menu (top right)
echo    - Tap 3-dot menu and select "Device Token"
echo    - Copy the token
echo    - Edit this file: set DEVICE_TOKEN=your_token_here
echo.
echo 3. Run this script
echo.
echo 4. Check your phone notification panel for the notification
echo.
echo ============================================================================
echo.
pause
