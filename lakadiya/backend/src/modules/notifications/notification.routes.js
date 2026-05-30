const router = require('express').Router();
const { authenticate } = require('../../middleware/auth.middleware');
const controller = require('./notification.controller');
const { getUserNotifPrefs, setUserNotifPrefs } = require('./notification.service');

// Store device token (called from mobile after login)
router.post('/device-token', authenticate, controller.storeDeviceToken);

// Send test OTP (for development)
router.post('/send-test-otp', authenticate, controller.sendTestOtp);

// Get notification logs for user
router.get('/logs', authenticate, controller.getNotificationLogs);

// Send test notification to all active devices (admin only)
router.post('/broadcast-test', authenticate, controller.broadcastTestNotification);

// ── Per-user notification preferences ────────────────────────────────────────
router.get('/preferences', authenticate, async (req, res, next) => {
  try {
    const prefs = await getUserNotifPrefs(req.user.id);
    res.json(prefs);
  } catch (e) { next(e); }
});

router.patch('/preferences', authenticate, async (req, res, next) => {
  try {
    const { game, wallet, promo } = req.body;
    await setUserNotifPrefs(req.user.id, {
      game:   game   !== undefined ? Boolean(game)   : undefined,
      wallet: wallet !== undefined ? Boolean(wallet) : undefined,
      promo:  promo  !== undefined ? Boolean(promo)  : undefined,
    });
    const updated = await getUserNotifPrefs(req.user.id);
    res.json(updated);
  } catch (e) { next(e); }
});

module.exports = router;
