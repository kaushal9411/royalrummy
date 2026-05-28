const { query } = require('../../config/database');
const logger = require('../../config/logger');

// Auto-create table + seed default row on first boot
query(`
  CREATE TABLE IF NOT EXISTS platform_settings (
    id                   INTEGER PRIMARY KEY DEFAULT 1,
    maintenance_mode     BOOLEAN      NOT NULL DEFAULT FALSE,
    registration_enabled BOOLEAN      NOT NULL DEFAULT TRUE,
    min_withdrawal       NUMERIC(10,2) NOT NULL DEFAULT 100,
    max_withdrawal       NUMERIC(10,2) NOT NULL DEFAULT 10000,
    welcome_bonus        INTEGER      NOT NULL DEFAULT 50,
    max_bet_amount       NUMERIC(10,2) NOT NULL DEFAULT 100,
    platform_fee_pct     NUMERIC(5,2) NOT NULL DEFAULT 0,
    updated_at           TIMESTAMPTZ  DEFAULT NOW(),
    CONSTRAINT single_row CHECK (id = 1)
  )
`).then(() =>
  query(`INSERT INTO platform_settings (id) VALUES (1) ON CONFLICT (id) DO NOTHING`)
).catch(() => {});

// ── In-memory cache (60 s TTL) ────────────────────────────────────────────────
let _cache    = null;
let _cacheAt  = 0;
const CACHE_TTL = 60_000;

const DEFAULTS = {
  maintenance_mode:     false,
  registration_enabled: true,
  min_withdrawal:       100,
  max_withdrawal:       10000,
  welcome_bonus:        50,
  max_bet_amount:       100,
  platform_fee_pct:     0,
};

const getSettings = async () => {
  if (_cache && Date.now() - _cacheAt < CACHE_TTL) return _cache;
  try {
    const result = await query('SELECT * FROM platform_settings WHERE id = 1');
    _cache   = result.rows[0] ?? { id: 1, ...DEFAULTS };
    _cacheAt = Date.now();
  } catch {
    _cache = { id: 1, ...DEFAULTS };
  }
  return _cache;
};

const ALLOWED_KEYS = Object.keys(DEFAULTS);

const updateSettings = async (data) => {
  const updates = Object.entries(data).filter(([k]) => ALLOWED_KEYS.includes(k));
  if (!updates.length) throw { status: 400, message: 'No valid fields to update' };

  const sets   = updates.map(([k], i) => `${k} = $${i + 1}`).join(', ');
  const values = updates.map(([, v]) => v);

  const result = await query(
    `UPDATE platform_settings SET ${sets}, updated_at = NOW()
     WHERE id = 1 RETURNING *`,
    values
  );

  _cache   = result.rows[0];
  _cacheAt = Date.now();

  // Silently push updated settings to all active devices (fire-and-forget)
  _pushSettingsToDevices(_cache).catch(() => {});

  return _cache;
};

const _pushSettingsToDevices = async (settings) => {
  // Lazy-require to avoid circular deps and ensure Firebase is initialized
  const { ensureFirebase } = require('../../config/firebase');
  if (!ensureFirebase()) return;

  const admin = require('firebase-admin');

  const result = await query(
    `SELECT DISTINCT ON (user_id) fcm_token
     FROM device_tokens
     WHERE is_active = TRUE
     ORDER BY user_id, last_used DESC`
  );
  if (!result.rows.length) return;

  const tokens = result.rows.map((r) => r.fcm_token);
  const message = {
    data: {
      type:                 'SETTINGS_UPDATE',
      maintenance_mode:     String(settings.maintenance_mode),
      registration_enabled: String(settings.registration_enabled),
      min_withdrawal:       String(settings.min_withdrawal),
      max_withdrawal:       String(settings.max_withdrawal),
      welcome_bonus:        String(settings.welcome_bonus),
      max_bet_amount:       String(settings.max_bet_amount),
      platform_fee_pct:     String(settings.platform_fee_pct),
    },
    android: { priority: 'high' },
    apns:    { payload: { aps: { 'content-available': 1 } } },
  };

  const BATCH = 500;
  let sent = 0;
  for (let i = 0; i < tokens.length; i += BATCH) {
    const batch = tokens.slice(i, i + BATCH);
    try {
      const res = await admin.messaging().sendEachForMulticast({ ...message, tokens: batch });
      sent += res.successCount;
    } catch (err) {
      logger.error('[Settings] FCM push failed:', err.message);
    }
  }
  logger.info(`[Settings] FCM sync pushed to ${sent}/${tokens.length} devices`);
};

const invalidateCache = () => { _cache = null; };

module.exports = { getSettings, updateSettings, invalidateCache };
