const router = require('express').Router();
const { body } = require('express-validator');
const controller = require('./auth.controller');
const { otpSendLimiter, authLimiter } = require('../../middleware/rate-limit.middleware');

// Step 1: send OTP — strict limit to prevent SMS bombing
router.post('/otp/send', otpSendLimiter, [
  body('mobile').isMobilePhone().withMessage('Enter a valid mobile number'),
  body('fcmToken').optional().isString(),
], controller.requestOtp);

// Step 2: verify OTP — brute-force protection
router.post('/otp/verify', authLimiter, [
  body('mobile').isMobilePhone(),
  body('otp').isLength({ min: 6, max: 6 }).isNumeric(),
  body('fcmToken').optional().isString(),
], controller.verifyAndLogin);

// Guest login
router.post('/guest', authLimiter, [
  body('mobile').isMobilePhone(),
], controller.guestLogin);

// Google OAuth
router.post('/google', authLimiter, [
  body('googleId').notEmpty(),
  body('email').isEmail(),
  body('name').notEmpty(),
], controller.googleAuth);

// Admin login
router.post('/admin/login', authLimiter, [
  body('email').isEmail().normalizeEmail(),
  body('password').notEmpty(),
], controller.adminLogin);

module.exports = router;
