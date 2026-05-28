const admin = require('firebase-admin');
const { pool } = require('../../config/database');
const logger = require('../../config/logger');

/**
 * Initialize Firebase Admin SDK using environment variables
 */
function initFirebase() {
  if (admin.apps.length > 0) {
    return true;
  }

  const projectId = process.env.FIREBASE_PROJECT_ID;
  const clientEmail = process.env.FIREBASE_CLIENT_EMAIL;
  const privateKey = process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n');

  if (!projectId || !clientEmail || !privateKey) {
    logger.error('Firebase credentials missing in .env file');
    logger.error(`  FIREBASE_PROJECT_ID: ${projectId ? '✓' : '✗'}`);
    logger.error(`  FIREBASE_CLIENT_EMAIL: ${clientEmail ? '✓' : '✗'}`);
    logger.error(`  FIREBASE_PRIVATE_KEY: ${privateKey ? '✓' : '✗'}`);
    return false;
  }

  try {
    admin.initializeApp({
      credential: admin.credential.cert({
        projectId,
        clientEmail,
        privateKey,
      }),
    });
    logger.info('✓ Firebase Admin SDK initialized successfully');
    return true;
  } catch (err) {
    logger.error('✗ Firebase initialization failed:', err.message);
    return false;
  }
}

/**
 * Send OTP notification to user's device token
 */
async function sendOtpNotification(userId, otp) {
  if (!initFirebase()) {
    logger.warn('Firebase not initialized, skipping OTP notification');
    return { success: false, reason: 'Firebase not initialized' };
  }

  try {
    const result = await pool.query(
      'SELECT fcm_token FROM device_tokens WHERE user_id = $1 AND is_active = true ORDER BY last_used DESC LIMIT 1',
      [userId]
    );

    if (result.rows.length === 0) {
      logger.warn(`No active device token for user ${userId}`);
      return { success: false, reason: 'No device token found' };
    }

    const { fcm_token } = result.rows[0];
    const messaging = admin.messaging();

    const message = {
      token: fcm_token,
      notification: {
        title: 'Your OTP Code',
        body: `Your verification code is: ${otp}`,
      },
      data: {
        type: 'OTP',
        otp: otp,
        timestamp: new Date().toISOString(),
      },
      android: {
        ttl: 3600,
        priority: 'high',
        notification: {
          title: 'Your OTP Code',
          body: `OTP: ${otp}`,
          icon: '@mipmap/ic_launcher',
          color: '#4CAF50',
          sound: 'default',
          channelId: 'otp_channel',
          clickAction: 'FLUTTER_NOTIFICATION_CLICK',
        },
      },
      apns: {
        payload: {
          aps: {
            alert: {
              title: 'Your OTP Code',
              body: `Your verification code is: ${otp}`,
            },
            sound: 'default',
            badge: 1,
          },
        },
      },
    };

    const messageId = await messaging().send(message);

    // Log notification
    await pool.query(
      `INSERT INTO notification_logs (user_id, fcm_token, title, body, data, status) 
       VALUES ($1, $2, $3, $4, $5, 'sent')`,
      [userId, fcm_token, 'Your OTP Code', `OTP: ${otp}`, JSON.stringify({ type: 'OTP', otp })]
    );

    logger.info(`✓ OTP notification sent to user ${userId}: ${messageId}`);
    return { success: true, messageId };
  } catch (error) {
    logger.error(`✗ Failed to send OTP notification: ${error.message}`);
    
    // Log failure
    try {
      await pool.query(
        `INSERT INTO notification_logs (user_id, title, body, status, error_msg) 
         VALUES ($1, $2, $3, 'failed', $4)`,
        [userId, 'Your OTP Code', 'OTP notification', error.message]
      );
    } catch (logErr) {
      logger.error('Failed to log notification error:', logErr.message);
    }

    return { success: false, reason: error.message };
  }
}

/**
 * Send generic notification to user
 */
async function sendNotification(userId, title, body, data = {}) {
  if (!initFirebase()) {
    logger.warn('Firebase not initialized, skipping notification');
    return { success: false, reason: 'Firebase not initialized' };
  }

  try {
    const result = await pool.query(
      'SELECT fcm_token FROM device_tokens WHERE user_id = $1 AND is_active = true ORDER BY last_used DESC LIMIT 1',
      [userId]
    );

    if (result.rows.length === 0) {
      logger.warn(`No active device token for user ${userId}`);
      return { success: false, reason: 'No device token found' };
    }

    const { fcm_token } = result.rows[0];
    const messaging = admin.messaging();

    const message = {
      token: fcm_token,
      notification: { title, body },
      data: { ...data, timestamp: new Date().toISOString() },
      android: {
        priority: 'high',
        notification: {
          title,
          body,
          icon: '@mipmap/ic_launcher',
          channelId: 'default_channel',
        },
      },
      apns: {
        payload: {
          aps: {
            alert: { title, body },
            sound: 'default',
          },
        },
      },
    };

    const messageId = await messaging.send(message);

    // Log notification
    await pool.query(
      `INSERT INTO notification_logs (user_id, fcm_token, title, body, data, status) 
       VALUES ($1, $2, $3, $4, $5, 'sent')`,
      [userId, fcm_token, title, body, JSON.stringify(data)]
    );

    logger.info(`✓ Notification sent to user ${userId}: ${messageId}`);
    return { success: true, messageId };
  } catch (error) {
    logger.error(`✗ Failed to send notification: ${error.message}`);
    
    try {
      await pool.query(
        `INSERT INTO notification_logs (user_id, title, body, status, error_msg) 
         VALUES ($1, $2, $3, 'failed', $4)`,
        [userId, title, body, error.message]
      );
    } catch (logErr) {
      logger.error('Failed to log notification error:', logErr.message);
    }

    return { success: false, reason: error.message };
  }
}

/**
 * Send notification to multiple users
 */
async function sendNotificationToMultiple(userIds, title, body, data = {}) {
  if (!initFirebase()) {
    logger.error('Firebase not initialized');
    return { success: false, sent: 0, failed: 0, reason: 'Firebase not initialized' };
  }

  let sent = 0;
  let failed = 0;

  for (const userId of userIds) {
    const result = await sendNotification(userId, title, body, data);
    if (result.success) {
      sent++;
    } else {
      failed++;
    }
  }

  return { success: true, sent, failed };
}

module.exports = {
  initFirebase,
  sendOtpNotification,
  sendNotification,
  sendNotificationToMultiple,
};
