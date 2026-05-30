const paymentService = require('./payment.service');
const { getIO } = require('../../socket/socket.manager');
const { sendNotification } = require('../notifications/notification.service');
const { sendWithdrawalRequestEmail, sendWithdrawalStatusEmail, sendPaymentReceiptEmail } = require('../email/email.service');
const { query } = require('../../config/database');

const emitBalanceUpdated = (userId) => {
  try { getIO().to(`user_${userId}`).emit('balance_updated'); } catch (_) {}
};

const initiateAddMoney = async (req, res, next) => {
  try {
    const { amount } = req.body;
    console.log(`[Payment Controller] Initiate - User: ${req.user?.id}, Amount: ${amount}`);
    
    if (!amount) throw { status: 400, message: 'Amount is required' };

    const orderDetails = await paymentService.createPaymentOrder(req.user.id, amount, 'add');
    console.log(`[Payment Controller] Order created successfully`);
    res.json(orderDetails);
  } catch (err) {
    console.error(`[Payment Controller Error] Initiate failed:`, err);
    next(err);
  }
};

const verifyPayment = async (req, res, next) => {
  try {
    const { paymentId, orderId, signature } = req.body;
    console.log(`[Payment Controller] Verify - User: ${req.user?.id}, PaymentID: ${paymentId}`);
    
    if (!paymentId || !orderId || !signature) {
      throw { status: 400, message: 'Missing payment verification details' };
    }

    const result = await paymentService.verifyPayment(req.user.id, paymentId, orderId, signature);
    console.log(`[Payment Controller] Payment verified successfully`);
    emitBalanceUpdated(req.user.id);
    res.json(result);
    sendNotification(
      req.user.id,
      '💰 Money Added Successfully!',
      `₹${result.amount} has been added to your Lakadiya wallet. Happy playing!`,
      { type: 'WALLET_ADD', amount: String(result.amount), coins: String(result.coins) },
      'wallet_channel'
    ).catch(() => {});
    // Send payment receipt email if user has an email address
    query('SELECT email, username FROM users WHERE id = $1', [req.user.id])
      .then(({ rows }) => {
        if (rows[0]?.email) {
          sendPaymentReceiptEmail({
            to: rows[0].email,
            username: rows[0].username,
            amount: result.amount,
            coins: result.coins,
            txnId: result.transactionId,
            paymentId: result.paymentId,
            paidAt: new Date().toLocaleString('en-IN', { timeZone: 'Asia/Kolkata' }),
          }).catch(() => {});
        }
      }).catch(() => {});
  } catch (err) {
    console.error(`[Payment Controller Error] Verify failed:`, err);
    next(err);
  }
};

const getWalletBalance = async (req, res, next) => {
  try {
    console.log(`[Payment Controller] Get balance - User: ${req.user?.id}`);
    const balance = await paymentService.getWalletBalance(req.user.id);
    console.log(`[Payment Controller] Balance response:`, balance);
    res.json(balance);
  } catch (err) {
    console.error(`[Payment Controller Error] Get balance failed:`, err);
    next(err);
  }
};

const getTransactionHistory = async (req, res, next) => {
  try {
    const { limit = 20, offset = 0 } = req.query;
    console.log(`[Payment Controller] Get history - User: ${req.user?.id}, Limit: ${limit}, Offset: ${offset}`);
    const transactions = await paymentService.getTransactionHistory(
      req.user.id,
      Number(limit),
      Number(offset)
    );
    res.json(transactions);
  } catch (err) {
    console.error(`[Payment Controller Error] Get history failed:`, err);
    next(err);
  }
};

const getWithdrawalRequests = async (req, res, next) => {
  try {
    const { limit = 20, offset = 0 } = req.query;
    console.log(`[Payment Controller] Get withdrawals - User: ${req.user?.id}, Limit: ${limit}, Offset: ${offset}`);
    const withdrawals = await paymentService.getWithdrawalRequests(
      req.user.id,
      Number(limit),
      Number(offset)
    );
    console.log(`[Payment Controller] Found ${withdrawals.length} withdrawal requests`);
    res.json(withdrawals);
  } catch (err) {
    console.error(`[Payment Controller Error] Get withdrawals failed:`, err);
    next(err);
  }
};

const requestWithdrawal = async (req, res, next) => {
  try {
    const { amount } = req.body;
    console.log(`[Payment Controller] Withdraw request - User: ${req.user?.id}, Amount: ${amount}`);
    
    if (!amount) throw { status: 400, message: 'Amount is required' };

    const withdrawal = await paymentService.requestWithdrawal(req.user.id, amount);
    console.log(`[Payment Controller] Withdrawal request submitted`);
    res.json({ message: 'Withdrawal request submitted', data: withdrawal });
    sendNotification(
      req.user.id,
      '📤 Withdrawal Request Submitted',
      `Your request for ₹${amount} is under review. We'll process it within 24 hours.`,
      { type: 'WITHDRAWAL_REQUESTED', amount: String(amount) },
      'wallet_channel'
    ).catch(() => {});
    // Send confirmation email
    query('SELECT email, username FROM users WHERE id = $1', [req.user.id])
      .then(({ rows }) => {
        if (rows[0]?.email) {
          sendWithdrawalRequestEmail({
            to: rows[0].email,
            username: rows[0].username,
            amount,
            txnId: withdrawal.id,
            requestedAt: new Date().toLocaleString('en-IN', { timeZone: 'Asia/Kolkata' }),
          }).catch(() => {});
        }
      }).catch(() => {});
  } catch (err) {
    console.error(`[Payment Controller Error] Withdraw failed:`, err);
    next(err);
  }
};

// Admin endpoints
const getAllUserTransactions = async (req, res, next) => {
  try {
    const { userId, type, limit = 50, offset = 0 } = req.query;
    console.log(`[Payment Admin] Get all transactions - UserID: ${userId}, Type: ${type}`);
    
    const transactions = await paymentService.getAllUserTransactions(
      userId,
      type,
      Number(limit),
      Number(offset)
    );
    res.json(transactions);
  } catch (err) {
    console.error(`[Payment Admin Error] Get transactions failed:`, err);
    next(err);
  }
};

const getAllWithdrawalRequests = async (req, res, next) => {
  try {
    const { status, limit = 50, offset = 0 } = req.query;
    console.log(`[Payment Admin] Get all withdrawals - Status: ${status}`);
    
    const withdrawals = await paymentService.getAllWithdrawalRequests(
      status,
      Number(limit),
      Number(offset)
    );
    console.log(`[Payment Admin] Found ${withdrawals.length} withdrawal requests`);
    res.json(withdrawals);
  } catch (err) {
    console.error(`[Payment Admin Error] Get withdrawals failed:`, err);
    next(err);
  }
};

const approveWithdrawal = async (req, res, next) => {
  try {
    const { transactionId } = req.params;
    console.log(`[Payment Admin] Approving withdrawal - Transaction: ${transactionId}`);
    
    const result = await paymentService.approveWithdrawal(transactionId);
    emitBalanceUpdated(result.user_id);
    res.json({ message: 'Withdrawal approved', data: result });
    sendNotification(
      result.user_id,
      '✅ Withdrawal Approved!',
      `Your withdrawal of ₹${result.amount} has been approved. The amount will be transferred to your account shortly.`,
      { type: 'WITHDRAWAL_APPROVED', amount: String(result.amount) },
      'wallet_channel'
    ).catch(() => {});
    query('SELECT email, username FROM users WHERE id = $1', [result.user_id])
      .then(({ rows }) => {
        if (rows[0]?.email) {
          sendWithdrawalStatusEmail({
            to: rows[0].email,
            username: rows[0].username,
            amount: result.amount,
            txnId: result.id,
            status: 'success',
          }).catch(() => {});
        }
      }).catch(() => {});
  } catch (err) {
    console.error(`[Payment Admin Error] Approve withdrawal failed:`, err);
    next(err);
  }
};

const rejectWithdrawal = async (req, res, next) => {
  try {
    const { transactionId } = req.params;
    const { reason } = req.body;
    console.log(`[Payment Admin] Rejecting withdrawal - Transaction: ${transactionId}`);
    
    const result = await paymentService.rejectWithdrawal(transactionId, reason);
    emitBalanceUpdated(result.user_id);
    res.json({ message: 'Withdrawal rejected', data: result });
    sendNotification(
      result.user_id,
      '❌ Withdrawal Request Rejected',
      `Your withdrawal of ₹${result.amount} was not approved.${reason ? ` Reason: ${reason}.` : ''} Your coins have been refunded.`,
      { type: 'WITHDRAWAL_REJECTED', amount: String(result.amount), reason: reason || '' },
      'wallet_channel'
    ).catch(() => {});
    query('SELECT email, username FROM users WHERE id = $1', [result.user_id])
      .then(({ rows }) => {
        if (rows[0]?.email) {
          sendWithdrawalStatusEmail({
            to: rows[0].email,
            username: rows[0].username,
            amount: result.amount,
            txnId: result.id,
            status: 'rejected',
            remark: reason,
          }).catch(() => {});
        }
      }).catch(() => {});
  } catch (err) {
    console.error(`[Payment Admin Error] Reject withdrawal failed:`, err);
    next(err);
  }
};

const getPaymentStats = async (req, res, next) => {
  try {
    const stats = await paymentService.getPaymentStats();
    res.json(stats);
  } catch (err) {
    next(err);
  }
};

const getGameBets = async (req, res, next) => {
  try {
    const { status, limit = 50, offset = 0 } = req.query;
    const bets = await paymentService.getAllGameBets(status, Number(limit), Number(offset));
    res.json(bets);
  } catch (err) {
    next(err);
  }
};

module.exports = {
  initiateAddMoney,
  verifyPayment,
  getWalletBalance,
  getTransactionHistory,
  getWithdrawalRequests,
  requestWithdrawal,
  getAllUserTransactions,
  getAllWithdrawalRequests,
  approveWithdrawal,
  rejectWithdrawal,
  getPaymentStats,
  getGameBets,
};
