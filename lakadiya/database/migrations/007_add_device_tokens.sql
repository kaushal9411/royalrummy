-- Add device tokens table for push notifications
CREATE TABLE IF NOT EXISTS device_tokens (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  fcm_token    VARCHAR(500) NOT NULL UNIQUE,
  device_type  VARCHAR(20),  -- android | ios | web
  is_active    BOOLEAN DEFAULT TRUE,
  last_used    TIMESTAMPTZ DEFAULT NOW(),
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  updated_at   TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_device_tokens_user ON device_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_device_tokens_active ON device_tokens(is_active);

-- Add notification log table
CREATE TABLE IF NOT EXISTS notification_logs (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id      UUID REFERENCES users(id) ON DELETE SET NULL,
  fcm_token    VARCHAR(500),
  title        VARCHAR(255),
  body         TEXT,
  data         JSONB,
  status       VARCHAR(20) DEFAULT 'sent',  -- sent | failed | pending
  error_msg    TEXT,
  sent_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notification_logs_user ON notification_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_notification_logs_status ON notification_logs(status);
