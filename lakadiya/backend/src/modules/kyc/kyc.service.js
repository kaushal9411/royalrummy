const { query } = require('../../config/database');
const path = require('path');
const fs = require('fs');

async function ensureTable() {
  await query(`
    CREATE TABLE IF NOT EXISTS kyc_submissions (
      id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      pan_number    TEXT,
      full_name     TEXT,
      pan_doc_path  TEXT,
      selfie_path   TEXT,
      status        TEXT NOT NULL DEFAULT 'pending',  -- pending | approved | rejected
      admin_remark  TEXT,
      submitted_at  TIMESTAMPTZ DEFAULT NOW(),
      reviewed_at   TIMESTAMPTZ,
      UNIQUE (user_id)
    )
  `);
}

async function submitKyc(userId, { panNumber, fullName, panDocPath, selfiePath }) {
  await ensureTable();
  const { rows } = await query(
    `INSERT INTO kyc_submissions (user_id, pan_number, full_name, pan_doc_path, selfie_path, status, submitted_at)
     VALUES ($1, $2, $3, $4, $5, 'pending', NOW())
     ON CONFLICT (user_id) DO UPDATE
       SET pan_number=$2, full_name=$3, pan_doc_path=$4, selfie_path=$5,
           status='pending', admin_remark=NULL, submitted_at=NOW(), reviewed_at=NULL
     RETURNING *`,
    [userId, panNumber, fullName, panDocPath, selfiePath]
  );
  return rows[0];
}

async function getKycStatus(userId) {
  await ensureTable();
  const { rows } = await query(
    'SELECT id, status, admin_remark, submitted_at, reviewed_at FROM kyc_submissions WHERE user_id=$1',
    [userId]
  );
  return rows[0] || null;
}

async function approveKyc(kycId) {
  const { rows } = await query(
    `UPDATE kyc_submissions SET status='approved', reviewed_at=NOW() WHERE id=$1 RETURNING user_id`,
    [kycId]
  );
  if (rows.length) {
    await query('UPDATE users SET kyc_verified=TRUE WHERE id=$1', [rows[0].user_id]);
  }
  return rows[0];
}

async function rejectKyc(kycId, remark) {
  const { rows } = await query(
    `UPDATE kyc_submissions SET status='rejected', admin_remark=$2, reviewed_at=NOW() WHERE id=$1 RETURNING user_id`,
    [kycId, remark]
  );
  if (rows.length) {
    await query('UPDATE users SET kyc_verified=FALSE WHERE id=$1', [rows[0].user_id]);
  }
  return rows[0];
}

async function listPendingKyc() {
  await ensureTable();
  const { rows } = await query(
    `SELECT k.*, u.username, u.mobile FROM kyc_submissions k
     JOIN users u ON u.id = k.user_id
     WHERE k.status='pending' ORDER BY k.submitted_at ASC`
  );
  return rows;
}

module.exports = { submitKyc, getKycStatus, approveKyc, rejectKyc, listPendingKyc };
