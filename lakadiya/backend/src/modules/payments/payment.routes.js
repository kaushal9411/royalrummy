const express = require('express');
const paymentController = require('./payment.controller');
const { authenticate, authenticateAdmin } = require('../../middleware/auth.middleware');

const router = express.Router();

// User routes (require auth)
router.use(authenticate);

// Initiate payment order
router.post('/initiate', paymentController.initiateAddMoney);

// Verify payment
router.post('/verify', paymentController.verifyPayment);

// Get wallet balance
router.get('/balance', paymentController.getWalletBalance);

// Get transaction history (add money only)
router.get('/transactions', paymentController.getTransactionHistory);

// Get withdrawal requests
router.get('/withdrawals', paymentController.getWithdrawalRequests);

// Request withdrawal
router.post('/withdraw', paymentController.requestWithdrawal);

// Admin routes (require admin auth)
router.get('/admin/stats',        authenticateAdmin, paymentController.getPaymentStats);
router.get('/admin/transactions', authenticateAdmin, paymentController.getAllUserTransactions);
router.get('/admin/withdrawals',  authenticateAdmin, paymentController.getAllWithdrawalRequests);
router.patch('/admin/withdrawals/:transactionId/approve', authenticateAdmin, paymentController.approveWithdrawal);
router.patch('/admin/withdrawals/:transactionId/reject',  authenticateAdmin, paymentController.rejectWithdrawal);

module.exports = router;
