const axios = require('axios');
const logger = require('../utils/logger');

/**
 * Send OTP via SMS.
 * In development: logs OTP to console (no actual SMS sent).
 * In production: uses MSG91 or Twilio based on SMS_PROVIDER env var.
 */
async function sendOtp(phone, otp) {
  if (process.env.NODE_ENV !== 'production') {
    // Dev mode: just log the OTP
    logger.info(`[DEV OTP] Phone: ${phone} | OTP: ${otp}`);
    console.log(`\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
    console.log(`  OTP for ${phone}: ${otp}`);
    console.log(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n`);
    return { success: true, dev: true };
  }

  const provider = process.env.SMS_PROVIDER || 'msg91';

  if (provider === 'msg91') {
    return sendViaMSG91(phone, otp);
  } else if (provider === 'twilio') {
    return sendViaTwilio(phone, otp);
  } else {
    throw new Error(`Unknown SMS provider: ${provider}`);
  }
}

async function sendViaMSG91(phone, otp) {
  const authKey = process.env.MSG91_AUTH_KEY;
  const templateId = process.env.MSG91_TEMPLATE_ID;

  if (!authKey || !templateId) {
    throw new Error('MSG91_AUTH_KEY and MSG91_TEMPLATE_ID must be set for production');
  }

  try {
    const response = await axios.post(
      'https://api.msg91.com/api/v5/otp',
      {
        template_id: templateId,
        mobile: phone.replace('+', ''),
        authkey: authKey,
        otp,
      },
      { timeout: 10000 }
    );

    logger.info(`OTP sent via MSG91 to ${phone}`);
    return { success: true, provider: 'msg91', response: response.data };
  } catch (err) {
    logger.error(`MSG91 OTP send failed for ${phone}: ${err.message}`);
    throw new Error('Failed to send OTP');
  }
}

async function sendViaTwilio(phone, otp) {
  const accountSid = process.env.TWILIO_ACCOUNT_SID;
  const authToken = process.env.TWILIO_AUTH_TOKEN;
  const from = process.env.TWILIO_FROM_NUMBER;

  if (!accountSid || !authToken || !from) {
    throw new Error('Twilio credentials must be set for production');
  }

  try {
    const response = await axios.post(
      `https://api.twilio.com/2010-04-01/Accounts/${accountSid}/Messages.json`,
      new URLSearchParams({
        To: phone,
        From: from,
        Body: `Your RummyRoyale OTP is: ${otp}. Valid for 5 minutes. Do not share.`,
      }),
      {
        auth: { username: accountSid, password: authToken },
        timeout: 10000,
      }
    );

    logger.info(`OTP sent via Twilio to ${phone}`);
    return { success: true, provider: 'twilio', sid: response.data.sid };
  } catch (err) {
    logger.error(`Twilio OTP send failed for ${phone}: ${err.message}`);
    throw new Error('Failed to send OTP');
  }
}

/**
 * Send a general SMS notification
 */
async function sendSms(phone, message) {
  if (process.env.NODE_ENV !== 'production') {
    logger.info(`[DEV SMS] Phone: ${phone} | Message: ${message}`);
    return { success: true, dev: true };
  }

  const provider = process.env.SMS_PROVIDER || 'msg91';
  if (provider === 'twilio') {
    return sendViaTwilio(phone, message);
  }
  logger.warn(`sendSms not fully implemented for provider: ${provider}`);
  return { success: false };
}

module.exports = { sendOtp, sendSms };
