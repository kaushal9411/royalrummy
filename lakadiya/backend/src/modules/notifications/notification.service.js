const admin  = require('firebase-admin');
const { query } = require('../../config/database');
const logger = require('../../config/logger');
const { sendOtpViaFcm } = require('../../config/firebase');

// Create required tables on startup
query(`
  CREATE TABLE IF NOT EXISTS device_tokens (
    id          SERIAL PRIMARY KEY,
    user_id     UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    fcm_token   TEXT         NOT NULL,
    device_type VARCHAR(20)  DEFAULT 'android',
    is_active   BOOLEAN      DEFAULT TRUE,
    last_used   TIMESTAMPTZ  DEFAULT NOW(),
    created_at  TIMESTAMPTZ  DEFAULT NOW(),
    UNIQUE(user_id, fcm_token)
  )
`).catch(() => {});

query(`
  CREATE TABLE IF NOT EXISTS notification_logs (
    id         SERIAL PRIMARY KEY,
    user_id    UUID         REFERENCES users(id) ON DELETE SET NULL,
    fcm_token  TEXT,
    title      VARCHAR(255),
    body       TEXT,
    data       JSONB,
    status     VARCHAR(20)  DEFAULT 'sent',
    error_msg  TEXT,
    created_at TIMESTAMPTZ  DEFAULT NOW()
  )
`).catch(() => {});

// ── Store / refresh device FCM token ─────────────────────────────────────────
const storeDeviceToken = async (userId, fcmToken, deviceType = 'android') => {
  await query(
    `INSERT INTO device_tokens (user_id, fcm_token, device_type, is_active, last_used)
     VALUES ($1, $2, $3, TRUE, NOW())
     ON CONFLICT (user_id, fcm_token)
     DO UPDATE SET is_active = TRUE, last_used = NOW(), device_type = $3`,
    [userId, fcmToken, deviceType]
  );
  logger.info(`[FCM] Token stored for user ${userId}`);
};

// ── Send OTP notification (uses direct fcmToken from request) ─────────────────
const sendOtpNotification = async (fcmToken, otp) => {
  return sendOtpViaFcm(fcmToken, otp);
};

// ── Send generic notification to a user (looks up their token from DB) ────────
const sendNotification = async (userId, title, body, data = {}, channelId = 'default_channel') => {
  const messaging = admin.messaging();

  const result = await query(
    `SELECT fcm_token FROM device_tokens
     WHERE user_id = $1 AND is_active = TRUE
     ORDER BY last_used DESC LIMIT 1`,
    [userId]
  );

  if (!result.rows.length) {
    logger.warn(`[FCM] No active token for user ${userId}`);
    return { success: false, reason: 'No device token found' };
  }

  const { fcm_token } = result.rows[0];

  const message = {
    token: fcm_token,
    notification: { title, body },
    // title + body forwarded in data so foreground handler can read them
    data: {
      ...Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])),
      title,
      body,
      timestamp: new Date().toISOString(),
    },
    android: {
      priority: 'high',
      notification: { title, body, icon: '@mipmap/ic_launcher', channelId },
    },
    apns: { payload: { aps: { alert: { title, body }, sound: 'default' } } },
  };

  try {
    const messageId = await messaging.send(message);
    await query(
      `INSERT INTO notification_logs (user_id, fcm_token, title, body, data, status)
       VALUES ($1, $2, $3, $4, $5, 'sent')`,
      [userId, fcm_token, title, body, JSON.stringify(data)]
    ).catch(() => {});
    logger.info(`[FCM] Notification sent to user ${userId}: ${messageId}`);
    return { success: true, messageId };
  } catch (err) {
    logger.error(`[FCM] Send failed for user ${userId}:`, err.message);
    await query(
      `INSERT INTO notification_logs (user_id, title, body, status, error_msg)
       VALUES ($1, $2, $3, 'failed', $4)`,
      [userId, title, body, err.message]
    ).catch(() => {});
    return { success: false, reason: err.message };
  }
};

// ── Broadcast to multiple users ───────────────────────────────────────────────
const sendNotificationToMultiple = async (userIds, title, body, data = {}) => {
  let sent = 0, failed = 0;
  for (const userId of userIds) {
    const r = await sendNotification(userId, title, body, data);
    r.success ? sent++ : failed++;
  }
  return { success: true, sent, failed };
};

// ── Notify ALL users about a new open bet room ────────────────────────────────
const sendOpenRoomNotification = async (roomCode, betAmount, hostName = 'A player') => {
  if (!admin.apps.length) return;

  const result = await query(
    `SELECT DISTINCT ON (user_id) fcm_token
     FROM device_tokens
     WHERE is_active = TRUE
     ORDER BY user_id, last_used DESC`
  );
  if (!result.rows.length) return;

  const allTokens = result.rows.map((r) => r.fcm_token);
  const title = '🎮 New Bet Room – Join Now!';
  const body  = `Code: ${roomCode}  •  ₹${betAmount} Bet — Fill up fast!`;

  const baseMessage = {
    data: {
      type:       'NEW_ROOM',
      roomCode:   String(roomCode),
      betAmount:  String(betAmount),
      hostName:   String(hostName),
      title,
      body,
      bigText:    `${hostName} just opened a ₹${betAmount} bet room!\n\n  Room Code:  ${roomCode}\n  Bet Amount: ₹${betAmount}\n\nJoin before it fills up!`,
    },
    notification: { title, body },
    android: {
      priority: 'high',
      notification: {
        title,
        body: `${hostName} opened a ₹${betAmount} room — Code: ${roomCode}`,
        channelId: 'room_channel',
        icon:  '@mipmap/ic_launcher',
        color: '#FF6F00',
      },
    },
    apns: {
      payload: {
        aps: { alert: { title, body }, sound: 'default' },
      },
    },
  };

  // FCM multicast limit is 500 tokens per call
  const BATCH = 500;
  let sent = 0, failed = 0;
  for (let i = 0; i < allTokens.length; i += BATCH) {
    const tokens = allTokens.slice(i, i + BATCH);
    try {
      const res = await admin.messaging().sendEachForMulticast({ ...baseMessage, tokens });
      sent   += res.successCount;
      failed += res.failureCount;
    } catch (err) {
      logger.error('[FCM] Room notification batch failed:', err.message);
    }
  }
  logger.info(`[FCM] Room notification sent: ${sent} ok, ${failed} failed — room ${roomCode}`);
};

module.exports = {
  storeDeviceToken,
  sendOtpNotification,
  sendNotification,
  sendNotificationToMultiple,
  sendOpenRoomNotification,
};
