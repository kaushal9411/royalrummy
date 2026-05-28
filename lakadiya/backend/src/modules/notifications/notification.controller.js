const { pool } = require('../../config/database');
const { sendOtpNotification, sendNotification } = require('./notification.service');
const logger = require('../../config/logger');

/**
 * Store device token for a user
 * POST /api/notifications/device-token
 */
async function storeDeviceToken(req, res) {
  try {
    const { fcmToken, deviceType } = req.body;
    const userId = req.user.id;

    if (!fcmToken) {
      return res.status(400).json({ error: 'FCM token is required' });
    }

    // Check if token already exists for user
    const existing = await pool.query(
      'SELECT id FROM device_tokens WHERE fcm_token = $1',
      [fcmToken]
    );

    if (existing.rows.length > 0) {
      // Update last_used
      await pool.query(
        'UPDATE device_tokens SET last_used = NOW() WHERE fcm_token = $1',
        [fcmToken]
      );
    } else {
      // Insert new token
      await pool.query(
        `INSERT INTO device_tokens (user_id, fcm_token, device_type, is_active) 
         VALUES ($1, $2, $3, true)`,
        [userId, fcmToken, deviceType || 'android']
      );
    }

    logger.info(`Device token stored for user ${userId}`);
    res.json({
      success: true,
      message: 'Device token stored successfully',
      fcmToken: fcmToken.substring(0, 20) + '...',
    });
  } catch (error) {
    logger.error('Error storing device token:', error);
    res.status(500).json({ error: error.message });
  }
}

/**
 * Send test OTP notification (for development)
 * POST /api/notifications/send-test-otp
 */
async function sendTestOtp(req, res) {
  try {
    const userId = req.user.id;
    const { otp } = req.body;

    if (!otp || otp.length !== 6) {
      return res.status(400).json({ error: 'OTP must be 6 digits' });
    }

    const result = await sendOtpNotification(userId, otp);

    if (result.success) {
      res.json({
        success: true,
        message: 'OTP notification sent',
        messageId: result.messageId,
      });
    } else {
      res.status(400).json({
        success: false,
        error: result.reason,
      });
    }
  } catch (error) {
    logger.error('Error sending test OTP:', error);
    res.status(500).json({ error: error.message });
  }
}

/**
 * Get notification logs for user
 * GET /api/notifications/logs
 */
async function getNotificationLogs(req, res) {
  try {
    const userId = req.user.id;
    const limit = Math.min(parseInt(req.query.limit) || 20, 100);

    const result = await pool.query(
      `SELECT id, title, body, status, error_msg, sent_at 
       FROM notification_logs 
       WHERE user_id = $1 
       ORDER BY sent_at DESC 
       LIMIT $2`,
      [userId, limit]
    );

    res.json({
      success: true,
      logs: result.rows,
      count: result.rows.length,
    });
  } catch (error) {
    logger.error('Error fetching notification logs:', error);
    res.status(500).json({ error: error.message });
  }
}

/**
 * Broadcast test notification to all active devices
 * POST /api/notifications/broadcast-test
 */
async function broadcastTestNotification(req, res) {
  try {
    const { title, body, message } = req.body;
    const notifTitle = title || 'Test Notification';
    const notifBody = body || message || 'This is a test notification from the server';

    // Fetch all active device tokens
    const result = await pool.query(
      `SELECT DISTINCT user_id, fcm_token FROM device_tokens WHERE is_active = true`
    );

    const tokens = result.rows;
    logger.info(`Found ${tokens.length} active devices to notify`);

    if (tokens.length === 0) {
      return res.json({
        success: false,
        message: 'No active devices found',
        sent: 0,
        failed: 0,
      });
    }

    let sent = 0;
    let failed = 0;
    const errors = [];

    // Send notification to each device
    for (const { user_id, fcm_token } of tokens) {
      try {
        const notifResult = await sendNotification(
          user_id,
          notifTitle,
          notifBody,
          { type: 'broadcast_test' }
        );

        if (notifResult.success) {
          sent++;
        } else {
          failed++;
          errors.push({ token: fcm_token.substring(0, 20) + '...', error: notifResult.reason });
        }
      } catch (err) {
        failed++;
        errors.push({ token: fcm_token.substring(0, 20) + '...', error: err.message });
      }
    }

    logger.info(`Broadcast complete: ${sent} sent, ${failed} failed`);

    res.json({
      success: true,
      message: `Notification sent to all devices`,
      title: notifTitle,
      body: notifBody,
      totalDevices: tokens.length,
      sent,
      failed,
      errors: errors.length > 0 ? errors : undefined,
    });
  } catch (error) {
    logger.error('Error broadcasting notification:', error);
    res.status(500).json({ error: error.message });
  }
}

module.exports = {
  storeDeviceToken,
  sendTestOtp,
  getNotificationLogs,
  broadcastTestNotification,
};
