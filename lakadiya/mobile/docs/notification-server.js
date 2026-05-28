/**
 * Firebase OTP Notification Sender
 * Simple Express server to send test notifications
 * 
 * Setup:
 * 1. npm init -y
 * 2. npm install express cors firebase-admin dotenv
 * 3. Copy your firebase-adminsdk key to project root
 * 4. Create .env file with FIREBASE_KEY_PATH
 * 5. node server.js
 */

const express = require('express');
const cors = require('cors');
require('dotenv').config();
const admin = require('firebase-admin');

const app = express();
app.use(cors());
app.use(express.json());

// Initialize Firebase Admin SDK
const serviceAccount = require('./lakadiya-3e18a-firebase-adminsdk-fbsvc-0fe9480f2e.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: 'lakadiya-3e18a',
});

const messaging = admin.messaging();

/**
 * POST /send-otp
 * Send OTP notification to a device
 * 
 * Body:
 * {
 *   "deviceToken": "your-device-fcm-token",
 *   "otp": "123456"
 * }
 */
app.post('/send-otp', async (req, res) => {
  try {
    const { deviceToken, otp } = req.body;

    if (!deviceToken) {
      return res.status(400).json({ error: 'deviceToken is required' });
    }

    if (!otp || otp.length !== 6) {
      return res.status(400).json({ error: 'OTP must be 6 digits' });
    }

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

    const response = await messaging.send(message, deviceToken);
    
    console.log('✓ Notification sent successfully');
    console.log('  Message ID:', response);
    console.log('  Device Token:', deviceToken);
    console.log('  OTP:', otp);

    res.json({
      success: true,
      messageId: response,
      deviceToken: deviceToken,
      otp: otp,
    });
  } catch (error) {
    console.error('✗ Error sending notification:', error.message);
    res.status(500).json({
      error: error.message,
      details: error.code,
    });
  }
});

/**
 * POST /send-notification
 * Send generic notification
 * 
 * Body:
 * {
 *   "deviceToken": "your-device-fcm-token",
 *   "title": "Notification Title",
 *   "body": "Notification Body",
 *   "data": { "key": "value" }
 * }
 */
app.post('/send-notification', async (req, res) => {
  try {
    const { deviceToken, title, body, data } = req.body;

    if (!deviceToken) {
      return res.status(400).json({ error: 'deviceToken is required' });
    }

    const message = {
      notification: {
        title: title || 'Notification',
        body: body || '',
      },
      data: data || {},
      android: {
        priority: 'high',
        notification: {
          title: title || 'Notification',
          body: body || '',
          icon: '@mipmap/ic_launcher',
          channelId: 'default_channel',
        },
      },
      apns: {
        payload: {
          aps: {
            alert: {
              title: title || 'Notification',
              body: body || '',
            },
            sound: 'default',
          },
        },
      },
    };

    const response = await messaging.send(message, deviceToken);
    
    console.log('✓ Notification sent successfully');
    console.log('  Message ID:', response);
    console.log('  Device Token:', deviceToken);

    res.json({
      success: true,
      messageId: response,
    });
  } catch (error) {
    console.error('✗ Error sending notification:', error.message);
    res.status(500).json({
      error: error.message,
      details: error.code,
    });
  }
});

/**
 * GET /health
 * Check if server is running
 */
app.get('/health', (req, res) => {
  res.json({ status: 'OK', timestamp: new Date().toISOString() });
});

/**
 * GET /
 * API documentation
 */
app.get('/', (req, res) => {
  res.json({
    name: 'Firebase OTP Notification Sender',
    version: '1.0.0',
    endpoints: {
      'POST /send-otp': {
        description: 'Send OTP notification',
        body: { deviceToken: 'string', otp: 'string (6 digits)' },
      },
      'POST /send-notification': {
        description: 'Send generic notification',
        body: { deviceToken: 'string', title: 'string', body: 'string', data: 'object' },
      },
      'GET /health': {
        description: 'Check if server is running',
      },
    },
  });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`\n🔥 Firebase Notification Server running on http://localhost:${PORT}`);
  console.log(`📱 Ready to send notifications!\n`);
});
