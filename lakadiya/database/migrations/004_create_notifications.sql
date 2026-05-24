-- In-app notifications
CREATE TABLE IF NOT EXISTS notifications (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type       VARCHAR(40) NOT NULL,  -- friend_request | game_invite | reward | system
  title      VARCHAR(100) NOT NULL,
  body       TEXT,
  is_read    BOOLEAN DEFAULT FALSE,
  data       JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id, is_read);
