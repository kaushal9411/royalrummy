-- Rounds (5 per match)
CREATE TABLE IF NOT EXISTS rounds (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  match_id     UUID NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
  round_number SMALLINT NOT NULL CHECK (round_number BETWEEN 1 AND 5),
  dealer_seat  SMALLINT NOT NULL,
  status       VARCHAR(20) DEFAULT 'bidding',  -- bidding | playing | completed
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(match_id, round_number)
);

CREATE INDEX IF NOT EXISTS idx_rounds_match ON rounds(match_id);

-- Bids (one per player per round)
CREATE TABLE IF NOT EXISTS bids (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  round_id     UUID NOT NULL REFERENCES rounds(id) ON DELETE CASCADE,
  seat         SMALLINT NOT NULL,
  user_id      UUID REFERENCES users(id) ON DELETE SET NULL,
  bid_amount   SMALLINT NOT NULL CHECK (bid_amount BETWEEN 1 AND 13),
  tricks_won   SMALLINT DEFAULT 0,
  score        NUMERIC(5,2) DEFAULT 0,
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(round_id, seat)
);

CREATE INDEX IF NOT EXISTS idx_bids_round ON bids(round_id);

-- Tricks (13 per round)
CREATE TABLE IF NOT EXISTS tricks (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  round_id     UUID NOT NULL REFERENCES rounds(id) ON DELETE CASCADE,
  trick_number SMALLINT NOT NULL CHECK (trick_number BETWEEN 1 AND 13),
  winner_seat  SMALLINT,
  led_suit     VARCHAR(10),
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(round_id, trick_number)
);

-- Trick cards (4 per trick)
CREATE TABLE IF NOT EXISTS trick_cards (
  trick_id   UUID NOT NULL REFERENCES tricks(id) ON DELETE CASCADE,
  seat       SMALLINT NOT NULL,
  card_suit  VARCHAR(10) NOT NULL,
  card_rank  VARCHAR(5) NOT NULL,
  PRIMARY KEY (trick_id, seat)
);
