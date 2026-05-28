const Razorpay = require('razorpay');
const crypto = require('crypto');
const { query, getClient } = require('../../config/database');
const logger = require('../../config/logger');
const { getSettings } = require('../admin/settings.service');

const razorpay = new Razorpay({
  key_id: process.env.RAZORPAY_KEY_ID,
  key_secret: process.env.RAZORPAY_KEY_SECRET,
});

// Conversion: 1 INR = 1 coin
const COINS_PER_RUPEE = 1;

const createPaymentOrder = async (userId, amount, type = 'add') => {
  try {
    console.log(`[Payment] Creating order - User: ${userId}, Amount: ${amount}, Type: ${type}`);
    
    if (amount <= 0) throw { status: 400, message: 'Invalid amount' };
    
    const coins = Math.floor(amount * COINS_PER_RUPEE);
    
    // Receipt must be max 40 characters for Razorpay
    const timestamp = Date.now().toString().slice(-10);
    const randomId = Math.random().toString(36).substring(2, 8).toUpperCase();
    const receipt = `ORD${timestamp}${randomId}`.substring(0, 40);
    
    const options = {
      amount: Math.round(amount * 100),
      currency: 'INR',
      receipt: receipt,
      notes: {
        userId,
        type,
        coins,
      },
    };

    console.log(`[Payment] Razorpay options:`, options);
    
    const order = await razorpay.orders.create(options);
    console.log(`[Payment] Order created: ${order.id}`);
    
    const result = await query(
      `INSERT INTO payment_transactions 
       (user_id, razorpay_order_id, amount, coins, type, status, metadata)
       VALUES ($1, $2, $3, $4, $5, 'pending', $6)
       RETURNING id, razorpay_order_id, amount, coins, type, status, created_at`,
      [userId, order.id, amount, coins, type, JSON.stringify({ orderId: order.id })]
    );

    console.log(`[Payment] Transaction saved: ${result.rows[0].id}`);

    return {
      orderId: order.id,
      amount: order.amount,
      currency: order.currency,
      transactionId: result.rows[0].id,
      coins,
    };
  } catch (err) {
    console.error(`[Payment Error] ${err.message}`, err);
    logger.error(`Failed to create payment order: ${err.message}`, err);
    throw { status: 500, message: 'Failed to create payment order', error: err.message };
  }
};

const verifyPayment = async (userId, paymentId, orderId, signature) => {
  try {
    console.log(`[Payment] Verifying payment - User: ${userId}, PaymentID: ${paymentId}, OrderID: ${orderId}`);
    
    const text = `${orderId}|${paymentId}`;
    const expectedSignature = crypto
      .createHmac('sha256', process.env.RAZORPAY_KEY_SECRET)
      .update(text)
      .digest('hex');

    if (expectedSignature !== signature) {
      throw { status: 400, message: 'Invalid payment signature' };
    }

    console.log(`[Payment] Signature verified`);

    const payment = await razorpay.payments.fetch(paymentId);

    if (payment.status !== 'captured') {
      throw { status: 400, message: 'Payment not captured' };
    }

    console.log(`[Payment] Payment captured`);

    const transactionResult = await query(
      `SELECT id, type, amount, coins FROM payment_transactions 
       WHERE user_id = $1 AND razorpay_order_id = $2 AND status = 'pending'
       LIMIT 1`,
      [userId, orderId]
    );

    if (!transactionResult.rows.length) {
      throw { status: 404, message: 'Transaction not found' };
    }

    const transaction = transactionResult.rows[0];

    await query(
      `UPDATE payment_transactions 
       SET status = 'success', 
           razorpay_payment_id = $1,
           razorpay_signature = $2,
           updated_at = NOW()
       WHERE id = $3
       RETURNING id, razorpay_payment_id, coins, type, amount`,
      [paymentId, signature, transaction.id]
    );

    if (transaction.type === 'add') {
      await query(
        `UPDATE users SET coins = coins + $1 WHERE id = $2`,
        [transaction.coins, userId]
      );
      console.log(`[Payment] Coins added: ${transaction.coins}`);
    }

    return {
      success: true,
      transactionId: transaction.id,
      paymentId,
      coins: transaction.coins,
      amount: transaction.amount,
      type: transaction.type,
      message: 'Payment verified successfully',
    };
  } catch (err) {
    console.error(`[Payment Verify Error] ${err.message}`, err);
    logger.error(`Payment verification failed: ${err.message}`, err);
    
    try {
      await query(
        `UPDATE payment_transactions 
         SET status = 'failed', updated_at = NOW()
         WHERE razorpay_order_id = $1`,
        [orderId]
      );
    } catch (e) {
      console.error(`[Payment] Failed to mark transaction as failed:`, e);
    }

    throw { status: 400, message: err.message || 'Payment verification failed', error: err.message };
  }
};

const getWalletBalance = async (userId) => {
  try {
    console.log(`[Payment] Getting wallet balance for user: ${userId}`);
    
    const userResult = await query(
      `SELECT id, coins FROM users WHERE id = $1`,
      [userId]
    );

    if (!userResult.rows.length) {
      throw { status: 404, message: 'User not found' };
    }

    const user = userResult.rows[0];
    const userCoins = user.coins || 0;

    const statsResult = await query(
      `SELECT
         COALESCE(SUM(CASE WHEN type IN ('add', 'bet_win')      AND status = 'success' THEN amount ELSE 0 END), 0) as total_added,
         COALESCE(SUM(CASE WHEN type IN ('withdraw', 'bet_deduct') AND status = 'success' THEN amount ELSE 0 END), 0) as total_withdrawn
       FROM payment_transactions
       WHERE user_id = $1`,
      [userId]
    );

    const stats = statsResult.rows[0];
    const totalAdded = parseFloat(stats.total_added) || 0;
    const totalWithdrawn = parseFloat(stats.total_withdrawn) || 0;
    const currentBalance = totalAdded - totalWithdrawn;

    // ✅ SYNC: Return coins from users table as canonical source
    // This matches what frontend auth uses and what game logic deducts
    console.log(`[Payment] Wallet balance:`, {
      coins: userCoins,
      total_added: totalAdded,
      total_withdrawn: totalWithdrawn,
      current_balance: userCoins,  // Use coins column, not calculated balance
    });

    return {
      coins: userCoins,
      total_added: totalAdded,
      total_withdrawn: totalWithdrawn,
      current_balance: userCoins,  // ✅ SYNC with users.coins
    };
  } catch (err) {
    console.error(`[Payment Error] getWalletBalance failed:`, err);
    logger.error(`Failed to get wallet balance: ${err.message}`, err);
    throw { status: 500, message: 'Failed to get wallet balance', error: err.message };
  }
};

const getTransactionHistory = async (userId, limit = 20, offset = 0) => {
  try {
    console.log(`[Payment] Getting transaction history - User: ${userId}, Limit: ${limit}, Offset: ${offset}`);
    
    const result = await query(
      `SELECT id, amount, coins, type, status, created_at, updated_at
       FROM payment_transactions
       WHERE user_id = $1 AND type = 'add'
       ORDER BY created_at DESC
       LIMIT $2 OFFSET $3`,
      [userId, limit, offset]
    );

    console.log(`[Payment] Found ${result.rows.length} transactions`);
    return result.rows;
  } catch (err) {
    console.error(`[Payment Error] getTransactionHistory failed:`, err);
    throw { status: 500, message: 'Failed to get transaction history', error: err.message };
  }
};

const getWithdrawalRequests = async (userId, limit = 20, offset = 0) => {
  try {
    console.log(`[Payment] Getting withdrawal requests - User: ${userId}, Limit: ${limit}, Offset: ${offset}`);
    
    const result = await query(
      `SELECT id, amount, coins, type, status, description, created_at, updated_at
       FROM payment_transactions
       WHERE user_id = $1 AND type = 'withdraw'
       ORDER BY created_at DESC
       LIMIT $2 OFFSET $3`,
      [userId, limit, offset]
    );

    console.log(`[Payment] Found ${result.rows.length} withdrawal requests`);
    return result.rows;
  } catch (err) {
    console.error(`[Payment Error] getWithdrawalRequests failed:`, err);
    throw { status: 500, message: 'Failed to get withdrawal requests', error: err.message };
  }
};

const requestWithdrawal = async (userId, amount) => {
  try {
    if (amount <= 0) throw { status: 400, message: 'Invalid withdrawal amount' };

    const settings = await getSettings();
    const minW = parseFloat(settings.min_withdrawal) || 100;
    const maxW = parseFloat(settings.max_withdrawal) || 10000;
    if (amount < minW)
      throw { status: 400, message: `Minimum withdrawal amount is ₹${minW}` };
    if (amount > maxW)
      throw { status: 400, message: `Maximum withdrawal amount is ₹${maxW}` };

    console.log(`[Payment] Requesting withdrawal - User: ${userId}, Amount: ${amount}`);

    const userResult = await query('SELECT coins FROM users WHERE id = $1', [userId]);
    if (!userResult.rows.length) throw { status: 404, message: 'User not found' };

    const userCoins = userResult.rows[0].coins || 0;
    const coinsRequired = Math.floor(amount * COINS_PER_RUPEE);

    if (userCoins < coinsRequired) {
      throw { status: 400, message: `Insufficient coins. You have ${userCoins} coins, need ${coinsRequired}` };
    }

    const client = await getClient();
    let result;
    try {
      await client.query('BEGIN');
      result = await client.query(
        `INSERT INTO payment_transactions
         (user_id, amount, coins, type, status, description)
         VALUES ($1, $2, $3, 'withdraw', 'pending', 'Withdrawal request')
         RETURNING id, amount, coins, type, status, created_at`,
        [userId, amount, coinsRequired]
      );
      await client.query(
        `UPDATE users SET coins = GREATEST(coins - $1, 0) WHERE id = $2`,
        [coinsRequired, userId]
      );
      await client.query('COMMIT');
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }

    console.log(`[Payment] Withdrawal request created: ${result.rows[0].id}`);

    return result.rows[0];
  } catch (err) {
    console.error(`[Payment Error] requestWithdrawal failed:`, err);
    throw { status: 400, message: err.message || 'Withdrawal request failed', error: err.message };
  }
};

// Admin methods
const getAllUserTransactions = async (userId, type, limit = 50, offset = 0) => {
  try {
    console.log(`[Payment Admin] Getting all transactions - UserID: ${userId}, Type: ${type}`);
    
    let query_text = `
      SELECT pt.id, pt.user_id, pt.amount, pt.coins, pt.type, pt.status, pt.created_at,
             u.username, u.email
      FROM payment_transactions pt
      JOIN users u ON pt.user_id = u.id
      WHERE pt.type = 'add'
    `;
    const params = [];

    if (userId) {
      query_text += ` AND pt.user_id = $${params.length + 1}`;
      params.push(userId);
    }

    query_text += ` ORDER BY pt.created_at DESC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
    params.push(limit, offset);

    const result = await query(query_text, params);
    console.log(`[Payment Admin] Found ${result.rows.length} transactions`);
    return result.rows;
  } catch (err) {
    console.error(`[Payment Admin Error] getAllUserTransactions failed:`, err);
    throw { status: 500, message: 'Failed to get transactions', error: err.message };
  }
};

const getAllWithdrawalRequests = async (status, limit = 50, offset = 0) => {
  try {
    console.log(`[Payment Admin] Getting all withdrawals - Status: ${status}`);
    
    let query_text = `
      SELECT pt.id, pt.user_id, pt.amount, pt.coins, pt.status, pt.created_at, pt.updated_at,
             u.username, u.email
      FROM payment_transactions pt
      JOIN users u ON pt.user_id = u.id
      WHERE pt.type = 'withdraw'
    `;
    const params = [];

    if (status) {
      query_text += ` AND pt.status = $${params.length + 1}`;
      params.push(status);
    }

    query_text += ` ORDER BY pt.created_at DESC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
    params.push(limit, offset);

    const result = await query(query_text, params);
    console.log(`[Payment Admin] Found ${result.rows.length} withdrawal requests`);
    return result.rows;
  } catch (err) {
    console.error(`[Payment Admin Error] getAllWithdrawalRequests failed:`, err);
    throw { status: 500, message: 'Failed to get withdrawals', error: err.message };
  }
};

const approveWithdrawal = async (transactionId) => {
  try {
    console.log(`[Payment Admin] Approving withdrawal - Transaction: ${transactionId}`);
    
    const transactionResult = await query(
      `SELECT user_id, amount, coins FROM payment_transactions WHERE id = $1 AND type = 'withdraw'`,
      [transactionId]
    );

    if (!transactionResult.rows.length) {
      throw { status: 404, message: 'Withdrawal transaction not found' };
    }

    const transaction = transactionResult.rows[0];

    // Update transaction status
    const result = await query(
      `UPDATE payment_transactions 
       SET status = 'success', updated_at = NOW()
       WHERE id = $1
       RETURNING *`,
      [transactionId]
    );

    console.log(`[Payment Admin] Withdrawal approved - UserID: ${transaction.user_id}, Amount: ₹${transaction.amount}`);
    return result.rows[0];
  } catch (err) {
    console.error(`[Payment Admin Error] approveWithdrawal failed:`, err);
    throw { status: 500, message: 'Failed to approve withdrawal', error: err.message };
  }
};

const rejectWithdrawal = async (transactionId, reason) => {
  try {
    console.log(`[Payment Admin] Rejecting withdrawal - Transaction: ${transactionId}, Reason: ${reason}`);
    
    const transactionResult = await query(
      `SELECT user_id, amount, coins FROM payment_transactions WHERE id = $1 AND type = 'withdraw'`,
      [transactionId]
    );

    if (!transactionResult.rows.length) {
      throw { status: 404, message: 'Withdrawal transaction not found' };
    }

    const transaction = transactionResult.rows[0];

    // Update transaction status and add reason
    const result = await query(
      `UPDATE payment_transactions 
       SET status = 'failed', description = $1, updated_at = NOW()
       WHERE id = $2
       RETURNING *`,
      [reason || 'Rejection reason not provided', transactionId]
    );

    // Refund coins to user
    await query(
      `UPDATE users SET coins = coins + $1 WHERE id = $2`,
      [transaction.coins, transaction.user_id]
    );

    console.log(`[Payment Admin] Withdrawal rejected - UserID: ${transaction.user_id}, Amount: ₹${transaction.amount}`);
    return result.rows[0];
  } catch (err) {
    console.error(`[Payment Admin Error] rejectWithdrawal failed:`, err);
    throw { status: 500, message: 'Failed to reject withdrawal', error: err.message };
  }
};

const getAllGameBets = async (status, limit = 50, offset = 0) => {
  try {
    let q = `
      SELECT gb.id, gb.room_id, gb.match_id, gb.seat, gb.amount, gb.status,
             gb.created_at, gb.settled_at,
             u.username, u.email,
             r.code AS room_code, r.bet_amount AS room_bet_amount
      FROM game_bets gb
      JOIN users u ON u.id = gb.user_id
      JOIN rooms r ON r.id = gb.room_id
    `;
    const params = [];
    if (status) {
      q += ` WHERE gb.status = $${params.length + 1}`;
      params.push(status);
    }
    q += ` ORDER BY gb.created_at DESC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
    params.push(limit, offset);

    const result = await query(q, params);
    return result.rows;
  } catch (err) {
    console.error('[Payment Admin Error] getAllGameBets failed:', err);
    throw { status: 500, message: 'Failed to get game bets', error: err.message };
  }
};

const getPaymentStats = async () => {
  try {
    const result = await query(`
      SELECT
        COALESCE(SUM(CASE WHEN type = 'add'      AND status = 'success' THEN amount ELSE 0 END), 0)::float  AS total_revenue,
        COALESCE(SUM(CASE WHEN type = 'withdraw' AND status = 'success' THEN amount ELSE 0 END), 0)::float  AS total_withdrawn,
        COALESCE(SUM(CASE WHEN type = 'withdraw' AND status = 'pending' THEN amount ELSE 0 END), 0)::float  AS pending_amount,
        COUNT(CASE WHEN type = 'withdraw' AND status = 'pending'  THEN 1 END)::int                          AS pending_count,
        COUNT(CASE WHEN type = 'add'      AND status = 'success'  THEN 1 END)::int                          AS total_add_count,
        COALESCE(SUM(CASE WHEN type = 'add' AND status = 'success'
                          AND created_at >= CURRENT_DATE THEN amount ELSE 0 END), 0)::float                 AS today_revenue,
        COALESCE(SUM(CASE WHEN type = 'bet_win'    AND status = 'success' THEN amount ELSE 0 END), 0)::float AS total_bet_payouts,
        COALESCE(SUM(CASE WHEN type = 'bet_deduct' AND status = 'success' THEN amount ELSE 0 END), 0)::float AS total_bet_escrowed,
        COUNT(CASE WHEN type = 'bet_win' AND status = 'success' THEN 1 END)::int AS total_bet_games,
        COALESCE(SUM(CASE WHEN type = 'bet_deduct' AND status = 'success'
                          AND created_at >= CURRENT_DATE THEN amount ELSE 0 END), 0)::float AS today_bet_volume
      FROM payment_transactions
    `);
    return result.rows[0];
  } catch (err) {
    console.error('[Payment Admin Error] getPaymentStats failed:', err);
    throw { status: 500, message: 'Failed to get payment stats', error: err.message };
  }
};

// ─── Bet helpers ──────────────────────────────────────────────────────────────

const getUserBalance = async (userId) => {
  const result = await query(
    `SELECT COALESCE(coins, 0)::float AS balance FROM users WHERE id = $1`,
    [userId]
  );
  return parseFloat(result.rows[0]?.balance) || 0;
};

const escrowBets = async (roomId, matchId) => {
  const roomResult = await query('SELECT bet_amount FROM rooms WHERE id = $1', [roomId]);
  if (!roomResult.rows.length) throw { status: 404, message: 'Room not found' };

  const betAmount = parseFloat(roomResult.rows[0].bet_amount) || 0;
  if (betAmount <= 0) return { betAmount: 0, totalPot: 0, players: [] };

  const playersResult = await query(
    `SELECT rp.seat, rp.user_id
     FROM room_players rp
     WHERE rp.room_id = $1 AND rp.is_bot = FALSE`,
    [roomId]
  );
  const realPlayers = playersResult.rows;
  if (realPlayers.length < 2) return { betAmount: 0, totalPot: 0, players: [] };

  // Validate each player has enough balance to cover the bet
  for (const p of realPlayers) {
    const balance = await getUserBalance(p.user_id);
    if (balance < betAmount) throw { status: 400, message: `A player has insufficient balance for this bet (need ₹${betAmount})` };
  }

  const client = await getClient();
  try {
    await client.query('BEGIN');
    for (const p of realPlayers) {
      const coins = Math.floor(betAmount * COINS_PER_RUPEE);
      await client.query(
        `INSERT INTO payment_transactions (user_id, amount, coins, type, status, description, metadata)
         VALUES ($1, $2, $3, 'bet_deduct', 'success', 'Bet escrowed for game', $4)`,
        [p.user_id, betAmount, coins, JSON.stringify({ room_id: roomId, match_id: matchId })]
      );
      await client.query(
        `UPDATE users SET coins = GREATEST(coins - $1, 0) WHERE id = $2`,
        [coins, p.user_id]
      );
      await client.query(
        `INSERT INTO game_bets (room_id, match_id, user_id, seat, amount, status)
         VALUES ($1, $2, $3, $4, $5, 'escrowed')
         ON CONFLICT (room_id, user_id) DO UPDATE SET match_id=$2, amount=$5, status='escrowed', settled_at=NULL`,
        [roomId, matchId, p.user_id, p.seat, betAmount]
      );
    }
    await client.query('COMMIT');
    return { betAmount, totalPot: betAmount * realPlayers.length, players: realPlayers };
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
};

const payoutWinner = async (roomId, matchId, winnerUserId) => {
  const roomResult = await query('SELECT bet_amount FROM rooms WHERE id = $1', [roomId]);
  if (!roomResult.rows.length) return null;

  const betAmount = parseFloat(roomResult.rows[0].bet_amount) || 0;
  if (betAmount <= 0) return null;

  const betsResult = await query(
    `SELECT user_id, amount, seat FROM game_bets
     WHERE room_id = $1 AND status = 'escrowed'`,
    [roomId]
  );
  if (!betsResult.rows.length) return null;

  const totalPot = betsResult.rows.reduce((s, b) => s + parseFloat(b.amount), 0);
  const winCoins = Math.floor(totalPot * COINS_PER_RUPEE);

  const client = await getClient();
  try {
    await client.query('BEGIN');

    // Credit winner
    await client.query(
      `INSERT INTO payment_transactions (user_id, amount, coins, type, status, description, metadata)
       VALUES ($1, $2, $3, 'bet_win', 'success', 'Game bet winnings', $4)`,
      [winnerUserId, totalPot, winCoins, JSON.stringify({ room_id: roomId, match_id: matchId })]
    );
    await client.query(
      `UPDATE users SET coins = coins + $1 WHERE id = $2`,
      [winCoins, winnerUserId]
    );

    // Mark all bets settled
    for (const bet of betsResult.rows) {
      const isWinner = bet.user_id === winnerUserId;
      await client.query(
        `UPDATE game_bets SET status=$1, settled_at=NOW()
         WHERE room_id=$2 AND user_id=$3`,
        [isWinner ? 'won' : 'lost', roomId, bet.user_id]
      );
    }

    await client.query('COMMIT');
    return { betAmount, totalPot, winnerUserId, playerCount: betsResult.rows.length };
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
};

const refundBets = async (roomId) => {
  const betsResult = await query(
    `SELECT user_id, amount FROM game_bets WHERE room_id=$1 AND status='escrowed'`,
    [roomId]
  );
  if (!betsResult.rows.length) return;

  const client = await getClient();
  try {
    await client.query('BEGIN');
    for (const bet of betsResult.rows) {
      const betAmount = parseFloat(bet.amount);
      const coins = Math.floor(betAmount * COINS_PER_RUPEE);
      await client.query(
        `INSERT INTO payment_transactions (user_id, amount, coins, type, status, description, metadata)
         VALUES ($1, $2, $3, 'bet_win', 'success', 'Bet refunded (game cancelled)', $4)`,
        [bet.user_id, betAmount, coins, JSON.stringify({ room_id: roomId, refund: true })]
      );
      await client.query(
        `UPDATE users SET coins = coins + $1 WHERE id = $2`,
        [coins, bet.user_id]
      );
      await client.query(
        `UPDATE game_bets SET status='refunded', settled_at=NOW()
         WHERE room_id=$1 AND user_id=$2`,
        [roomId, bet.user_id]
      );
    }
    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
};

module.exports = {
  createPaymentOrder,
  verifyPayment,
  getWalletBalance,
  getUserBalance,
  getTransactionHistory,
  getWithdrawalRequests,
  requestWithdrawal,
  getAllUserTransactions,
  getAllWithdrawalRequests,
  approveWithdrawal,
  rejectWithdrawal,
  getPaymentStats,
  escrowBets,
  payoutWinner,
  refundBets,
  getAllGameBets,
  COINS_PER_RUPEE,
};
