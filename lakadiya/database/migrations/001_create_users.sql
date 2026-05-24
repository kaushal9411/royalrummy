-- Users table
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS users (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  username      VARCHAR(30) UNIQUE NOT NULL,
  email         VARCHAR(255) UNIQUE,
  password_hash VARCHAR(255),
  avatar_url    VARCHAR(500),
  provider      VARCHAR(20) DEFAULT 'local',  -- local | google | guest
  provider_id   VARCHAR(255),
  coins         INTEGER DEFAULT 1000,
  xp            INTEGER DEFAULT 0,
  level         INTEGER DEFAULT 1,
  is_banned     BOOLEAN DEFAULT FALSE,
  ban_reason    TEXT,
  is_admin      BOOLEAN DEFAULT FALSE,
  last_seen     TIMESTAMPTZ DEFAULT NOW(),
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_provider ON users(provider, provider_id);

-- Player stats
CREATE TABLE IF NOT EXISTS player_stats (
  user_id        UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  matches_played INTEGER DEFAULT 0,
  matches_won    INTEGER DEFAULT 0,
  total_score    NUMERIC(10,2) DEFAULT 0,
  highest_score  NUMERIC(10,2) DEFAULT 0,
  total_bids     INTEGER DEFAULT 0,
  bids_exact     INTEGER DEFAULT 0,
  bids_over      INTEGER DEFAULT 0,
  bids_failed    INTEGER DEFAULT 0,
  updated_at     TIMESTAMPTZ DEFAULT NOW()
);

-- Friendships
CREATE TABLE IF NOT EXISTS friendships (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  friend_id  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status     VARCHAR(20) DEFAULT 'pending',  -- pending | accepted | blocked
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, friend_id)
);

CREATE INDEX IF NOT EXISTS idx_friendships_user ON friendships(user_id, status);

-- Rewards / transactions
CREATE TABLE IF NOT EXISTS coin_transactions (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  amount      INTEGER NOT NULL,
  type        VARCHAR(30) NOT NULL,  -- win | lose | daily_bonus | purchase | reward
  description TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_coins_user ON coin_transactions(user_id);

-- Function to auto-update updated_at
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER users_updated_at BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
