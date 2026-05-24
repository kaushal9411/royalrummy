require('dotenv').config({ path: '../../../.env' });
const express = require('express');
const { v4: uuidv4 } = require('uuid');
const Razorpay = require('razorpay');
const crypto = require('crypto');
const db = require('../../../libs/database/db');
const redis = require('../../../libs/cache/redis');
const logger = require('../../../libs/utils/logger');
const { sendResponse, sendError } = require('../../../libs/utils/response');
const { authenticateJWT } = require('../../../libs/middleware/auth.middleware');
const { errorHandler, asyncHandler } = require('../../../libs/middleware/error.middleware');
const { requestLogger } = require('../../../libs/middleware/logger.middleware');
const { paginationParams } = require('../../../libs/utils/helpers');

const app = express();
app.use(express.json());
app.use(requestLogger);

const PORT = process.env.WALLET_SERVICE_PORT || 3003;
const LOCK_TTL_SECS = 10;

const razorpay = new Razorpay({
  key_id: process.env.RAZORPAY_KEY_ID,
  key_secret: process.env.RAZORPAY_KEY_SECRET,
});

// Health
app.get('/health', (req, res) => res.json({ status: 'ok', service: 'wallet-service' }));

// =============================================================================
// GET /v1/wallet — wallet balance + totals
// =============================================================================
app.get('/v1/wallet', authenticateJWT, asyncHandler(async (req, res) => {
  const result = await db.query(`
    SELECT balance_cash, balance_bonus, balance_winnings,
           total_deposited, total_withdrawn, total_won, total_lost
    FROM wallets WHERE user_id = $1
  `, [req.user.id]);

  if (!result.rows.length) return sendError(res, 404, 'WALLET_NOT_FOUND', 'Wallet not found');

  sendResponse(res, 200, result.rows[0]);
}));

// =============================================================================
// GET /v1/wallet/transactions — paginated transaction history
// =============================================================================
app.get('/v1/wallet/transactions', authenticateJWT, asyncHandler(async (req, res) => {
  const { page, limit, offset } = paginationParams(req.query.page, req.query.limit);
  const { type } = req.query;

  let query = `
    SELECT id, type, amount, currency_type, balance_before, balance_after,
           status, reference_type, reference_id, description, created_at
    FROM transactions
    WHERE user_id = $1
  `;
  const params = [req.user.id];

  if (type) { params.push(type); query += ` AND type = $${params.length}`; }
  query += ` ORDER BY created_at DESC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
  params.push(limit, offset);

  const countResult = await db.query(
    `SELECT COUNT(*) FROM transactions WHERE user_id = $1${type ? ' AND type = $2' : ''}`,
    type ? [req.user.id, type] : [req.user.id]
  );

  const result = await db.query(query, params);
  sendResponse(res, 200, result.rows, { page, limit, total: parseInt(countResult.rows[0].count) });
}));

// =============================================================================
// POST /v1/wallet/deposit/initiate — create Razorpay order
// =============================================================================
app.post('/v1/wallet/deposit/initiate', authenticateJWT, asyncHandler(async (req, res) => {
  const { amount } = req.body;

  if (!amount || amount < 10 || amount > 100000) {
    return sendError(res, 400, 'WALLET_002', 'Amount must be between ₹10 and ₹1,00,000');
  }

  const amountPaise = Math.round(parseFloat(amount) * 100);
  const orderId = uuidv4();

  const razorpayOrder = await razorpay.orders.create({
    amount: amountPaise,
    currency: 'INR',
    receipt: orderId,
    notes: { user_id: req.user.id, platform: 'RoyalRummy' },
  });

  // Persist the pending payment order
  await db.query(`
    INSERT INTO payment_orders (id, user_id, razorpay_order_id, amount, currency, status, type)
    VALUES ($1, $2, $3, $4, 'INR', 'created', 'deposit')
  `, [orderId, req.user.id, razorpayOrder.id, amount]);

  sendResponse(res, 201, {
    order_id: orderId,
    razorpay_order_id: razorpayOrder.id,
    amount,
    currency: 'INR',
    key: process.env.RAZORPAY_KEY_ID,
  });
}));

// =============================================================================
// POST /v1/wallet/deposit/verify — verify Razorpay payment signature
// =============================================================================
app.post('/v1/wallet/deposit/verify', authenticateJWT, asyncHandler(async (req, res) => {
  const { order_id, razorpay_order_id, razorpay_payment_id, razorpay_signature } = req.body;

  // Verify Razorpay signature
  const expectedSig = crypto
    .createHmac('sha256', process.env.RAZORPAY_KEY_SECRET)
    .update(`${razorpay_order_id}|${razorpay_payment_id}`)
    .digest('hex');

  if (expectedSig !== razorpay_signature) {
    return sendError(res, 400, 'WALLET_003', 'Invalid payment signature');
  }

  // Fetch the pending order
  const orderResult = await db.query(
    'SELECT * FROM payment_orders WHERE id = $1 AND user_id = $2 AND status = $3',
    [order_id, req.user.id, 'created']
  );

  if (!orderResult.rows.length) {
    return sendError(res, 404, 'WALLET_004', 'Payment order not found or already processed');
  }

  const order = orderResult.rows[0];
  const amount = parseFloat(order.amount);

  // Idempotency lock
  const lockKey = `wallet:deposit:lock:${razorpay_payment_id}`;
  const locked = await redis.setnx(lockKey, '1');
  if (!locked) return sendError(res, 409, 'WALLET_005', 'Payment already being processed');
  await redis.expire(lockKey, LOCK_TTL_SECS);

  const client = await db.connect();
  try {
    await client.query('BEGIN');

    const wallet = await client.query(
      'SELECT balance_cash FROM wallets WHERE user_id = $1 FOR UPDATE',
      [req.user.id]
    );
    const balanceBefore = parseFloat(wallet.rows[0]?.balance_cash || 0);

    // Credit wallet
    await client.query(
      'UPDATE wallets SET balance_cash = balance_cash + $1, total_deposited = total_deposited + $1 WHERE user_id = $2',
      [amount, req.user.id]
    );

    // Mark order paid
    await client.query(
      'UPDATE payment_orders SET status = $1, razorpay_payment_id = $2, paid_at = NOW() WHERE id = $3',
      ['paid', razorpay_payment_id, order_id]
    );

    // Record transaction
    await client.query(`
      INSERT INTO transactions (id, user_id, type, amount, currency_type, balance_before, balance_after,
        status, reference_id, reference_type, description)
      VALUES ($1, $2, 'deposit', $3, 'cash', $4, $5, 'completed', $6, 'payment', 'Wallet top-up via Razorpay')
    `, [uuidv4(), req.user.id, amount, balanceBefore, balanceBefore + amount, razorpay_payment_id]);

    await client.query('COMMIT');
    logger.info({ userId: req.user.id, amount, event: 'deposit_success' });

    sendResponse(res, 200, { message: 'Deposit successful', amount, new_balance: balanceBefore + amount });
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
    await redis.del(lockKey);
  }
}));

// =============================================================================
// POST /v1/wallet/withdraw — request withdrawal
// =============================================================================
app.post('/v1/wallet/withdraw', authenticateJWT, asyncHandler(async (req, res) => {
  const { amount, bank_account_id } = req.body;

  if (!amount || amount < 100) {
    return sendError(res, 400, 'WALLET_006', 'Minimum withdrawal is ₹100');
  }
  if (!bank_account_id) {
    return sendError(res, 400, 'WALLET_007', 'Bank account is required');
  }

  // Check KYC
  const user = await db.query('SELECT kyc_status FROM users WHERE id = $1', [req.user.id]);
  if (user.rows[0]?.kyc_status !== 'approved') {
    return sendError(res, 403, 'WALLET_008', 'KYC verification required for withdrawals');
  }

  // Distributed lock to prevent concurrent withdrawal requests
  const lockKey = `wallet:withdraw:lock:${req.user.id}`;
  const locked = await redis.setnx(lockKey, '1');
  if (!locked) return sendError(res, 409, 'WALLET_009', 'A withdrawal request is already being processed');
  await redis.expire(lockKey, LOCK_TTL_SECS);

  const client = await db.connect();
  try {
    await client.query('BEGIN');

    const wallet = await client.query(
      'SELECT balance_cash, balance_winnings FROM wallets WHERE user_id = $1 FOR UPDATE',
      [req.user.id]
    );
    const w = wallet.rows[0];
    const withdrawable = parseFloat(w.balance_cash); // Only cash balance is withdrawable

    if (withdrawable < amount) {
      await client.query('ROLLBACK');
      return sendError(res, 400, 'WALLET_010', `Insufficient withdrawable balance. Available: ₹${withdrawable.toFixed(2)}`);
    }

    const tdsAmount = amount >= 10000 ? Math.round(amount * 0.30 * 100) / 100 : 0;
    const netAmount = amount - tdsAmount;

    const txnId = uuidv4();
    const balanceBefore = withdrawable;

    // Debit wallet immediately; status = pending (admin approval required)
    await client.query(
      'UPDATE wallets SET balance_cash = balance_cash - $1, total_withdrawn = total_withdrawn + $1 WHERE user_id = $2',
      [amount, req.user.id]
    );

    await client.query(`
      INSERT INTO transactions (id, user_id, type, amount, currency_type, balance_before, balance_after,
        status, reference_type, description)
      VALUES ($1, $2, 'withdrawal', $3, 'cash', $4, $5, 'pending', 'withdrawal', $6)
    `, [txnId, req.user.id, -amount, balanceBefore, balanceBefore - amount,
      `Withdrawal request ₹${amount} (TDS: ₹${tdsAmount})`]);

    await client.query('COMMIT');
    logger.info({ userId: req.user.id, amount, tdsAmount, netAmount, event: 'withdrawal_requested' });

    sendResponse(res, 202, {
      message: 'Withdrawal request submitted. Processing takes 1-3 business days.',
      transaction_id: txnId,
      amount,
      tds_deducted: tdsAmount,
      net_amount: netAmount,
    });
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
    await redis.del(lockKey);
  }
}));

// =============================================================================
// POST /v1/wallet/transfer — internal transfer for game entry fee
// Used by game-service (internal call only, validated by shared secret)
// =============================================================================
app.post('/v1/wallet/transfer', asyncHandler(async (req, res) => {
  const internalSecret = req.headers['x-internal-secret'];
  if (internalSecret !== process.env.INTERNAL_SERVICE_SECRET) {
    return sendError(res, 403, 'FORBIDDEN', 'Forbidden');
  }

  const { from_user_id, to_user_id, amount, reference_id, description } = req.body;

  const lockKey = `wallet:transfer:lock:${reference_id}`;
  const locked = await redis.setnx(lockKey, '1');
  if (!locked) return sendError(res, 409, 'CONFLICT', 'Transfer already in progress');
  await redis.expire(lockKey, LOCK_TTL_SECS);

  const client = await db.connect();
  try {
    await client.query('BEGIN');

    if (from_user_id) {
      // Debit source (entry fee)
      const fromWallet = await client.query(
        'SELECT balance_cash, balance_bonus FROM wallets WHERE user_id = $1 FOR UPDATE',
        [from_user_id]
      );
      const fw = fromWallet.rows[0];
      const total = parseFloat(fw.balance_cash) + parseFloat(fw.balance_bonus);
      if (total < amount) throw Object.assign(new Error('Insufficient balance'), { status: 400, code: 'WALLET_001' });

      const bonusDed = Math.min(parseFloat(fw.balance_bonus), amount);
      const cashDed = amount - bonusDed;

      await client.query(
        'UPDATE wallets SET balance_cash = balance_cash - $1, balance_bonus = balance_bonus - $2 WHERE user_id = $3',
        [cashDed, bonusDed, from_user_id]
      );

      await client.query(`
        INSERT INTO transactions (id, user_id, type, amount, currency_type, balance_before, balance_after, status, reference_id, reference_type, description)
        VALUES ($1, $2, 'game_entry', $3, 'mixed', $4, $5, 'completed', $6, 'game', $7)
      `, [uuidv4(), from_user_id, -amount, parseFloat(fw.balance_cash), parseFloat(fw.balance_cash) - cashDed, reference_id, description]);
    }

    if (to_user_id) {
      // Credit destination (prize)
      const toWallet = await client.query(
        'SELECT balance_cash FROM wallets WHERE user_id = $1 FOR UPDATE',
        [to_user_id]
      );
      const tw = toWallet.rows[0];
      const balBefore = parseFloat(tw.balance_cash);

      await client.query(
        'UPDATE wallets SET balance_cash = balance_cash + $1, total_won = total_won + $1 WHERE user_id = $2',
        [amount, to_user_id]
      );

      await client.query(`
        INSERT INTO transactions (id, user_id, type, amount, currency_type, balance_before, balance_after, status, reference_id, reference_type, description)
        VALUES ($1, $2, 'game_win', $3, 'cash', $4, $5, 'completed', $6, 'game', $7)
      `, [uuidv4(), to_user_id, amount, balBefore, balBefore + amount, reference_id, description]);
    }

    await client.query('COMMIT');
    sendResponse(res, 200, { success: true });
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
    await redis.del(lockKey);
  }
}));

// =============================================================================
// POST /v1/wallet/bonus — credit signup/referral bonus (internal)
// =============================================================================
app.post('/v1/wallet/bonus', asyncHandler(async (req, res) => {
  const internalSecret = req.headers['x-internal-secret'];
  if (internalSecret !== process.env.INTERNAL_SERVICE_SECRET) {
    return sendError(res, 403, 'FORBIDDEN', 'Forbidden');
  }

  const { user_id, amount, bonus_type, reference_id } = req.body;

  const client = await db.connect();
  try {
    await client.query('BEGIN');

    const wallet = await client.query(
      'SELECT balance_bonus FROM wallets WHERE user_id = $1 FOR UPDATE',
      [user_id]
    );
    const balBefore = parseFloat(wallet.rows[0]?.balance_bonus || 0);

    await client.query(
      'UPDATE wallets SET balance_bonus = balance_bonus + $1 WHERE user_id = $2',
      [amount, user_id]
    );

    await client.query(`
      INSERT INTO transactions (id, user_id, type, amount, currency_type, balance_before, balance_after, status, reference_id, reference_type, description)
      VALUES ($1, $2, $3, $4, 'bonus', $5, $6, 'completed', $7, 'bonus', $8)
    `, [uuidv4(), user_id, bonus_type || 'bonus_credit', amount, balBefore, balBefore + amount,
      reference_id || null, `Bonus credit: ${bonus_type || 'bonus'}`]);

    await client.query('COMMIT');
    sendResponse(res, 200, { success: true, new_bonus_balance: balBefore + amount });
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}));

app.use(errorHandler);

app.listen(PORT, () => logger.info(`Wallet Service running on port ${PORT}`));
module.exports = { app };
