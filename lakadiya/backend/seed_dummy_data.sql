-- ============================================================
--  Lakadiya Dummy Seed Data
--  Run with: psql -U postgres -d lakadiya -f seed_dummy_data.sql
-- ============================================================

BEGIN;

-- ─── 1. Ensure messages table exists ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS messages (
  id          SERIAL PRIMARY KEY,
  sender_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  receiver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  text        TEXT NOT NULL CHECK (char_length(text) BETWEEN 1 AND 500),
  is_read     BOOLEAN DEFAULT FALSE,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ─── 2. Ensure matches table has required columns ────────────────────────────
CREATE TABLE IF NOT EXISTS matches (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  status      VARCHAR(20) DEFAULT 'finished',
  winner_id   UUID REFERENCES users(id),
  bet_amount  NUMERIC(10,2) DEFAULT 0,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  finished_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS match_players (
  id          SERIAL PRIMARY KEY,
  match_id    UUID REFERENCES matches(id) ON DELETE CASCADE,
  user_id     UUID REFERENCES users(id) ON DELETE CASCADE,
  seat        INT DEFAULT 0,
  final_score INT DEFAULT 0
);

-- ─── 3. Create 6 dummy players ───────────────────────────────────────────────
INSERT INTO users (username, mobile, provider, coins, xp, level)
VALUES
  ('AceKing2024',    '9000000001', 'local', 1250, 3400, 7),
  ('SharpShark99',   '9000000002', 'local',  980, 2100, 5),
  ('WildDealer007',  '9000000003', 'local', 2600, 5800, 11),
  ('LuckyChamp55',   '9000000004', 'local',  430,  900, 3),
  ('RoyalMaster88',  '9000000005', 'local', 4200, 9100, 16),
  ('SwiftPro123',    '9000000006', 'local',  760, 1600, 4)
ON CONFLICT (mobile) DO NOTHING;

-- Add player_stats for any dummy users that don't have it yet
INSERT INTO player_stats (user_id, matches_played, matches_won, total_score, bids_exact, bids_failed, bids_over)
SELECT u.id, 42, 18, 8940, 95, 38, 22
FROM users u WHERE u.mobile = '9000000001'
  AND NOT EXISTS (SELECT 1 FROM player_stats WHERE user_id = u.id);

INSERT INTO player_stats (user_id, matches_played, matches_won, total_score, bids_exact, bids_failed, bids_over)
SELECT u.id, 28, 9, 5240, 61, 45, 18
FROM users u WHERE u.mobile = '9000000002'
  AND NOT EXISTS (SELECT 1 FROM player_stats WHERE user_id = u.id);

INSERT INTO player_stats (user_id, matches_played, matches_won, total_score, bids_exact, bids_failed, bids_over)
SELECT u.id, 87, 54, 19800, 210, 60, 35
FROM users u WHERE u.mobile = '9000000003'
  AND NOT EXISTS (SELECT 1 FROM player_stats WHERE user_id = u.id);

INSERT INTO player_stats (user_id, matches_played, matches_won, total_score, bids_exact, bids_failed, bids_over)
SELECT u.id, 12, 3, 1800, 22, 18, 7
FROM users u WHERE u.mobile = '9000000004'
  AND NOT EXISTS (SELECT 1 FROM player_stats WHERE user_id = u.id);

INSERT INTO player_stats (user_id, matches_played, matches_won, total_score, bids_exact, bids_failed, bids_over)
SELECT u.id, 156, 98, 43200, 380, 95, 55
FROM users u WHERE u.mobile = '9000000005'
  AND NOT EXISTS (SELECT 1 FROM player_stats WHERE user_id = u.id);

INSERT INTO player_stats (user_id, matches_played, matches_won, total_score, bids_exact, bids_failed, bids_over)
SELECT u.id, 19, 7, 3100, 40, 28, 11
FROM users u WHERE u.mobile = '9000000006'
  AND NOT EXISTS (SELECT 1 FROM player_stats WHERE user_id = u.id);

-- ─── 4. Create / update main user (7007249428) ───────────────────────────────
-- Create if not exists, then update stats
INSERT INTO users (username, mobile, provider, coins, xp, level)
VALUES ('KaushalPro', '7007249428', 'local', 1800, 4200, 9)
ON CONFLICT (mobile) DO UPDATE SET
  xp    = GREATEST(users.xp, 4200),
  level = GREATEST(users.level, 9),
  coins = GREATEST(users.coins, 1800);

-- Ensure player_stats row
INSERT INTO player_stats (user_id, matches_played, matches_won, total_score, bids_exact, bids_failed, bids_over)
SELECT u.id, 34, 15, 7200, 78, 42, 19
FROM users u WHERE u.mobile = '7007249428'
ON CONFLICT (user_id) DO UPDATE SET
  matches_played = GREATEST(player_stats.matches_played, 34),
  matches_won    = GREATEST(player_stats.matches_won, 15),
  total_score    = GREATEST(player_stats.total_score, 7200),
  bids_exact     = GREATEST(player_stats.bids_exact, 78),
  bids_failed    = GREATEST(player_stats.bids_failed, 42),
  bids_over      = GREATEST(player_stats.bids_over, 19);

-- ─── 5. Friendships: main user ↔ 3 dummy players ─────────────────────────────
-- AceKing2024 (accepted)
INSERT INTO friendships (user_id, friend_id, status)
SELECT u.id, d.id, 'accepted'
FROM users u, users d
WHERE u.mobile = '7007249428' AND d.mobile = '9000000001'
  AND NOT EXISTS (
    SELECT 1 FROM friendships WHERE user_id = u.id AND friend_id = d.id
  );

INSERT INTO friendships (user_id, friend_id, status)
SELECT d.id, u.id, 'accepted'
FROM users u, users d
WHERE u.mobile = '7007249428' AND d.mobile = '9000000001'
  AND NOT EXISTS (
    SELECT 1 FROM friendships WHERE user_id = d.id AND friend_id = u.id
  );

-- WildDealer007 (accepted)
INSERT INTO friendships (user_id, friend_id, status)
SELECT u.id, d.id, 'accepted'
FROM users u, users d
WHERE u.mobile = '7007249428' AND d.mobile = '9000000003'
  AND NOT EXISTS (
    SELECT 1 FROM friendships WHERE user_id = u.id AND friend_id = d.id
  );

INSERT INTO friendships (user_id, friend_id, status)
SELECT d.id, u.id, 'accepted'
FROM users u, users d
WHERE u.mobile = '7007249428' AND d.mobile = '9000000003'
  AND NOT EXISTS (
    SELECT 1 FROM friendships WHERE user_id = d.id AND friend_id = u.id
  );

-- RoyalMaster88 (accepted)
INSERT INTO friendships (user_id, friend_id, status)
SELECT u.id, d.id, 'accepted'
FROM users u, users d
WHERE u.mobile = '7007249428' AND d.mobile = '9000000005'
  AND NOT EXISTS (
    SELECT 1 FROM friendships WHERE user_id = u.id AND friend_id = d.id
  );

INSERT INTO friendships (user_id, friend_id, status)
SELECT d.id, u.id, 'accepted'
FROM users u, users d
WHERE u.mobile = '7007249428' AND d.mobile = '9000000005'
  AND NOT EXISTS (
    SELECT 1 FROM friendships WHERE user_id = d.id AND friend_id = u.id
  );

-- SharpShark99 (pending — they sent request to main user)
INSERT INTO friendships (user_id, friend_id, status)
SELECT d.id, u.id, 'pending'
FROM users u, users d
WHERE u.mobile = '7007249428' AND d.mobile = '9000000002'
  AND NOT EXISTS (
    SELECT 1 FROM friendships WHERE user_id = d.id AND friend_id = u.id
  );

-- ─── 6. Match history (10 finished matches with main user) ───────────────────
DO $$
DECLARE
  main_id  UUID;
  p1_id    UUID;
  p2_id    UUID;
  p3_id    UUID;
  p4_id    UUID;
  room_id  UUID;
  match_id UUID;
BEGIN
  SELECT id INTO main_id FROM users WHERE mobile = '7007249428';
  SELECT id INTO p1_id   FROM users WHERE mobile = '9000000001';
  SELECT id INTO p2_id   FROM users WHERE mobile = '9000000003';
  SELECT id INTO p3_id   FROM users WHERE mobile = '9000000005';
  SELECT id INTO p4_id   FROM users WHERE mobile = '9000000002';

  IF main_id IS NULL THEN
    RAISE NOTICE 'Main user not found — skipping match history';
    RETURN;
  END IF;

  -- Match 1: main user wins vs p1, p4, p2 (3 days ago)
  INSERT INTO rooms (code, host_id, status) VALUES ('SEED01', main_id, 'finished') RETURNING id INTO room_id;
  INSERT INTO matches (room_id, status, winner_id, created_at, finished_at)
  VALUES (room_id, 'finished', main_id, NOW() - INTERVAL '3 days', NOW() - INTERVAL '3 days' + INTERVAL '25 minutes')
  RETURNING id INTO match_id;
  INSERT INTO match_players (match_id, user_id, seat, final_score) VALUES
    (match_id, main_id, 0, 320), (match_id, p1_id, 1, 190), (match_id, p4_id, 2, 145), (match_id, p2_id, 3, 210);

  -- Match 2: p2 wins (5 days ago)
  INSERT INTO rooms (code, host_id, status) VALUES ('SEED02', p2_id, 'finished') RETURNING id INTO room_id;
  INSERT INTO matches (room_id, status, winner_id, created_at, finished_at)
  VALUES (room_id, 'finished', p2_id, NOW() - INTERVAL '5 days', NOW() - INTERVAL '5 days' + INTERVAL '30 minutes')
  RETURNING id INTO match_id;
  INSERT INTO match_players (match_id, user_id, seat, final_score) VALUES
    (match_id, main_id, 0, 180), (match_id, p2_id, 1, 410), (match_id, p1_id, 2, 200), (match_id, p3_id, 3, 155);

  -- Match 3: main user wins (6 days ago)
  INSERT INTO rooms (code, host_id, status) VALUES ('SEED03', main_id, 'finished') RETURNING id INTO room_id;
  INSERT INTO matches (room_id, status, winner_id, created_at, finished_at)
  VALUES (room_id, 'finished', main_id, NOW() - INTERVAL '6 days', NOW() - INTERVAL '6 days' + INTERVAL '20 minutes')
  RETURNING id INTO match_id;
  INSERT INTO match_players (match_id, user_id, seat, final_score) VALUES
    (match_id, main_id, 0, 380), (match_id, p3_id, 1, 260), (match_id, p4_id, 2, 170), (match_id, p1_id, 3, 195);

  -- Match 4: p3 wins (8 days ago)
  INSERT INTO rooms (code, host_id, status) VALUES ('SEED04', p3_id, 'finished') RETURNING id INTO room_id;
  INSERT INTO matches (room_id, status, winner_id, created_at, finished_at)
  VALUES (room_id, 'finished', p3_id, NOW() - INTERVAL '8 days', NOW() - INTERVAL '8 days' + INTERVAL '35 minutes')
  RETURNING id INTO match_id;
  INSERT INTO match_players (match_id, user_id, seat, final_score) VALUES
    (match_id, main_id, 0, 220), (match_id, p3_id, 1, 490), (match_id, p2_id, 2, 280), (match_id, p4_id, 3, 130);

  -- Match 5: main user wins (10 days ago)
  INSERT INTO rooms (code, host_id, status) VALUES ('SEED05', main_id, 'finished') RETURNING id INTO room_id;
  INSERT INTO matches (room_id, status, winner_id, created_at, finished_at)
  VALUES (room_id, 'finished', main_id, NOW() - INTERVAL '10 days', NOW() - INTERVAL '10 days' + INTERVAL '22 minutes')
  RETURNING id INTO match_id;
  INSERT INTO match_players (match_id, user_id, seat, final_score) VALUES
    (match_id, main_id, 0, 350), (match_id, p1_id, 1, 200), (match_id, p2_id, 2, 175), (match_id, p4_id, 3, 140);

  -- Match 6: p1 wins (12 days ago)
  INSERT INTO rooms (code, host_id, status) VALUES ('SEED06', p1_id, 'finished') RETURNING id INTO room_id;
  INSERT INTO matches (room_id, status, winner_id, created_at, finished_at)
  VALUES (room_id, 'finished', p1_id, NOW() - INTERVAL '12 days', NOW() - INTERVAL '12 days' + INTERVAL '28 minutes')
  RETURNING id INTO match_id;
  INSERT INTO match_players (match_id, user_id, seat, final_score) VALUES
    (match_id, main_id, 0, 210), (match_id, p1_id, 1, 360), (match_id, p3_id, 2, 245), (match_id, p4_id, 3, 160);

  -- Match 7: main user wins (14 days ago)
  INSERT INTO rooms (code, host_id, status) VALUES ('SEED07', main_id, 'finished') RETURNING id INTO room_id;
  INSERT INTO matches (room_id, status, winner_id, created_at, finished_at)
  VALUES (room_id, 'finished', main_id, NOW() - INTERVAL '14 days', NOW() - INTERVAL '14 days' + INTERVAL '18 minutes')
  RETURNING id INTO match_id;
  INSERT INTO match_players (match_id, user_id, seat, final_score) VALUES
    (match_id, main_id, 0, 400), (match_id, p2_id, 1, 215), (match_id, p3_id, 2, 290), (match_id, p4_id, 3, 155);

  -- Match 8: p4 wins (16 days ago)
  INSERT INTO rooms (code, host_id, status) VALUES ('SEED08', p4_id, 'finished') RETURNING id INTO room_id;
  INSERT INTO matches (room_id, status, winner_id, created_at, finished_at)
  VALUES (room_id, 'finished', p4_id, NOW() - INTERVAL '16 days', NOW() - INTERVAL '16 days' + INTERVAL '40 minutes')
  RETURNING id INTO match_id;
  INSERT INTO match_players (match_id, user_id, seat, final_score) VALUES
    (match_id, main_id, 0, 195), (match_id, p4_id, 1, 330), (match_id, p1_id, 2, 240), (match_id, p3_id, 3, 200);

  -- Match 9: main user wins (18 days ago)
  INSERT INTO rooms (code, host_id, status) VALUES ('SEED09', main_id, 'finished') RETURNING id INTO room_id;
  INSERT INTO matches (room_id, status, winner_id, created_at, finished_at)
  VALUES (room_id, 'finished', main_id, NOW() - INTERVAL '18 days', NOW() - INTERVAL '18 days' + INTERVAL '24 minutes')
  RETURNING id INTO match_id;
  INSERT INTO match_players (match_id, user_id, seat, final_score) VALUES
    (match_id, main_id, 0, 370), (match_id, p1_id, 1, 185), (match_id, p2_id, 2, 250), (match_id, p4_id, 3, 175);

  -- Match 10: p2 wins (20 days ago)
  INSERT INTO rooms (code, host_id, status) VALUES ('SEED10', p2_id, 'finished') RETURNING id INTO room_id;
  INSERT INTO matches (room_id, status, winner_id, created_at, finished_at)
  VALUES (room_id, 'finished', p2_id, NOW() - INTERVAL '20 days', NOW() - INTERVAL '20 days' + INTERVAL '32 minutes')
  RETURNING id INTO match_id;
  INSERT INTO match_players (match_id, user_id, seat, final_score) VALUES
    (match_id, main_id, 0, 205), (match_id, p2_id, 1, 445), (match_id, p3_id, 2, 270), (match_id, p4_id, 3, 140);

END $$;

-- ─── 7. DM Messages (3 conversations) ────────────────────────────────────────
DO $$
DECLARE
  main_id UUID;
  p1_id   UUID;  -- AceKing2024
  p2_id   UUID;  -- WildDealer007
  p3_id   UUID;  -- RoyalMaster88
BEGIN
  SELECT id INTO main_id FROM users WHERE mobile = '7007249428';
  SELECT id INTO p1_id   FROM users WHERE mobile = '9000000001';
  SELECT id INTO p2_id   FROM users WHERE mobile = '9000000003';
  SELECT id INTO p3_id   FROM users WHERE mobile = '9000000005';

  IF main_id IS NULL THEN
    RAISE NOTICE 'Main user not found — skipping messages';
    RETURN;
  END IF;

  -- Conversation with AceKing2024
  INSERT INTO messages (sender_id, receiver_id, text, is_read, created_at) VALUES
    (p1_id,   main_id, 'Hey! Great game yesterday bro 🔥', true,  NOW() - INTERVAL '2 days' - INTERVAL '4 hours'),
    (main_id, p1_id,   'Thanks man! Your bidding was insane 😂', true,  NOW() - INTERVAL '2 days' - INTERVAL '3 hours 50 minutes'),
    (p1_id,   main_id, 'Haha I got lucky with the spades. Want to play again tonight?', true,  NOW() - INTERVAL '2 days' - INTERVAL '3 hours 40 minutes'),
    (main_id, p1_id,   'Sure! What time works for you?', true,  NOW() - INTERVAL '2 days' - INTERVAL '3 hours 30 minutes'),
    (p1_id,   main_id, 'Around 9 PM. I will create a private room.', true,  NOW() - INTERVAL '2 days' - INTERVAL '3 hours'),
    (main_id, p1_id,   'Perfect 👍 See you then!', true,  NOW() - INTERVAL '2 days' - INTERVAL '2 hours'),
    (p1_id,   main_id, 'Rematch tonight? I want revenge lol', false, NOW() - INTERVAL '1 hour');

  -- Conversation with WildDealer007
  INSERT INTO messages (sender_id, receiver_id, text, is_read, created_at) VALUES
    (main_id, p2_id,   'Bhai room join karo abhi', true,  NOW() - INTERVAL '4 days' - INTERVAL '2 hours'),
    (p2_id,   main_id, 'Coming in 5 min', true,  NOW() - INTERVAL '4 days' - INTERVAL '1 hour 55 minutes'),
    (p2_id,   main_id, 'That was an amazing game! Your last bid was pure genius', true,  NOW() - INTERVAL '4 days' - INTERVAL '1 hour'),
    (main_id, p2_id,   'Thanks! You played really well too 🎉', true,  NOW() - INTERVAL '4 days' - INTERVAL '55 minutes'),
    (p2_id,   main_id, 'How do you always read the opponent''s hand so well?', true,  NOW() - INTERVAL '3 days'),
    (main_id, p2_id,   'Practice and patience lol. Watch the discards carefully!', true,  NOW() - INTERVAL '3 days' + INTERVAL '5 minutes'),
    (p2_id,   main_id, 'Pro tips 💪 We should play daily', true,  NOW() - INTERVAL '3 days' + INTERVAL '10 minutes'),
    (main_id, p2_id,   'Absolutely! Daily grind bro 🔥', false, NOW() - INTERVAL '3 days' + INTERVAL '15 minutes'),
    (p2_id,   main_id, 'GG last night. You destroyed us 😂', false, NOW() - INTERVAL '30 minutes');

  -- Conversation with RoyalMaster88
  INSERT INTO messages (sender_id, receiver_id, text, is_read, created_at) VALUES
    (p3_id,   main_id, 'I saw you in the leaderboard! Top 10 nice!', true,  NOW() - INTERVAL '6 days'),
    (main_id, p3_id,   'Thanks! You are way ahead at rank 3 though 😅', true,  NOW() - INTERVAL '6 days' + INTERVAL '10 minutes'),
    (p3_id,   main_id, 'Been playing for 2 years haha. Keep grinding!', true,  NOW() - INTERVAL '6 days' + INTERVAL '20 minutes'),
    (main_id, p3_id,   'Can you share some tips? Your bidding strategy is different', true,  NOW() - INTERVAL '6 days' + INTERVAL '25 minutes'),
    (p3_id,   main_id, 'Count high cards in each suit. Bid conservatively early game.', true,  NOW() - INTERVAL '6 days' + INTERVAL '35 minutes'),
    (main_id, p3_id,   'That makes sense! Will try tonight', true,  NOW() - INTERVAL '5 days'),
    (p3_id,   main_id, 'Good luck! Let me know how it goes 😄', true,  NOW() - INTERVAL '5 days' + INTERVAL '5 minutes'),
    (main_id, p3_id,   'Won 3 in a row! Your tips worked 🎉🎉', true,  NOW() - INTERVAL '4 days'),
    (p3_id,   main_id, 'Haha told you! Keep going!', true,  NOW() - INTERVAL '4 days' + INTERVAL '10 minutes'),
    (main_id, p3_id,   'Want to play a match? I feel confident now 😂', false, NOW() - INTERVAL '2 hours'),
    (p3_id,   main_id, 'Challenge accepted! Creating room now 👑', false, NOW() - INTERVAL '1 hour 45 minutes');

END $$;

-- ─── 8. Wallet: add some transaction history for main user ───────────────────
DO $$
DECLARE
  main_id UUID;
BEGIN
  SELECT id INTO main_id FROM users WHERE mobile = '7007249428';
  IF main_id IS NULL THEN RETURN; END IF;

  INSERT INTO payment_transactions (user_id, amount, coins, type, status, description, created_at)
  VALUES
    (main_id, 500,  500,  'add',      'success', 'Added via UPI',      NOW() - INTERVAL '15 days'),
    (main_id, 200,  200,  'add',      'success', 'Added via UPI',      NOW() - INTERVAL '10 days'),
    (main_id, 100,  100,  'bet_win',  'success', 'Won bet - Room ABC1', NOW() - INTERVAL '8 days'),
    (main_id, 50,   50,   'bet_deduct','success','Lost bet - Room XY2', NOW() - INTERVAL '7 days'),
    (main_id, 100,  100,  'bet_win',  'success', 'Won bet - Room DEF3', NOW() - INTERVAL '5 days'),
    (main_id, 100,  100,  'bet_win',  'success', 'Won bet - Room GHI4', NOW() - INTERVAL '3 days'),
    (main_id, 50,   50,   'bet_deduct','success','Lost bet - Room JKL5', NOW() - INTERVAL '2 days')
  ON CONFLICT DO NOTHING;
END $$;

-- ─── 9. Notifications for main user ──────────────────────────────────────────
DO $$
DECLARE
  main_id UUID;
  p1_id   UUID;
  p2_id   UUID;
BEGIN
  SELECT id INTO main_id FROM users WHERE mobile = '7007249428';
  SELECT id INTO p1_id   FROM users WHERE mobile = '9000000001';
  SELECT id INTO p2_id   FROM users WHERE mobile = '9000000002';

  IF main_id IS NULL THEN RETURN; END IF;

  -- Friend request from SharpShark99
  INSERT INTO notifications (user_id, type, title, body, data, is_read, created_at)
  SELECT
    main_id,
    'friend_request',
    'Friend Request',
    'SharpShark99 sent you a friend request',
    json_build_object('fromUserId', p2_id),
    false,
    NOW() - INTERVAL '1 day'
  WHERE p2_id IS NOT NULL;

  -- Unread message notifications
  INSERT INTO notifications (user_id, type, title, body, data, is_read, created_at)
  SELECT
    main_id,
    'private_message',
    'AceKing2024',
    'Rematch tonight? I want revenge lol',
    json_build_object('fromUserId', p1_id),
    false,
    NOW() - INTERVAL '1 hour'
  WHERE p1_id IS NOT NULL;

END $$;

COMMIT;

-- ─── Summary ──────────────────────────────────────────────────────────────────
SELECT
  '=== Main User ===' AS info,
  u.id, u.username, u.mobile, u.level, u.xp, u.coins,
  ps.matches_played, ps.matches_won
FROM users u
LEFT JOIN player_stats ps ON ps.user_id = u.id
WHERE u.mobile = '7007249428';

SELECT
  '=== Dummy Players ===' AS info,
  u.username, u.mobile, u.level,
  ps.matches_played, ps.matches_won
FROM users u
LEFT JOIN player_stats ps ON ps.user_id = u.id
WHERE u.mobile IN ('9000000001','9000000002','9000000003','9000000004','9000000005','9000000006')
ORDER BY u.level DESC;

SELECT '=== Friendships ===' AS info, count(*) AS total
FROM friendships f
JOIN users u ON u.id = f.user_id
WHERE u.mobile = '7007249428';

SELECT '=== Messages ===' AS info, count(*) AS total
FROM messages m
JOIN users u ON u.id = m.sender_id OR u.id = m.receiver_id
WHERE u.mobile = '7007249428';

SELECT '=== Matches ===' AS info, count(*) AS total
FROM match_players mp
JOIN users u ON u.id = mp.user_id
WHERE u.mobile = '7007249428';
