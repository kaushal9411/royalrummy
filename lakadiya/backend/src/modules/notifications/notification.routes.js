const router = require('express').Router();
const { authenticate } = require('../../middleware/auth.middleware');
const controller = require('./notification.controller');

// Store device token (called from mobile after login)
router.post('/device-token', authenticate, controller.storeDeviceToken);

// Send test OTP (for development)
router.post('/send-test-otp', authenticate, controller.sendTestOtp);

// Get notification logs for user
router.get('/logs', authenticate, controller.getNotificationLogs);

// Send test notification to all active devices (admin only)
router.post('/broadcast-test', authenticate, controller.broadcastTestNotification);

module.exports = router;
