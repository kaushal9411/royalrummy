# Admin Payment Management - Implementation Complete

## Backend Endpoints

### User Endpoints (Authenticated)
- `POST /api/payments/initiate` — Create payment order
- `POST /api/payments/verify` — Verify payment
- `GET /api/payments/balance` — Get wallet balance
- `GET /api/payments/transactions` — Get add money history
- `GET /api/payments/withdrawals` — Get withdrawal requests
- `POST /api/payments/withdraw` — Request withdrawal

### Admin Endpoints (Admin Auth Required)
- `GET /api/payments/admin/transactions?userId=xxx` — Get all add money transactions (optionally filtered by user)
- `GET /api/payments/admin/withdrawals?status=pending` — Get all withdrawals (filterable by status: pending/success/failed)
- `PATCH /api/payments/admin/withdrawals/:transactionId/approve` — Approve withdrawal
- `PATCH /api/payments/admin/withdrawals/:transactionId/reject` — Reject withdrawal (with reason)

## Features Implemented

### 1. Payment Management
- View all user payments (add money transactions)
- Filter by user ID
- See status (pending, success, failed)
- View user details (username, email, amount, timestamp)

### 2. Withdrawal Management
- View all withdrawal requests
- Filter by status: pending, success, failed
- Approve pending withdrawals (status → success)
- Reject withdrawals with reason (status → failed, coins refunded to user)
- Approve/reject actions in popup menu

### 3. Admin Dashboard UI
Two tabs in mobile admin panel:
- **Add Money Tab**: Shows all user add money transactions
- **Withdrawals Tab**: Shows all withdrawal requests with approve/reject actions

## Database Changes

Tables created in migration `005_create_payments.sql`:
- `payment_transactions` — Tracks all add/withdraw transactions
- `wallet_balance` — Tracks wallet totals per user

## Admin Flow

1. Admin opens Payment Management dashboard
2. Switch between "Add Money" and "Withdrawals" tabs
3. View all transactions with user details
4. For withdrawals: Click menu → Approve/Reject
5. Rejection requires reason (refunds coins automatically)
6. Refresh to see updated status

## API Response Examples

### Get All Withdrawals
```bash
GET /api/payments/admin/withdrawals?status=pending
```
Response:
```json
[
  {
    "id": "uuid",
    "user_id": "uuid",
    "username": "player_name",
    "email": "player@email.com",
    "amount": 200,
    "coins": 2000,
    "status": "pending",
    "created_at": "2026-05-25T10:00:00Z",
    "updated_at": "2026-05-25T10:00:00Z"
  }
]
```

### Approve Withdrawal
```bash
PATCH /api/payments/admin/withdrawals/{transactionId}/approve
```

### Reject Withdrawal
```bash
PATCH /api/payments/admin/withdrawals/{transactionId}/reject
Body: { "reason": "Insufficient documentation" }
```
When rejected:
- Status changes to "failed"
- Coins automatically refunded to user
- Reason stored in description field

## Integration Points

1. **In Admin Panel**: Import and add `AdminPaymentDashboard` to admin routes
2. **Auth Check**: Uses `authenticateAdmin` middleware (requires admin role from JWT)
3. **Real-time**: Use refresh button or pull-to-refresh to see updates

## Testing Checklist

- [ ] View add money transactions
- [ ] View pending withdrawals
- [ ] Filter withdrawals by status
- [ ] Approve a withdrawal
- [ ] Reject a withdrawal (with reason)
- [ ] Verify coins refunded on rejection
- [ ] Check user wallet balance updated correctly
