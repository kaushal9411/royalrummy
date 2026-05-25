-- Add bet_amount to rooms (0 = free game)
ALTER TABLE rooms ADD COLUMN IF NOT EXISTS bet_amount NUMERIC(10,2) DEFAULT 0;

-- Track per-player bet escrow for each game
CREATE TABLE IF NOT EXISTS game_bets (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  room_id     UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  match_id    UUID REFERENCES matches(id) ON DELETE SET NULL,
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  seat        SMALLINT NOT NULL CHECK (seat BETWEEN 0 AND 3),
  amount      NUMERIC(10,2) NOT NULL,
  status      VARCHAR(20) DEFAULT 'escrowed',  -- escrowed | won | lost | refunded
  settled_at  TIMESTAMPTZ,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(room_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_game_bets_room  ON game_bets(room_id);
CREATE INDEX IF NOT EXISTS idx_game_bets_match ON game_bets(match_id);
CREATE INDEX IF NOT EXISTS idx_game_bets_user  ON game_bets(user_id);
