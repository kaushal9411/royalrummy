-- Payment transactions table for Razorpay
CREATE TABLE IF NOT EXISTS payment_transactions (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id          UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  razorpay_order_id VARCHAR(50),
  razorpay_payment_id VARCHAR(50),
  razorpay_signature VARCHAR(255),
  amount           NUMERIC(10,2) NOT NULL,
  coins            INTEGER NOT NULL,
  type             VARCHAR(20) NOT NULL,  -- add | withdraw
  status           VARCHAR(20) DEFAULT 'pending',  -- pending | success | failed | cancelled
  description      TEXT,
  metadata         JSONB,
  created_at       TIMESTAMPTZ DEFAULT NOW(),
  updated_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payment_user ON payment_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_payment_status ON payment_transactions(status);
CREATE INDEX IF NOT EXISTS idx_payment_razorpay_order ON payment_transactions(razorpay_order_id);

-- Wallet balance tracking
CREATE TABLE IF NOT EXISTS wallet_balance (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id      UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  total_added  NUMERIC(10,2) DEFAULT 0,
  total_withdrawn NUMERIC(10,2) DEFAULT 0,
  current_balance NUMERIC(10,2) DEFAULT 0,
  last_updated TIMESTAMPTZ DEFAULT NOW()
);

-- Trigger to update wallet balance
CREATE OR REPLACE FUNCTION update_wallet_balance()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'success' THEN
    INSERT INTO wallet_balance (user_id, total_added, total_withdrawn, current_balance)
    VALUES (NEW.user_id, 
            CASE WHEN NEW.type = 'add' THEN NEW.amount ELSE 0 END,
            CASE WHEN NEW.type = 'withdraw' THEN NEW.amount ELSE 0 END,
            CASE WHEN NEW.type = 'add' THEN NEW.amount ELSE -NEW.amount END)
    ON CONFLICT (user_id) DO UPDATE SET
      total_added = wallet_balance.total_added + CASE WHEN NEW.type = 'add' THEN NEW.amount ELSE 0 END,
      total_withdrawn = wallet_balance.total_withdrawn + CASE WHEN NEW.type = 'withdraw' THEN NEW.amount ELSE 0 END,
      current_balance = wallet_balance.current_balance + CASE WHEN NEW.type = 'add' THEN NEW.amount ELSE -NEW.amount END,
      last_updated = NOW();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER payment_wallet_trigger AFTER INSERT ON payment_transactions
  FOR EACH ROW EXECUTE FUNCTION update_wallet_balance();

-- Update timestamp trigger
CREATE TRIGGER payment_transactions_updated_at BEFORE UPDATE ON payment_transactions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
