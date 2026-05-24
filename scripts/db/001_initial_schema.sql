-- =============================================================================
-- RummyRoyale — Initial Database Schema
-- Run: psql $DATABASE_URL -f scripts/db/001_initial_schema.sql
-- =============================================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- =============================================================================
-- USERS & AUTH
-- =============================================================================
CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone           VARCHAR(15) UNIQUE,
    email           VARCHAR(255) UNIQUE,
    username        VARCHAR(50) UNIQUE NOT NULL,
    password_hash   VARCHAR(255),
    status          VARCHAR(20) DEFAULT 'active'
                    CHECK (status IN ('active','suspended','banned','pending_kyc')),
    role            VARCHAR(20) DEFAULT 'player'
                    CHECK (role IN ('player','admin','moderator','super_admin')),
    kyc_status      VARCHAR(20) DEFAULT 'pending'
                    CHECK (kyc_status IN ('pending','verified','rejected')),
    is_verified     BOOLEAN DEFAULT FALSE,
    referral_code   VARCHAR(12) UNIQUE NOT NULL,
    referred_by     UUID REFERENCES users(id),
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),
    last_login_at   TIMESTAMPTZ,
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX idx_users_phone       ON users(phone) WHERE phone IS NOT NULL;
CREATE INDEX idx_users_email       ON users(email) WHERE email IS NOT NULL;
CREATE INDEX idx_users_referral    ON users(referral_code);
CREATE INDEX idx_users_status      ON users(status) WHERE deleted_at IS NULL;
CREATE INDEX idx_users_username_trgm ON users USING gin(username gin_trgm_ops);

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

CREATE TABLE user_devices (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID REFERENCES users(id) ON DELETE CASCADE,
    device_id       VARCHAR(255) NOT NULL,
    device_type     VARCHAR(20) DEFAULT 'android',
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

CREATE TABLE refresh_tokens (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID REFERENCES users(id) ON DELETE CASCADE,
    token_hash      VARCHAR(255) UNIQUE NOT NULL,
    device_id       VARCHAR(255),
    expires_at      TIMESTAMPTZ NOT NULL,
    revoked_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_tokens_user      ON refresh_tokens(user_id);
CREATE INDEX idx_tokens_hash      ON refresh_tokens(token_hash);
CREATE INDEX idx_tokens_active    ON refresh_tokens(user_id, expires_at)
    WHERE revoked_at IS NULL;

-- =============================================================================
-- WALLETS & TRANSACTIONS
-- =============================================================================
CREATE TABLE wallets (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    balance_cash        DECIMAL(12,2) DEFAULT 0.00,
    balance_bonus       DECIMAL(12,2) DEFAULT 0.00,
    balance_tokens      BIGINT DEFAULT 0,
    total_deposited     DECIMAL(12,2) DEFAULT 0.00,
    total_withdrawn     DECIMAL(12,2) DEFAULT 0.00,
    total_won           DECIMAL(12,2) DEFAULT 0.00,
    total_lost          DECIMAL(12,2) DEFAULT 0.00,
    is_frozen           BOOLEAN DEFAULT FALSE,
    version             BIGINT DEFAULT 0,
    updated_at          TIMESTAMPTZ DEFAULT NOW(),
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT chk_positive_cash    CHECK (balance_cash >= 0),
    CONSTRAINT chk_positive_bonus   CHECK (balance_bonus >= 0),
    CONSTRAINT chk_positive_tokens  CHECK (balance_tokens >= 0)
);

CREATE TABLE transactions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id),
    type            VARCHAR(50) NOT NULL,
    amount          DECIMAL(12,2) NOT NULL,
    currency_type   VARCHAR(20) DEFAULT 'cash'
                    CHECK (currency_type IN ('cash','bonus','tokens','mixed')),
    balance_before  DECIMAL(12,2) NOT NULL,
    balance_after   DECIMAL(12,2) NOT NULL,
    status          VARCHAR(20) DEFAULT 'completed'
                    CHECK (status IN ('pending','completed','failed','reversed')),
    reference_id    VARCHAR(255),
    reference_type  VARCHAR(50),
    metadata        JSONB DEFAULT '{}',
    ip_address      INET,
    created_at      TIMESTAMPTZ DEFAULT NOW()
) PARTITION BY RANGE (created_at);

CREATE TABLE transactions_default PARTITION OF transactions DEFAULT;

CREATE INDEX idx_txn_user_id     ON transactions(user_id, created_at DESC);
CREATE INDEX idx_txn_type        ON transactions(type, created_at DESC);
CREATE INDEX idx_txn_reference   ON transactions(reference_id, reference_type)
    WHERE reference_id IS NOT NULL;
CREATE INDEX idx_txn_status      ON transactions(status)
    WHERE status = 'pending';

CREATE TABLE payment_orders (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID REFERENCES users(id),
    gateway             VARCHAR(30) NOT NULL,
    gateway_order_id    VARCHAR(255) UNIQUE,
    gateway_payment_id  VARCHAR(255),
    gateway_signature   VARCHAR(500),
    amount              DECIMAL(12,2) NOT NULL,
    currency            VARCHAR(5) DEFAULT 'INR',
    status              VARCHAR(20) DEFAULT 'created'
                        CHECK (status IN ('created','attempted','paid','failed','refunded')),
    type                VARCHAR(20) DEFAULT 'deposit'
                        CHECK (type IN ('deposit','withdrawal')),
    failure_reason      VARCHAR(500),
    metadata            JSONB DEFAULT '{}',
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================================================
-- GAME TABLES & MATCHES
-- =============================================================================
CREATE TABLE game_tables (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_code      VARCHAR(20) UNIQUE NOT NULL,
    game_type       VARCHAR(30) NOT NULL
                    CHECK (game_type IN ('points_rummy','pool_rummy_101','pool_rummy_201','deals_rummy')),
    variant         VARCHAR(30) DEFAULT 'real_money'
                    CHECK (variant IN ('practice','real_money','private','tournament')),
    max_players     SMALLINT NOT NULL CHECK (max_players IN (2,6)),
    min_players     SMALLINT DEFAULT 2,
    entry_fee       DECIMAL(10,2) DEFAULT 0,
    prize_pool      DECIMAL(10,2) DEFAULT 0,
    currency_type   VARCHAR(20) DEFAULT 'cash',
    status          VARCHAR(20) DEFAULT 'waiting'
                    CHECK (status IN ('waiting','in_progress','completed','cancelled')),
    host_user_id    UUID REFERENCES users(id),
    is_private      BOOLEAN DEFAULT FALSE,
    private_code    VARCHAR(10),
    max_deals       SMALLINT,
    points_per_coin DECIMAL(8,2),
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    started_at      TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ
);

CREATE INDEX idx_tables_status    ON game_tables(status);
CREATE INDEX idx_tables_type      ON game_tables(game_type, variant);
CREATE INDEX idx_tables_private   ON game_tables(private_code)
    WHERE is_private = TRUE;

CREATE TABLE table_seats (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_id        UUID REFERENCES game_tables(id) ON DELETE CASCADE,
    user_id         UUID REFERENCES users(id),
    seat_position   SMALLINT NOT NULL,
    joined_at       TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(table_id, seat_position),
    UNIQUE(table_id, user_id)
);

CREATE TABLE matches (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_id        UUID REFERENCES game_tables(id),
    match_number    SMALLINT DEFAULT 1,
    status          VARCHAR(20) DEFAULT 'in_progress'
                    CHECK (status IN ('in_progress','completed','cancelled')),
    winner_id       UUID REFERENCES users(id),
    winning_hand    JSONB,
    total_points    INTEGER,
    prize_amount    DECIMAL(10,2),
    started_at      TIMESTAMPTZ DEFAULT NOW(),
    ended_at        TIMESTAMPTZ,
    duration_secs   INTEGER
) PARTITION BY RANGE (started_at);

CREATE TABLE matches_default PARTITION OF matches DEFAULT;

CREATE TABLE match_players (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id        UUID REFERENCES matches(id),
    user_id         UUID REFERENCES users(id),
    is_bot          BOOLEAN DEFAULT FALSE,
    seat_position   SMALLINT NOT NULL,
    join_time       TIMESTAMPTZ DEFAULT NOW(),
    status          VARCHAR(20) DEFAULT 'playing'
                    CHECK (status IN ('playing','dropped','finished','disconnected','timed_out')),
    final_points    INTEGER,
    final_hand      JSONB,
    prize_won       DECIMAL(10,2) DEFAULT 0,
    rank            SMALLINT
);

CREATE INDEX idx_match_players_user   ON match_players(user_id, match_id);
CREATE INDEX idx_match_players_match  ON match_players(match_id);

CREATE TABLE game_rounds (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id        UUID REFERENCES matches(id),
    round_number    SMALLINT NOT NULL,
    current_player  UUID REFERENCES users(id),
    action          VARCHAR(30),
    card_drawn      VARCHAR(5),
    card_discarded  VARCHAR(5),
    hand_state      TEXT,
    timestamp       TIMESTAMPTZ DEFAULT NOW()
) PARTITION BY RANGE (timestamp);

CREATE TABLE game_rounds_default PARTITION OF game_rounds DEFAULT;

-- =============================================================================
-- TOURNAMENTS
-- =============================================================================
CREATE TABLE tournaments (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(200) NOT NULL,
    description     TEXT,
    banner_url      VARCHAR(500),
    game_type       VARCHAR(30) NOT NULL,
    format          VARCHAR(30) DEFAULT 'elimination',
    status          VARCHAR(20) DEFAULT 'upcoming'
                    CHECK (status IN ('upcoming','registration','in_progress','completed','cancelled')),
    max_players     INTEGER NOT NULL,
    min_players     INTEGER DEFAULT 2,
    registered_count INTEGER DEFAULT 0,
    entry_fee       DECIMAL(10,2) DEFAULT 0,
    prize_pool      DECIMAL(12,2) DEFAULT 0,
    prize_structure JSONB,
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
    current_round   SMALLINT DEFAULT 1,
    total_points    INTEGER DEFAULT 0,
    final_rank      SMALLINT,
    prize_won       DECIMAL(10,2),
    registered_at   TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(tournament_id, user_id)
);

-- =============================================================================
-- REFERRALS & SOCIAL
-- =============================================================================
CREATE TABLE referrals (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    referrer_id     UUID NOT NULL REFERENCES users(id),
    referee_id      UUID NOT NULL REFERENCES users(id),
    code_used       VARCHAR(12) NOT NULL,
    status          VARCHAR(20) DEFAULT 'pending'
                    CHECK (status IN ('pending','qualified','rewarded')),
    qualified_at    TIMESTAMPTZ,
    reward_amount   DECIMAL(10,2),
    reward_type     VARCHAR(20),
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(referee_id)
);

CREATE INDEX idx_referrals_referrer ON referrals(referrer_id);

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
    role            VARCHAR(20) DEFAULT 'member',
    joined_at       TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(team_id, user_id)
);

CREATE TABLE friendships (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requester_id    UUID REFERENCES users(id),
    addressee_id    UUID REFERENCES users(id),
    status          VARCHAR(20) DEFAULT 'pending',
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(requester_id, addressee_id),
    CHECK (requester_id <> addressee_id)
);

-- =============================================================================
-- NOTIFICATIONS & CHAT
-- =============================================================================
CREATE TABLE notifications (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID REFERENCES users(id),
    type            VARCHAR(50),
    title           VARCHAR(200),
    body            TEXT,
    data            JSONB DEFAULT '{}',
    is_read         BOOLEAN DEFAULT FALSE,
    sent_via        TEXT[],
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    read_at         TIMESTAMPTZ
) PARTITION BY RANGE (created_at);

CREATE TABLE notifications_default PARTITION OF notifications DEFAULT;

CREATE INDEX idx_notif_user_unread ON notifications(user_id, is_read, created_at DESC)
    WHERE is_read = FALSE;

CREATE TABLE chat_messages (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id         VARCHAR(100) NOT NULL,
    sender_id       UUID REFERENCES users(id),
    message         TEXT,
    message_type    VARCHAR(20) DEFAULT 'text',
    is_deleted      BOOLEAN DEFAULT FALSE,
    moderation_flag BOOLEAN DEFAULT FALSE,
    created_at      TIMESTAMPTZ DEFAULT NOW()
) PARTITION BY RANGE (created_at);

CREATE TABLE chat_messages_default PARTITION OF chat_messages DEFAULT;
CREATE INDEX idx_chat_room ON chat_messages(room_id, created_at DESC);

-- =============================================================================
-- KYC & FRAUD
-- =============================================================================
CREATE TABLE kyc_documents (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID REFERENCES users(id),
    doc_type        VARCHAR(50),
    doc_number      VARCHAR(100),
    doc_front_url   VARCHAR(500),
    doc_back_url    VARCHAR(500),
    selfie_url      VARCHAR(500),
    status          VARCHAR(20) DEFAULT 'pending'
                    CHECK (status IN ('pending','under_review','approved','rejected')),
    reviewed_by     UUID REFERENCES users(id),
    rejection_reason VARCHAR(500),
    submitted_at    TIMESTAMPTZ DEFAULT NOW(),
    reviewed_at     TIMESTAMPTZ
);

CREATE TABLE fraud_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID REFERENCES users(id),
    event_type      VARCHAR(100),
    severity        VARCHAR(20) CHECK (severity IN ('low','medium','high','critical')),
    details         JSONB DEFAULT '{}',
    ip_address      INET,
    device_id       VARCHAR(255),
    resolved        BOOLEAN DEFAULT FALSE,
    reviewed_by     UUID REFERENCES users(id),
    created_at      TIMESTAMPTZ DEFAULT NOW()
) PARTITION BY RANGE (created_at);

CREATE TABLE fraud_events_default PARTITION OF fraud_events DEFAULT;
CREATE INDEX idx_fraud_user      ON fraud_events(user_id, created_at DESC);
CREATE INDEX idx_fraud_unresolved ON fraud_events(resolved, severity)
    WHERE resolved = FALSE;

-- =============================================================================
-- GAMIFICATION
-- =============================================================================
CREATE TABLE achievements (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key             VARCHAR(100) UNIQUE NOT NULL,
    name            VARCHAR(200) NOT NULL,
    description     TEXT,
    icon_url        VARCHAR(500),
    xp_reward       INTEGER DEFAULT 0,
    token_reward    INTEGER DEFAULT 0,
    condition_type  VARCHAR(50),
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

CREATE TABLE daily_reward_claims (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID REFERENCES users(id),
    day_streak      INTEGER NOT NULL,
    reward_type     VARCHAR(20),
    reward_amount   DECIMAL(10,2),
    claimed_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE banners (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title           VARCHAR(200),
    image_url       VARCHAR(500) NOT NULL,
    link_url        VARCHAR(500),
    link_type       VARCHAR(30),
    screen          VARCHAR(50),
    position        SMALLINT DEFAULT 0,
    is_active       BOOLEAN DEFAULT TRUE,
    starts_at       TIMESTAMPTZ,
    ends_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE support_tickets (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID REFERENCES users(id),
    ticket_number   VARCHAR(20) UNIQUE NOT NULL,
    category        VARCHAR(50),
    subject         VARCHAR(300),
    description     TEXT,
    status          VARCHAR(20) DEFAULT 'open',
    priority        VARCHAR(20) DEFAULT 'normal',
    assigned_to     UUID REFERENCES users(id),
    attachments     TEXT[],
    resolved_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================================================
-- UTILITY FUNCTION: auto-update updated_at
-- =============================================================================
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_profiles_updated_at
    BEFORE UPDATE ON user_profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
