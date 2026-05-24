-- =============================================================================
-- RoyalRummy — Seed Data
-- Run after 001_initial_schema.sql
-- =============================================================================

-- Admin user (password: Admin@123 — bcrypt hash, change in production)
INSERT INTO users (id, phone, username, email, status, role, kyc_status, phone_verified)
VALUES (
  'admin-00000000-0000-0000-0000-000000000001',
  '+919999999999',
  'admin',
  'admin@royalrummy.com',
  'active',
  'admin',
  'approved',
  true
) ON CONFLICT (phone) DO NOTHING;

INSERT INTO user_profiles (id, user_id, full_name)
VALUES (
  gen_random_uuid(),
  'admin-00000000-0000-0000-0000-000000000001',
  'Platform Admin'
) ON CONFLICT (user_id) DO NOTHING;

INSERT INTO wallets (id, user_id)
VALUES (
  gen_random_uuid(),
  'admin-00000000-0000-0000-0000-000000000001'
) ON CONFLICT (user_id) DO NOTHING;

-- =============================================================================
-- Achievements
-- =============================================================================
INSERT INTO achievements (id, name, description, icon, category, condition_type, condition_value, reward_coins) VALUES
  ('ach-001', 'First Win',        'Win your first game',                    '🏆', 'game',    'wins',        1,    50),
  ('ach-002', 'Hat Trick',        'Win 3 games in a row',                   '🎩', 'game',    'win_streak',  3,    100),
  ('ach-003', 'Centurion',        'Win 100 games',                          '💯', 'game',    'wins',        100,  500),
  ('ach-004', 'Speed Demon',      'Win a game in under 5 minutes',          '⚡', 'game',    'fast_win',    300,  75),
  ('ach-005', 'Pure Pro',         'Declare with a pure sequence first try', '♠️', 'game',    'pure_declare',1,    150),
  ('ach-006', 'First Deposit',    'Make your first deposit',                '💰', 'wallet',  'deposits',    1,    25),
  ('ach-007', 'High Roller',      'Deposit ₹10,000 in total',              '💎', 'wallet',  'total_deposited', 10000, 200),
  ('ach-008', 'Social Butterfly', 'Add 10 friends',                         '🦋', 'social',  'friends',     10,   50),
  ('ach-009', 'Daily Grind',      'Play 7 days in a row',                   '📅', 'streak',  'login_streak',7,    100),
  ('ach-010', 'Millionaire',      'Accumulate ₹1,00,000 in winnings',      '🤑', 'wallet',  'total_won',   100000, 1000),
  ('ach-011', 'Referral King',    'Refer 5 friends who complete KYC',       '👑', 'social',  'referrals',   5,    250),
  ('ach-012', 'Tournament Ace',   'Win a tournament',                       '🏅', 'tournament', 'tournament_wins', 1, 500)
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- Default game table configurations (lobby templates)
-- =============================================================================
DO $$
BEGIN
  -- Points Rummy tables (various entry fees)
  INSERT INTO game_tables (id, game_type, variant, max_players, min_players, entry_fee, prize_pool, status, is_private, table_code)
  SELECT gen_random_uuid(), 'points', 'classic', 6, 2, fee, fee * 6 * 0.90, 'waiting', false,
    'TBL-' || UPPER(SUBSTR(MD5(RANDOM()::TEXT), 1, 6))
  FROM UNNEST(ARRAY[0, 5, 10, 25, 50, 100, 200, 500]) AS fee
  ON CONFLICT DO NOTHING;

  -- Deals Rummy (best of 2 deals)
  INSERT INTO game_tables (id, game_type, variant, max_players, min_players, entry_fee, prize_pool, status, is_private, table_code)
  SELECT gen_random_uuid(), 'deals', '2deals', 6, 2, fee, fee * 6 * 0.90, 'waiting', false,
    'TBL-' || UPPER(SUBSTR(MD5(RANDOM()::TEXT), 1, 6))
  FROM UNNEST(ARRAY[10, 50, 100, 500]) AS fee
  ON CONFLICT DO NOTHING;

  -- Pool Rummy (101 & 201 pool)
  INSERT INTO game_tables (id, game_type, variant, max_players, min_players, entry_fee, prize_pool, status, is_private, table_code)
  SELECT gen_random_uuid(), 'pool', variant, 6, 2, fee, fee * 6 * 0.90, 'waiting', false,
    'TBL-' || UPPER(SUBSTR(MD5(RANDOM()::TEXT), 1, 6))
  FROM UNNEST(ARRAY['101pool', '201pool']) AS variant,
       UNNEST(ARRAY[10, 50, 100]) AS fee
  ON CONFLICT DO NOTHING;
EXCEPTION WHEN OTHERS THEN
  -- game_tables may not have variant column yet; skip
  RAISE NOTICE 'Skipping game_tables seed: %', SQLERRM;
END;
$$;

-- =============================================================================
-- Banners (home screen promotional banners)
-- =============================================================================
INSERT INTO banners (id, title, subtitle, image_url, action_url, action_type, is_active, priority, start_at, end_at)
VALUES
  (gen_random_uuid(), 'Welcome Bonus!', 'Get ₹50 free on signup', '/images/banners/welcome.png', '/deposit', 'navigate', true, 1, NOW(), NOW() + INTERVAL '1 year'),
  (gen_random_uuid(), 'Refer & Earn', 'Earn ₹100 for every friend you refer', '/images/banners/refer.png', '/referral', 'navigate', true, 2, NOW(), NOW() + INTERVAL '1 year'),
  (gen_random_uuid(), 'Weekend Tournament', 'Win big every weekend!', '/images/banners/tournament.png', '/tournaments', 'navigate', true, 3, NOW(), NOW() + INTERVAL '6 months')
ON CONFLICT DO NOTHING;

-- =============================================================================
-- Support ticket categories (stored as reference data)
-- =============================================================================
-- No separate table needed — stored as CHECK constraint values in schema.

-- =============================================================================
-- Indexes (supplementary — on top of 001_initial_schema.sql)
-- =============================================================================
CREATE INDEX IF NOT EXISTS idx_transactions_type_status ON transactions(type, status) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_fraud_events_unresolved ON fraud_events(created_at) WHERE resolved_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_users_status_role ON users(status, role) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_game_tables_status ON game_tables(status) WHERE status IN ('waiting', 'in_progress');

-- =============================================================================
-- Verify seed ran successfully
-- =============================================================================
DO $$
DECLARE
  ach_count INT;
BEGIN
  SELECT COUNT(*) INTO ach_count FROM achievements;
  RAISE NOTICE 'Seed complete. Achievements: %', ach_count;
END;
$$;
