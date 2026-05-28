const admin = require('firebase-admin');
const logger = require('./logger');

let _ready = false;

const _init = () => {
  if (_ready) return true;
  if (admin.apps.length) { _ready = true; return true; }

  const projectId   = process.env.FIREBASE_PROJECT_ID;
  const clientEmail = process.env.FIREBASE_CLIENT_EMAIL;
  const privateKey  = process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n');

  if (!projectId || !clientEmail || !privateKey ||
      projectId === 'your-firebase-project-id') {
    return false;
  }

  try {
    admin.initializeApp({
      credential: admin.credential.cert({ projectId, clientEmail, privateKey }),
    });
    _ready = true;
    logger.info('[Firebase] Admin SDK initialised');
    return true;
  } catch (err) {
    logger.error('[Firebase] Init failed:', err.message);
    return false;
  }
};

/**
 * Send a silent data-only notification to a device.
 * The Flutter app reads `data.otp` and auto-fills the OTP field.
 */
const sendOtpViaFcm = async (fcmToken, otp) => {
  if (!_init()) {
    throw { status: 503, message: 'Firebase not configured — set FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, FIREBASE_PRIVATE_KEY in .env' };
  }
  if (!fcmToken) {
    throw { status: 400, message: 'FCM token missing — cannot deliver OTP via notification' };
  }

  const message = {
    token: fcmToken,
    data: {
      type:  'OTP',
      otp:   String(otp),
      title: 'Lakadiya OTP',
      body:  `Your OTP is ${otp}. Valid for 10 minutes.`,
    },
    android: {
      priority: 'high',
      ttl: 600000, // 10 min in ms
    },
    apns: {
      headers: { 'apns-priority': '10' },
      payload: { aps: { 'content-available': 1 } },
    },
  };

  await admin.messaging().send(message);
  logger.info(`[Firebase] OTP notification sent (token: ...${fcmToken.slice(-6)})`);
};

module.exports = { sendOtpViaFcm };
