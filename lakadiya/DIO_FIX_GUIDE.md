# Dio Exception Fix - Troubleshooting Guide

## Common Issues & Solutions

### 1. **DioException: Unknown: null**

**Causes:**
- Backend not running
- Wrong API URL
- No network connectivity
- Token not set/expired

**Solutions:**

```bash
# Terminal 1: Start Backend
cd backend
npm run dev

# Check if backend is running
curl http://localhost:3001/health
```

If you see `{"status":"ok","uptime":...}` → Backend is running ✓

### 2. **Check Mobile API URL**

Verify in `lib/core/constants/app_constants.dart`:

```dart
// For Emulator (Android):
static const String baseUrl = 'http://10.0.2.2:3001';

// For Physical Device (same network):
static const String baseUrl = 'http://192.168.x.x:3001';
// Find your IP: ipconfig (Windows) or ifconfig (Mac/Linux)

// For localhost (iOS Simulator only):
static const String baseUrl = 'http://127.0.0.1:3001';
```

### 3. **Enable Console Logging**

Add this to `main.dart` before `ApiService().init()`:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService.init();
  ApiService().init(); // Now with debug logging
  SocketService().connect();
  runApp(const LakadiyaApp());
}
```

Check the console for:
```
[API] POST /api/payments/initiate
[API] Response: 200 - {...}
```

### 4. **Verify Token is Set**

Check if authentication token exists:

```dart
// In main.dart or debug screen
print('Token: ${StorageService.getToken()}');
```

If empty, user needs to login first.

### 5. **Test Endpoint Manually (Postman/Curl)**

```bash
# Get wallet balance
curl -X GET http://localhost:3001/api/payments/balance \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -H "Content-Type: application/json"

# Add money
curl -X POST http://localhost:3001/api/payments/initiate \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{"amount": 100}'
```

### 6. **Network Configuration Issues**

**Android Emulator:**
- Use `10.0.2.2` instead of `127.0.0.1`
- Update `app_constants.dart`:
  ```dart
  static const String baseUrl = 'http://10.0.2.2:3001';
  ```

**iOS Simulator:**
- Can use `127.0.0.1:3001` directly

**Physical Device:**
- Must be on same WiFi network
- Get your PC IP:
  ```bash
  # Windows
  ipconfig
  
  # Mac/Linux
  ifconfig
  ```
- Update `app_constants.dart`:
  ```dart
  static const String baseUrl = 'http://192.168.1.100:3001';
  ```

### 7. **Database Connection Issues**

If backend starts but API returns error:

```bash
# Check database connection
psql -h localhost -U postgres -d lakadiya -c "SELECT 1;"

# If fails, run migrations
cd backend
npm run migrate
```

### 8. **CORS Issues**

Update backend `backend/.env`:

```
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:3001,http://192.168.1.100:3000
```

Then restart backend.

### 9. **Full Debug Checklist**

- [ ] Backend running: `npm run dev` in `/backend`
- [ ] Database migrated: `npm run migrate`
- [ ] User logged in (token exists)
- [ ] API URL correct for your setup
- [ ] Network connectivity working
- [ ] Check console logs for exact error
- [ ] Try with Postman/curl first

## Complete Setup Flow

```bash
# 1. Terminal - Backend
cd C:\xampp\htdocs\OwnProject\RoyalRummy\lakadiya\backend
npm install
npm run migrate
npm run dev

# 2. Terminal - Mobile
cd C:\xampp\htdocs\OwnProject\RoyalRummy\lakadiya\mobile
flutter pub get
flutter run -d emulator-5554  # or your device ID

# 3. Test
# Open app → Login → Profile → Wallet → Add Money
```

## If Still Getting Error

**Collect this info:**

1. Exact error message from console
2. Backend logs (from terminal)
3. Mobile API logs (from console output)
4. Result of: `curl http://localhost:3001/health`
5. Your IP address (for device testing)

Then check:
- Backend `.env` has Razorpay keys
- Database tables created (run: `npm run migrate`)
- Token being sent in request headers
