const admin  = require('firebase-admin');
const { query } = require('../../config/database');
const logger = require('../../config/logger');
const { sendOtpViaFcm, ensureFirebase } = require('../../config/firebase');

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

query(`
  CREATE TABLE IF NOT EXISTS broadcast_logs (
    id         SERIAL PRIMARY KEY,
    type       VARCHAR(50)  DEFAULT 'GENERAL',
    title      VARCHAR(255) NOT NULL,
    body       TEXT         NOT NULL,
    sent_to    INTEGER      DEFAULT 0,
    created_at TIMESTAMPTZ  DEFAULT NOW()
  )
`).catch(() => {});

// Per-user notification opt-out preferences
// otp is always allowed — not stored here
query(`
  CREATE TABLE IF NOT EXISTS notification_preferences (
    user_id    UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    game       BOOLEAN DEFAULT TRUE,
    wallet     BOOLEAN DEFAULT TRUE,
    promo      BOOLEAN DEFAULT TRUE,
    updated_at TIMESTAMPTZ DEFAULT NOW()
  )
`).catch(() => {});

// ── Notification preference helpers ──────────────────────────────────────────

// Returns user's stored prefs or safe defaults (all enabled)
const getUserNotifPrefs = async (userId) => {
  const { rows } = await query(
    'SELECT game, wallet, promo FROM notification_preferences WHERE user_id = $1',
    [userId]
  );
  if (!rows.length) return { game: true, wallet: true, promo: true };
  return rows[0];
};

const setUserNotifPrefs = async (userId, { game, wallet, promo }) => {
  await query(
    `INSERT INTO notification_preferences (user_id, game, wallet, promo, updated_at)
     VALUES ($1, $2, $3, $4, NOW())
     ON CONFLICT (user_id) DO UPDATE
       SET game=$2, wallet=$3, promo=$4, updated_at=NOW()`,
    [userId, game ?? true, wallet ?? true, promo ?? true]
  );
};

// Map channel ID → preference key  (otp_channel is always allowed)
const _channelAllowed = (prefs, channelId) => {
  if (!channelId || channelId === 'otp_channel') return true;
  if (channelId === 'room_channel')   return prefs.game   !== false;
  if (channelId === 'wallet_channel') return prefs.wallet !== false;
  return prefs.promo !== false; // default_channel, general
};

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
  // Check user's notification preferences before sending
  try {
    const prefs = await getUserNotifPrefs(userId);
    if (!_channelAllowed(prefs, channelId)) {
      logger.info(`[FCM] Skipped — user ${userId} disabled channel "${channelId}"`);
      return { success: false, reason: 'User disabled this notification type' };
    }
  } catch (_) { /* if prefs lookup fails, allow the notification through */ }

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
  if (!ensureFirebase()) return;

  // Only send to users who have NOT disabled game notifications
  const result = await query(
    `SELECT DISTINCT ON (dt.user_id) dt.fcm_token
     FROM device_tokens dt
     LEFT JOIN notification_preferences np ON np.user_id = dt.user_id
     WHERE dt.is_active = TRUE
       AND (np.game IS NULL OR np.game = TRUE)
     ORDER BY dt.user_id, dt.last_used DESC`
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

// ── Admin broadcast to ALL active devices ─────────────────────────────────────
const sendAdminBroadcast = async (title, body, type = 'GENERAL', data = {}) => {
  if (!ensureFirebase()) throw { status: 503, message: 'Firebase not configured — check FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, FIREBASE_PRIVATE_KEY in .env' };

  const result = await query(
    `SELECT DISTINCT ON (user_id) fcm_token
     FROM device_tokens
     WHERE is_active = TRUE
     ORDER BY user_id, last_used DESC`
  );

  const allTokens = result.rows.map((r) => r.fcm_token);
  if (!allTokens.length) {
    await query(
      `INSERT INTO broadcast_logs (type, title, body, sent_to) VALUES ($1, $2, $3, 0)`,
      [type, title, body]
    ).catch(() => {});
    return { sent: 0 };
  }

  const message = {
    data: {
      ...Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])),
      type,
      title,
      body,
      timestamp: new Date().toISOString(),
    },
    notification: { title, body },
    android: {
      priority: 'high',
      notification: { title, body, channelId: 'default_channel', icon: '@mipmap/ic_launcher' },
    },
    apns: { payload: { aps: { alert: { title, body }, sound: 'default' } } },
  };

  const BATCH = 500;
  let sent = 0;
  for (let i = 0; i < allTokens.length; i += BATCH) {
    const tokens = allTokens.slice(i, i + BATCH);
    try {
      const res = await admin.messaging().sendEachForMulticast({ ...message, tokens });
      sent += res.successCount;
    } catch (err) {
      logger.error('[FCM] Admin broadcast batch failed:', err.message);
    }
  }

  await query(
    `INSERT INTO broadcast_logs (type, title, body, sent_to) VALUES ($1, $2, $3, $4)`,
    [type, title, body, sent]
  ).catch(() => {});

  logger.info(`[FCM] Admin broadcast: ${sent}/${allTokens.length} devices`);
  return { sent };
};

// ── Get broadcast history ─────────────────────────────────────────────────────
const getBroadcastHistory = async (limit = 50) => {
  const result = await query(
    `SELECT id, type, title, body, sent_to, created_at
     FROM broadcast_logs
     ORDER BY created_at DESC
     LIMIT $1`,
    [limit]
  );
  return result.rows;
};

module.exports = {
  storeDeviceToken,
  sendOtpNotification,
  sendNotification,
  sendNotificationToMultiple,
  sendOpenRoomNotification,
  sendAdminBroadcast,
  getBroadcastHistory,
  getUserNotifPrefs,
  setUserNotifPrefs,
};
