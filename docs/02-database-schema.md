# Database Schema — RummyRoyale

## PostgreSQL 15 — Complete Schema Design

---

## 1. Users & Authentication

```sql
-- Core user account
CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone           VARCHAR(15) UNIQUE,
    email           VARCHAR(255) UNIQUE,
    username        VARCHAR(50) UNIQUE NOT NULL,
    password_hash   VARCHAR(255),
    status          VARCHAR(20) DEFAULT 'active', -- active|suspended|banned|pending_kyc
    role            VARCHAR(20) DEFAULT 'player', -- player|admin|moderator
    kyc_status      VARCHAR(20) DEFAULT 'pending', -- pending|verified|rejected
    is_verified     BOOLEAN DEFAULT FALSE,
    referral_code   VARCHAR(12) UNIQUE NOT NULL,
    referred_by     UUID REFERENCES users(id),
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),
    last_login_at   TIMESTAMPTZ,
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX idx_users_phone       ON users(phone);
CREATE INDEX idx_users_email       ON users(email);
CREATE INDEX idx_users_referral    ON users(referral_code);
CREATE INDEX idx_users_status      ON users(status) WHERE deleted_at IS NULL;

-- User profiles
CREATE TABLE user_profiles (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    full_name       VARCHAR(100),
    avatar_url      VARCHAR(500),
    date_of_birth   DATE,
    gender          VARCHAR(10),
    city            VARCHAR(100),
    state           VARCHAR(100),
    country         VARCHAR(50) DEFAULT 'IN',
    bio             VARCHAR(500),
    level           INTEGER DEFAULT 1,
    xp_points       BIGINT DEFAULT 0,
    total_games     INTEGER DEFAULT 0,
    wins            INTEGER DEFAULT 0,
    losses          INTEGER DEFAULT 0,
    win_rate        DECIMAL(5,2) DEFAULT 0.00,
    highest_score   INTEGER DEFAULT 0,
    elo_rating      INTEGER DEFAULT 1200,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Device sessions
CREATE TABLE user_devices (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID REFERENCES users(id) ON DELETE CASCADE,
    device_id       VARCHAR(255) NOT NULL,
    device_type     VARCHAR(20), -- android|ios|web
    device_model    VARCHAR(100),
    os_version      VARCHAR(50),
    app_version     VARCHAR(20),
    fcm_token       VARCHAR(500),
    ip_address      INET,
    is_trusted      BOOLEAN DEFAULT FALSE,
    last_active_at  TIMESTAMPTZ DEFAULT NOW(),
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, device_id)
);

CREATE INDEX idx_devices_user_id  ON user_devices(user_id);
CREATE INDEX idx_devices_fcm      ON user_devices(fcm_token) WHERE fcm_token IS NOT NULL;

-- Refresh tokens
CREATE TABLE refresh_tokens (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID REFERENCES users(id) ON DELETE CASCADE,
    token_hash      VARCHAR(255) UNIQUE NOT NULL,
    device_id       VARCHAR(255),
    expires_at      TIMESTAMPTZ NOT NULL,
    revoked_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_tokens_user  ON refresh_tokens(user_id);
CREATE INDEX idx_tokens_hash  ON refresh_tokens(token_hash);
```

---

## 2. Wallet & Transactions

```sql
-- User wallet (partitioned by user_id range)
CREATE TABLE wallets (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    balance_cash        DECIMAL(12,2) DEFAULT 0.00,    -- real/withdrawable
    balance_bonus       DECIMAL(12,2) DEFAULT 0.00,    -- bonus cash (non-withdrawable)
    balance_tokens      BIGINT DEFAULT 0,               -- virtual tokens/coins
    total_deposited     DECIMAL(12,2) DEFAULT 0.00,
    total_withdrawn     DECIMAL(12,2) DEFAULT 0.00,
    total_won           DECIMAL(12,2) DEFAULT 0.00,
    total_lost          DECIMAL(12,2) DEFAULT 0.00,
    is_frozen           BOOLEAN DEFAULT FALSE,
    version             BIGINT DEFAULT 0,               -- optimistic locking
    updated_at          TIMESTAMPTZ DEFAULT NOW(),
    created_at          TIMESTAMPTZ DEFAULT NOW()
);

-- Append-only transaction ledger
CREATE TABLE transactions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id),
    type            VARCHAR(50) NOT NULL,
    -- deposit|withdraw|game_entry|game_win|game_loss|refund|bonus|referral_reward
    -- tournament_entry|tournament_prize|daily_reward|cashback|admin_credit|admin_debit
    amount          DECIMAL(12,2) NOT NULL,
    currency_type   VARCHAR(20) DEFAULT 'cash',        -- cash|bonus|tokens
    balance_before  DECIMAL(12,2) NOT NULL,
    balance_after   DECIMAL(12,2) NOT NULL,
    status          VARCHAR(20) DEFAULT 'completed',   -- pending|completed|failed|reversed
    reference_id    VARCHAR(255),                       -- game_id, match_id, payment_id
    reference_type  VARCHAR(50),                        -- game|tournament|payment|reward
    metadata        JSONB DEFAULT '{}',
    ip_address      INET,
    created_at      TIMESTAMPTZ DEFAULT NOW()
) PARTITION BY RANGE (created_at);

-- Monthly partitions (example)
CREATE TABLE transactions_2024_01 PARTITION OF transactions
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
CREATE TABLE transactions_2024_02 PARTITION OF transactions
    FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');

CREATE INDEX idx_txn_user_id     ON transactions(user_id, created_at DESC);
CREATE INDEX idx_txn_type        ON transactions(type, created_at DESC);
CREATE INDEX idx_txn_reference   ON transactions(reference_id, reference_type);
CREATE INDEX idx_txn_status      ON transactions(status) WHERE status = 'pending';

-- Payment gateway orders
CREATE TABLE payment_orders (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID REFERENCES users(id),
    gateway         VARCHAR(30) NOT NULL,   -- razorpay|stripe|paytm
    gateway_order_id VARCHAR(255) UNIQUE,
    gateway_payment_id VARCHAR(255),
    gateway_signature VARCHAR(500),
    amount          DECIMAL(12,2) NOT NULL,
    currency        VARCHAR(5) DEFAULT 'INR',
    status          VARCHAR(20) DEFAULT 'created',
    -- created|attempted|paid|failed|refunded
    type            VARCHAR(20) DEFAULT 'deposit',     -- deposit|withdrawal
    failure_reason  VARCHAR(500),
    metadata        JSONB DEFAULT '{}',
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);
```

---

## 3. Game Tables & Match History

```sql
-- Game table configurations
CREATE TABLE game_tables (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_code      VARCHAR(20) UNIQUE NOT NULL,
    game_type       VARCHAR(30) NOT NULL,
    -- points_rummy|pool_rummy_101|pool_rummy_201|deals_rummy
    variant         VARCHAR(30),            -- practice|real_money|private|tournament
    max_players     SMALLINT NOT NULL,      -- 2|6
    min_players     SMALLINT DEFAULT 2,
    entry_fee       DECIMAL(10,2) DEFAULT 0,
    prize_pool      DECIMAL(10,2) DEFAULT 0,
    currency_type   VARCHAR(20) DEFAULT 'cash',
    status          VARCHAR(20) DEFAULT 'waiting',
    -- waiting|in_progress|completed|cancelled
    host_user_id    UUID REFERENCES users(id),
    is_private      BOOLEAN DEFAULT FALSE,
    private_code    VARCHAR(10),
    max_deals       SMALLINT,               -- for deals rummy
    points_per_coin DECIMAL(8,2),           -- for points rummy
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    started_at      TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ
);

CREATE INDEX idx_tables_status    ON game_tables(status);
CREATE INDEX idx_tables_type      ON game_tables(game_type, variant);
CREATE INDEX idx_tables_private   ON game_tables(private_code) WHERE is_private = TRUE;

-- Match (game session)
CREATE TABLE matches (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_id        UUID REFERENCES game_tables(id),
    match_number    SMALLINT DEFAULT 1,     -- deal number in deals rummy
    status          VARCHAR(20) DEFAULT 'in_progress',
    winner_id       UUID REFERENCES users(id),
    winning_hand    JSONB,                  -- validated winning cards
    total_points    INTEGER,
    prize_amount    DECIMAL(10,2),
    started_at      TIMESTAMPTZ DEFAULT NOW(),
    ended_at        TIMESTAMPTZ,
    duration_secs   INTEGER
) PARTITION BY RANGE (started_at);

CREATE TABLE matches_2024_q1 PARTITION OF matches
    FOR VALUES FROM ('2024-01-01') TO ('2024-04-01');

-- Player participation in each match
CREATE TABLE match_players (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id        UUID REFERENCES matches(id),
    user_id         UUID REFERENCES users(id),
    is_bot          BOOLEAN DEFAULT FALSE,
    seat_position   SMALLINT NOT NULL,
    join_time       TIMESTAMPTZ DEFAULT NOW(),
    status          VARCHAR(20) DEFAULT 'playing',
    -- playing|dropped|finished|disconnected|timed_out
    final_points    INTEGER,
    final_hand      JSONB,                  -- cards at end
    prize_won       DECIMAL(10,2) DEFAULT 0,
    rank            SMALLINT,
    UNIQUE(match_id, seat_position)
);

CREATE INDEX idx_match_players_user   ON match_players(user_id, match_id);
CREATE INDEX idx_match_players_match  ON match_players(match_id);

-- Individual game rounds/turns
CREATE TABLE game_rounds (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id        UUID REFERENCES matches(id),
    round_number    SMALLINT NOT NULL,
    current_player  UUID REFERENCES users(id),
    action          VARCHAR(30),
    -- draw_closed|draw_open|discard|declare|drop|show
    card_drawn      VARCHAR(5),             -- e.g. "AS" (Ace of Spades)
    card_discarded  VARCHAR(5),
    hand_state      JSONB,                  -- encrypted hand state
    timestamp       TIMESTAMPTZ DEFAULT NOW()
) PARTITION BY RANGE (timestamp);
```

---

## 4. Tournaments

```sql
CREATE TABLE tournaments (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(200) NOT NULL,
    description     TEXT,
    banner_url      VARCHAR(500),
    game_type       VARCHAR(30) NOT NULL,
    format          VARCHAR(30) DEFAULT 'elimination',
    -- elimination|round_robin|swiss|league
    status          VARCHAR(20) DEFAULT 'upcoming',
    -- upcoming|registration|in_progress|completed|cancelled
    max_players     INTEGER NOT NULL,
    min_players     INTEGER DEFAULT 2,
    registered_count INTEGER DEFAULT 0,
    entry_fee       DECIMAL(10,2) DEFAULT 0,
    prize_pool      DECIMAL(12,2) DEFAULT 0,
    prize_structure JSONB,
    -- [{"rank":1,"amount":5000},{"rank":2,"amount":2000}]
    registration_starts_at TIMESTAMPTZ,
    registration_ends_at   TIMESTAMPTZ,
    starts_at       TIMESTAMPTZ,
    ends_at         TIMESTAMPTZ,
    created_by      UUID REFERENCES users(id),
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE tournament_registrations (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tournament_id   UUID REFERENCES tournaments(id),
    user_id         UUID REFERENCES users(id),
    status          VARCHAR(20) DEFAULT 'registered',
    -- registered|playing|eliminated|winner
    current_round   SMALLINT DEFAULT 1,
    total_points    INTEGER DEFAULT 0,
    final_rank      SMALLINT,
    prize_won       DECIMAL(10,2),
    registered_at   TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(tournament_id, user_id)
);

CREATE INDEX idx_tourney_reg_tournament ON tournament_registrations(tournament_id);
CREATE INDEX idx_tourney_reg_user       ON tournament_registrations(user_id);
```

---

## 5. Referrals & Social

```sql
CREATE TABLE referrals (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    referrer_id     UUID NOT NULL REFERENCES users(id),
    referee_id      UUID NOT NULL REFERENCES users(id),
    code_used       VARCHAR(12) NOT NULL,
    status          VARCHAR(20) DEFAULT 'pending',
    -- pending|qualified|rewarded
    qualified_at    TIMESTAMPTZ,
    reward_amount   DECIMAL(10,2),
    reward_type     VARCHAR(20),            -- cash|bonus|tokens
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(referee_id)
);

CREATE INDEX idx_referrals_referrer ON referrals(referrer_id);

-- Teams / Clans
CREATE TABLE teams (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(100) UNIQUE NOT NULL,
    tag             VARCHAR(10) UNIQUE NOT NULL,
    description     VARCHAR(500),
    logo_url        VARCHAR(500),
    owner_id        UUID REFERENCES users(id),
    max_members     SMALLINT DEFAULT 20,
    member_count    SMALLINT DEFAULT 1,
    total_wins      INTEGER DEFAULT 0,
    level           SMALLINT DEFAULT 1,
    xp              BIGINT DEFAULT 0,
    is_public       BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE team_members (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    team_id         UUID REFERENCES teams(id) ON DELETE CASCADE,
    user_id         UUID REFERENCES users(id) ON DELETE CASCADE,
    role            VARCHAR(20) DEFAULT 'member',  -- owner|admin|member
    joined_at       TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(team_id, user_id)
);

-- Friends
CREATE TABLE friendships (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requester_id    UUID REFERENCES users(id),
    addressee_id    UUID REFERENCES users(id),
    status          VARCHAR(20) DEFAULT 'pending',  -- pending|accepted|blocked
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(requester_id, addressee_id)
);
```

---

## 6. Gamification

```sql
-- Achievements
CREATE TABLE achievements (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key             VARCHAR(100) UNIQUE NOT NULL,
    name            VARCHAR(200) NOT NULL,
    description     TEXT,
    icon_url        VARCHAR(500),
    xp_reward       INTEGER DEFAULT 0,
    token_reward    INTEGER DEFAULT 0,
    condition_type  VARCHAR(50),    -- games_played|wins|streak|tournament_win
    condition_value INTEGER,
    is_active       BOOLEAN DEFAULT TRUE
);

CREATE TABLE user_achievements (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID REFERENCES users(id),
    achievement_id  UUID REFERENCES achievements(id),
    unlocked_at     TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, achievement_id)
);

-- Daily Missions
CREATE TABLE missions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title           VARCHAR(200) NOT NULL,
    description     TEXT,
    mission_type    VARCHAR(50),    -- daily|weekly|special
    target_type     VARCHAR(50),    -- games_played|wins|deposit|referral
    target_value    INTEGER NOT NULL,
    xp_reward       INTEGER DEFAULT 0,
    token_reward    INTEGER DEFAULT 0,
    cash_reward     DECIMAL(8,2) DEFAULT 0,
    is_active       BOOLEAN DEFAULT TRUE,
    starts_at       TIMESTAMPTZ,
    ends_at         TIMESTAMPTZ
);

CREATE TABLE user_mission_progress (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID REFERENCES users(id),
    mission_id      UUID REFERENCES missions(id),
    progress        INTEGER DEFAULT 0,
    is_completed    BOOLEAN DEFAULT FALSE,
    completed_at    TIMESTAMPTZ,
    reward_claimed  BOOLEAN DEFAULT FALSE,
    date            DATE DEFAULT CURRENT_DATE,
    UNIQUE(user_id, mission_id, date)
);

-- Daily Login Rewards
CREATE TABLE daily_reward_claims (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID REFERENCES users(id),
    day_streak      INTEGER NOT NULL,
    reward_type     VARCHAR(20),
    reward_amount   DECIMAL(10,2),
    claimed_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Leaderboard snapshots (Redis is primary, DB is archive)
CREATE TABLE leaderboard_snapshots (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    period_type     VARCHAR(20),    -- daily|weekly|monthly|all_time
    period_key      VARCHAR(20),    -- '2024-W15', '2024-01', etc
    user_id         UUID REFERENCES users(id),
    rank            INTEGER,
    score           BIGINT,
    games_played    INTEGER,
    wins            INTEGER,
    created_at      TIMESTAMPTZ DEFAULT NOW()
) PARTITION BY LIST (period_type);
```

---

## 7. KYC & Compliance

```sql
CREATE TABLE kyc_documents (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID REFERENCES users(id),
    doc_type        VARCHAR(50),    -- aadhaar|pan|passport|driving_license
    doc_number      VARCHAR(100),
    doc_front_url   VARCHAR(500),
    doc_back_url    VARCHAR(500),
    selfie_url      VARCHAR(500),
    status          VARCHAR(20) DEFAULT 'pending',
    -- pending|under_review|approved|rejected
    reviewed_by     UUID REFERENCES users(id),
    rejection_reason VARCHAR(500),
    submitted_at    TIMESTAMPTZ DEFAULT NOW(),
    reviewed_at     TIMESTAMPTZ
);

-- Fraud detection events
CREATE TABLE fraud_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID REFERENCES users(id),
    event_type      VARCHAR(100),
    -- multiple_accounts|suspicious_withdrawal|emulator_detected|vpn_detected
    -- unusual_win_rate|collusion_suspected|rapid_transactions
    severity        VARCHAR(20),    -- low|medium|high|critical
    details         JSONB DEFAULT '{}',
    ip_address      INET,
    device_id       VARCHAR(255),
    resolved        BOOLEAN DEFAULT FALSE,
    reviewed_by     UUID REFERENCES users(id),
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_fraud_user      ON fraud_events(user_id, created_at DESC);
CREATE INDEX idx_fraud_type      ON fraud_events(event_type, severity);
CREATE INDEX idx_fraud_resolved  ON fraud_events(resolved) WHERE resolved = FALSE;
```

---

## 8. Notifications & Chat

```sql
CREATE TABLE notifications (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID REFERENCES users(id),
    type            VARCHAR(50),
    -- game_invite|game_result|tournament|reward|system|friend_request|chat
    title           VARCHAR(200),
    body            TEXT,
    data            JSONB DEFAULT '{}',
    is_read         BOOLEAN DEFAULT FALSE,
    sent_via        VARCHAR(50)[],  -- ['push','in_app','email']
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    read_at         TIMESTAMPTZ
) PARTITION BY RANGE (created_at);

CREATE INDEX idx_notif_user_unread ON notifications(user_id, is_read, created_at DESC)
    WHERE is_read = FALSE;

-- Chat messages (partitioned by month)
CREATE TABLE chat_messages (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id         VARCHAR(100) NOT NULL,  -- table_id, team_id, 'global', 'user:{id}'
    sender_id       UUID REFERENCES users(id),
    message         TEXT,
    message_type    VARCHAR(20) DEFAULT 'text', -- text|emoji|gif|sticker|system
    is_deleted      BOOLEAN DEFAULT FALSE,
    moderation_flag BOOLEAN DEFAULT FALSE,
    created_at      TIMESTAMPTZ DEFAULT NOW()
) PARTITION BY RANGE (created_at);

CREATE INDEX idx_chat_room ON chat_messages(room_id, created_at DESC);
```

---

## 9. Admin & CMS

```sql
CREATE TABLE admin_users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID REFERENCES users(id),
    permissions     TEXT[] DEFAULT '{}',
    -- ['users:read','users:write','wallet:manage','kyc:review','fraud:manage']
    is_active       BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Audit log for all admin actions
CREATE TABLE admin_audit_logs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id        UUID REFERENCES admin_users(id),
    action          VARCHAR(100),
    entity_type     VARCHAR(50),
    entity_id       UUID,
    changes         JSONB,
    ip_address      INET,
    created_at      TIMESTAMPTZ DEFAULT NOW()
) PARTITION BY RANGE (created_at);

-- CMS Banners
CREATE TABLE banners (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title           VARCHAR(200),
    image_url       VARCHAR(500) NOT NULL,
    link_url        VARCHAR(500),
    link_type       VARCHAR(30),    -- game|tournament|external|none
    screen          VARCHAR(50),    -- home|lobby|tournament|wallet
    position        SMALLINT DEFAULT 0,
    is_active       BOOLEAN DEFAULT TRUE,
    starts_at       TIMESTAMPTZ,
    ends_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Support tickets
CREATE TABLE support_tickets (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID REFERENCES users(id),
    ticket_number   VARCHAR(20) UNIQUE NOT NULL,
    category        VARCHAR(50),    -- wallet|game|account|kyc|other
    subject         VARCHAR(300),
    description     TEXT,
    status          VARCHAR(20) DEFAULT 'open',
    -- open|in_progress|resolved|closed
    priority        VARCHAR(20) DEFAULT 'normal',
    assigned_to     UUID REFERENCES admin_users(id),
    attachments     TEXT[],
    resolved_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);
```

---

## 10. Redis Cache Strategy

```
Key Pattern                    TTL     Value
─────────────────────────────────────────────────────────────────
session:{userId}               7d      JWT refresh token data
game:state:{tableId}           1h      Active game state JSON
game:hand:{tableId}:{userId}   1h      Player's current hand (encrypted)
leaderboard:daily              24h     Sorted set (ZSET: score → userId)
leaderboard:weekly             7d      Sorted set
matchmaking:queue:{type}       -       LIST (userId entries)
matchmaking:lock:{tableId}     30s     Mutex lock (SETNX)
user:online:{userId}           5m      "1" (heartbeat refresh)
table:players:{tableId}        1h      HASH (seatNo → userId)
bot:pool:{type}                -       SET of available bot IDs
rate_limit:{ip}:{endpoint}     1m      Counter (INCR)
wallet:lock:{userId}           10s     SETNX mutex for tx
notification:unread:{userId}   -       Counter (INCR/DECR)
```

---

## 11. Indexing Strategy Summary

| Table            | Critical Indexes                                              |
|------------------|---------------------------------------------------------------|
| users            | phone, email, referral_code, status                          |
| transactions     | (user_id, created_at DESC), (reference_id, reference_type)  |
| matches          | (table_id, started_at DESC), status                         |
| match_players    | (user_id, match_id), match_id                               |
| notifications    | (user_id, is_read, created_at) partial WHERE is_read=FALSE  |
| fraud_events     | (user_id), (event_type, severity), resolved partial         |
| game_rounds      | (match_id, round_number)                                    |
