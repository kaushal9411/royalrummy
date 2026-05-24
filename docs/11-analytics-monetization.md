# Analytics & Monetization — RummyRoyale

## 1. Revenue Streams

| Stream                  | Mechanism                              | Typical Margin |
|-------------------------|----------------------------------------|----------------|
| Platform Rake           | 10-15% of each game prize pool         | Primary         |
| Tournament Entry        | Platform cut from tournament prize pools| Primary        |
| Deposit Bonus Rollover  | Users must play 2× deposit before WD  | Retention       |
| VIP Membership          | ₹99/month, ₹999/year — perks           | Subscription    |
| Battle Pass             | ₹199/month — cosmetics + bonuses       | Subscription    |
| Token Shop              | Buy cosmetics with tokens              | Microtransaction|
| Referral Acquisition    | Lower CAC vs paid ads                  | Cost Reduction  |

---

## 2. Rake Calculation

```typescript
// Platform fee by game type
const RAKE_CONFIG = {
  points_rummy: {
    rake_percent: 0.10,    // 10%
    max_rake_per_game: 50, // ₹50 cap
  },
  pool_rummy_101: {
    rake_percent: 0.10,
    max_rake_per_game: 100,
  },
  pool_rummy_201: {
    rake_percent: 0.08,
    max_rake_per_game: 200,
  },
  deals_rummy: {
    rake_percent: 0.10,
    max_rake_per_game: 150,
  },
  tournament: {
    rake_percent: 0.15,     // Higher for tournaments
    max_rake: null,
  },
};
```

---

## 3. Key Metrics to Track

### Acquisition Metrics
```
DAI  — Daily Active Installs
CAC  — Cost of Acquisition per User
CVR  — Install → Registration conversion rate
      Target: > 60%
Reg → Deposit CVR
      Target: > 25%
```

### Engagement Metrics
```
DAU  — Daily Active Users
MAU  — Monthly Active Users
DAU/MAU — Stickiness ratio
          Target: > 25%
Avg session duration    Target: > 20 min
Games per session       Target: > 3
Avg sessions per day    Target: > 2
```

### Retention Metrics
```
D1  Retention   Target: > 45%
D7  Retention   Target: > 25%
D14 Retention   Target: > 18%
D30 Retention   Target: > 12%
```

### Revenue Metrics
```
ARPU    — Average Revenue Per User (monthly)
ARPPU   — Average Revenue Per Paying User
Revenue = Rake + Membership + Token Sales
LTV     — Lifetime Value
          Target: LTV > 3× CAC
```

---

## 4. Analytics Event Schema

```typescript
// Every event has this base structure
interface AnalyticsEvent {
  event_name: string;
  user_id: string;
  session_id: string;
  device_id: string;
  app_version: string;
  platform: 'android' | 'ios' | 'web';
  timestamp: string;
  properties: Record<string, any>;
}

// Key events
const EVENTS = {
  // Acquisition
  'app_install':              { referrer: string, campaign: string },
  'registration_started':     { method: 'phone' | 'email' | 'google' },
  'registration_completed':   { referral_code_used: boolean },
  'otp_verified':             {},

  // Onboarding
  'tutorial_started':         {},
  'tutorial_step_completed':  { step: number },
  'tutorial_completed':       { time_taken_secs: number },
  'first_game_started':       { game_type: string, is_practice: boolean },
  'first_deposit_completed':  { amount: number, method: string },

  // Game
  'game_table_viewed':        { game_type: string, entry_fee: number },
  'game_joined':              { game_type: string, entry_fee: number, table_id: string },
  'game_started':             { game_type: string, player_count: number },
  'game_completed':           { result: 'win'|'loss'|'drop', points: number, prize: number },
  'game_dropped':             { reason: 'manual'|'timeout', turn_number: number },

  // Wallet
  'deposit_initiated':        { amount: number, method: string },
  'deposit_completed':        { amount: number, method: string },
  'deposit_failed':           { amount: number, failure_reason: string },
  'withdrawal_requested':     { amount: number },
  'withdrawal_completed':     { amount: number },

  // Tournament
  'tournament_viewed':        { tournament_id: string, entry_fee: number },
  'tournament_registered':    { tournament_id: string, entry_fee: number },
  'tournament_completed':     { tournament_id: string, rank: number, prize: number },

  // Social
  'referral_link_shared':     { channel: 'whatsapp'|'telegram'|'copy' },
  'friend_invited':           { method: string },
};
```

---

## 5. Analytics Pipeline

```
Game/API Events
      │
      ▼
analytics-service (NestJS)
      │
      ├─ Write to analytics_events table (PostgreSQL)
      ├─ Publish to analytics Kafka topic
      │
      ▼
Data Warehouse (BigQuery / Redshift)
      │
      ├─ Nightly ETL jobs
      ├─ Funnel analysis
      ├─ Cohort analysis
      │
      ▼
BI Dashboard (Metabase / Superset)
      │
      └─ Revenue reports, retention curves, A/B test results
```

---

## 6. A/B Testing Framework

```typescript
// Remote config + Firebase A/B Testing
const AB_TESTS = {
  'new_user_bonus_amount': {
    control: 25,      // ₹25 bonus
    variant_a: 50,    // ₹50 bonus
    variant_b: 100,   // ₹100 bonus (higher CAC but better CVR?)
    metric: 'first_deposit_rate',
  },
  'matchmaking_bot_threshold': {
    control: 30,       // Bot fills after 30s wait
    variant_a: 15,     // Faster fill = faster game start
    metric: 'game_drop_rate_pre_start',
  },
};

// Assign user to variant deterministically
function getVariant(userId: string, testKey: string): string {
  const hash = crypto.createHash('md5')
    .update(`${userId}-${testKey}`)
    .digest('hex');
  const bucket = parseInt(hash.slice(0, 8), 16) % 100;

  if (bucket < 33) return 'control';
  if (bucket < 66) return 'variant_a';
  return 'variant_b';
}
```

---

## 7. VIP Membership System

```typescript
const VIP_TIERS = {
  bronze: {
    threshold_monthly_deposit: 1000,
    perks: {
      cashback_percent: 2,
      tournament_discount: 5,
      extra_daily_bonus: 10,
      priority_support: false,
      exclusive_tables: false,
    },
  },
  silver: {
    threshold_monthly_deposit: 5000,
    perks: {
      cashback_percent: 5,
      tournament_discount: 10,
      extra_daily_bonus: 25,
      priority_support: true,
      exclusive_tables: false,
    },
  },
  gold: {
    threshold_monthly_deposit: 20000,
    perks: {
      cashback_percent: 8,
      tournament_discount: 15,
      extra_daily_bonus: 50,
      priority_support: true,
      exclusive_tables: true,
      personal_account_manager: true,
    },
  },
  platinum: {
    threshold_monthly_deposit: 50000,
    perks: {
      cashback_percent: 12,
      tournament_discount: 20,
      extra_daily_bonus: 100,
      priority_support: true,
      exclusive_tables: true,
      personal_account_manager: true,
      weekly_bonus: 500,
    },
  },
};
```

---

## 8. Battle Pass

```typescript
interface BattlePassTier {
  tier: number;
  xp_required: number;
  free_reward: Reward | null;
  premium_reward: Reward;
}

const BATTLE_PASS_SEASON = {
  name: 'Monsoon Madness Season 1',
  duration_days: 30,
  price: 199,
  tiers: [
    { tier: 1,  xp_required: 0,    free_reward: { type: 'tokens', amount: 50 },  premium_reward: { type: 'avatar_frame', id: 'gold_frame' } },
    { tier: 5,  xp_required: 500,  free_reward: { type: 'bonus', amount: 20 },   premium_reward: { type: 'bonus', amount: 50 } },
    { tier: 10, xp_required: 1500, free_reward: null,                            premium_reward: { type: 'cash', amount: 100 } },
    { tier: 20, xp_required: 4000, free_reward: { type: 'tokens', amount: 200 }, premium_reward: { type: 'cash', amount: 300 } },
    { tier: 30, xp_required: 8000, free_reward: null,                            premium_reward: { type: 'cash', amount: 500 } },
  ],
};
```

---

## 9. Retention Mechanics

```
Day 1:   Guided first game with tutorial
Day 1:   First deposit bonus (match 100% up to ₹500)
Day 1-7: Daily login streak reward (escalating)

Day 3:   "You're on a 3-day streak!" push notification
Day 7:   Week 1 achievement badge + ₹25 bonus

Week 2:  First tournament unlock
Week 2:  Friend invite push ("You and friends can earn extra")

Day 14:  Re-engagement push if inactive 3 days
Day 30:  Monthly leaderboard close notification

Churn prevention:
  - User inactive 2 days → "Your friend X just won ₹500!" notification
  - User inactive 4 days → "₹25 bonus waiting for you" notification
  - User inactive 7 days → Email + SMS with exclusive offer
```
