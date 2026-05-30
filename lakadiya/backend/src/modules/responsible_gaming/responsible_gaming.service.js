const { query } = require('../../config/database');

async function ensureTables() {
  await query(`
    CREATE TABLE IF NOT EXISTS responsible_gaming_settings (
      user_id             UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      daily_limit         NUMERIC(10,2),
      weekly_limit        NUMERIC(10,2),
      monthly_limit       NUMERIC(10,2),
      self_excluded       BOOLEAN DEFAULT FALSE,
      exclusion_until     TIMESTAMPTZ,
      updated_at          TIMESTAMPTZ DEFAULT NOW()
    )
  `);
}

async function getSettings(userId) {
  await ensureTables();
  const { rows } = await query(
    'SELECT * FROM responsible_gaming_settings WHERE user_id=$1',
    [userId]
  );
  return rows[0] || {
    user_id: userId,
    daily_limit: null,
    weekly_limit: null,
    monthly_limit: null,
    self_excluded: false,
    exclusion_until: null,
  };
}

async function updateSettings(userId, { dailyLimit, weeklyLimit, monthlyLimit }) {
  await ensureTables();
  const { rows } = await query(
    `INSERT INTO responsible_gaming_settings (user_id, daily_limit, weekly_limit, monthly_limit, updated_at)
     VALUES ($1, $2, $3, $4, NOW())
     ON CONFLICT (user_id) DO UPDATE
       SET daily_limit=$2, weekly_limit=$3, monthly_limit=$4, updated_at=NOW()
     RETURNING *`,
    [userId, dailyLimit || null, weeklyLimit || null, monthlyLimit || null]
  );
  return rows[0];
}

async function setSelfExclusion(userId, days) {
  await ensureTables();
  const exclusionUntil = days > 0
    ? new Date(Date.now() + days * 24 * 60 * 60 * 1000)
    : null;
  const { rows } = await query(
    `INSERT INTO responsible_gaming_settings (user_id, self_excluded, exclusion_until, updated_at)
     VALUES ($1, $2, $3, NOW())
     ON CONFLICT (user_id) DO UPDATE
       SET self_excluded=$2, exclusion_until=$3, updated_at=NOW()
     RETURNING *`,
    [userId, days > 0, exclusionUntil]
  );
  return rows[0];
}

// Returns true if user is currently self-excluded — called before allowing game entry/betting
async function isExcluded(userId) {
  await ensureTables();
  const { rows } = await query(
    `SELECT self_excluded, exclusion_until FROM responsible_gaming_settings WHERE user_id=$1`,
    [userId]
  );
  if (!rows.length || !rows[0].self_excluded) return false;
  if (rows[0].exclusion_until && new Date(rows[0].exclusion_until) < new Date()) {
    // Exclusion expired — lift it automatically
    await query(
      `UPDATE responsible_gaming_settings SET self_excluded=FALSE, exclusion_until=NULL WHERE user_id=$1`,
      [userId]
    );
    return false;
  }
  return true;
}

// Returns { used, limit, exceeded } for the given period ('daily'|'weekly'|'monthly')
async function checkSpendLimit(userId, period) {
  await ensureTables();
  const { rows: settRows } = await query(
    `SELECT ${period}_limit AS lim FROM responsible_gaming_settings WHERE user_id=$1`,
    [userId]
  );
  const limit = settRows[0]?.lim ? parseFloat(settRows[0].lim) : null;
  if (!limit) return { used: 0, limit: null, exceeded: false };

  const intervals = { daily: '1 day', weekly: '7 days', monthly: '30 days' };
  const { rows } = await query(
    `SELECT COALESCE(SUM(amount),0) AS used
     FROM payment_transactions
     WHERE user_id=$1 AND type='bet_deduct' AND status='success'
       AND created_at >= NOW() - INTERVAL '${intervals[period]}'`,
    [userId]
  );
  const used = parseFloat(rows[0].used);
  return { used, limit, exceeded: used >= limit };
}

module.exports = { getSettings, updateSettings, setSelfExclusion, isExcluded, checkSpendLimit };
