const crypto = require('crypto');
const { query } = require('../../config/database');

const ALGO = 'aes-256-gcm';
const KEY = Buffer.from(
  process.env.CREDENTIALS_ENCRYPTION_KEY || 'lakadiya_default_key_change_me!!',
  'utf8'
).slice(0, 32);

async function ensureTable() {
  await query(`
    CREATE TABLE IF NOT EXISTS credentials (
      key_name   TEXT PRIMARY KEY,
      encrypted  TEXT NOT NULL,
      iv         TEXT NOT NULL,
      tag        TEXT NOT NULL,
      updated_at TIMESTAMPTZ DEFAULT NOW()
    )
  `);
}

function encrypt(plaintext) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv(ALGO, KEY, iv);
  let enc = cipher.update(plaintext, 'utf8', 'hex');
  enc += cipher.final('hex');
  return { encrypted: enc, iv: iv.toString('hex'), tag: cipher.getAuthTag().toString('hex') };
}

function decrypt(encrypted, ivHex, tagHex) {
  const decipher = crypto.createDecipheriv(ALGO, KEY, Buffer.from(ivHex, 'hex'));
  decipher.setAuthTag(Buffer.from(tagHex, 'hex'));
  let dec = decipher.update(encrypted, 'hex', 'utf8');
  dec += decipher.final('utf8');
  return dec;
}

async function setCredential(keyName, value) {
  await ensureTable();
  const { encrypted, iv, tag } = encrypt(value);
  await query(
    `INSERT INTO credentials (key_name, encrypted, iv, tag, updated_at)
     VALUES ($1, $2, $3, $4, NOW())
     ON CONFLICT (key_name) DO UPDATE
       SET encrypted = $2, iv = $3, tag = $4, updated_at = NOW()`,
    [keyName, encrypted, iv, tag]
  );
}

async function getCredential(keyName) {
  await ensureTable();
  const { rows } = await query(
    'SELECT encrypted, iv, tag FROM credentials WHERE key_name = $1',
    [keyName]
  );
  if (!rows.length) return null;
  return decrypt(rows[0].encrypted, rows[0].iv, rows[0].tag);
}

async function getPublicAppKeys() {
  const razorpayKey = await getCredential('razorpay_key_id');
  return { razorpay_key_id: razorpayKey || null };
}

async function listCredentials() {
  await ensureTable();
  const { rows } = await query(
    'SELECT key_name, encrypted, iv, tag, updated_at FROM credentials ORDER BY key_name ASC'
  );
  return rows.map(row => {
    let masked = '••••••••';
    try {
      const plain = decrypt(row.encrypted, row.iv, row.tag);
      masked = plain.length <= 8
        ? '•'.repeat(plain.length)
        : plain.slice(0, 4) + '••••••••' + plain.slice(-4);
    } catch (_) {}
    return { key_name: row.key_name, masked_value: masked, updated_at: row.updated_at };
  });
}

async function deleteCredential(keyName) {
  await ensureTable();
  const { rowCount } = await query(
    'DELETE FROM credentials WHERE key_name = $1', [keyName]
  );
  return rowCount > 0;
}

module.exports = { setCredential, getCredential, getPublicAppKeys, listCredentials, deleteCredential };
