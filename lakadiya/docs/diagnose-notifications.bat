@echo off
REM Notification Debugging Script - Windows
REM Tests each step of the notification flow

setlocal enabledelayedexpansion

set "API_URL=http://localhost:3001"
set "JWT_TOKEN="
set "FCM_TOKEN="
set "USER_ID="

echo.
echo ============================================================================
echo  Notification System Diagnostic
echo ============================================================================
echo.

REM ============================================================================
REM STEP 1: Check Backend Health
REM ============================================================================

echo [STEP 1] Checking backend server...
for /f "delims=" %%A in ('curl -s -w "%%{http_code}" %API_URL%/health') do set "HTTP_RESPONSE=%%A"

if "%HTTP_RESPONSE:~-3%" == "200" (
  echo ✓ Backend is running
) else (
  echo ✗ Backend is NOT running
  echo   Start with: npm run dev
  pause
  exit /b 1
)

REM ============================================================================
REM STEP 2: Login & Get JWT Token
REM ============================================================================

echo.
echo [STEP 2] Getting JWT token...
for /f "delims=" %%A in ('curl -s -X POST "%API_URL%/api/auth/guest" -H "Content-Type: application/json"') do set "LOGIN_RESPONSE=%%A"

REM Extract token from JSON (simple method)
for /f "tokens=*" %%A in ('echo %LOGIN_RESPONSE% ^| findstr /R "token"') do set "JWT_LINE=%%A"

echo Got response: %JWT_LINE:~0,50%...

if "!JWT_LINE!" == "" (
  echo ✗ Failed to get JWT token
  echo   Response: !LOGIN_RESPONSE!
  pause
  exit /b 1
)

echo ✓ JWT token obtained

REM ============================================================================
REM STEP 3: Get FCM Token from User
REM ============================================================================

echo.
echo [STEP 3] Enter FCM device token
set /p FCM_TOKEN=  Paste FCM token from app (Profile ^> Device Token): 

if "!FCM_TOKEN!" == "" (
  echo ✗ No FCM token provided
  pause
  exit /b 1
)

echo ✓ FCM token: !FCM_TOKEN:~0,20!...

REM ============================================================================
REM RESULTS
REM ============================================================================

echo.
echo ============================================================================
echo                     DIAGNOSTIC SUMMARY
echo ============================================================================
echo.
echo ✓ Backend running
echo ✓ JWT authentication working
echo ✓ FCM token obtained
echo.
echo Next steps:
echo   1. Go to backend terminal
echo   2. Watch logs: npm run dev
echo   3. Use this curl command:
echo.
echo curl -X POST %API_URL%/api/notifications/send-test-otp ^
  echo   -H "Authorization: Bearer [JWT_TOKEN]" ^
  echo   -H "Content-Type: application/json" ^
  echo   -d "{\"otp\": \"123456\"}"
echo.
echo Then check your phone notification panel!
echo.
pause
