# Wallet System — RummyRoyale

## 1. Wallet Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          WALLET SERVICE                                 │
│                                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────────┐    │
│  │  Deposit     │  │  Withdrawal  │  │  Internal Transfer Engine  │    │
│  │  Engine      │  │  Engine      │  │  (entry fees, prizes)      │    │
│  └──────┬───────┘  └──────┬───────┘  └───────────────┬────────────┘    │
│         │                 │                           │                 │
│  ┌──────▼───────────────────────────────────────────-▼────────────┐    │
│  │              LEDGER ENGINE (Append-only)                       │    │
│  │  Double-entry bookkeeping │ Atomic transactions │ Audit trail  │    │
│  └───────────────────────────────────────────────────────────────┘    │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────┐      │
│  │              FRAUD DETECTION ENGINE                          │      │
│  │  Velocity checks │ Pattern detection │ ML scoring           │      │
│  └──────────────────────────────────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────────────────┘
         │                │                │
   ┌─────▼─────┐   ┌──────▼──────┐  ┌─────▼──────┐
   │ Razorpay  │   │  PostgreSQL │  │   Redis    │
   │ / Stripe  │   │  (Ledger)   │  │  (Locks)   │
   └───────────┘   └─────────────┘  └────────────┘
```

---

## 2. Currency Types

| Type         | Withdrawable | Earned By                           | Use Case                    |
|--------------|-------------|--------------------------------------|-----------------------------|
| cash         | YES         | Deposits, winnings                   | Real games, withdrawals     |
| bonus        | NO          | Sign-up, referrals, promotions       | Only for entry fees         |
| tokens       | NO          | Daily rewards, missions, achievements| Buy cosmetics, powerups     |

### Balance Rules
- Entry fee deducted from `bonus` first, then `cash`
- Winnings always credited to `cash`
- Minimum withdrawal: ₹100
- Withdrawal requires KYC verification

---

## 3. Transaction Flow: Game Entry Fee

```
User joins table (entry fee ₹50)
        │
        ▼
  WalletService.deductEntryFee(userId, tableId, amount=50)
        │
        ├─ Acquire Redis lock: wallet:lock:{userId} (10s SETNX)
        │   └─ If lock fails → retry 3x with 100ms delay
        │
        ├─ Fetch wallet with optimistic lock (SELECT ... FOR UPDATE)
        │
        ├─ Check balance: bonus_balance + cash_balance >= 50
        │   └─ If insufficient → throw WALLET_001
        │
        ├─ Deduct (bonus first, then cash):
        │   bonus_deducted = min(bonus_balance, 50) = 20
        │   cash_deducted  = 50 - 20 = 30
        │
        ├─ BEGIN TRANSACTION
        │   UPDATE wallets SET
        │     balance_bonus = balance_bonus - 20,
        │     balance_cash = balance_cash - 30,
        │     version = version + 1
        │   WHERE user_id = ? AND version = current_version
        │   → If 0 rows affected → version conflict → retry
        │
        │   INSERT INTO transactions (type='game_entry', amount=-50, ...)
        │   INSERT INTO transactions (type='game_entry', amount=-20, currency='bonus', ...)
        │
        │   UPDATE game_tables SET prize_pool = prize_pool + 50 WHERE id = tableId
        │
        ├─ COMMIT
        │
        └─ Release Redis lock
```

---

## 4. Transaction Flow: Prize Distribution

```
Game ends → Winner determined
        │
        ▼
  TournamentService.distributePrizes(matchId, winnerId, amount)
        │
        ├─ Calculate platform fee: amount * 0.10 (10% rake)
        ├─ Net prize = amount - platform_fee
        │
        ├─ BEGIN TRANSACTION
        │   UPDATE wallets SET
        │     balance_cash = balance_cash + net_prize
        │   WHERE user_id = winner_id
        │
        │   INSERT INTO transactions (type='game_win', amount=+net_prize, ...)
        │
        │   INSERT INTO transactions (type='platform_fee', amount=-rake, ...)
        │
        ├─ COMMIT
        │
        ├─ Update match_players.prize_won
        ├─ Update user_profiles.total_won, wins
        └─ Emit wallet_updated via WebSocket to winner
```

---

## 5. Wallet Service Implementation

```typescript
// wallet-service/src/wallet/wallet.service.ts
@Injectable()
export class WalletService {

  constructor(
    @InjectRepository(Wallet) private walletRepo: Repository<Wallet>,
    @InjectRepository(Transaction) private txnRepo: Repository<Transaction>,
    private readonly redisService: RedisService,
    private readonly dataSource: DataSource,
  ) {}

  async deductEntryFee(
    userId: string,
    referenceId: string,
    amount: number,
  ): Promise<Transaction> {
    const lockKey = `wallet:lock:${userId}`;
    const lockAcquired = await this.redisService.setnx(lockKey, '1', 10);

    if (!lockAcquired) {
      throw new WalletException('WALLET_CONCURRENT_OPERATION');
    }

    try {
      return await this.dataSource.transaction(async (manager) => {
        // Pessimistic lock on wallet row
        const wallet = await manager.findOne(Wallet, {
          where: { user_id: userId },
          lock: { mode: 'pessimistic_write' },
        });

        const totalAvailable = +wallet.balance_cash + +wallet.balance_bonus;
        if (totalAvailable < amount) {
          throw new WalletException('WALLET_001');
        }

        // Deduct bonus first
        const bonusDeducted = Math.min(+wallet.balance_bonus, amount);
        const cashDeducted = amount - bonusDeducted;

        const snapshot = {
          cash_before: wallet.balance_cash,
          bonus_before: wallet.balance_bonus,
        };

        await manager.update(Wallet, { user_id: userId }, {
          balance_cash: () => `balance_cash - ${cashDeducted}`,
          balance_bonus: () => `balance_bonus - ${bonusDeducted}`,
          updated_at: new Date(),
        });

        const txn = manager.create(Transaction, {
          user_id: userId,
          type: 'game_entry',
          amount: -amount,
          currency_type: 'mixed',
          balance_before: snapshot.cash_before,
          balance_after: +snapshot.cash_before - cashDeducted,
          reference_id: referenceId,
          reference_type: 'game',
          metadata: {
            bonus_deducted: bonusDeducted,
            cash_deducted: cashDeducted,
          },
        });

        return manager.save(txn);
      });
    } finally {
      await this.redisService.del(lockKey);
    }
  }

  async creditPrize(
    userId: string,
    amount: number,
    matchId: string,
  ): Promise<void> {
    const rake = amount * 0.10;
    const netPrize = amount - rake;

    await this.dataSource.transaction(async (manager) => {
      const wallet = await manager.findOne(Wallet, {
        where: { user_id: userId },
        lock: { mode: 'pessimistic_write' },
      });

      await manager.update(Wallet, { user_id: userId }, {
        balance_cash: () => `balance_cash + ${netPrize}`,
        total_won: () => `total_won + ${netPrize}`,
      });

      await manager.save(Transaction, {
        user_id: userId,
        type: 'game_win',
        amount: netPrize,
        currency_type: 'cash',
        balance_before: wallet.balance_cash,
        balance_after: +wallet.balance_cash + netPrize,
        reference_id: matchId,
        reference_type: 'game',
        metadata: { gross_prize: amount, rake_deducted: rake },
      });
    });
  }
}
```

---

## 6. Razorpay Integration

```typescript
// wallet-service/src/payment/razorpay.service.ts
@Injectable()
export class RazorpayService {

  private razorpay: Razorpay;

  constructor() {
    this.razorpay = new Razorpay({
      key_id: process.env.RAZORPAY_KEY_ID,
      key_secret: process.env.RAZORPAY_KEY_SECRET,
    });
  }

  async createOrder(userId: string, amountINR: number): Promise<PaymentOrder> {
    // Razorpay amount is in paise (×100)
    const razorOrder = await this.razorpay.orders.create({
      amount: amountINR * 100,
      currency: 'INR',
      receipt: `dep_${userId}_${Date.now()}`,
      notes: { user_id: userId },
    });

    return this.orderRepo.save({
      user_id: userId,
      gateway: 'razorpay',
      gateway_order_id: razorOrder.id,
      amount: amountINR,
      currency: 'INR',
      status: 'created',
      type: 'deposit',
    });
  }

  async verifyPayment(
    orderId: string,
    paymentId: string,
    signature: string,
  ): Promise<boolean> {
    const expectedSignature = crypto
      .createHmac('sha256', process.env.RAZORPAY_KEY_SECRET)
      .update(`${orderId}|${paymentId}`)
      .digest('hex');

    return expectedSignature === signature;
  }

  async handleWebhook(payload: any, signature: string): Promise<void> {
    // Verify webhook signature
    const isValid = this.verifyWebhook(payload, signature);
    if (!isValid) throw new Error('Invalid webhook signature');

    const event = payload.event;

    if (event === 'payment.captured') {
      await this.handlePaymentCaptured(payload.payload.payment.entity);
    } else if (event === 'refund.processed') {
      await this.handleRefundProcessed(payload.payload.refund.entity);
    }
  }
}
```

---

## 7. GST & Tax Compliance (India)

```typescript
// Tax calculation for Indian market
interface TaxCalculation {
  gross_amount: number;
  gst_amount: number;      // 28% GST on platform fee
  tds_amount: number;      // 30% TDS on net winnings > ₹10,000
  net_amount: number;
}

function calculateTax(grossWinning: number, entryFee: number): TaxCalculation {
  const platformFee = grossWinning * 0.10;
  const gst = platformFee * 0.28;

  const netWinning = grossWinning - entryFee;
  const tds = netWinning > 10000 ? netWinning * 0.30 : 0;

  return {
    gross_amount: grossWinning,
    gst_amount: gst,
    tds_amount: tds,
    net_amount: grossWinning - gst - tds,
  };
}
```

---

## 8. Fraud Prevention Rules

```typescript
// Real-time fraud checks triggered on each transaction
const fraudRules = [
  {
    name: 'rapid_withdrawals',
    check: async (userId, amount) => {
      const recentWithdrawals = await countTransactions(userId, 'withdraw', '1h');
      return recentWithdrawals > 3;
    },
    action: 'flag_and_review',
  },
  {
    name: 'unusual_win_rate',
    check: async (userId) => {
      const stats = await getUserGameStats(userId, '24h');
      return stats.win_rate > 0.95 && stats.games_played > 20;
    },
    action: 'flag_high_severity',
  },
  {
    name: 'multiple_accounts_same_device',
    check: async (userId, deviceId) => {
      const deviceUsers = await getUsersByDevice(deviceId);
      return deviceUsers.length > 1;
    },
    action: 'ban_and_freeze_wallet',
  },
  {
    name: 'velocity_deposits',
    check: async (userId) => {
      const deposits24h = await sumTransactions(userId, 'deposit', '24h');
      return deposits24h > 50000; // ₹50K in 24h
    },
    action: 'require_enhanced_kyc',
  },
];
```

---

## 9. Daily Reward System

```typescript
// Streak-based daily rewards
const DAILY_REWARDS = [
  { day: 1, type: 'tokens', amount: 100 },
  { day: 2, type: 'tokens', amount: 150 },
  { day: 3, type: 'bonus_cash', amount: 5 },
  { day: 4, type: 'tokens', amount: 200 },
  { day: 5, type: 'tokens', amount: 250 },
  { day: 6, type: 'bonus_cash', amount: 10 },
  { day: 7, type: 'bonus_cash', amount: 25 },  // Week reward
];
```

---

## 10. Referral Engine

```typescript
// Referral reward tiers
const REFERRAL_CONFIG = {
  referee_signup_bonus: { type: 'bonus', amount: 50 },    // Person who joined
  referrer_first_deposit: { type: 'cash', amount: 100 },  // When referred deposits
  referrer_first_game: { type: 'tokens', amount: 500 },   // When referred plays first game
  referrer_milestone: [
    { count: 5, reward: { type: 'cash', amount: 200 } },
    { count: 10, reward: { type: 'cash', amount: 500 } },
    { count: 25, reward: { type: 'cash', amount: 1500 } },
  ],
};
```
