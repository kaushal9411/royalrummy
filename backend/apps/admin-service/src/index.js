require('dotenv').config({ path: '../../../.env' });
const express = require('express');
const { v4: uuidv4 } = require('uuid');
const db = require('../../../libs/database/db');
const redis = require('../../../libs/cache/redis');
const logger = require('../../../libs/utils/logger');
const { sendResponse, sendError } = require('../../../libs/utils/response');
const { authenticateJWT, requireAdmin } = require('../../../libs/middleware/auth.middleware');
const { errorHandler, asyncHandler } = require('../../../libs/middleware/error.middleware');
const { requestLogger } = require('../../../libs/middleware/logger.middleware');
const { paginationParams } = require('../../../libs/utils/helpers');

const app = express();
app.use(express.json());
app.use(requestLogger);

const PORT = process.env.ADMIN_SERVICE_PORT || 3009;

// All admin routes require JWT + admin role
app.use(authenticateJWT, requireAdmin);

app.get('/health', (req, res) => res.json({ status: 'ok', service: 'admin-service' }));

// =============================================================================
// GET /admin/metrics/dashboard — KPI summary for the admin panel
// =============================================================================
app.get('/admin/metrics/dashboard', asyncHandler(async (req, res) => {
  const [
    dauResult,
    revenueResult,
    activeTablesResult,
    pendingWithdrawalsResult,
    fraudFlagsResult,
    newUsersResult,
  ] = await Promise.all([
    db.query(`SELECT COUNT(DISTINCT user_id) AS dau FROM transactions WHERE created_at >= NOW() - INTERVAL '24 hours'`),
    db.query(`SELECT COALESCE(SUM(amount), 0) AS daily_revenue FROM transactions WHERE type = 'game_entry' AND created_at >= NOW() - INTERVAL '24 hours'`),
    db.query(`SELECT COUNT(*) AS count FROM game_tables WHERE status = 'in_progress'`),
    db.query(`SELECT COUNT(*) AS count, COALESCE(SUM(ABS(amount)), 0) AS total_amount FROM transactions WHERE type = 'withdrawal' AND status = 'pending'`),
    db.query(`SELECT COUNT(*) AS count FROM fraud_events WHERE created_at >= NOW() - INTERVAL '24 hours' AND resolved_at IS NULL`),
    db.query(`SELECT COUNT(*) AS count FROM users WHERE created_at >= NOW() - INTERVAL '24 hours'`),
  ]);

  // Fetch WebSocket connection count from Redis
  const wsCount = parseInt(await redis.get('ws:connections') || '0');

  // Revenue last 7 days (for chart)
  const revenueChartResult = await db.query(`
    SELECT DATE_TRUNC('day', created_at) AS day,
           COALESCE(SUM(amount), 0) AS revenue
    FROM transactions
    WHERE type = 'game_entry' AND created_at >= NOW() - INTERVAL '7 days'
    GROUP BY 1 ORDER BY 1
  `);

  sendResponse(res, 200, {
    dau: parseInt(dauResult.rows[0].dau),
    daily_revenue: parseFloat(revenueResult.rows[0].daily_revenue),
    active_tables: parseInt(activeTablesResult.rows[0].count),
    ws_connections: wsCount,
    pending_withdrawals: {
      count: parseInt(pendingWithdrawalsResult.rows[0].count),
      total_amount: parseFloat(pendingWithdrawalsResult.rows[0].total_amount),
    },
    fraud_flags: parseInt(fraudFlagsResult.rows[0].count),
    new_users_today: parseInt(newUsersResult.rows[0].count),
    revenue_chart: revenueChartResult.rows,
  });
}));

// =============================================================================
// GET /admin/users — list users with filters
// =============================================================================
app.get('/admin/users', asyncHandler(async (req, res) => {
  const { page, limit, offset } = paginationParams(req.query.page, req.query.limit);
  const { search, status, kyc_status } = req.query;

  let query = `
    SELECT u.id, u.phone, u.username, u.email, u.status, u.kyc_status,
           u.created_at, u.last_login_at,
           up.full_name, up.wins, up.losses, up.total_games,
           w.balance_cash, w.balance_bonus, w.total_deposited, w.total_won
    FROM users u
    LEFT JOIN user_profiles up ON up.user_id = u.id
    LEFT JOIN wallets w ON w.user_id = u.id
    WHERE u.deleted_at IS NULL
  `;
  const params = [];

  if (search) {
    params.push(`%${search}%`);
    query += ` AND (u.phone ILIKE $${params.length} OR u.username ILIKE $${params.length} OR up.full_name ILIKE $${params.length})`;
  }
  if (status) { params.push(status); query += ` AND u.status = $${params.length}`; }
  if (kyc_status) { params.push(kyc_status); query += ` AND u.kyc_status = $${params.length}`; }

  const countQuery = query.replace(/SELECT[\s\S]*?FROM/, 'SELECT COUNT(*) FROM');
  const countResult = await db.query(countQuery, params);

  query += ` ORDER BY u.created_at DESC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
  params.push(limit, offset);

  const result = await db.query(query, params);
  sendResponse(res, 200, result.rows, { page, limit, total: parseInt(countResult.rows[0].count) });
}));

// =============================================================================
// GET /admin/users/:id — user detail
// =============================================================================
app.get('/admin/users/:id', asyncHandler(async (req, res) => {
  const result = await db.query(`
    SELECT u.*, up.*, w.balance_cash, w.balance_bonus, w.total_deposited, w.total_won, w.total_withdrawn
    FROM users u
    LEFT JOIN user_profiles up ON up.user_id = u.id
    LEFT JOIN wallets w ON w.user_id = u.id
    WHERE u.id = $1
  `, [req.params.id]);

  if (!result.rows.length) return sendError(res, 404, 'USER_NOT_FOUND', 'User not found');

  const recentMatches = await db.query(`
    SELECT m.id, m.started_at, m.ended_at, gt.game_type, gt.entry_fee,
           mp.final_points, mp.prize_won, mp.status
    FROM match_players mp
    JOIN matches m ON m.id = mp.match_id
    JOIN game_tables gt ON gt.id = m.table_id
    WHERE mp.user_id = $1
    ORDER BY m.started_at DESC LIMIT 10
  `, [req.params.id]);

  sendResponse(res, 200, { ...result.rows[0], recent_matches: recentMatches.rows });
}));

// =============================================================================
// PATCH /admin/users/:id/status — ban, suspend, or activate a user
// =============================================================================
app.patch('/admin/users/:id/status', asyncHandler(async (req, res) => {
  const { status, reason } = req.body;
  const validStatuses = ['active', 'suspended', 'banned'];

  if (!validStatuses.includes(status)) {
    return sendError(res, 400, 'INVALID_STATUS', `Status must be one of: ${validStatuses.join(', ')}`);
  }

  await db.query(
    'UPDATE users SET status = $1, updated_at = NOW() WHERE id = $2',
    [status, req.params.id]
  );

  // Revoke all sessions if banning/suspending
  if (status !== 'active') {
    await db.query('DELETE FROM refresh_tokens WHERE user_id = $1', [req.params.id]);
    await redis.del(`user:online:${req.params.id}`);
  }

  logger.info({ adminId: req.user.id, targetId: req.params.id, status, reason, event: 'user_status_changed' });
  sendResponse(res, 200, { message: `User ${status} successfully` });
}));

// =============================================================================
// GET /admin/kyc — list KYC submissions pending review
// =============================================================================
app.get('/admin/kyc', asyncHandler(async (req, res) => {
  const { page, limit, offset } = paginationParams(req.query.page, req.query.limit);
  const { status = 'pending' } = req.query;

  const result = await db.query(`
    SELECT kd.id, kd.user_id, kd.doc_type, kd.status, kd.submitted_at,
           u.phone, u.username, up.full_name
    FROM kyc_documents kd
    JOIN users u ON u.id = kd.user_id
    LEFT JOIN user_profiles up ON up.user_id = kd.user_id
    WHERE kd.status = $1
    ORDER BY kd.submitted_at ASC
    LIMIT $2 OFFSET $3
  `, [status, limit, offset]);

  const countResult = await db.query(
    'SELECT COUNT(*) FROM kyc_documents WHERE status = $1', [status]
  );

  sendResponse(res, 200, result.rows, { page, limit, total: parseInt(countResult.rows[0].count) });
}));

// =============================================================================
// PATCH /admin/kyc/:id — approve or reject a KYC document
// =============================================================================
app.patch('/admin/kyc/:id', asyncHandler(async (req, res) => {
  const { action, rejection_reason } = req.body; // action: 'approve' | 'reject'

  if (!['approve', 'reject'].includes(action)) {
    return sendError(res, 400, 'INVALID_ACTION', 'Action must be approve or reject');
  }

  const docResult = await db.query('SELECT * FROM kyc_documents WHERE id = $1', [req.params.id]);
  if (!docResult.rows.length) return sendError(res, 404, 'KYC_NOT_FOUND', 'Document not found');

  const doc = docResult.rows[0];
  const newStatus = action === 'approve' ? 'approved' : 'rejected';

  await db.query(
    'UPDATE kyc_documents SET status = $1, rejection_reason = $2, reviewed_at = NOW(), reviewed_by = $3 WHERE id = $4',
    [newStatus, rejection_reason || null, req.user.id, req.params.id]
  );

  // Update user kyc_status
  await db.query(
    'UPDATE users SET kyc_status = $1, updated_at = NOW() WHERE id = $2',
    [newStatus, doc.user_id]
  );

  logger.info({ adminId: req.user.id, kycId: req.params.id, action, event: 'kyc_reviewed' });
  sendResponse(res, 200, { message: `KYC document ${newStatus}` });
}));

// =============================================================================
// GET /admin/withdrawals — list pending withdrawals
// =============================================================================
app.get('/admin/withdrawals', asyncHandler(async (req, res) => {
  const { page, limit, offset } = paginationParams(req.query.page, req.query.limit);

  const result = await db.query(`
    SELECT t.id, t.user_id, t.amount, t.status, t.created_at, t.description,
           u.phone, u.username
    FROM transactions t
    JOIN users u ON u.id = t.user_id
    WHERE t.type = 'withdrawal' AND t.status = 'pending'
    ORDER BY t.created_at ASC
    LIMIT $1 OFFSET $2
  `, [limit, offset]);

  const countResult = await db.query(
    `SELECT COUNT(*), COALESCE(SUM(ABS(amount)), 0) AS total
     FROM transactions WHERE type = 'withdrawal' AND status = 'pending'`
  );

  sendResponse(res, 200, result.rows, {
    page, limit,
    total: parseInt(countResult.rows[0].count),
    total_amount: parseFloat(countResult.rows[0].total),
  });
}));

// =============================================================================
// PATCH /admin/withdrawals/:id — approve or reject a withdrawal
// =============================================================================
app.patch('/admin/withdrawals/:id', asyncHandler(async (req, res) => {
  const { action, rejection_reason } = req.body;
  if (!['approve', 'reject'].includes(action)) {
    return sendError(res, 400, 'INVALID_ACTION', 'Action must be approve or reject');
  }

  const txnResult = await db.query(
    'SELECT * FROM transactions WHERE id = $1 AND type = $2 AND status = $3',
    [req.params.id, 'withdrawal', 'pending']
  );

  if (!txnResult.rows.length) {
    return sendError(res, 404, 'TXN_NOT_FOUND', 'Withdrawal not found or already processed');
  }

  const txn = txnResult.rows[0];

  if (action === 'reject') {
    // Refund the amount
    const client = await db.connect();
    try {
      await client.query('BEGIN');
      await client.query(
        'UPDATE transactions SET status = $1, description = $2 WHERE id = $3',
        ['rejected', rejection_reason || 'Rejected by admin', req.params.id]
      );
      await client.query(
        'UPDATE wallets SET balance_cash = balance_cash + $1, total_withdrawn = total_withdrawn - $1 WHERE user_id = $2',
        [Math.abs(txn.amount), txn.user_id]
      );
      await client.query('COMMIT');
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  } else {
    await db.query(
      'UPDATE transactions SET status = $1, updated_at = NOW() WHERE id = $2',
      ['completed', req.params.id]
    );
  }

  logger.info({ adminId: req.user.id, txnId: req.params.id, action, event: 'withdrawal_reviewed' });
  sendResponse(res, 200, { message: `Withdrawal ${action}d successfully` });
}));

// =============================================================================
// GET /admin/fraud — list fraud events
// =============================================================================
app.get('/admin/fraud', asyncHandler(async (req, res) => {
  const { page, limit, offset } = paginationParams(req.query.page, req.query.limit);
  const { resolved } = req.query;

  let query = `
    SELECT fe.id, fe.user_id, fe.event_type, fe.severity, fe.description,
           fe.created_at, fe.resolved_at, fe.resolved_by,
           u.phone, u.username
    FROM fraud_events fe
    JOIN users u ON u.id = fe.user_id
    WHERE 1=1
  `;
  const params = [];

  if (resolved === 'false') query += ' AND fe.resolved_at IS NULL';
  else if (resolved === 'true') query += ' AND fe.resolved_at IS NOT NULL';

  query += ` ORDER BY fe.created_at DESC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
  params.push(limit, offset);

  const result = await db.query(query, params);
  sendResponse(res, 200, result.rows, { page, limit });
}));

// =============================================================================
// PATCH /admin/fraud/:id/resolve — mark fraud event as resolved
// =============================================================================
app.patch('/admin/fraud/:id/resolve', asyncHandler(async (req, res) => {
  const { resolution_notes } = req.body;

  await db.query(
    'UPDATE fraud_events SET resolved_at = NOW(), resolved_by = $1, resolution_notes = $2 WHERE id = $3',
    [req.user.id, resolution_notes || null, req.params.id]
  );

  sendResponse(res, 200, { message: 'Fraud event resolved' });
}));

// =============================================================================
// GET /admin/metrics/revenue — revenue breakdown by period
// =============================================================================
app.get('/admin/metrics/revenue', asyncHandler(async (req, res) => {
  const { period = '7d' } = req.query;
  const intervalMap = { '24h': '24 hours', '7d': '7 days', '30d': '30 days' };
  const interval = intervalMap[period] || '7 days';
  const groupBy = period === '24h' ? 'hour' : 'day';

  const result = await db.query(`
    SELECT DATE_TRUNC($1, created_at) AS period,
           SUM(CASE WHEN type = 'deposit' THEN amount ELSE 0 END) AS deposits,
           SUM(CASE WHEN type = 'game_entry' THEN ABS(amount) ELSE 0 END) AS entry_fees,
           SUM(CASE WHEN type = 'game_win' THEN amount ELSE 0 END) AS payouts,
           SUM(CASE WHEN type = 'withdrawal' AND status = 'completed' THEN ABS(amount) ELSE 0 END) AS withdrawals,
           COUNT(DISTINCT user_id) AS unique_users
    FROM transactions
    WHERE created_at >= NOW() - INTERVAL '${interval}'
    GROUP BY 1 ORDER BY 1
  `, [groupBy]);

  sendResponse(res, 200, result.rows);
}));

// =============================================================================
// POST /admin/notifications/push — broadcast push notification
// =============================================================================
app.post('/admin/notifications/push', asyncHandler(async (req, res) => {
  const { title, body, target = 'all', user_ids, topic } = req.body;

  if (!title || !body) return sendError(res, 400, 'MISSING_FIELDS', 'title and body are required');

  // Queue notification job (actual FCM sending handled by notification service)
  const notifId = uuidv4();
  await db.query(`
    INSERT INTO notifications (id, user_id, type, title, body, data, status)
    SELECT $1, u.id, 'push', $2, $3, $4::jsonb, 'pending'
    FROM users u
    WHERE u.status = 'active' AND u.deleted_at IS NULL
    ${target === 'specific' ? 'AND u.id = ANY($5)' : ''}
  `, target === 'specific'
    ? [notifId, title, body, JSON.stringify({ topic }), user_ids]
    : [notifId, title, body, JSON.stringify({ topic })]);

  logger.info({ adminId: req.user.id, title, target, event: 'push_notification_queued' });
  sendResponse(res, 202, { message: 'Push notification queued', notification_id: notifId });
}));

// =============================================================================
// GET /admin/tables — live game tables overview
// =============================================================================
app.get('/admin/tables', asyncHandler(async (req, res) => {
  const result = await db.query(`
    SELECT gt.id, gt.game_type, gt.status, gt.entry_fee, gt.max_players,
           gt.started_at, gt.created_at,
           COUNT(ts.id) AS seated_players,
           m.id AS match_id
    FROM game_tables gt
    LEFT JOIN table_seats ts ON ts.table_id = gt.id
    LEFT JOIN matches m ON m.table_id = gt.id AND m.status = 'in_progress'
    WHERE gt.status IN ('waiting', 'in_progress')
    GROUP BY gt.id, m.id
    ORDER BY gt.started_at DESC NULLS LAST
    LIMIT 100
  `);

  sendResponse(res, 200, result.rows);
}));

app.use(errorHandler);

app.listen(PORT, () => logger.info(`Admin Service running on port ${PORT}`));
module.exports = { app };
