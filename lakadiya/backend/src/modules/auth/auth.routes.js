const router = require('express').Router();
const { body } = require('express-validator');
const controller = require('./auth.controller');

// Step 1: send OTP to mobile
// fcmToken is optional — used for Firebase notification delivery when Fast2SMS is not configured
router.post('/otp/send', [
  body('mobile').isMobilePhone().withMessage('Enter a valid mobile number'),
  body('fcmToken').optional().isString(),
], controller.requestOtp);

// Step 2: verify OTP → auto login or auto register (unified)
router.post('/otp/verify', [
  body('mobile').isMobilePhone(),
  body('otp').isLength({ min: 6, max: 6 }).isNumeric(),
], controller.verifyAndLogin);

// Guest: mobile only, no OTP — find-or-create
router.post('/guest', [
  body('mobile').isMobilePhone(),
], controller.guestLogin);

// Google OAuth
router.post('/google', [
  body('googleId').notEmpty(),
  body('email').isEmail(),
  body('name').notEmpty(),
], controller.googleAuth);

// Admin login
router.post('/admin/login', [
  body('email').isEmail().normalizeEmail(),
  body('password').notEmpty(),
], controller.adminLogin);

module.exports = router;
