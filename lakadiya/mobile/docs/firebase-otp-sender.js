/**
 * Firebase Cloud Messaging - Send OTP Notification
 * Backend helper to send OTP via FCM to a specific device
 * 
 * Usage:
 * const admin = require('firebase-admin');
 * const serviceAccount = require('./path-to-your-firebase-adminsdk-key.json');
 * 
 * admin.initializeApp({
 *   credential: admin.credential.cert(serviceAccount),
 * });
 * 
 * sendOtpNotification('device-token-here', '123456');
 */

const admin = require('firebase-admin');

async function sendOtpNotification(deviceToken, otp) {
  const message = {
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
      ttl: 3600, // 1 hour
      priority: 'high',
      notification: {
        title: 'Your OTP Code',
        body: `Your verification code is: ${otp}`,
        icon: 'ic_launcher',
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

  try {
    const response = await admin.messaging().send(message, {
      tokens: [deviceToken],
    });
    console.log('OTP notification sent successfully:', response);
    return { success: true, messageId: response };
  } catch (error) {
    console.error('Error sending OTP notification:', error);
    throw error;
  }
}

module.exports = { sendOtpNotification };
