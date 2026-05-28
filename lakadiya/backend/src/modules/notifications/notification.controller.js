const { query } = require('../../config/database');
const { storeDeviceToken, sendNotification } = require('./notification.service');
const { sendOtpViaFcm } = require('../../config/firebase');
const logger = require('../../config/logger');

// POST /api/notifications/device-token
async function storeDeviceTokenHandler(req, res) {
  try {
    const { fcmToken, deviceType } = req.body;
    if (!fcmToken) return res.status(400).json({ error: 'FCM token is required' });

    await storeDeviceToken(req.user.id, fcmToken, deviceType || 'android');
    res.json({ success: true, message: 'Device token stored' });
  } catch (err) {
    logger.error('[FCM] Store token error:', err.message);
    res.status(500).json({ error: err.message });
  }
}

// POST /api/notifications/send-test-otp  (dev only — sends OTP notification to logged-in user's device)
async function sendTestOtp(req, res) {
  try {
    const { otp = '123456' } = req.body;
    const result = await query(
      `SELECT fcm_token FROM device_tokens WHERE user_id = $1 AND is_active = TRUE ORDER BY last_used DESC LIMIT 1`,
      [req.user.id]
    );
    if (!result.rows.length) return res.status(404).json({ error: 'No device token found for this user' });

    await sendOtpViaFcm(result.rows[0].fcm_token, String(otp));
    res.json({ success: true, message: 'Test OTP notification sent', otp });
  } catch (err) {
    logger.error('[FCM] Test OTP error:', err.message);
    res.status(500).json({ error: err.message });
  }
}

// GET /api/notifications/logs
async function getNotificationLogs(req, res) {
  try {
    const limit = Math.min(parseInt(req.query.limit) || 20, 100);
    const result = await query(
      `SELECT id, title, body, status, error_msg, created_at
       FROM notification_logs WHERE user_id = $1
       ORDER BY created_at DESC LIMIT $2`,
      [req.user.id, limit]
    );
    res.json({ success: true, logs: result.rows });
  } catch (err) {
    logger.error('[FCM] Logs error:', err.message);
    res.status(500).json({ error: err.message });
  }
}

// POST /api/notifications/broadcast-test  (admin utility)
async function broadcastTestNotification(req, res) {
  try {
    const { title = 'Test', body = 'This is a test notification' } = req.body;
    const devices = await query(`SELECT DISTINCT user_id FROM device_tokens WHERE is_active = TRUE`);
    let sent = 0, failed = 0;
    for (const { user_id } of devices.rows) {
      const r = await sendNotification(user_id, title, body, { type: 'broadcast_test' });
      r.success ? sent++ : failed++;
    }
    res.json({ success: true, total: devices.rows.length, sent, failed });
  } catch (err) {
    logger.error('[FCM] Broadcast error:', err.message);
    res.status(500).json({ error: err.message });
  }
}

module.exports = {
  storeDeviceToken: storeDeviceTokenHandler,
  sendTestOtp,
  getNotificationLogs,
  broadcastTestNotification,
};
