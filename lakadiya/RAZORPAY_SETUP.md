# Razorpay Payment Integration Setup Guide

## Backend Setup

### 1. Install Dependencies
```bash
cd backend
npm install
```

### 2. Run Database Migration
The migration file `005_create_payments.sql` will create:
- `payment_transactions` table
- `wallet_balance` table  
- Automatic triggers for wallet updates

```bash
npm run migrate
```

### 3. Verify .env Configuration
Ensure `.env` file contains:
```
RAZORPAY_KEY_ID=rzp_test_SrD9RqGOrFNN3c
RAZORPAY_KEY_SECRET=nd61HKtvxcHYG8O1VIb7GYIn
```

### 4. Start Backend
```bash
npm run dev
```

## Mobile Setup

### 1. Update Dependencies
```bash
cd mobile
flutter pub get
```

This installs `razorpay_flutter` package.

### 2. Android Configuration (for Razorpay)

**android/build.gradle:**
```gradle
buildscript {
  repositories {
    google()
    mavenCentral()
  }
}

allprojects {
  repositories {
    google()
    mavenCentral()
    maven { url 'https://maven.razorpay.com' }
  }
}
```

**android/app/build.gradle:**
```gradle
android {
  compileSdkVersion 33
  minSdkVersion 21
}
```

### 3. iOS Configuration

No additional setup needed for Razorpay on iOS beyond the dependency.

### 4. Run the App
```bash
flutter run
```

## API Endpoints

### 1. Initiate Payment (Add Money)
```
POST /api/payments/initiate
Authorization: Bearer <token>
Content-Type: application/json

{
  "amount": 100
}

Response:
{
  "orderId": "order_ABC123",
  "amount": 10000,
  "currency": "INR",
  "transactionId": "uuid-here",
  "coins": 1000
}
```

### 2. Verify Payment
```
POST /api/payments/verify
Authorization: Bearer <token>
Content-Type: application/json

{
  "paymentId": "pay_ABC123",
  "orderId": "order_ABC123",
  "signature": "signature_hash"
}

Response:
{
  "success": true,
  "transactionId": "uuid-here",
  "paymentId": "pay_ABC123",
  "coins": 1000,
  "amount": 100,
  "type": "add",
  "message": "Payment verified successfully"
}
```

### 3. Get Wallet Balance
```
GET /api/payments/balance
Authorization: Bearer <token>

Response:
{
  "coins": 5000,
  "totalAdded": 500,
  "totalWithdrawn": 100,
  "currentBalance": 400
}
```

### 4. Get Transaction History
```
GET /api/payments/transactions?limit=20&offset=0
Authorization: Bearer <token>

Response:
[
  {
    "id": "uuid",
    "amount": 100,
    "coins": 1000,
    "type": "add",
    "status": "success",
    "createdAt": "2024-01-15T10:30:00Z",
    "updatedAt": "2024-01-15T10:31:00Z"
  }
]
```

### 5. Request Withdrawal
```
POST /api/payments/withdraw
Authorization: Bearer <token>
Content-Type: application/json

{
  "amount": 100
}

Response:
{
  "message": "Withdrawal request submitted",
  "data": {
    "id": "uuid",
    "amount": 100,
    "coins": 1000,
    "type": "withdraw",
    "status": "pending",
    "createdAt": "2024-01-15T10:30:00Z"
  }
}
```

## Coin Conversion

**1 INR = 10 Coins**

Examples:
- ₹100 = 1000 coins
- ₹200 = 2000 coins
- ₹500 = 5000 coins

## Integration in Profile Screen

Add to your profile screen:

```dart
import 'package:go_router/go_router.dart';

// In Profile Widget
ListTile(
  leading: const Icon(Icons.wallet),
  title: const Text('Wallet & Payments'),
  subtitle: const Text('View balance & transactions'),
  onTap: () => context.push('/wallet'),
)
```

Add route in main router:
```dart
GoRoute(
  path: '/wallet',
  builder: (context, state) => BlocProvider(
    create: (_) => PaymentBloc(PaymentRepository(dio)),
    child: const WalletScreen(),
  ),
)
```

## Features Implemented

✅ Add Money via Razorpay
✅ Payment Verification with Signature Validation
✅ Wallet Balance Display
✅ Transaction History
✅ Withdrawal Requests
✅ Real-time Coin Updates
✅ Multiple Quick Amount Selection
✅ Transaction Status Tracking

## Testing

### Test Cards (Razorpay Sandbox)

**Success:**
- Card: 4111111111111111
- Expiry: Any future date
- CVV: Any 3 digits

**Test Phone:** Any 10-digit number

## Production Checklist

- [ ] Update Razorpay keys to live keys
- [ ] Update backend API URL to production
- [ ] Test with real payments
- [ ] Implement withdrawal approval workflow
- [ ] Set up bank account linking for withdrawals
- [ ] Add KYC verification for withdrawals
- [ ] Implement TDS calculations if applicable
- [ ] Add audit logging for all transactions
- [ ] Set up alerts for failed payments
- [ ] Implement rate limiting on payment endpoints
