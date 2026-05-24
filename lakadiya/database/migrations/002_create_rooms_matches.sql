-- Rooms
CREATE TABLE IF NOT EXISTS rooms (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  code        VARCHAR(8) UNIQUE NOT NULL,
  host_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status      VARCHAR(20) DEFAULT 'waiting',  -- waiting | playing | finished
  is_private  BOOLEAN DEFAULT FALSE,
  max_players INTEGER DEFAULT 4,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_rooms_code ON rooms(code);
CREATE INDEX IF NOT EXISTS idx_rooms_status ON rooms(status);

CREATE TRIGGER rooms_updated_at BEFORE UPDATE ON rooms
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Room players (snapshot of who was in a room)
CREATE TABLE IF NOT EXISTS room_players (
  room_id    UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  user_id    UUID REFERENCES users(id) ON DELETE SET NULL,
  seat       SMALLINT NOT NULL CHECK (seat BETWEEN 0 AND 3),
  is_bot     BOOLEAN DEFAULT FALSE,
  bot_level  VARCHAR(10),  -- easy | medium | hard
  joined_at  TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (room_id, seat)
);

-- Matches (one room can have one match at a time)
CREATE TABLE IF NOT EXISTS matches (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  room_id      UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  status       VARCHAR(20) DEFAULT 'active',  -- active | completed | abandoned
  winner_id    UUID REFERENCES users(id) ON DELETE SET NULL,
  total_rounds SMALLINT DEFAULT 5,
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  finished_at  TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_matches_room ON matches(room_id);
CREATE INDEX IF NOT EXISTS idx_matches_status ON matches(status);

-- Match players (final scores per player per match)
CREATE TABLE IF NOT EXISTS match_players (
  match_id    UUID NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
  user_id     UUID REFERENCES users(id) ON DELETE SET NULL,
  seat        SMALLINT NOT NULL,
  is_bot      BOOLEAN DEFAULT FALSE,
  final_score NUMERIC(8,2) DEFAULT 0,
  PRIMARY KEY (match_id, seat)
);
