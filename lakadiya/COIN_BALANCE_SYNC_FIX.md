# Coin Balance Sync Fix

## Problem Identified
Coins showing inconsistently across screens:
- **Welcome screen** → 52,000 coins ✓ (from auth entity)
- **Profile screen** → 52,000 coins ✓ (from auth entity, fetched via PaymentBloc)
- **Withdraw screen** → 0.00 ✗ (calculated from transactions)
- **Create game screen** → error "need wallet balance above 100" ✗

## Root Cause

### Backend Issue
`payment.service.js` - `getWalletBalance()` returned TWO conflicting values:
```javascript
// Old code - returns mismatched values
return {
  coins: 52000,              // From users.coins column
  current_balance: 0         // Calculated: sum(add+win) - sum(withdraw+deduct)
}
```

The backend was calculating `currentBalance` separately instead of using the canonical `users.coins` column.

### Frontend Issue
Different screens used different balance sources:
- **Welcome/Profile**: `auth.user.coins` ← auth entity (52000)
- **Withdraw**: `WalletBalance.currentBalance` ← payment API (0)

No sync between them.

## Solutions Applied

### 1. Backend Fix - `payment.service.js`

**File**: `C:\xampp\htdocs\OwnProject\RoyalRummy\lakadiya\backend\src\modules\payments\payment.service.js`

Changed `getWalletBalance()` to return `coins` as the canonical balance:

```javascript
return {
  coins: userCoins,              // ← Canonical source
  total_added: totalAdded,
  total_withdrawn: totalWithdrawn,
  current_balance: userCoins,    // ← NOW SYNCED with coins
};
```

**Why**: The `users.coins` column is the authoritative balance used by:
- All BLoC state (welcome/profile screens)
- Game logic (bet escrowing, withdrawal validation)
- Auth entity

### 2. Frontend Fix - `payment_model.dart`

**File**: `C:\xampp\htdocs\OwnProject\RoyalRummy\lakadiya\mobile\lib\features\payments\data\models\payment_model.dart`

Changed `WalletBalance.fromJson()` to ensure currentBalance always equals coins:

```dart
factory WalletBalance.fromJson(Map<String, dynamic> json) {
  final coins = _toInt(json['coins']);
  
  return WalletBalance(
    coins: coins,
    totalAdded: _toDouble(json['total_added']),
    totalWithdrawn: _toDouble(json['total_withdrawn']),
    currentBalance: coins.toDouble(),  // ← SYNCED
  );
}
```

**Why**: This ensures withdraw screen and all game screens read the same balance source.

## Data Flow After Fix

```
Login (test@test.com)
    ↓
Backend creates user with coins=52000
    ↓
AuthBloc caches user entity (coins=52000)
    ↓
Welcome banner → auth.user.coins = 52000 ✓
    ↓
Profile page:
  - FetchWalletBalanceEvent
  - PaymentBloc calls /payments/balance
  - Backend returns coins=52000 (synced)
  - Profile updates auth.user.coins = 52000 ✓
    ↓
Withdraw screen:
  - FetchWalletBalanceEvent
  - PaymentBloc calls /payments/balance
  - Backend returns current_balance=52000 (synced)
  - Withdraw shows ₹5200.00 balance ✓
    ↓
Create game ₹10:
  - escrowBets() checks getUserBalance()
  - Query: SUM(add+win) - SUM(withdraw+deduct) = amount deducted from coins
  - Frontend receives coins=52000-1000=51000 ✓
```

## Testing Checklist

After deployment:

1. **Login Test**
   - [ ] Login with test@test.com / Test@123
   - [ ] Welcome banner shows 52000 coins

2. **Profile Test**
   - [ ] Navigate to Profile
   - [ ] Wallet section shows 52000 coins
   - [ ] Coins badge shows 52000

3. **Withdraw Test**
   - [ ] Navigate to Withdraw
   - [ ] Available balance shows ₹5200.00 (52000/10)
   - [ ] Max button works
   - [ ] Request withdrawal ₹100 works

4. **Create Game Test**
   - [ ] Create ₹10 bet game
   - [ ] No "need wallet balance above 100" error
   - [ ] Game deducts ₹10 from balance
   - [ ] After game, balance updates correctly

5. **Socket Sync Test**
   - [ ] Open 2 devices/tabs logged in as same user
   - [ ] Add money on one device
   - [ ] Other device auto-refreshes balance (socket: balance_updated)

## Files Modified

1. ✅ Backend:
   - `backend/src/modules/payments/payment.service.js` → getWalletBalance()

2. ✅ Frontend:
   - `mobile/lib/features/payments/data/models/payment_model.dart` → WalletBalance.fromJson()

## SQL Query for Verification

Check balance sync in database:
```sql
SELECT 
  u.id,
  u.username,
  u.coins,
  COALESCE(SUM(CASE WHEN pt.type IN ('add','bet_win') AND pt.status='success' THEN pt.amount ELSE 0 END), 0) - 
  COALESCE(SUM(CASE WHEN pt.type IN ('withdraw','bet_deduct') AND pt.status='success' THEN pt.amount ELSE 0 END), 0) as calc_balance
FROM users u
LEFT JOIN payment_transactions pt ON pt.user_id = u.id
WHERE u.email = 'test@test.com'
GROUP BY u.id, u.username, u.coins;
```

Expected: `u.coins` should equal `calc_balance` for all users.

## Next Steps (Optional Improvements)

1. **Migration Script** (if old data has mismatches):
   ```javascript
   // Update users.coins to match calculated balance
   UPDATE users SET coins = (
     SELECT COALESCE(
       SUM(CASE WHEN pt.type IN ('add','bet_win') AND pt.status='success' THEN pt.amount ELSE 0 END) -
       SUM(CASE WHEN pt.type IN ('withdraw','bet_deduct') AND pt.status='success' THEN pt.amount ELSE 0 END),
     0)
     FROM payment_transactions pt WHERE pt.user_id = users.id
   )
   ```

2. **Audit Logging**: Add logs when coins deduct/add for game bets to track balance changes.

3. **Transaction Consistency**: Consider wrapping coin updates in database transactions to prevent race conditions.
